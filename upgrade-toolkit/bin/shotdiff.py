#!/usr/bin/env python3
"""shotdiff.py: compare the old app's screenshots with the new app's, pair by pair, so a page that renders but shows
less than before cannot PASS.

Why: in run E4 a module update added a constant (default False) that hides most rows from the dashboard charts. The
menu journey reached the page and PASSed, constcheck listed the constant as INFO, every other rung was green. The old
and new screenshots of that page were side by side in the work folder and nobody compared them. Run E5b caught it by
looking.

  shotdiff.py OLD NEW [--accept accept.txt] [--threshold 0.06] [--lost 0.03] [--md out.md] [--json out.json]

OLD and NEW are two journey run folders (run_journeys.py <work>/<label>, holding shots-<Role>/*.png), two work folders
(one label folder inside each), or any two folders of PNG files. Screenshots pair by relative path; a trailing
"-NOT-REACHED" is not part of the name, so a step that was reached before and not after still pairs (and is INVALID).

Per pair the images are reduced to a grid of cells (grey level mean and spread per cell):
  changed   fraction of cells whose mean or spread moved by more than a small tolerance
  lost      fraction of cells that had content in OLD (spread above the flat level) and are flat in NEW
Verdicts:
  PASS      changed <= threshold and lost <= lost-limit and same page size
  REVIEW    more changed than that, or content lost, or the page size changed: look at both images and write down
            why the difference is expected (accept.txt), or treat it as a regression. Also REVIEW: the progress-bar
            detector fires on BOTH sides at the same row (within SAME_Y px) and the pair is under the thresholds
            ("indicator on both sides, images equal"; T5-18 a file-upload field, T6-15 a static line in a dashboard
            card): retaking cannot change it, so look at the pair once and accept it
  PASS*     a REVIEW, or a closable INVALID (STUCK, BASELINE DEFECT), accepted in accept.txt with a reason
  INVALID   a screenshot exists on one side only, or the NEW step was NOT-REACHED, or an image cannot be read,
            or there are no pairs at all, or either side was taken while the page was still loading (E6-17): the file
            is named ...-LOADING.png (smokewalk.js and the journey engine copy wait for the page to settle and mark it
            when it does not), or the image shows the Mendix progress bar on one side only, or on both sides of a pair
            that changed (a thin centred bar in an otherwise empty white box, see loading_marker). A loading screen
            says nothing about the page; take the shot again. A -LOADING pair, a progress-bar INVALID and a NEW-only
            NOT-REACHED pair can never be accepted. Closable by an accept line after a look (PASS*):
              STUCK            (a -STUCK on ONE side only, with images pixel-identical below the top 10 px, is PASS:
                               the theme's thin top bar fooled settle.js on one side, N1-8; both sides STUCK stays INVALID)
                               ...-STUCK.png on either side: settle.js saw the indicator stay while the DOM stood still
                               (an empty 10.6 Data grid 2, an error page, T7-22); it will not finish, retaking cannot help
              BASELINE DEFECT  the OLD step was NOT-REACHED (T1-24: NOT-REACHED on both sides used to PASS); fix the
                               plan, or accept it as a baseline defect (the report lists it apart)

accept.txt, one line per accepted pair (T7-28: pair NAMES repeat on every rung, an accept for rung 1 silently accepted
a different, broken rung-2 image):
  fnmatch-pattern-on-the-pair-name [@sha256:<12 hex of the NEW image>] # reason (required)
Every REVIEW and INVALID line prints the NEW image's hash ("new @sha256:..."). A pinned line matches only that image;
another NEW image of the same name is judged again ("pinned to another image"). An unpinned line still matches by
name, and its PASS* says "unpinned accept". Keep one accept file per rung.
Masked pin (B4T2-17: a page with per-run content, a created row's id or ${RUN_ID} text, rows an earlier journey added,
gets a new file hash every run, so a plain pin never holds twice and people fell back to unpinned accepts):
  fnmatch-pattern @mask:x,y,w,h[+x,y,w,h...] @sha256:<12 hex of the MASKED image> # reason
The rectangles (pixels, as read off the NEW image) are blanked and the hash is taken over the rest of the image (its
size included, so a page that grew does not match). Everything outside the mask stays pinned. Get the hash with
  shotdiff.py --hash NEW.png --mask x,y,w,h      (a mismatching masked line also prints this image's masked hash)
Bounded: the mask may cover at most MASK_MAX (25%) of the image, a larger one is refused for that pair, and a masked
PASS* says "masked accept: N% not pinned" and is counted apart ("N masked accepts"): weaker than a pin, stronger than
an unpinned line. A mask without a pin is an input error (it would be an unpinned accept).
Every STUCK line prints "ink OLD a% NEW b%", a one-sided STUCK PASS "ink n%" (B4N1-14): the share of grid cells below the top cell row with any content,
so a truly blank page (ink near 0) is told apart from a rendered one named -STUCK.
Visible text (NR1-25): a lost caption is a few pixels and a big regression ("Status" became "Select", a paging text
doubled: changed 4.8 %, PASS). smokewalk.js and the journey engine save the page's visible text next to each shot
(NAME.txt, document.body.innerText). When both sides of a pair have one, the words (letters only, so dates, counts and
ids do not count) are compared as a multiset: any word lost, new, or shown more or fewer times is a REVIEW whatever the
pixel share ("visible text changed: lost Status; new Select"). A pair without both files is judged on pixels only, as
before, and says nothing about text. Accepting works as for any REVIEW.
Exit: 0 = only PASS / PASS*, 1 = open REVIEW, 2 = INVALID.
"""
import argparse, fnmatch, hashlib, json, os, re, struct, sys, zlib

NR = re.compile(r"-NOT-REACHED(?=\.png$)")
LOADING = re.compile(r"-LOADING(?=\.png$)")
STUCK = re.compile(r"-STUCK(?=\.png$)")
BAND = 10              # px: top rows where the theme's thin top bar counts as a loading indicator (N1-8)
SAME_Y = 4             # px: the indicator row on both sides counts as the same place within this distance
PIN = re.compile(r"^(?P<pat>.*?)(?:\s+@mask:(?P<mask>\S+))?(?:\s+@sha256:(?P<sha>[0-9a-fA-F]{12,64}))?$")
MASK_MAX = 0.25        # B4T2-17: a masked pin may leave at most this share of the image unpinned
GRID_W = 48            # cells across; rows follow the aspect ratio
TOL_MEAN, TOL_SPREAD, FLAT = 14.0, 10.0, 4.0


def find_root(p):
    """A work folder holds one label folder (with shots-*); a label folder holds shots-*; else the folder itself."""
    p = os.path.abspath(p)
    if not os.path.isdir(p):
        sys.exit(f"shotdiff: INVALID, no folder {p}")
    if any(d.startswith("shots-") for d in os.listdir(p)):
        return p
    labels = [d for d in sorted(os.listdir(p)) if os.path.isdir(os.path.join(p, d))
              and any(x.startswith("shots-") for x in os.listdir(os.path.join(p, d)))]
    if len(labels) == 1:
        return os.path.join(p, labels[0])
    if len(labels) > 1:
        sys.exit(f"shotdiff: INVALID, {p} holds several run labels {labels}; name one")
    return p


def shots(root):
    out = {}
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in ("engine", "artifacts", "node_modules")]
        for f in fns:
            if f.lower().endswith(".png"):
                full = os.path.join(dp, f)
                rel = os.path.relpath(full, root)
                key = STUCK.sub("", LOADING.sub("", NR.sub("", rel)))
                out[key] = (full, bool(NR.search(rel)), bool(LOADING.search(rel)), bool(STUCK.search(rel)))
    return out


def _png_grey(path):
    """Minimal PNG reader (8-bit, non-interlaced, grey/RGB/RGBA/grey+alpha) for hosts without PIL."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, w = 8, b"", 0
    while pos < len(data):
        n, = struct.unpack(">I", data[pos:pos + 4]); typ = data[pos + 4:pos + 8]; body = data[pos + 8:pos + 8 + n]
        if typ == b"IHDR":
            w, h, depth, ctype, _, _, inter = struct.unpack(">IIBBBBB", body)
            if depth != 8 or inter:
                raise ValueError("only 8-bit non-interlaced PNG")
            bpp = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
        elif typ == b"IDAT":
            idat += body
        pos += 12 + n
    raw = zlib.decompress(idat); stride = w * bpp
    prev = bytearray(stride); rows = []
    for y in range(h):
        f = raw[y * (stride + 1)]; line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0; b = prev[i]; c = prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append([line[x * bpp] if bpp <= 2 else (line[x * bpp] * 3 + line[x * bpp + 1] * 6 + line[x * bpp + 2]) // 10
                     for x in range(w)])
        prev = line
    return w, h, rows


def grey(path):
    try:
        from PIL import Image
        im = Image.open(path).convert("L")
        return im.size[0], im.size[1], im
    except ImportError:
        w, h, rows = _png_grey(path)
        return w, h, rows


def cells(path, rows_n=None):
    """Return (width, height, grid of (mean, spread)) with GRID_W cells across."""
    w, h, img = grey(path)
    cw = w / GRID_W
    rn = rows_n or max(1, round(h / cw))
    ch = h / rn
    grid = []
    try:
        from PIL import Image  # noqa: F401
        px = img.load()
        get = lambda x, y: px[x, y]
    except ImportError:
        get = lambda x, y: img[y][x]
    step = max(1, int(min(cw, ch) // 6))
    for r in range(rn):
        row = []
        for c in range(GRID_W):
            x0, x1 = int(c * cw), max(int(c * cw) + 1, int((c + 1) * cw))
            y0, y1 = int(r * ch), max(int(r * ch) + 1, int((r + 1) * ch))
            vals = [get(x, y) for y in range(y0, min(y1, h), step) for x in range(x0, min(x1, w), step)]
            m = sum(vals) / len(vals)
            sd = (sum((v - m) ** 2 for v in vals) / len(vals)) ** 0.5
            row.append((m, sd))
        grid.append(row)
    return w, h, grid


def loading_marker(path):
    """Row of a Mendix progress bar in the image, or None (E6-17).

    The page-load progress indicator is a white box near the top, horizontally centred, holding one thin bar (a light
    track with a dark moving part) and nothing else. Measured on the E6 MonitoringDashboard smoke shot: box 250x42,
    bar 2 px high and 216 px wide at the page centre, dark part 54 px. A page divider is wider than the box or has no
    dark part, and real content is not surrounded by an empty white box, so this does not fire on finished pages."""
    w, h, img = grey(path)
    try:
        from PIL import Image  # noqa: F401
        px = img.load()
        get = lambda x, y: px[x, y]
    except ImportError:
        get = lambda x, y: img[y][x]
    cx = w // 2
    x0, x1 = max(0, cx - 220), min(w, cx + 220)
    for y in range(12, min(h, 1600) - 16):
        row = [get(x, y) for x in range(x0, x1)]
        x = 0
        while x < len(row):
            if row[x] > 250:
                x += 1; continue
            e = x
            while e < len(row) and row[e] <= 250:
                e += 1
            a, b = x0 + x, x0 + e          # run [a, b)
            x = e
            if not (100 <= b - a <= 400) or abs((a + b) // 2 - cx) > 60:
                continue
            if sum(1 for v in row[a - x0:b - x0] if v < 200) < 15:
                continue
            t = 1
            while t < 5 and y + t < h and sum(1 for xx in range(a, b) if get(xx, y + t) <= 250) > (b - a) // 2:
                t += 1
            if t > 4:
                continue
            pad = [yy for yy in list(range(y - 12, y - 2)) + list(range(y + t + 2, min(h, y + t + 12)))]
            if all(get(xx, yy) >= 252 for yy in pad for xx in range(a, b, 2)):
                return y
    return None


def equal_below_band(a, b, band=BAND):
    """True when both images have the same size and every pixel below the top `band` rows is identical (N1-8: the
    theme's thin top bar is the only place a loading indicator may differ between two shots of the same page)."""
    wa, ha, ia = grey(a)
    wb, hb, ib = grey(b)
    if (wa, ha) != (wb, hb):
        return False
    try:
        from PIL import Image  # noqa: F401
        return ia.tobytes()[band * wa:] == ib.tobytes()[band * wa:]
    except ImportError:
        return ia[band:] == ib[band:]


WORD = re.compile(r"[^\W\d_]{2,}")


def text_diff(old_png, new_png):
    """None when either side has no NAME.txt sidecar, else (lost, new): word lists (with 'xN' for a repeat count) from
    comparing the visible words of both pages as a multiset (NR1-25)."""
    import collections
    po, pn = old_png[:-4] + ".txt", new_png[:-4] + ".txt"
    if not (os.path.isfile(po) and os.path.isfile(pn)):
        return None
    cnt = lambda p: collections.Counter(w.lower() for w in WORD.findall(open(p, encoding="utf-8", errors="replace").read()))
    a, b = cnt(po), cnt(pn)
    fmt = lambda c: [w + (f" x{n}" if n > 1 else "") for w, n in sorted(c.items())]
    return fmt(a - b), fmt(b - a)


def compare(old, new):
    ow, oh, og = cells(old)
    nw, nh, ng = cells(new)
    rows = min(len(og), len(ng))
    changed = lost = total = 0
    for r in range(rows):
        for c in range(GRID_W):
            (om, osd), (nm, nsd) = og[r][c], ng[r][c]
            total += 1
            if abs(om - nm) > TOL_MEAN or abs(osd - nsd) > TOL_SPREAD:
                changed += 1
            if osd > FLAT * 2 and nsd <= FLAT:
                lost += 1
    extra = abs(len(og) - len(ng)) * GRID_W   # rows on one side only count as changed
    total += extra; changed += extra
    return {"old_size": [ow, oh], "new_size": [nw, nh], "changed": round(changed / total, 4) if total else 1.0,
            "lost": round(lost / total, 4) if total else 0.0}


def parse_mask(text):
    """'x,y,w,h[+x,y,w,h...]' -> [(x, y, w, h)] (B4T2-17); ValueError on anything else."""
    out = []
    for part in text.split("+"):
        v = [int(t) for t in part.split(",")]
        if len(v) != 4 or min(v) < 0 or v[2] == 0 or v[3] == 0:
            raise ValueError(f"mask {part!r}: want x,y,w,h with w and h above 0")
        out.append(tuple(v))
    return out


def masked_sha(path, mask):
    """(sha256 hex over the image with the mask rectangles blanked, share of the image masked) (B4T2-17). Always the
    plain decoder, never PIL: the hash must not depend on which grey conversion the host has."""
    w, h, rows = _png_grey(path)
    cover = [[False] * w for _ in range(h)]
    for x, y, mw, mh in mask:
        for yy in range(min(y, h), min(y + mh, h)):
            r, c = rows[yy], cover[yy]
            for xx in range(min(x, w), min(x + mw, w)):
                r[xx] = 0; c[xx] = True
    masked = sum(sum(c) for c in cover)
    d = hashlib.sha256(f"{w}x{h}:".encode())
    for r in rows:
        d.update(bytes(r))
    return d.hexdigest(), masked / float(w * h)


def ink(path):
    """Share of grid cells below the top cell row that hold any content (spread above FLAT), B4N1-14."""
    _, _, g = cells(path)
    body = [c for row in g[1:] for c in row]
    return sum(1 for _, sd in body if sd > FLAT) / len(body) if body else 0.0


def read_accept(path):
    """Lines 'pattern [@mask:...] [@sha256:<hex>] # reason' -> [(pattern, pinned hash or None, reason, mask or None)]."""
    accept = []
    for line in open(path):
        if line.strip() and not line.lstrip().startswith("#"):
            pat, _, why = line.partition("#")
            if not why.strip():
                sys.exit(f"shotdiff: {path}: {pat.strip()!r} has no reason; write '# why this change is expected'")
            m = PIN.match(pat.strip())
            if "@" in m.group("pat"):   # a mistyped pin (short hash, no space) became part of the pattern: never matches
                sys.exit(f"shotdiff: {path}: {pat.strip()!r}: the pin must be ' @sha256:<12 to 64 hex>' as printed on "
                         "the pair's line (a mask goes before it: ' @mask:x,y,w,h @sha256:<hash>')")
            mask = None
            if m.group("mask"):
                if not m.group("sha"):
                    sys.exit(f"shotdiff: {path}: {pat.strip()!r}: a mask needs the masked pin ' @sha256:<hash>' "
                             "(shotdiff.py --hash NEW.png --mask ...): a mask alone would be an unpinned accept")
                try:
                    mask = parse_mask(m.group("mask"))
                except ValueError as e:
                    sys.exit(f"shotdiff: {path}: {pat.strip()!r}: {e}")
            accept.append((m.group("pat").strip(), (m.group("sha") or "").lower() or None, why.strip(), mask))
    return accept


def sha(path):
    """First 12 hex of the sha256 of the image file: what an accept line pins (T7-28)."""
    try:
        return hashlib.sha256(open(path, "rb").read()).hexdigest()[:12]
    except OSError:
        return "?"


def match_accept(key, h, accept, path=None):
    """(reason or None, note). A pinned line matches only the image it was written for; an unpinned one says so; a
    masked one (B4T2-17) matches the image outside its mask and says how much it leaves unpinned."""
    other, notes = None, []
    for pat, pin, why, *rest in accept:
        mask = rest[0] if rest else None
        if not fnmatch.fnmatch(key, pat):
            continue
        if pin is None:
            return why, f"unpinned accept: add @sha256:{h} to the line"
        if mask:
            try:
                mh, share = masked_sha(path, mask)
            except Exception as e:  # noqa: BLE001  an unreadable image never matches a masked pin
                notes.append(f"masked line not applied: {e}"); continue
            if share > MASK_MAX:
                notes.append(f"mask covers {share:.0%} of the image, more than {MASK_MAX:.0%}: refused"); continue
            if mh.startswith(pin):
                return why, f"masked accept: {share:.1%} not pinned"
            notes.append(f"masked line pinned to another image @sha256:{pin}; this image masked @sha256:{mh[:12]}")
            continue
        if h.startswith(pin) or pin.startswith(h):
            return why, ""
        other = other or pin
    if other:
        notes.insert(0, f"accept line pinned to another image @sha256:{other}")
    if notes:
        return None, "; ".join(notes) + ", look at this pair again"
    return None, ""


def run(ro, rn, threshold=0.06, lost=0.03, accept=()):
    """Pair and judge every screenshot under the two roots; returns rows {pair, verdict, detail, sha, changed, lost}."""
    so, sn = shots(ro), shots(rn)
    res = []
    for key in sorted(set(so) | set(sn)):
        row = {"pair": key}
        res.append(row)
        if key not in sn:
            row.update(verdict="INVALID", detail="no NEW screenshot (journey or step missing after the upgrade)")
            continue
        h = row["sha"] = sha(sn[key][0])

        def judge(verdict, detail, closable):
            """An open verdict. REVIEW, STUCK and BASELINE DEFECT are closable: an accept line makes them PASS*."""
            hit, note = match_accept(key, h, accept, sn[key][0])
            if hit and closable:
                row.update(verdict="PASS*", detail=f"{detail} (accepted: {hit})" + (f" [{note}]" if note else ""))
                row["unpinned"] = note.startswith("unpinned")
                row["masked"] = note.startswith("masked accept")
            elif hit:
                row.update(verdict=verdict, detail=f"{detail}; new @sha256:{h} [accept line refused: this pair can "
                                                   "never be accepted]")
            else:
                row.update(verdict=verdict, detail=f"{detail}; new @sha256:{h}" + (f" [{note}]" if note else ""))

        if key not in so:
            judge("INVALID", "no OLD screenshot: run the same journey on the old app first", False)
            continue
        o, n = so[key], sn[key]
        if n[1] and not o[1]:
            judge("INVALID", "NEW step NOT-REACHED, OLD reached it", False)
            continue
        if o[2] or n[2]:
            side = " and ".join(s for s, v in (("OLD", o[2]), ("NEW", n[2])) if v)
            judge("INVALID", f"{side} screenshot taken while the page was still loading (-LOADING): "
                             "take it again once the page has settled", False)
            continue
        if o[1]:   # T1-24: NOT-REACHED on the OLD side says nothing about the page, on either side
            judge("INVALID", "BASELINE DEFECT: OLD step NOT-REACHED" + (" and NEW too" if n[1] else ", NEW reached it")
                  + ": fix the plan, or accept it as a baseline defect after a look", True)
            continue
        if o[3] != n[3]:
            # N1-8: STUCK on one side only. settle.js reads the theme's thin top bar as an indicator, so the same page
            # can be named -STUCK on one side and settled on the other. Pixel-identical below the top BAND rows
            # means both sides show the same page: not judged per side. Any other content: still INVALID STUCK.
            try:
                same = equal_below_band(o[0], n[0])
            except Exception:
                same = False
            if same:
                try:   # B4N1-14: say how much of the page is there, so a blank page under the bar is visible
                    ik = f", ink {ink(n[0]):.1%}"
                except Exception:
                    ik = ", ink ?"
                row.update(verdict="PASS", detail=f"{'OLD' if o[3] else 'NEW'} named -STUCK, other side settled; images "
                                                  f"equal below the top {BAND} px (indicator only{ik})")
                continue
        if o[3] or n[3]:
            side = " and ".join(s for s, v in (("OLD", o[3]), ("NEW", n[3])) if v)
            try:   # B4N1-14: a rendered page and a blank one look alike in a verdict line; the ink share tells them apart
                ik = f"; ink OLD {ink(o[0]):.1%} NEW {ink(n[0]):.1%}"
            except Exception:
                ik = "; ink ?"
            judge("INVALID", f"STUCK: {side} loading indicator never went away while the page stood still (empty grid, "
                             f"error page): open both images, then accept with what you saw, or repair{ik}", True)
            continue
        try:
            yo, yn = loading_marker(o[0]), loading_marker(n[0])
            m = compare(o[0], n[0])
        except Exception as e:
            row.update(verdict="INVALID", detail=f"cannot read: {e}")
            continue
        row.update(m)
        why = []
        if m["old_size"] != m["new_size"]:
            why.append(f"page size {m['old_size'][0]}x{m['old_size'][1]} -> {m['new_size'][0]}x{m['new_size'][1]}")
        if m["changed"] > threshold:
            why.append(f"{m['changed']:.0%} of the page changed")
        if m["lost"] > lost:
            why.append(f"{m['lost']:.0%} of the page had content before and is empty now")
        if yo is not None or yn is not None:
            bar = " and ".join(f"{s} (progress bar at y={y})" for s, y in (("OLD", yo), ("NEW", yn)) if y is not None)
            if yo is not None and yn is not None and abs(yo - yn) <= SAME_Y and not why:
                # T5-18 / T6-15: the same "bar" at the same place on two equal images is page content, not loading
                judge("REVIEW", f"indicator on both sides, images equal: {bar}, changed {m['changed']:.1%}: "
                                "open both images; accept when the page is complete, take both again when it is a "
                                "loading screen", True)
            else:
                judge("INVALID", f"loading indicator in the {bar} screenshot: the page had not finished loading; "
                                 "take it again", False)
            continue
        td = text_diff(o[0], n[0])
        if td and (td[0] or td[1]):
            cut = lambda ws: ", ".join(ws[:8]) + (f" (+{len(ws) - 8} more)" if len(ws) > 8 else "")
            why.append("visible text changed: " + "; ".join(x for x in (f"lost {cut(td[0])}" if td[0] else "",
                                                                       f"new {cut(td[1])}" if td[1] else "") if x))
        if not why:
            row.update(verdict="PASS", detail=f"changed {m['changed']:.1%}, lost {m['lost']:.1%}"
                                              + (", text same" if td is not None else ""))
        else:
            judge("REVIEW", "; ".join(why), True)
    return res


def counts_line(res):
    """'screens: N PASS, N PASS*, N REVIEW, N INVALID' (+ unpinned accepts): the line the gate cites (T1-26, T4-17)."""
    c = {k: sum(1 for r in res if r["verdict"] == k) for k in ("PASS", "PASS*", "REVIEW", "INVALID")}
    up = sum(1 for r in res if r.get("unpinned"))
    mk = sum(1 for r in res if r.get("masked"))
    extra = [f"{up} unpinned accepts"] * bool(up) + [f"{mk} masked accepts"] * bool(mk)
    return c, "screens: " + ", ".join(f"{v} {k}" for k, v in c.items()) + (f" ({', '.join(extra)})" if extra else "")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old", nargs="?"); ap.add_argument("new", nargs="?")
    ap.add_argument("--hash", metavar="PNG", help="print the pin for PNG (with --mask: the masked pin, B4T2-17) and exit")
    ap.add_argument("--mask", help="with --hash: x,y,w,h[+x,y,w,h...] rectangles to leave out of the pin")
    ap.add_argument("--accept", help="'fnmatch-pattern [@sha256:<hash>] # reason', one per line: an expected REVIEW "
                                     "(or a looked-at STUCK / BASELINE DEFECT pair) becomes PASS*")
    ap.add_argument("--threshold", type=float, default=0.06, help="changed-cell fraction above which a pair is REVIEW")
    ap.add_argument("--lost", type=float, default=0.03, help="lost-content fraction above which a pair is REVIEW")
    ap.add_argument("--md"); ap.add_argument("--json")
    a = ap.parse_args()
    if a.hash:
        try:
            if a.mask:
                mh, share = masked_sha(a.hash, parse_mask(a.mask))
                if share > MASK_MAX:
                    sys.exit(f"shotdiff: mask covers {share:.0%} of {a.hash}, more than {MASK_MAX:.0%}: pin less away")
                print(f"@mask:{a.mask} @sha256:{mh[:12]}  ({share:.1%} of the image not pinned)")
            else:
                print(f"@sha256:{sha(a.hash)}")
        except (OSError, ValueError, KeyError) as e:
            sys.exit(f"shotdiff: {a.hash}: {e}")
        sys.exit(0)
    if not (a.old and a.new):
        ap.error("OLD and NEW are required (or --hash PNG)")
    ro, rn = find_root(a.old), find_root(a.new)
    res = run(ro, rn, a.threshold, a.lost, read_accept(a.accept) if a.accept else [])
    if not res:
        print(f"shotdiff: INVALID, no screenshots under {ro} or {rn}", file=sys.stderr); sys.exit(2)
    order = {"INVALID": 0, "REVIEW": 1, "PASS*": 2, "PASS": 3}
    res.sort(key=lambda r: (order[r["verdict"]], r["pair"]))
    counts = {k: sum(1 for r in res if r["verdict"] == k) for k in order}
    lines = [f"# shotdiff {ro} -> {rn}", "", f"pairs {len(res)}: " + " | ".join(f"{k} {v}" for k, v in counts.items()), ""]
    lines += [f"{r['verdict']:7} {r['pair']}  {r['detail']}" for r in res]
    lines += ["", counts_line(res)[1]]
    if any(r.get("unpinned") for r in res):
        lines += ["unpinned accepts match every image of that name, on every rung: add the @sha256 the pair printed; a page "
                  "with per-run content (a created row's id) takes a masked pin: shotdiff.py --hash NEW.png --mask x,y,w,h "
                  "(B4T2-17)"]
    if counts["REVIEW"] or any(r["verdict"] == "INVALID" and ("STUCK" in r["detail"] or "BASELINE DEFECT" in r["detail"])
                               for r in res):
        lines += ["", "REVIEW / STUCK / BASELINE DEFECT: open both images. Expected: add "
                      "'pattern @sha256:<new hash> # what you saw' to this rung's accept file (per-run content: "
                      "'pattern @mask:x,y,w,h @sha256:<masked hash>', see --hash). "
                      "Otherwise it is a regression (empty chart, missing rows, lost widget): repair it."]
    out = "\n".join(lines)
    print(out)
    if a.md:
        open(a.md, "w").write(out + "\n")
    if a.json:
        json.dump(res, open(a.json, "w"), indent=1)
    sys.exit(2 if counts["INVALID"] else 1 if counts["REVIEW"] else 0)


if __name__ == "__main__":
    main()
