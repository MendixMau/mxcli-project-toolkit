#!/usr/bin/env python3
"""remedy.py: one decision card per upgrade blocker, with the options that apply (RM).

Why: the gate ends at a verdict. A FAIL rung or a kept module was reported and the run stopped there: the reader got a
dead end, not a choice. Blockers repeat across apps (a widget with no React 19 build, a Data Widgets 3 caption loss, an
Administration update that drops app-owned associations), and so do the ways out. This reads what the run already wrote
and gives, per blocker, the options from playbooks/remedies.tsv: A keep or pin the old version, B swap to another widget,
module or version, C rebuild, D stay on the source version. Each option carries effort (S, M, L), risk, evidence source,
the test it still needs, and AUTO-TRY (the pipeline may apply it itself) or HUMAN.

Run by: steps/remedy.md, after the gate (steps/gate.md) and before the report (Step 6). Output $W/remedy-cards.md and
$W/remediation.json. Reads only; never changes the app.

  remedy.py --work W [--gate W/gate-x/gate-summary.md] [--app APP] [--kept-file F ...] [--release F]
            [--replacements F.json] [--dojo F.json] [--finding TEXT ...] [--findings F ...] [--tried F]
            [--keptdeps F ...] [--kept-snapshot F | --reset-kept-snapshot]
            [--from VER --to VER] [--table playbooks/remedies.tsv] [--out remedy-cards.md] [--json remediation.json] [--next]

Inputs (each optional; a default is read only when the file exists):
  --gate          gate-summary.md, or the gate folder that holds it (default: the newest W/gate-*/gate-summary.md, not a gate-remedy-* trial). FAIL rungs: the REGRESSION lines of the
                  rung's .out file next to the summary (smoke.out, journeys.out) are the blockers; a FAIL rung with none
                  is one blocker "rung: <name> FAIL". A FAIL whose report says "instrument not measuring" or "0 regression",
                  and every INVALID or required NOT RUN rung, is an instrument gap: listed, no card (it needs a measurement,
                  not a remedy).
  --kept-file     stepupdate's .stepupdate/kept.txt (default APP/.stepupdate/kept.txt, else W/kept.txt); one module per
                  line, first word the module. Lines saying "newest" are no blocker; "skipped by --skip" is listed
                  under "by choice" (a plan choice, BACKLOG #77, RT-13): no card and no instrument gap.
  --kept-snapshot what the kept list held on earlier runs (default W/remedy-kept-snapshot.txt, used only when the kept
                  list is the default APP/.stepupdate/kept.txt, which is gitignored and shared across branches: RT-9, a
                  trial's own stepupdate overwrote it and a card with a tried FAIL vanished without a word). A module in
                  the snapshot and gone from the kept list keeps its card (WARN kept list shrank) unless a tried PASS
                  resolved it; --reset-kept-snapshot starts the snapshot again from the current list.
  --keptdeps      keptdeps.py output to read for the kept dependents of a subject (repeatable; APP/.stepupdate/keptdeps.txt
                  is read too when it exists). With --app, remedy.py also runs `keptdeps.py APP --kept <the other kept
                  modules> --updated <subject>` itself (read only) for every AUTO-TRY option whose test names keptdeps
                  (RT-8: GenAICommons B was AUTO-TRY while the kept MxGenAIConnector calls it; 19 CE1613 at mx check).
  --release       release-impact.md (default W/release-impact.md): every open row (handled cell empty, "open:" or
                  "blocked:"). Its header "Mendix X to Y" gives the jump when --from/--to are not given. An open row no
                  remedy row matches is an instrument gap (a fact to check), not a card.
  --replacements  replacement_check.py --json (default W/replacements.json): HIT rows whose evidence says BLOCKER.
  --dojo          dojo_report.py --json (default W/dojo-react.json): "can't move" packages, only when the report is BLOCKING.
  --finding TEXT  a blocker a person or the run wrote down (a journey outside the gate, an ASSUMPTIONS line); --findings F
                  reads one per non-empty line, '#' lines skipped.
  --tried         W/remedy-tried.txt (default): what the pipeline already tried, one line each:
                  `<card key> <option> PASS|FAIL <evidence path or commit> [# note]`. PASS resolves the card; FAIL moves to
                  the next AUTO-TRY option, and with none left the card is HUMAN.

Matching: every blocker becomes one text line (kept: <kept.txt line>, release: <section> row <n> <type> <change> <affected>
<handled>, smoke: REGRESSION ..., journeys: REGRESSION ..., rung: <name> FAIL <line>, replacement: <id> HIT <evidence>,
dojo: can't move <package>, finding: <text>). A remedies.tsv row whose match regex hits the line takes the blocker; blockers
on the same key share one card. A 'generic-*' key takes a blocker only when no specific key did, and makes one card per
subject (the kept module, the rung, the replacement row). A blocker no row takes gets a card with no options: "no remedy
row: decide, then add a row". Options whose jump does not hold are dropped (with --from/--to unknown, all are kept).

AUTO-TRY rules (read_table refuses a table that breaks them, exit 2): option A or B, or a C whose verified column says
yes (a proven mechanical fix, RT-4: the global .sr-only theme rule); never D; never a row whose verified column says
disproven; apply and regate given. Code also makes an option HUMAN when
  - a blocker of its card is a kept module whose kept line names data (idcheck, REMOVED, GUID, persistence): data
    decisions are never automatic;
  - its verified column is no or - (an unproven recipe is never automatic); a partial one stays AUTO-TRY but ranks
    behind every verified option, HUMAN ones included (RT-1: no better than HUMAN);
  - its test names keptdeps and keptdeps is not shown clean for the subject: another kept module calls it (then an extra
    HUMAN option "update the subject with its dependents in one step" is added), or keptdeps could not run (RT-8).
Ranking (RT-1: the dw3 card put A first by the letter and A was the worst option): options are listed and tried by
evidence first (verified yes, partial, no or -, then disproven or tried FAIL), then effort, the letter only as the
tie-break. A disproven row prints DISPROVEN with its evidence. Per card the next option to try is the first AUTO-TRY
option in that order that remedy-tried.txt does not list.
By eye (RT-6): a row whose regate names the pseudo-rung `eye` fixes a visual symptom that shotdiff and smoke can pass
(the doubled paging text passed at 4.8 percent). A tried PASS on it resolves the card only when its evidence holds
`eye=<shot path>` (the shot a person looked at); `eye` is never passed to gate.sh --only.

A tried line whose card key this run does not generate is printed as WARN (RT-9: never drop a known FAIL silently).

Exit: 0 = no open card (none, or each resolved by a tried PASS); 3 = an AUTO-TRY option is waiting (apply it with
remedy_apply.sh, which re-gates the rungs it names and records the result in remedy-tried.txt; run again); 1 = only
HUMAN decisions are open; 2 = input error (unreadable table or input file named on the command line).
"""
import argparse, json, re, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_impact import HANDLED, cells, cmpv  # noqa: E402

HERE = Path(__file__).resolve().parent
DEFAULT_TABLE = HERE.parent / "playbooks" / "remedies.tsv"
COLS = ["key", "title", "match", "jump", "option", "action", "effort", "risk", "evidence", "test", "mode", "apply",
        "regate", "source", "verified"]
EFFORT = {"S": 0, "M": 1, "L": 2}
DATA_KEPT = re.compile(r"(?i)idcheck|REMOVED|GUID|persist")
GAP_FAIL = re.compile(r"(?i)instrument not measuring|\b0 regression\b")
KD_CALLS = re.compile(r"^(FAIL|REVIEW|NOTE) kept (\S+) \S+ calls updated (\S+)")


def ev_rank(verified):
    """RT-1: evidence first. 0 verified yes, 1 partial, 2 no or unknown, 3 disproven."""
    v = str(verified or "").strip().lower()
    return 3 if v.startswith("disproven") else 0 if v.startswith("yes") else 1 if v.startswith("partial") else 2


def regate_list(r):
    return [x.strip() for x in str(r or "").split(",") if x.strip() and x.strip() != "-"]


class TableError(Exception):
    pass


def vt(s):
    m = re.match(r"\s*(\d+(?:\.\d+)*)", str(s or ""))
    return tuple(int(x) for x in m.group(1).split(".")) if m else None


def read_table(path):
    rows, header = [], None
    for n, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        c = line.split("\t")
        if header is None:
            if c != COLS:
                raise TableError(f"{path}:{n}: header is not {' '.join(COLS)}")
            header = c
            continue
        if len(c) != len(COLS):
            raise TableError(f"{path}:{n}: {len(c)} fields, want {len(COLS)}")
        r = dict(zip(COLS, c))
        r["line"] = n
        if not re.fullmatch(r"[ABCD]\d?", r["option"]):
            raise TableError(f"{path}:{n}: option {r['option']!r} is not A, B, C or D (B2, B3 for more swaps)")
        if r["effort"] not in EFFORT:
            raise TableError(f"{path}:{n}: effort {r['effort']!r} is not S, M or L")
        if r["mode"] not in ("AUTO-TRY", "HUMAN"):
            raise TableError(f"{path}:{n}: mode {r['mode']!r} is not AUTO-TRY or HUMAN")
        if r["mode"] == "AUTO-TRY":
            if r["option"][0] == "D" or (r["option"][0] == "C" and ev_rank(r["verified"]) != 0):
                raise TableError(f"{path}:{n}: AUTO-TRY on option {r['option']}: only A (keep or pin) and B (swap) may be "
                                 "tried by the pipeline, or a C whose verified column says yes (a proven mechanical fix); "
                                 "a rebuild and D (stay) are always HUMAN")
            if ev_rank(r["verified"]) == 3:
                raise TableError(f"{path}:{n}: AUTO-TRY on a disproven row (verified: {r['verified'][:80]}): make it HUMAN")
            if r["apply"] in ("", "-") or r["regate"] in ("", "-"):
                raise TableError(f"{path}:{n}: AUTO-TRY needs apply (what to run) and regate (the rungs to re-run)")
        try:
            r["rx"] = re.compile(r["match"])
        except re.error as e:
            raise TableError(f"{path}:{n}: match is no regex: {e}")
        for j in r["jump"].split(","):
            j = j.strip()
            if j != "any" and not re.fullmatch(r"to:(<|>=)\d+(\.\d+)*", j):
                raise TableError(f"{path}:{n}: jump {j!r} is not any, to:<X or to:>=X")
        rows.append(r)
    if header is None:
        raise TableError(f"{path}: no header")
    return rows


def jump_ok(r, tv):
    if tv is None:
        return True
    for j in r["jump"].split(","):
        j = j.strip()
        if j == "any":
            continue
        op, v = re.fullmatch(r"to:(<|>=)(.+)", j).groups()
        c = cmpv(tv, vt(v))
        if (op == "<" and c >= 0) or (op == ">=" and c < 0):
            return False
    return True


def stay_text(frm, to):
    fv, tv = vt(frm), vt(to)
    if not fv:
        return "the source version"
    if tv and fv[0] < tv[0] and fv[0] in (9, 10):
        return f"{fv[0]}.24 LTS" + ("" if fv[:2] == (fv[0], 24) else f" (the source is {frm}: finish the {fv[0]}.24 rung)")
    return f"{frm} (the source version)"


# ---- inputs -----------------------------------------------------------------------------------------------------
def read_gate(path):
    """(verdict, blockers, gaps) from a gate-summary.md and the .out files next to it."""
    text = Path(path).read_text(errors="replace")
    m = re.search(r"Overall: \*\*([^*]+)\*\*", text)
    verdict = m.group(1).strip() if m else "unknown"
    m = re.search(r"evidence: `([^`]+)`", text)
    gdir = Path(m.group(1)) if m and Path(m.group(1)).is_dir() else Path(path).parent
    blockers, gaps = [], []
    for line in text.splitlines():
        c = cells(line)
        if not c or len(c) < 5 or not re.fullmatch(r"\d+", c[0]):
            continue
        rung, v, one = c[1], c[2], c[4]
        out = gdir / f"{rung}.out"
        body = out.read_text(errors="replace") if out.exists() else ""
        if v == "FAIL":
            regs = [ln.strip() for ln in body.splitlines() if re.match(r"\s*REGRESSION\b", ln)]
            if regs:
                for ln in regs:
                    blockers.append({"source": f"gate {rung}", "file": str(out), "subject": rung,
                                     "text": f"{'journeys' if rung == 'journeys' else 'smoke'}: {ln[:400]}"})
            elif GAP_FAIL.search(one + "\n" + body):
                why = next((ln.strip() for ln in body.splitlines() if "instrument not measuring" in ln), one)
                gaps.append({"source": f"gate {rung}", "file": str(out if body else path),
                             "text": f"{rung} FAIL with no regression: the instrument did not measure ({why[:300]})"})
            else:
                blockers.append({"source": f"gate {rung}", "file": str(path), "subject": rung,
                                 "text": f"rung: {rung} FAIL {one[:300]}"})
        elif v == "INVALID" or (v == "NOT RUN" and "optional rung" not in one):
            gaps.append({"source": f"gate {rung}", "file": str(path), "text": f"{rung} {v}: {one[:300]}"})
    return verdict, blockers, gaps


def read_kept_lines(path):
    return [ln.strip() for ln in Path(path).read_text(errors="replace").splitlines()
            if ln.strip() and not ln.strip().startswith("#")]


def read_kept(path, gaps, choices=None, lines=None):
    out = []
    choices = gaps if choices is None else choices
    for line in (lines if lines is not None else read_kept_lines(path)):
        src = "kept (snapshot)" if line.startswith("\x00") else "kept"
        line = line.lstrip("\x00")
        if re.search(r"(?i)\bnewest\b", line):
            continue
        if re.search(r"skipped by --skip", line):   # a plan choice, not a refusal (BACKLOG #77); RT-13: not a gap either
            choices.append({"source": "kept", "file": str(path), "text": f"kept line '{line}': skipped by choice, not "
                            "refused; check the module is still at its old version (a later pass may have updated it)"})
            continue
        out.append({"source": src, "file": str(path), "subject": line.split()[0], "text": f"kept: {line}",
                    "data": bool(DATA_KEPT.search(line))})
    return out


def read_release(path):
    """(header jump, open rows as blockers)."""
    text = Path(path).read_text(errors="replace")
    m = re.search(r"^# Release impact: Mendix (\S+) to (\S+)", text, re.M)
    jump = (m.group(1), m.group(2)) if m else (None, None)
    out, section = [], ""
    for line in text.splitlines():
        if line.startswith("## "):
            section = line[3:].split(" (")[0]
        c = cells(line)
        if not c or not re.fullmatch(r"\d+", c[0]) or HANDLED.match(c[-1]):
            continue
        if c[-1] and not re.match(r"(?i)^(open|blocked)\s*:", c[-1]):
            continue  # some other entry: release_impact --check judges it, not this
        out.append({"source": f"release {section} row {c[0]}", "file": str(path), "subject": f"{section} row {c[0]}",
                    "text": f"release: {section} row {c[0]} " + " ".join(c[1:])[:600]})
    return jump, out


def read_replacements(path):
    d = json.loads(Path(path).read_text())
    out = []
    for r in d.get("rows", []):
        ev = "; ".join(r.get("evidence", []))
        if r.get("status") == "HIT" and "BLOCKER" in ev:
            out.append({"source": f"replacement {r['id']}", "file": str(path), "subject": r["id"],
                        "text": f"replacement: {r['id']} HIT {ev[:400]}"})
    return out


def read_dojo(path):
    d = json.loads(Path(path).read_text())
    out = []
    for r in d if isinstance(d, list) else [d]:
        if "BLOCKING" not in r.get("summary", ""):
            continue
        for p in r.get("packages", []):
            if p.get("status") == "can't move":
                out.append({"source": f"dojo {p['package']}", "file": str(path), "subject": p["package"],
                            "text": f"dojo: can't move {p['package']}"})
    return out


def read_findings(texts, files):
    out = [{"source": "finding", "file": "-", "subject": t[:40], "text": f"finding: {t}"} for t in texts]
    for f in files:
        for line in Path(f).read_text(errors="replace").splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                out.append({"source": "finding", "file": str(f), "subject": line[:40], "text": f"finding: {line}"})
    return out


def read_tried(path):
    tried = {}
    for n, line in enumerate(Path(path).read_text(errors="replace").splitlines(), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        p = line.split()
        if len(p) < 4 or p[2] not in ("PASS", "FAIL"):
            raise TableError(f"{path}:{n}: want '<card key> <option> PASS|FAIL <evidence>' (an option that is not on the card: X:<label>)")
        tried[(p[0], p[1])] = (p[2], " ".join(p[3:]))
    return tried


# ---- cards ------------------------------------------------------------------------------------------------------
def opt_key(o):
    """RT-1: evidence first (a tried FAIL counts as disproven for this app), then effort, the letter last."""
    r = 3 if o.get("tried", "").startswith("FAIL") else o["ev"]
    return (r, EFFORT[o["effort"]], o["option"])


def build_cards(rows, blockers, frm, to, tried, deps=None):
    tv = vt(to)
    keys = list(dict.fromkeys(r["key"] for r in rows))
    byk = {k: [r for r in rows if r["key"] == k] for k in keys}
    cards, order = {}, []

    def add(cid, key, title, b):
        if cid not in cards:
            cards[cid] = {"id": cid, "key": key, "title": title, "blockers": []}
            order.append(cid)
        cards[cid]["blockers"].append(b)

    for b in blockers:
        hit = [k for k in keys if not k.startswith("generic-") and byk[k][0]["rx"].search(b["text"])]
        if not hit:
            hit = [k for k in keys if k.startswith("generic-") and byk[k][0]["rx"].search(b["text"])][:1]
        if not hit:
            add(f"none:{b['subject']}", None, f"no remedy row for: {b['text'][:120]}", b)
            continue
        for k in hit:
            if k.startswith("generic-"):
                add(f"{k}:{b['subject']}", k, byk[k][0]["title"].replace("{subject}", b["subject"]), b)
            else:
                add(k, k, byk[k][0]["title"], b)
    stay = stay_text(frm, to) if frm else "the source version"
    out = []
    for cid in order:
        c = cards[cid]
        subject = cid.split(":", 1)[1] if ":" in cid else ""
        data = any(b.get("data") for b in c["blockers"])
        kept_subjects = list(dict.fromkeys(b["subject"] for b in c["blockers"] if b["source"].startswith("kept")))
        opts, dependents = [], []
        for r in byk.get(c["key"], []):
            if not jump_ok(r, tv):
                continue
            fill = lambda s: s.replace("{stay}", stay).replace("{from}", frm or "the source").replace(
                "{to}", to or "the target").replace("{subject}", subject)
            mode = r["mode"]
            why = ""
            ev = ev_rank(r["verified"])
            if mode == "AUTO-TRY" and data:
                mode, why = "HUMAN", "a kept line names data: never automatic"
            elif mode == "AUTO-TRY" and ev == 2:
                mode, why = "HUMAN", f"evidence is '{r['verified'][:60] or '-'}': an unproven recipe is never automatic"
            elif mode == "AUTO-TRY" and re.search(r"(?i)keptdeps", r["test"]) and kept_subjects:
                for subj in kept_subjects:
                    clean, deps_found, kwhy = deps(subj) if deps else (False, [], "keptdeps not run (give --app or --keptdeps)")
                    if not clean:
                        mode, why = "HUMAN", kwhy
                        dependents += [(subj, d) for d in deps_found if (subj, d) not in dependents]
                        break
            o = {"option": r["option"], "action": fill(r["action"]), "effort": r["effort"], "risk": fill(r["risk"]),
                 "evidence": fill(r["evidence"]), "test": fill(r["test"]), "mode": mode, "apply": fill(r["apply"]),
                 "regate": r["regate"], "source": r["source"], "verified": r["verified"], "row": r["line"], "ev": ev,
                 "eye": "eye" in regate_list(r["regate"])}
            if ev == 3:
                o["disproven"] = r["verified"]
            if why:
                o["why_human"] = why
            t = tried.get((cid, r["option"]))
            if t:
                o["tried"] = f"{t[0]} {t[1]}"
            opts.append(o)
        if dependents:   # RT-8: the subject and the kept module that calls it move together, or not at all
            used = {o["option"] for o in opts}
            oid = next(f"B{n}" for n in range(2, 10) if f"B{n}" not in used)
            subj = dependents[0][0]
            dl = ", ".join(sorted({d for _, d in dependents}))
            o = {"option": oid, "action": f"update {subj} together with {dl} in one step (the plan.txt versions of both), "
                 f"after the card of {dl} is decided", "effort": "M",
                 "risk": f"{dl} is kept for its own reason (local edits, no version): that card decides first",
                 "evidence": f"keptdeps: kept {dl} calls {subj}", "test": "keptdeps clear, mx check 0 errors, step idcheck "
                 "clean, smoke and screens of the pages of both modules", "mode": "HUMAN", "apply": "-",
                 "regate": "build,idcheck,data,smoke,screens,release", "source": "RT-8", "verified": "no", "row": 0,
                 "ev": 2, "eye": False}
            t = tried.get((cid, oid))
            if t:
                o["tried"] = f"{t[0]} {t[1]}"
            opts.append(o)
        opts.sort(key=opt_key)
        c["options"] = opts
        # V3D-6: a tried line `<key> X:<label> PASS|FAIL ...` names something done that is not an option of the card. It is
        # listed as an extra row and never resolves the card (the letter of a card option is not borrowed for it).
        c["extras"] = [{"option": opt, "tried": f"{t[0]} {t[1]}"} for (k, opt), t in sorted(tried.items())
                       if k == cid and opt.startswith("X:")]
        passed = [o for o in opts if o.get("tried", "").startswith("PASS")]
        noeye = [o for o in passed if o["eye"] and not re.search(r"(?:^|\s)eye=\S", o["tried"])]
        if passed and len(noeye) < len(passed):
            o = next(o for o in passed if o not in noeye)
            c["status"], c["next"] = "RESOLVED", f"resolved by a tried option: {o['option']} {o['tried']}"
        elif noeye:
            o = noeye[0]
            c["status"] = "HUMAN"
            c["next"] = (f"HUMAN: {o['option']} PASS needs a by-eye screens verdict (RT-6: shotdiff and smoke pass this "
                         f"symptom): look at the shots, then add eye=<shot path> to its line in remedy-tried.txt")
        else:
            auto = sorted((o for o in opts if o["mode"] == "AUTO-TRY" and "tried" not in o), key=opt_key)
            if auto:
                o = auto[0]
                rg = ",".join(x for x in regate_list(o["regate"]) if x != "eye")
                c["status"] = "AUTO-TRY"
                c["next"] = (f"AUTO-TRY {o['option']}: bash $B/remedy_apply.sh --config <remedy.conf> {cid} {o['option']} "
                             f"({o['apply']}; then gate.sh --only {rg}" + ("; then a by-eye look at the screens" if o["eye"] else "")
                             + f"); it records '{cid} {o['option']} PASS|FAIL <evidence>' in remedy-tried.txt; run remedy.py again")
            elif opts:
                failed = [o["option"] for o in opts if o.get("tried", "").startswith("FAIL")]
                c["status"] = "HUMAN"
                left = [o["option"] for o in opts if "tried" not in o and "disproven" not in o]
                c["next"] = ((("HUMAN: choose one of " + ", ".join(left)) if left else
                              "HUMAN: no untried option left: decide (a new row in playbooks/remedies.tsv, or stay)")
                             + "".join(f" (disproven: {o['option']})" for o in opts if "disproven" in o and "tried" not in o)
                             + (f" (tried and failed: {', '.join(failed)})" if failed else ""))
            else:
                c["status"] = "HUMAN"
                c["next"] = ("HUMAN: no option applies to this jump; decide, then add a row to playbooks/remedies.tsv"
                             if c["key"] else "HUMAN: no remedy row; decide, then add a row to playbooks/remedies.tsv")
        ex_pass = [e["option"] for e in c["extras"] if e["tried"].startswith("PASS")]
        if ex_pass and c["status"] != "RESOLVED":
            c["next"] += (f" (extra tried and PASS, not on the card: {', '.join(ex_pass)}; a person decides whether it "
                          "closes the card)")
        out.append(c)
    for n, c in enumerate(out, 1):
        c["card"] = f"C{n}"
    return out


def esc(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


def markdown(res):
    L = [f"# Remediation options: {res['from'] or '?'} to {res['to'] or '?'}", "",
         f"Gate verdict: **{res['verdict']}** ({res['gate'] or 'no gate summary read'}). The verdict stands; these cards say "
         "what can be done about each blocker.", "", res["line"], ""]
    if not res["cards"]:
        L += ["No blocker: no decision card.", ""]
    for c in res["cards"]:
        L += [f"## {c['card']} {c['title']}", "", f"Card key `{c['id']}`. Status: **{c['status']}**.", "", "Blocker evidence:"]
        for b in c["blockers"][:8]:
            L.append(f"- {b['source']}: {esc(b['text'][:220])} ({b['file']})")
        if len(c["blockers"]) > 8:
            L.append(f"- and {len(c['blockers']) - 8} more of the same kind")
        L.append("")
        if c["options"]:
            L += ["| option | what | effort | risk | evidence | test still needed | mode |", "|---|---|---|---|---|---|---|"]
            for o in c["options"]:
                mode = o["mode"] + (f" ({o['why_human']})" if o.get("why_human") else "") + (
                    f"; DISPROVEN: {o['disproven']}" if o.get("disproven") else "") + (
                    "; by eye" if o.get("eye") else "") + (f"; tried: {o['tried']}" if o.get("tried") else "")
                L.append("| " + " | ".join(esc(x) for x in (o["option"], o["action"], o["effort"], o["risk"],
                                                            o["evidence"], o["test"], mode)) + " |")
            L.append("")
        for e in c.get("extras", []):
            L.append(f"- extra, not an option of this card: {esc(e['option'])}, tried: {esc(e['tried'])}")
        if c.get("extras"):
            L.append("")
        L += [f"Next: {c['next']}", ""]
    if res.get("warnings"):
        L += ["## Warnings", ""] + [f"- {esc(w)}" for w in res["warnings"]] + [""]
    if res.get("choices"):
        L += ["## By choice (no card: a plan choice, not a refusal)", ""] + [f"- {esc(g['text'])}" for g in res["choices"]] + [""]
    L += ["## Instrument gaps (no card: a measurement is missing, not a remedy)", ""]
    L += [f"- {g['source']}: {esc(g['text'])}" for g in res["gaps"][:40]] or ["none"]
    if len(res["gaps"]) > 40:
        L.append(f"- and {len(res['gaps']) - 40} more")
    L += ["", "Option letters: A keep or pin the old version, B swap (another widget, module or version), C rebuild, "
          "D stay on the source version. Options are ranked by evidence (verified, partial, unproven, disproven), then effort; "
          "the letter only breaks a tie. AUTO-TRY: the pipeline applies it itself (bin/remedy_apply.sh: one branch, "
          "abandoned on FAIL), re-gates the named rungs and records the result; HUMAN: a person decides (steps/remedy.md).", ""]
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--work", required=True)
    ap.add_argument("--gate")
    ap.add_argument("--app")
    ap.add_argument("--kept-file", action="append", default=[])
    ap.add_argument("--release")
    ap.add_argument("--replacements")
    ap.add_argument("--dojo")
    ap.add_argument("--finding", action="append", default=[])
    ap.add_argument("--findings", action="append", default=[])
    ap.add_argument("--tried")
    ap.add_argument("--keptdeps", action="append", default=[])
    ap.add_argument("--kept-snapshot")
    ap.add_argument("--reset-kept-snapshot", action="store_true")
    ap.add_argument("--from", dest="frm")
    ap.add_argument("--to")
    ap.add_argument("--table", default=str(DEFAULT_TABLE))
    ap.add_argument("--out")
    ap.add_argument("--json")
    ap.add_argument("--next", action="store_true", help="print only the next action per open card")
    a = ap.parse_args()
    W = Path(a.work)
    if not W.is_dir():
        print(f"remedy: --work {W}: not a folder")
        return 2

    def pick(given, default):
        if given:
            if not Path(given).exists():
                raise TableError(f"no file {given}")
            return given
        return str(default) if default and Path(default).exists() else None

    try:
        rows = read_table(a.table)
        gates = sorted((g for g in W.glob("gate-*/gate-summary.md") if not g.parent.name.startswith("gate-remedy-")),
                       key=lambda p: p.stat().st_mtime)   # a remedy trial's gate (remedy_apply.sh) is not the run's gate
        gate = pick(a.gate, gates[-1] if gates else None)
        if gate and Path(gate).is_dir():   # QI-5: a gate folder is accepted, its gate-summary.md is read
            if not (Path(gate) / "gate-summary.md").is_file():
                raise TableError(f"--gate {gate} is a folder with no gate-summary.md")
            gate = str(Path(gate) / "gate-summary.md")
        kept = [pick(k, None) for k in a.kept_file] or [
            x for x in (pick(None, Path(a.app) / ".stepupdate" / "kept.txt") if a.app else None,
                        pick(None, W / "kept.txt")) if x][:1]
        app_kept = bool(a.app and kept and not a.kept_file and Path(kept[0]) == Path(a.app) / ".stepupdate" / "kept.txt")
        snap = a.kept_snapshot or (str(W / "remedy-kept-snapshot.txt") if app_kept else None)
        kdfiles = [pick(k, None) for k in a.keptdeps]
        if a.app and (Path(a.app) / ".stepupdate" / "keptdeps.txt").exists():
            kdfiles.append(str(Path(a.app) / ".stepupdate" / "keptdeps.txt"))
        release = pick(a.release, W / "release-impact.md")
        repl = pick(a.replacements, W / "replacements.json")
        dojo = pick(a.dojo, W / "dojo-react.json")
        tried_f = pick(a.tried, W / "remedy-tried.txt")
        for f in a.findings:
            pick(f, None)
        verdict, blockers, gaps = read_gate(gate) if gate else ("not read", [], [])
        frm, to = a.frm, a.to
        if release:
            (rf, rt), rel = read_release(release)
            frm, to = frm or rf, to or rt
        else:
            rel = []
        warnings, choices = [], []
        tried = read_tried(tried_f) if tried_f else {}
        for i, k in enumerate(kept):
            lines = read_kept_lines(k)
            if i == 0 and snap:   # RT-9: a later overwrite of kept.txt must not drop a known card silently
                mods = {ln.split()[0] for ln in lines}
                old = [] if a.reset_kept_snapshot or not Path(snap).exists() else read_kept_lines(snap)
                for ln in old:
                    m = ln.split()[0]
                    if m in mods:
                        continue
                    if any(t[0] == "PASS" and key.split(":", 1)[-1] == m for (key, _), t in tried.items()):
                        continue
                    warnings.append(f"kept list shrank: {m} is in the snapshot {snap} but not in {k} (a later stepupdate "
                                    "overwrote it?); its card is kept from the snapshot (--reset-kept-snapshot drops it)")
                    lines.append("\x00" + ln)
                    mods.add(m)
                try:
                    Path(snap).write_text("".join(ln.lstrip("\x00") + "\n" for ln in lines))
                except OSError as e:
                    warnings.append(f"kept snapshot {snap} not written: {e}")
            blockers += read_kept(k, gaps, choices, lines)
        blockers += read_replacements(repl) if repl else []
        blockers += read_dojo(dojo) if dojo else []
        blockers += read_findings(a.finding, a.findings)
    except (OSError, ValueError, TableError) as e:
        print(f"remedy: {e}")
        return 2
    # release rows: a card only when a specific remedy row takes them; the rest are facts to check (gaps)
    specific = [r for r in rows if not r["key"].startswith("generic-")]
    for b in rel:
        if any(r["rx"].search(b["text"]) for r in specific):
            blockers.append(b)
        else:
            gaps.append({"source": b["source"], "file": b["file"], "text": "open release row: " + b["text"][9:260]})
    kept_all = list(dict.fromkeys(b["subject"] for b in blockers if b["source"].startswith("kept")))
    kd_lines = []
    for f in kdfiles:
        kd_lines += [(f, ln) for ln in Path(f).read_text(errors="replace").splitlines()]
    kd_cache = {}

    def deps(subject):
        """RT-8: (clean, dependents, why) for updating subject while the other kept modules stay."""
        if subject in kd_cache:
            return kd_cache[subject]
        found, src = [], []
        for f, ln in kd_lines:
            m = KD_CALLS.match(ln)
            if m and m.group(3) == subject and m.group(2) != subject and m.group(2) not in found:
                found.append(m.group(2))
                src.append(f)
        others = [k for k in kept_all if k != subject]
        ran, err = False, ""
        if a.app and others:
            cmd = [sys.executable, str(HERE / "keptdeps.py"), a.app, "--kept", ",".join(others), "--updated", subject]
            try:
                p = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
                if p.returncode in (0, 1):
                    ran = True
                    for ln in p.stdout.splitlines():
                        m = KD_CALLS.match(ln)
                        if m and m.group(3) == subject and m.group(2) not in found:
                            found.append(m.group(2))
                            src.append("keptdeps.py run")
                else:
                    err = (p.stderr.strip() or p.stdout.strip()).splitlines()[-1:] or ["no output"]
                    err = f"keptdeps.py exit {p.returncode}: {err[0][:160]}"
            except (OSError, subprocess.TimeoutExpired) as e:
                err = f"keptdeps.py did not run: {e}"
        if found:
            r = (False, found, f"kept {', '.join(found)} calls {subject} (keptdeps, {src[0]}): updating {subject} alone "
                 "breaks it; update them in one step")
        elif not others:
            r = (True, [], "")
        elif ran:
            r = (True, [], "")
        else:
            r = (False, [], f"keptdeps not shown clean for the kept modules that may call {subject} ("
                 + (err or "give --app, or --keptdeps with a keptdeps.py run that updates " + subject) + ")")
        kd_cache[subject] = r
        return r

    cards = build_cards(rows, blockers, frm, to, tried, deps)
    keys = {c["id"] for c in cards}
    for (key, opt), t in tried.items():
        if key not in keys:
            warnings.append(f"tried line '{key} {opt} {t[0]}' matches no card of this run: its blocker is gone from the "
                            "inputs (resolved, or an input was overwritten): check before trusting it")
    n = {s: sum(1 for c in cards if c["status"] == s) for s in ("AUTO-TRY", "HUMAN", "RESOLVED")}
    auto_opts = [f"{c['card']} {o['option']}" for c in cards for o in c["options"] if o["mode"] == "AUTO-TRY"]
    line = (f"remedy: {len(cards)} cards ({n['AUTO-TRY']} AUTO-TRY waiting, {n['HUMAN']} HUMAN, {n['RESOLVED']} resolved); "
            f"instrument gaps {len(gaps)}; gate {verdict}; jump {frm or '?'} -> {to or '?'}")
    res = {"verdict": verdict, "gate": gate, "from": frm, "to": to, "line": line, "counts": n,
           "auto_try_options": auto_opts, "cards": cards, "gaps": gaps, "choices": choices, "warnings": warnings,
           "inputs": {"gate": gate, "kept": kept, "release": release, "replacements": repl, "dojo": dojo,
                      "findings": a.findings, "tried": tried_f, "table": a.table, "keptdeps": kdfiles,
                      "kept_snapshot": snap}}
    print(line)
    for w in warnings:
        print(f"WARN {w}")
    for c in cards:
        if a.next and c["status"] == "RESOLVED":
            continue
        print(f"{c['card']} {c['status']:<8} {c['id']}: {c['title']}")
        if not a.next:
            for o in c["options"]:
                t = f" [tried {o['tried']}]" if o.get("tried") else ""
                d = f" [DISPROVEN: {o['disproven'][:120]}]" if o.get("disproven") else ""
                h = f" [HUMAN: {o['why_human'][:160]}]" if o.get("why_human") else ""
                print(f"    {o['option']:<3} {o['mode']:<8} {o['effort']} {o['action'][:150]}{t}{d}{h}")
        for e in c.get("extras", []):
            print(f"    {e['option']:<3} EXTRA    (not on the card) [tried {e['tried']}]")
        print(f"    next: {c['next']}")
    if not a.next:
        for g in choices:
            print(f"CHOICE {g['text'][:200]}")
        for g in gaps[:20]:
            print(f"GAP {g['source']}: {g['text'][:200]}")
        if len(gaps) > 20:
            print(f"GAP and {len(gaps) - 20} more (see the report)")
    # QI-5: the default is remedy-cards.md, not remediation.md: steps and briefs write a merged REMEDIATION.md, and on a
    # case-insensitive disk (macOS) the two names are one file. The json keeps its name (remedy_apply.sh reads it).
    out = a.out or str(W / "remedy-cards.md")
    js = a.json or (str(Path(out).with_suffix(".json")) if a.out else str(W / "remediation.json"))
    Path(out).write_text(markdown(res))
    for c in cards:
        for b in c["blockers"]:
            b.pop("data", None)
    Path(js).write_text(json.dumps(res, indent=1))
    return 3 if n["AUTO-TRY"] else 1 if n["HUMAN"] else 0


if __name__ == "__main__":
    sys.exit(main())
