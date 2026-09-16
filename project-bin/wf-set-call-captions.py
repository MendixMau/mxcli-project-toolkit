#!/usr/bin/env python3
"""Set the display caption on workflow Call-microflow activities.

THE DEFECT. Drag "Call a microflow" onto a workflow and pick a target: Studio Pro
stamps the activity's Caption with the microflow's technical name, so a canvas meant
for business readers ends up reading ACT_ApprovalRun_FailProjection instead of
"Fail projection".

Caption is stored PER PLACED ACTIVITY, not on the microflow. "Expose as workflow
action 'Caption' in 'Category'" on the microflow only gives it a nice Toolbox entry
-- it affects activities dragged in AFTER that MDL runs, never the ones already on
the canvas. There is no MDL statement that reaches back and relabels a placed
activity's Caption. This tool is that missing retrofit.

Only Caption is written. Name -- the activity's identifier within the flow, referenced
by outgoing Flow elements -- is left exactly as it was, so nothing that points at the
activity can break. No structure, no outcomes, no flows are touched: this is a string
swap on one field, everywhere it occurs.

Defaults to a dry run. Nothing is written without --apply.

    <toolkit>/project-bin/wf-set-call-captions.py <unit.mxunit> \
        --captions Mod.ACT_ApprovalRun_FailProjection='Fail projection'
    <toolkit>/project-bin/wf-set-call-captions.py <unit.mxunit> \
        --captions-file captions.txt --apply

--captions takes repeated Qualified.Name='Caption' pairs. --captions-file reads the
same thing one per line, # for comments.

FIELD RUN. VB-USI, 2026-09-14, mxcli v0.21.0 / Mendix 11.13.0: 36 call-microflow
activities across one 16-station approval workflow, all still showing their raw
ACT_ names months after the microflows themselves had been exposed as workflow
actions. All 36 relabelled in one pass. Native `mx check`: 0 errors after.

NEVER run this against a model Studio Pro has open, or while the app is running --
same rule as every other .mxunit write in this toolkit.
"""
import os, sys, shutil

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mxunit_bson import load, enc_doc

CALL = "Workflows$CallMicroflowActivity"


def get(doc, key):
    for _t, k, v in doc:
        if k == key:
            return v
    return None


def is_doc(x):
    return isinstance(x, list) and all(isinstance(e, tuple) and len(e) == 3 for e in x)


def set_key(doc, key, value):
    """Replace key's value in place, preserving its position and BSON type."""
    for i, (t, k, _v) in enumerate(doc):
        if k == key:
            doc[i] = (t, k, value)
            return True
    return False


def walk(node, captions, state):
    if is_doc(node):
        if get(node, "$Type") == CALL:
            mf = get(node, "Microflow")
            if mf in captions:
                want = captions[mf]
                have = get(node, "Caption")
                if have == want:
                    state["already"].append(mf)
                elif set_key(node, "Caption", want):
                    state["changed"].append((mf, have, want))
                else:
                    state["no_caption_field"].append(mf)
        for _t, _k, v in node:
            walk(v, captions, state)
    elif isinstance(node, list):
        for v in node:
            walk(v, captions, state)


def parse_pair(s):
    if "=" not in s:
        sys.exit("bad --captions entry (want Qualified.Name='Caption'): %s" % s)
    mf, cap = s.split("=", 1)
    return mf.strip(), cap.strip().strip("'").strip('"')


def main():
    argv = sys.argv[1:]
    args, captions, apply_ = [], {}, False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--apply":
            apply_ = True
        elif a == "--captions":
            i += 1
            while i < len(argv) and not argv[i].startswith("--"):
                mf, cap = parse_pair(argv[i])
                captions[mf] = cap
                i += 1
            continue
        elif a == "--captions-file":
            i += 1
            for line in open(argv[i]):
                line = line.split("#", 1)[0].strip()
                if line:
                    mf, cap = parse_pair(line)
                    captions[mf] = cap
        elif not a.startswith("--"):
            args.append(a)
        i += 1

    if len(args) != 1 or not captions:
        sys.exit(__doc__)
    path = args[0]

    doc = load(path)
    state = {"changed": [], "already": [], "no_caption_field": []}
    walk(doc, captions, state)

    print("captions to set: %d" % len(state["changed"]))
    seen = {}
    for mf, have, want in state["changed"]:
        seen.setdefault((mf, have, want), 0)
        seen[(mf, have, want)] += 1
    for (mf, have, want), n in sorted(seen.items()):
        print("    %3d x %s" % (n, mf))
        print("          %r -> %r" % (have, want))
    print("already correct: %d" % len(state["already"]))
    if state["no_caption_field"]:
        print("NO Caption field (skipped): %d" % len(state["no_caption_field"]))

    missing = set(captions) - {mf for mf, _h, _w in state["changed"]} - set(state["already"])
    if missing:
        print("\nWARNING: no call site found for: %s" % ", ".join(sorted(missing)))

    if not state["changed"]:
        print("\nNothing to change.")
        return
    if not apply_:
        print("\nDry run. Re-run with --apply to write.")
        return

    # Encode before touching the original, so an encoder failure cannot destroy it.
    blob = enc_doc(doc)
    shutil.copy2(path, path + ".bak")
    was = os.path.getsize(path + ".bak")
    with open(path, "wb") as fh:
        fh.write(blob)
    print("\nwrote %s (%d bytes, was %d)" % (path, len(blob), was))
    print("backup: %s.bak" % path)
    print("\nNow run mx check.")


if __name__ == "__main__":
    main()
