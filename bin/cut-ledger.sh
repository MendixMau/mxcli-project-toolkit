#!/bin/bash
# cut-ledger.sh: the cut ledger of one Decompose slice — one row per crossing edge, each with a
#                resolution and its evidence, or the run fails.
#
# usage: bin/cut-ledger.sh (--catalog <catalog.db> | --refs <refs.tsv>) --slice <slice.txt>
#                          --rules <rules.tsv> [--check-log <mx-check.txt>]...
#                          [--exporter-json <export.json>]... [--extra <rows.tsv>]...
#                          [--dump-refs <refs.tsv>] -o <ledger.tsv>
#
# WHAT THIS IS. The Stage 5 slice-loop instrument of the decompose-and-rehost plan (step "replace each
# crossing edge"; the plan is split out of #293 and lands separately). bin/cut-score.sh scores a
# proposed cut at module level;
# this lists the edges of the cut you are actually executing, at document level, and refuses to
# finish while any of them has no decision. "Done" for a slice is not "mx check is green" — a stub
# turns an edge green and carries none of its behaviour — it is "every edge has a row that says
# resolved, stub, handoff or retire, with the evidence".
#
# WHAT IT READS.
#   --catalog   the mxcli catalog of the SOURCE app (.mxcli/catalog.db beside the .mpr, written by
#               `mxcli -p <app>.mpr graph-report`, which project-bin/app-facts.sh runs as the
#               mandatory Stage 0 facts step), refs table only. Or --refs: a TSV with the header
#               SourceType SourceName TargetType TargetName RefKind (what --dump-refs writes; the
#               committed fixture form, since a catalog is tens of MB).
#   --slice     one name per line: a module (moves whole) or Module.Doc (a document that moves with
#               the slice although its module stays, e.g. the Synchronization flows of one entity).
#   --rules     tab-separated: direction (out|in|check|*), pattern (fnmatch on the far-side
#               document, or 'OwnSide -> FarSide'), resolution, evidence. First match wins.
#               Resolutions: resolved[:how] · stub · handoff · retire · platform. A row with no
#               matching rule is UNRESOLVED and the run exits 1. A rule with no evidence is refused.
#   --check-log mx check output on the slice package (the exporter's self-check, Mendix 9.24 `mx check`
#               on the package's project.mpr). Every CE1613 name it reports that the catalog did not
#               record becomes a `check-only` row — the catalog does not see widget actions (App
#               events), layout placeholders, or images.
#   --exporter-json  the module-MPK exporter's --json output (export-module-mpk.py, split out of #293
#               and landing separately; any JSON with crossing_refs_by_module works): each module it counts
#               that has no out-edge row is printed as `exporter-only` (a false positive or a
#               catalog blind spot — read which).
#   --extra     rows no catalog holds, verbatim (direction, kind, source_doc, target_doc, refs,
#               resolution, evidence): second-order edges of a module brought along to satisfy an
#               edge, app-level settings the package scrubs, Java hand-off edits.
#
# WHAT IT WRITES. <ledger.tsv>: edge, direction, kind, source_doc, target_doc, refs, resolution,
# evidence. Out = the slice uses something that stays behind; in = something that stays behind uses
# the slice (the monolith-side work of the strangler). System is auto-resolved as platform.
#
# WHAT IT CANNOT SEE. Whether the resolution works: that is the target's mx check and mxbuild, and
# for a stub it never is — the evidence column says what the stub does not carry. Java and
# JavaScript bodies naming another module, and references by string (deep links, REST paths).
#
# Exit: 0 every row has a resolution · 1 at least one UNRESOLVED row (and only that) · 2 bad arguments,
#       an unreadable input (missing file, not a catalog, malformed JSON) or a malformed --refs line
#
# Field run: public field-service template app 9.24.2 -> its NativeNote slice into Mendix 11.13.0
# (2026-10-12): 346 crossing refs -> 308 ledger rows, 0 UNRESOLVED, 0.15 s. A captured subset of that
# run's inputs and ledger is the fixture: tests/wave2/fixtures/cut-ledger/ (test-cut-ledger.sh).
#
# LAYOUT. Every input is an explicit path (no .mpr discovery), so single-tree vs two-tree (`app/`)
# only changes the --catalog argument: <project>/.mxcli/catalog.db or <project>/app/.mxcli/catalog.db.
#
# portability-ok: bash 3.2, Python 3 resolved through portable.sh

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/portable.sh"
require_py

case "${1:-}" in
  -h|--help|"") sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; [ -z "${1:-}" ] && exit 2; exit 0 ;;
esac

"$PY" -I "$HERE/lib/cut-ledger.py" "$@"
rc=$?
[ "$rc" -gt 1 ] && exit 2
exit "$rc"
