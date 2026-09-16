#!/usr/bin/env python3
"""Add the missing EndOfParallelSplitPathActivity to every parallel-split path.

THE DEFECT (BUG-121). mxcli writes PARALLEL SPLIT paths and their contents correctly, but
never emits the terminator node that closes each path. Studio Pro emits exactly one per
path, always as the final element of that path's Flow.Activities. Without it the Mendix
runtime reaches the end of every path in the same millisecond, creates no task in any of
them, and walks straight past the split -- while `mxcli check`, `mxbuild --target=deploy`,
native `mx check` and a `DESCRIBE WORKFLOW` round-trip all report zero errors, on the broken
model and the fixed one alike. That is why the ledger entry spent three weeks calling the
symptom ("drops their contents") the mechanism.

WHY A PATCHER AND NOT MDL. There is no keyword. `mxcli syntax workflow --json` lists no
branch-ending activity of any kind -- not end-of-parallel-split-path, not END WORKFLOW
(learned-workflow-patterns.md §21 gap 2). Until the grammar has one, a scripted split needs
this pass after every write.

RUN IT AFTER EVERY SCRIPT THAT TOUCHES THE WORKFLOW. Re-running an MDL script rewrites the
unit and drops the terminators again. This tool is idempotent -- a path that already ends in
a terminator is left alone -- so running it again costs nothing and forgetting it costs the
whole fan-out.

    <toolkit>/bin/wf-add-path-terminators.py <unit.mxunit>            # report only
    <toolkit>/bin/wf-add-path-terminators.py <unit.mxunit> --apply    # patch, with a .bak

Find the unit: it is the `.mxunit` under mprcontents/ whose decoded `Name` is the workflow.
Count paths, not branches -- a nested split's paths are paths too.

VERIFY WITH A LIVE RUN, NEVER WITH A BUILD GATE. Both gates are blind in both directions.
Start an instance, walk it to the split, and count the tasks the engine actually opens
(`system$workflowactivity`, or the project's own e2e walk). Consecutive "End of parallel
split path" rows with no task between them is the unfixed signature.

FIELD RUN. the approval app, 2026-09-14, mxcli v0.21.0 / Mendix 11.13.0: a 16-station approval
workflow with a seven-leg split and a nested two-leg split inside it. 9 paths found, 9
terminators added, unit 87236 -> 89486 bytes. The same definition reached 8 of 16 stations
before the patch and 16 of 16 after, six of them open concurrently at the split. Native
`mx check`: 0 errors both times.

NEVER run this against a model Studio Pro has open, or while the app is running -- see
project-bin/snapshot-mpr.sh. Concurrent writers corrupt the .mpr.
"""
import os, sys, uuid, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mxunit_bson import Bin, load, dump, enc_doc

TERMINATOR = "Workflows$EndOfParallelSplitPathActivity"
SPLIT_OUTCOME = "Workflows$ParallelSplitOutcome"


def get(doc, key):
    """Value of `key` in an order-preserving [(type, key, value)] document."""
    for _t, k, v in doc:
        if k == key:
            return v
    return None


def is_doc(x):
    return isinstance(x, list) and all(
        isinstance(e, tuple) and len(e) == 3 for e in x
    )


def make_terminator(n):
    """An 8-field node with no outbound references -- the whole reason this is safe."""
    return [
        (0x05, "$ID", Bin(0, uuid.uuid4().bytes)),
        (0x02, "$Type", TERMINATOR),
        (0x0A, "Annotation", None),
        (0x02, "Caption", "End of parallel split path"),
        (0x02, "Name", "endOfParallelSplitPath%d" % n),
        (0x05, "PersistentId", Bin(0, uuid.uuid4().bytes)),
        (0x02, "RelativeMiddlePoint", "0;0"),
        (0x02, "Size", "0;0"),
    ]


def walk(node, state):
    """Recurse the unit, appending a terminator to every unterminated split path."""
    if is_doc(node):
        if get(node, "$Type") == SPLIT_OUTCOME:
            flow = get(node, "Flow")
            if is_doc(flow):
                acts = get(flow, "Activities")
                if isinstance(acts, list):
                    state["paths"] += 1
                    # An array is a document with numeric keys, so each element is a
                    # (type, key, value) tuple -- the activity doc is element[2].
                    last = acts[-1][2] if acts else None
                    if is_doc(last) and get(last, "$Type") == TERMINATOR:
                        state["already"] += 1
                    else:
                        state["n"] += 1
                        acts.append((0x03, str(len(acts)), make_terminator(state["n"])))
                        state["added"] += 1
        for _t, _k, v in node:
            walk(v, state)
    elif isinstance(node, list):
        for v in node:
            walk(v, state)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    apply_ = "--apply" in sys.argv[1:]
    if len(args) != 1:
        sys.exit(__doc__)
    path = args[0]

    doc = load(path)
    state = {"paths": 0, "added": 0, "already": 0, "n": 0}
    walk(doc, state)

    print("paths found          : %d" % state["paths"])
    print("already terminated   : %d" % state["already"])
    print("terminators to add   : %d" % state["added"])

    if state["paths"] == 0:
        print("\nNo parallel split in this unit -- nothing to do.")
        return
    if state["added"] == 0:
        print("\nEvery path is already terminated -- nothing to do.")
        return
    if not apply_:
        print("\nDry run. Re-run with --apply to write.")
        return

    # Encode before touching the original, so an encoder failure cannot destroy the unit.
    blob = enc_doc(doc)
    shutil.copy2(path, path + ".bak")
    with open(path, "wb") as fh:
        fh.write(blob)
    print("\nwrote %s (%d bytes, was %d)" % (path, len(blob), os.path.getsize(path + ".bak")))
    print("backup: %s.bak" % path)
    print("\nNow verify with a LIVE RUN and system$workflowactivity.")
    print("A green mx check proves nothing here -- it passes the broken model too.")
    print("Re-run this after ANY later script that rewrites this workflow.")


if __name__ == "__main__":
    main()
