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

    bin/wf-set-call-captions.py <unit.mxunit> \
        --captions Mod.ACT_ApprovalRun_FailProjection='Fail projection'
    bin/exec.sh --patch bin/wf-set-call-captions.py Mod.ApprovalWorkflow \
        --captions-file captions.txt --apply

The second form is the guarded one: exec.sh passes the .mpr first, the workflow is found by
its qualified name, and the write gets the snapshot, the `mxcli fix hashes` verify and the
mxbuild gate. A unit path works in either form.

The write goes through mxpatch.py, so the .mpr's ContentsHash for the unit is updated in
the same step. Until 2026-10-14 (#294) this tool rewrote the .mxunit and left the index
alone: every --apply left a stale hash that `mx check` cannot see and Studio Pro trips on.

--captions takes repeated Qualified.Name='Caption' pairs. --captions-file reads the
same thing one per line, # for comments.

Drift is refused: a Caption is replaced only while it is still the microflow's own name
(what Studio Pro stamps), or the value given with --expect-caption Qualified.Name='Old'.
Anything else -- a caption someone already edited -- exits 3 and writes nothing.

FIELD RUN. An approval-workflow app replacement, 2026-09-14, mxcli v0.21.0 / Mendix 11.13.0: 36 call-microflow
activities across one 16-station approval workflow, all still showing their raw
ACT_ names months after the microflows themselves had been exposed as workflow
actions. All 36 relabelled in one pass. Native `mx check`: 0 errors after.

NEVER run this against a model Studio Pro has open, or while the app is running --
same rule as every other .mxunit write in this toolkit.
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxpatch
from mxpatch import get, is_doc

CALL = "Workflows$CallMicroflowActivity"


def walk(node, captions, expects, state):
    if is_doc(node):
        if get(node, "$Type") == CALL:
            mf = get(node, "Microflow")
            if mf in captions:
                want = captions[mf]
                have = get(node, "Caption")
                # Drift guard: the caption this tool assumes is there is the one Studio Pro (and
                # mxcli) stamps -- the microflow's own name -- unless --expect-caption says other.
                # A caption someone already edited by hand is refused, never overwritten.
                expect = expects.get(mf, mf.split(".", 1)[-1])
                try:
                    r = mxpatch.set_value(node, "Caption", want, expect=expect)
                except mxpatch.Drift:
                    state["drifted"].append((mf, have, expect))
                except mxpatch.PatchError:     # no Caption key, or one that is not a string
                    state["no_caption_field"].append(mf)
                else:
                    if r == "already":
                        state["already"].append(mf)
                    else:
                        state["changed"].append((mf, have, want))
        for _t, _k, v in node:
            walk(v, captions, expects, state)
    elif isinstance(node, list):
        for v in node:
            walk(v, captions, expects, state)


def parse_pair(s):
    if "=" not in s:
        sys.exit("bad --captions entry (want Qualified.Name='Caption'): %s" % s)
    mf, cap = s.split("=", 1)
    return mf.strip(), cap.strip().strip("'").strip('"')


def main():
    argv = sys.argv[1:]
    args, captions, expects, apply_ = [], {}, {}, False
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
        elif a == "--expect-caption":
            i += 1
            while i < len(argv) and not argv[i].startswith("--"):
                mf, cap = parse_pair(argv[i])
                expects[mf] = cap
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

    if not args or not captions:
        sys.exit(__doc__)
    try:
        model, unit = mxpatch.resolve_unit(args, "Workflows$Workflow")
    except mxpatch.PatchError as e:
        sys.exit("wf-set-call-captions: %s" % e)
    doc = unit.doc
    state = {"changed": [], "already": [], "no_caption_field": [], "drifted": []}
    walk(doc, captions, expects, state)

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

    if state["drifted"]:
        print("\nREFUSED -- caption is not the one this run expects (edited since?): %d" % len(state["drifted"]))
        for mf, have, expect in state["drifted"]:
            print("    %s: is %r, expected %r" % (mf, have, expect))
        print("Nothing written. If the current caption is right to replace, pass it:")
        print("    --expect-caption %s='<current caption>'" % state["drifted"][0][0])
        sys.exit(3)

    missing = set(captions) - {mf for mf, _h, _w in state["changed"]} - set(state["already"])
    if missing:
        print("\nWARNING: no call site found for: %s" % ", ".join(sorted(missing)))

    if not state["changed"]:
        print("\nNothing to change.")
        return
    if not apply_:
        print("\nDry run. Re-run with --apply to write.")
        return

    # mxpatch encodes before touching the original, and updates the ContentsHash with the file.
    print("")
    model.write_unit(unit, apply=True, backup=True)
    print("\nNow run mx check (or run this under bin/exec.sh --patch, which does).")


if __name__ == "__main__":
    try:
        main()
    except mxpatch.PatchError as e:
        sys.exit("wf-set-call-captions: %s" % e)
