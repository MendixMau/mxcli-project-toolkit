#!/usr/bin/env python3
"""mf-canvas-facts.py -- what Studio Pro will draw on top of what, per microflow and nanoflow.

An INSTRUMENT (skills/skills-over-scripts.md): it prints facts, one line each, and no verdicts.
Which facts are defects, which are the norm in hand-drawn flows, and how to avoid or repair each
one is in skills/canvas-readability.md -- read that before acting on this output.

    mf-canvas-facts.py <model> --all                       every microflow and nanoflow
    mf-canvas-facts.py <model> --module Shop [--module M]  the flows of these modules
    mf-canvas-facts.py <model> Shop.ACT_Order_Save NAME    these flows (qualified or plain names)
    mf-canvas-facts.py <model> --names-file flows.txt      one name per line, # for comments

<model> is the .mpr, its directory, or its mprcontents/ (MPR v2 only). Units are read through
mxpatch.py, the toolkit's one BSON reader; nothing is written.

FACTS (geometry in canvas units; Studio Pro draws 1 unit = 1 px at 100%):
  OVERLAP    two drawn things share space (object box, the variable label under it, note box)
  LINE       a flow or note line passes through an object or label that is not one of its ends
  NOTE-SIDE  a note line leaves the note on a side that faces away from what it points at
  LEFTWARD   a flow ends left of where it starts (the reader follows it backwards)
  TURN       a flow leaves or enters an object on a side facing away from the other end (it curls)
  CAPTION    a caption has a word wider than its shape (Studio Pro breaks it mid-word), or more
             lines than fit
  SENSE      a decision's whole expression is negated (not(...), $x = empty) but its caption asks
             the positive question, so the line marked true answers "no" to the caption

CALIBRATION, measured from Studio Pro 10.24 screenshots: a variable label is ~5.5 units per
character, two lines (name, type) under the shape; an activity fits 3 caption lines of ~16
characters and no word over 14; a decision diamond fits 2 lines of ~10 characters and no word
over 10. Connection sides are stored as indexes: an annotation (note) numbers its sides top 0,
bottom 1, left 2, right 3; every other object top 0, right 1, bottom 2, left 3. The note is
always the origin of a note line. A flow line is the cubic Bezier through the two stored control
vectors, sampled at 48 points. SENSE is a prompt to read the true branch, not a verdict: on one
hand-drawn corpus 15 of its 18 hits were fine (`$Message = empty` really means "valid"), while all
9 hits in the mxcli-written flows were real.

OUTPUT: per flow `# Module.Name  (n)` then one indented fact line each; last line
`# facts: <flows> flows, OVERLAP a, LINE b, ...`. Field run, measured 2026-10-21 on one Mendix 10.24 app (1,588 flows, read in one pass):
on the 36 flows one mxcli-built branch added or changed in a single module, before any repair, OVERLAP 19,
LINE 27, NOTE-SIDE 17, LEFTWARD 3, TURN 4, SENSE 9, CAPTION 148; after the branch's later repair
commits, OVERLAP 3, LINE 7, TURN 4, CAPTION 113 and the rest 0.

Exit: 0 measured (facts or none), 2 could not measure (bad model path, a named flow not found,
a unit that does not decode -- the flows that did decode are still printed).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxpatch  # noqa: E402
from mxunit_bson import Bin  # noqa: E402

FLOW_TYPES = ("Microflows$Microflow", "Microflows$Nanoflow")
KINDS = ("OVERLAP", "LINE", "NOTE-SIDE", "LEFTWARD", "TURN", "CAPTION", "SENSE")
CH = 5.5
ACT_SIDES = {0: (0, -1), 1: (1, 0), 2: (0, 1), 3: (-1, 0)}
NOTE_SIDES = {0: (0, -1), 1: (0, 1), 2: (-1, 0), 3: (1, 0)}
SIDE_NAME = {(0, -1): "top", (0, 1): "bottom", (-1, 0): "left", (1, 0): "right"}
NEG = re.compile(r"\b(not|no|non|none|never|missing|wrong|without|empty|invalid|inactive|incomplete|"
                 r"incorrect|disabled|absent|expired|refused|failed|lacks?)\b|n't\b|"
                 # un- words that are negatives; an explicit set, because \bun[a-z]+ also takes
                 # unit, unique, under, until, union -- common caption words with no negative sense
                 r"\bun(?:able|assigned|available|changed|checked|defined|filled|finished|"
                 r"known|matched|paid|read|ready|resolved|saved|selected|sent|set|used|"
                 r"validated|verified)\b", re.I)


# -- the unit as plain data ----------------------------------------------------------------------
def plain(t, v):
    """A mxpatch (type, key, value) value as dicts and lists; arrays keep their version marker."""
    if t == 0x03:
        return {k: plain(tt, vv) for tt, k, vv in v}
    if t == 0x04:
        return [plain(tt, vv) for tt, _k, vv in v]
    if isinstance(v, Bin):
        return v.data.hex()
    return v


def items(v):
    """A stored list: its first element is a version marker, not an item."""
    return [x for x in (v or []) if isinstance(x, dict)]


def pt(s):
    x, y = (s or "0;0").split(";")
    return float(x), float(y)


def short(q):
    return (q or "").split(".")[-1]


def objects(mf):
    """Every drawn object as an absolute box: id, type, x, y, w, h, parent loop id, raw."""
    out = []

    def add(coll, ox, oy, parent):
        for o in items((coll or {}).get("Objects")):
            x, y = pt(o.get("RelativeMiddlePoint"))
            w, h = pt(o.get("Size"))
            t = o["$Type"].split("$")[-1]
            if parent is not None:              # inside a loop: relative to the loop's top-left
                x, y = ox + x, oy + y
            out.append(dict(id=o["$ID"], type=t, x=x, y=y, w=w, h=h, parent=parent, raw=o))
            if t == "LoopedActivity":
                add(o.get("ObjectCollection"), x - w / 2, y - h / 2, o["$ID"])
    add(mf.get("ObjectCollection"), 0, 0, None)
    return out


def edges(mf):
    """All sequence and annotation flows, those stored inside loops included."""
    out = list(items(mf.get("Flows")))

    def walk(coll):
        for o in items((coll or {}).get("Objects")):
            if o["$Type"].endswith("LoopedActivity"):
                out.extend(items((o.get("ObjectCollection") or {}).get("Flows")))
                walk(o.get("ObjectCollection"))
    walk(mf.get("ObjectCollection"))
    return out


# -- what Studio Pro writes under and inside each shape ------------------------------------------
def type_label(vt):
    t = (vt or {}).get("$Type", "").split("$")[-1]
    if t in ("ObjectType", "ListType"):
        e = short(vt.get("Entity"))
        return ("List of " + e) if t == "ListType" else e
    if t == "EnumerationType":
        return short(vt.get("Enumeration"))
    return t.replace("Type", "") or "Object"


def label_and_caption(o, exposed):
    """(variable label lines, the caption Studio Pro shows -- None when not known)."""
    r, t = o["raw"], o["type"]
    if "Parameter" in t:
        return [r.get("Name", ""), type_label(r.get("VariableType"))], None
    if t == "EndEvent":
        rv = r.get("ReturnValue") or ""
        return ([rv.split("\n")[0][:40], "x" * 8] if rv else []), None
    if t == "ExclusiveSplit":
        return [], r.get("Caption") or ""
    if t != "ActionActivity":
        return [], None
    a = r.get("Action") if isinstance(r.get("Action"), dict) else {}
    at = a.get("$Type", "").split("$")[-1]
    var = a.get("ResultVariableName") or a.get("VariableName") or a.get("OutputVariableName") or ""
    if at == "MicroflowCallAction" and not a.get("UseReturnVariable"):
        var = ""
    members = ", ".join(short(i.get("Attribute") or i.get("Association")) for i in items(a.get("Items")))
    src = a.get("RetrieveSource") if isinstance(a.get("RetrieveSource"), dict) else {}
    ent = short(a.get("Entity") or src.get("Entity")
                or short(src.get("AssociationId") or src.get("Association")).split("_")[0])
    typ = {"CreateVariableAction": type_label(a.get("VariableType")), "CreateChangeAction": ent,
           "RetrieveAction": "List of " + ent, "CreateListAction": "List of " + ent}.get(at, "x" * 12)
    cap = None
    if r.get("AutoGenerateCaption") is False:
        cap = r.get("Caption") or ""
    elif at == "MicroflowCallAction":
        called = (a.get("MicroflowCall") or {}).get("Microflow") or ""
        cap = exposed.get(called) or exposed.get(short(called)) or short(called)
    elif at == "CreateChangeAction":
        cap = "Create " + ent + (" (" + members + ")" if members else "")
    elif at == "ChangeAction":
        cap = "Change " + (a.get("ChangeVariableName") or "") + (" (" + members + ")" if members else "")
    elif at == "RetrieveAction":
        cap = "Retrieve list of " + ent + (" from database" if "Database" in src.get("$Type", "") else " by association")
    elif at == "ChangeVariableAction":
        cap = "Change variable " + (a.get("VariableName") or a.get("ChangeVariableName") or "")
    elif at == "CreateListAction":
        cap = "Create list of " + ent
    return ([var, typ] if var else []), cap


def closes_at_end(s):
    """s starts with '(': does that parenthesis close at the very end of s?"""
    depth, q = 0, False
    for i, c in enumerate(s):
        if c == "'":
            q = not q
        if q:
            continue
        depth += (c == "(") - (c == ")")
        if depth == 0:
            return i == len(s) - 1
    return False


def wrap(text, width):
    lines, cur = [], ""
    for w in text.split():
        if cur and len(cur) + 1 + len(w) > width:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    return lines + ([cur] if cur else [])


def box(x, y, w, h):
    return (x - w / 2, y - h / 2, x + w / 2, y + h / 2)


def hit(a, b, pad=0):
    return a[0] + pad < b[2] and b[0] + pad < a[2] and a[1] + pad < b[3] and b[1] + pad < a[3]


def end_point(o, idx):
    dx, dy = (NOTE_SIDES if o["type"] == "Annotation" else ACT_SIDES).get(idx, (0, 0))
    return o["x"] + dx * o["w"] / 2, o["y"] + dy * o["h"] / 2, (dx, dy)


# -- the facts ------------------------------------------------------------------------------------
def check(mf, exposed):
    objs = objects(mf)
    by = {o["id"]: o for o in objs}
    out, things = [], []          # things: (kind, owner id, box, text)
    for o in objs:
        lab, cap = label_and_caption(o, exposed)
        o["what"] = "%s@%d,%d" % (o["type"].replace("Activity", "").replace("Exclusive", "")[:10], o["x"], o["y"])
        things.append(("object" if o["type"] != "Annotation" else "note", o["id"],
                       box(o["x"], o["y"], o["w"], o["h"]), o["what"]))
        if lab:
            w = CH * max(len(s) for s in lab) + 4
            top = o["y"] + (18 if "Parameter" in o["type"] else o["h"] / 2 + 4)
            things.append(("label", o["id"], (o["x"] - w / 2, top, o["x"] + w / 2, top + 38),
                           'label "%s" of %s' % (lab[0], o["what"])))
        if o["type"] == "ExclusiveSplit" and cap:
            sc = o["raw"].get("SplitCondition") or {}
            ex = " ".join((sc.get("Expression") or "").split())
            negated = ((ex.startswith("not(") and ex.endswith(")") and closes_at_end(ex[3:]))
                       or re.fullmatch(r"\$[\w/]+\s*=\s*empty", ex))
            if negated and not NEG.search(cap):
                out.append('SENSE     %s "%s" asks the positive question; its true branch is %s'
                           % (o["what"], cap[:60], ex[:60]))
        if cap is not None:
            word, width, maxl = (10, 10, 2) if o["type"] == "ExclusiveSplit" else (14, 16, 3)
            long_ = [w for w in cap.split() if len(w) > word]
            n = len(wrap(cap, width))
            if long_ or n > maxl:
                out.append('CAPTION   %s "%s": %s' % (o["what"], cap[:60], ", ".join(
                    (["breaks %s" % " ".join(long_)] if long_ else [])
                    + (["%d lines, %d fit" % (n, maxl)] if n > maxl else []))))

    def inside(a, b):             # a is drawn inside loop b (any depth)
        p = by[a]["parent"] if a in by else None
        while p:
            if p == b:
                return True
            p = by[p]["parent"]
        return False

    for i, (ka, ia, ba, ta) in enumerate(things):
        for kb, ib, bb, tb in things[i + 1:]:
            if ia == ib or inside(ia, ib) or inside(ib, ia):
                continue
            if "Parameter" in by[ia]["type"] and "Parameter" in by[ib]["type"] and ka == kb == "object":
                continue
            if hit(ba, bb, -6 if ka == kb == "label" else 1):
                out.append("OVERLAP   %s  x  %s" % (ta, tb))
    for e in edges(mf):
        a, b = by.get(e.get("OriginPointer")), by.get(e.get("DestinationPointer"))
        if not a or not b:
            continue
        ax, ay, da = end_point(a, e.get("OriginConnectionIndex"))
        bx, by_, db = end_point(b, e.get("DestinationConnectionIndex"))
        line = e.get("Line") or {}
        c1, c2 = pt(line.get("OriginControlVector")), pt(line.get("DestinationControlVector"))
        p1, p2 = (ax + c1[0], ay + c1[1]), (bx + c2[0], by_ + c2[1])
        pts = []
        for k in range(1, 48):
            s = k / 48.0
            u = 1 - s
            pts.append((u ** 3 * ax + 3 * u * u * s * p1[0] + 3 * u * s * s * p2[0] + s ** 3 * bx,
                        u ** 3 * ay + 3 * u * u * s * p1[1] + 3 * u * s * s * p2[1] + s ** 3 * by_))
        is_note = e["$Type"].endswith("AnnotationFlow")
        desc = "%s %s -> %s" % ("note line" if is_note else "flow", a["what"], b["what"])
        crossed = []
        for k, owner, bx_, t in things:
            if owner in (a["id"], b["id"]) and k == "object" and by[owner]["type"] != "ActionActivity":
                continue
            if k == "object" and by[owner]["type"] == "LoopedActivity" and (inside(a["id"], owner) or inside(b["id"], owner)):
                continue
            sb = (bx_[0] + 3, bx_[1] + 3, bx_[2] - 3, bx_[3] - 3)
            if any(sb[0] < x < sb[2] and sb[1] < y < sb[3] for x, y in pts[2:-2]):
                crossed.append(t)
        if crossed:
            out.append("LINE      %s crosses %s" % (desc, "; ".join(crossed)))
        if is_note:
            n, t, side = (a, b, da) if a["type"] == "Annotation" else (b, a, db)
            vx, vy = t["x"] - n["x"], t["y"] - n["y"]
            if side[0] * vx + side[1] * vy <= 0:
                out.append("NOTE-SIDE %s leaves the note %s, away from %s"
                           % (desc, SIDE_NAME.get(side, "?"), t["what"]))
        else:
            if bx < ax - 10 and not e.get("IsErrorHandler"):
                out.append("LEFTWARD  %s runs %d units right-to-left" % (desc, ax - bx))
            vx, vy = b["x"] - a["x"], b["y"] - a["y"]
            if abs(vx) + abs(vy) > 30 and a["parent"] == b["parent"]:
                if da[0] * vx + da[1] * vy <= 0:
                    out.append("TURN      %s leaves on the %s, away from its target" % (desc, SIDE_NAME.get(da, "?")))
                if -(db[0] * vx + db[1] * vy) <= 0:
                    out.append("TURN      %s enters on the %s, the side away from its source" % (desc, SIDE_NAME.get(db, "?")))
    return out


# -- driver ---------------------------------------------------------------------------------------
def open_model(path):
    p = os.path.abspath(path)
    if os.path.isdir(p) and os.path.basename(p.rstrip(os.sep)) == "mprcontents":
        p = os.path.dirname(p.rstrip(os.sep))
    return mxpatch.Model(p)


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        sys.stdout.write(__doc__)
        return 2
    names, modules, every, i = [], [], False, 2
    while i < len(argv):
        a = argv[i]
        if a == "--all":
            every = True
        elif a in ("--module", "--names-file") and i + 1 < len(argv):
            if a == "--module":
                modules.append(argv[i + 1])
            else:
                names += [l.split("#", 1)[0].strip() for l in open(argv[i + 1])]
            i += 1
        elif a.startswith("--"):
            sys.stderr.write("mf-canvas-facts: unknown option %s\n" % a)
            return 2
        else:
            names.append(a)
        i += 1
    names = [n for n in names if n]
    if not (every or names or modules):
        sys.stderr.write("mf-canvas-facts: name flows, --module M, --names-file F or --all\n")
        return 2
    try:
        model = open_model(argv[1])
    except mxpatch.PatchError as e:
        sys.stderr.write("mf-canvas-facts: %s\n" % e)
        return 2
    # model.units() would stop at the first unit that does not decode; read each candidate on
    # its own so one bad unit is a named fault and every other flow is still measured.
    needles = [mxpatch._bson_str(0x02, "$Type", t) for t in FLOW_TYPES]
    flows, faults = [], []
    for p in model.unit_files():
        raw = open(p, "rb").read()
        if not any(n in raw for n in needles):
            continue
        try:
            u = mxpatch.Unit(p, raw)
        except Exception as e:          # any decode failure is a named fault, never a crash
            faults.append("%s: %s" % (os.path.basename(p), e))
            continue
        if u.type in FLOW_TYPES:
            flows.append(u)
    picked, exposed = [], {}
    for u in flows:
        mf = plain(0x03, u.doc)
        mod = model.module_of(u) or "?"
        q = "%s.%s" % (mod, u.name)
        info = mf.get("MicroflowActionInfo")
        if isinstance(info, dict) and info.get("Caption"):
            exposed[q] = info["Caption"]
            exposed.setdefault(u.name, info["Caption"])
        if every or mod in modules or q in names or u.name in names:
            picked.append((q, mf))
    found = {q for q, _ in picked} | {q.split(".", 1)[1] for q, _ in picked}
    missing = [n for n in names if n not in found]
    totals = dict.fromkeys(KINDS, 0)
    for q, mf in sorted(picked, key=lambda x: x[0]):
        res = check(mf, exposed)
        print("# %s  (%d)" % (q, len(res)))
        for line in res:
            print("  " + line)
            totals[line.split()[0]] += 1
    print("# facts: %d flows, %s" % (len(picked), ", ".join("%s %d" % (k, totals[k]) for k in KINDS)))
    for n in missing:
        sys.stderr.write("mf-canvas-facts: FAULT no microflow or nanoflow named %s\n" % n)
    for f in faults:
        sys.stderr.write("mf-canvas-facts: FAULT could not read %s\n" % f)
    for m in modules:
        if not any(q.startswith(m + ".") for q, _ in picked):
            sys.stderr.write("mf-canvas-facts: note: module %s has no microflows or nanoflows\n" % m)
    return 2 if (missing or faults) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
