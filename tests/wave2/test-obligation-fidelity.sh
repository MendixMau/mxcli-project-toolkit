#!/usr/bin/env bash
# Usage: bash tests/wave2/test-obligation-fidelity.sh [path-to-gate-check.sh]
#   (or the bin/lib/obligation-check.sh path directly; run-all.sh passes bin/gate-check.sh and
#   the fixture derives bin/lib/obligation-check.sh from its directory)
#
# test-obligation-fidelity.sh — the fidelity obligation's `names` match against the artifact
# project-bin/page-fidelity.js actually writes.
#
# THE BUG: page-fidelity.js matched the module qualifier in `CREATE PAGE Module.Page` with a
# non-capturing regex group and discarded it, so docs/PAGE-FIDELITY.tsv rows never named the
# module anywhere in the file. bin/lib/obligations.tsv's `fidelity` row is `match=names`
# (bin/lib/obligation-check.sh's `_ob_find`, match=names branch: `grep -qF -- "$unit" "$f"`
# over the WHOLE candidate file) — a row that never mentions the module can never be found, so
# every project's fidelity obligation reported PENDING forever, however many pages were scored.
# The fix adds a `module` column to the TSV that page-fidelity.js writes, so producer and
# consumer agree on where the module name lives. It fails on the pre-fix producer output —
# which is the point of shipping it with the fix (see T3 below).
#
# Run it against obligation-check.sh directly (it supports direct invocation — its own last
# lines: `mxtk_obligations_report "${1:-$(pwd)}"`), not through gate-check.sh: the fidelity
# obligation needs only a module scope unit (architecture/modules/<Name>/) and the TSV artifact,
# neither of which needs a full PROJECT.md/register wiring to exercise.
#
#   tests/wave2/test-obligation-fidelity.sh /path/to/bin/lib/obligation-check.sh
#
# Field run (cited in the commit that ships this): built a scratch project under
# tests/wave2/fixtures/page-fidelity-mocks/ (the repo's own Demo.Demo_Overview mock), ran the
# REAL project-bin/page-fidelity.js against it to append a real TSV row, then ran THIS FILE's
# subject, obligation-check.sh, against that scratch tree and read its actual verdict line —
# not a hand-written TSV row standing in for the producer.
set -uo pipefail

ARG="${1:?usage: test-obligation-fidelity.sh /path/to/bin/gate-check.sh (or /path/to/bin/lib/obligation-check.sh)}"
# run-all.sh can only hand over a bin/-level subject (its candidate list has no bin/lib/), so a
# bin/<anything>.sh argument maps to the lib file beside it; a direct lib path is used as-is.
case "$(basename "$ARG")" in
  obligation-check.sh) OBCHECK="$ARG" ;;
  *) OBCHECK="$(cd "$(dirname "$ARG")" && pwd)/lib/obligation-check.sh" ;;
esac
[ -r "$OBCHECK" ] || { echo "test-obligation-fidelity: no obligation-check.sh at $OBCHECK"; exit 2; }
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
PFJS="$HERE/project-bin/page-fidelity.js"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ob-fid.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# A minimal register-free project: architecture/modules/<Name>/ is what puts a module IN SCOPE
# for a module-scope obligation (_ob_modules, obligation-check.sh) — no PROJECT.md needed, and
# its absence is not the N/A case (that needs architecture/modules/ absent too).
mkproj() {
  d="$WORK/$1"; mkdir -p "$d/architecture/modules/ModuleX" "$d/architecture/modules/ModuleY" "$d/docs"
  echo "$d"
}

run() { "$OBCHECK" "$1" 2>&1 | grep '^Obligation fidelity'; }

echo "== T1: a PAGE-FIDELITY.tsv row naming ModuleX in the module column satisfies fidelity/ModuleX =="
P="$(mkproj t1)"
printf 'date\tpage\tmodule\tscore\theadings\tactions\tcontent\tclasses\tbindings\tsource\twireframe\n' \
  > "$P/docs/PAGE-FIDELITY.tsv"
printf '2026-09-21 00:00\tOverview\tModuleX\t92%%\t3/3\t2/2\t4/4\t5/5\t3/3\tdraft\tdesign/wireframes/Overview.html\n' \
  >> "$P/docs/PAGE-FIDELITY.tsv"
V="$(run "$P")"
case "$V" in
  *'ModuleX'*'PASS'*) bad "unexpected shape (single-module line should not print per-unit): $V" ;;
esac
case "$V" in
  *'NOT DONE:'*ModuleX*) bad "ModuleX reported NOT DONE — module column not matched: $V" ;;
  *'NOT DONE:'*ModuleY*) ok "ModuleX discharged, ModuleY still pending: $V" ;;
  *) bad "unexpected verdict line: $V" ;;
esac

echo "== T2: a module the TSV never mentions (ModuleY) stays PENDING, not falsely PASSed =="
# Same run as T1 — re-asserted on its own so a future change to T1's assertions can't hide this.
case "$V" in
  *PENDING*) ok "overall verdict is PENDING while ModuleY is undischarged" ;;
  *) bad "expected PENDING with ModuleY outstanding, got: $V" ;;
esac

echo "== T3: the PRE-fix shape (module blank/omitted) reproduces the original bug — both modules PENDING =="
P3="$(mkproj t3)"
# The pre-fix producer wrote no module column at all (row = 10 fields: date, page, score,
# headings, actions, content, classes, bindings, source, wireframe). A `names` match against
# the whole file still can't find "ModuleX" anywhere in that row.
printf 'date\tpage\tscore\theadings\tactions\tcontent\tclasses\tbindings\tsource\twireframe\n' \
  > "$P3/docs/PAGE-FIDELITY.tsv"
printf '2026-09-21 00:00\tOverview\t92%%\t3/3\t2/2\t4/4\t5/5\t3/3\tdraft\tdesign/wireframes/Overview.html\n' \
  >> "$P3/docs/PAGE-FIDELITY.tsv"
V3="$(run "$P3")"
case "$V3" in
  *'NOT DONE:'*ModuleX*ModuleY*|*'NOT DONE:'*ModuleY*ModuleX*)
    ok "pre-fix shape (no module column) reproduces the original bug — both modules PENDING: $V3" ;;
  *) bad "pre-fix shape unexpectedly satisfied the obligation (test would not have caught the bug): $V3" ;;
esac

echo "== T4: field run — the REAL page-fidelity.js against the repo's own Demo.Demo_Overview mock =="
if [ ! -r "$PFJS" ]; then
  bad "project-bin/page-fidelity.js not found at $PFJS — cannot field-run the producer"
elif ! command -v node >/dev/null 2>&1; then
  echo "  SKIP no node on PATH — field run not possible in this environment"
else
  FR="$WORK/field-run"
  mkdir -p "$FR/architecture/modules/Demo" "$FR/design/wireframes"
  # page-fidelity.js finds its project root by walking up from the wireframe looking for a
  # .mpr file (bin/page-fidelity.js's own comment: "Project root = nearest directory
  # containing a .mpr"). Under a shared /tmp with other checkouts present, an unstubbed field
  # run can wander past $FR and log against an unrelated ancestor's .mpr instead of $FR/docs
  # — this stub makes root resolution land on $FR deterministically, independent of whatever
  # else happens to be under $TMPDIR right now.
  : > "$FR/Scratch.mpr"
  cp "$HERE/tests/wave2/fixtures/page-fidelity-mocks/grouped-overview.html" \
     "$FR/design/wireframes/Demo_Overview.html"
  ( cd "$FR" && node "$PFJS" design/wireframes/Demo_Overview.html Demo_Overview \
      "$HERE/tests/wave2/fixtures/page-fidelity-mocks/demo-overview.mdl" >/dev/null 2>&1 )
  if [ ! -s "$FR/docs/PAGE-FIDELITY.tsv" ]; then
    bad "field run: page-fidelity.js produced no docs/PAGE-FIDELITY.tsv"
  else
    ROW="$(tail -1 "$FR/docs/PAGE-FIDELITY.tsv")"
    # The file leads with `#`-comment lines (see the producer's own header block) before the
    # tab-separated column header, so find that line rather than assuming it's line 1.
    HDR="$(grep -m1 -v '^#' "$FR/docs/PAGE-FIDELITY.tsv")"
    case "$HDR" in
      *$'\t'module$'\t'*) ok "field run: the real producer's header carries a module column" ;;
      *) bad "field run: producer header has no module column: $HDR" ;;
    esac
    case "$ROW" in
      *$'\t'Demo$'\t'*) ok "field run: the real producer wrote module=Demo into its own row" ;;
      *) bad "field run: producer row does not name the module: $ROW" ;;
    esac
    VF="$(run "$FR")"
    case "$VF" in
      *'NOT DONE:'*Demo*) bad "field run: obligation-check.sh still can't find Demo in the real producer's output: $VF" ;;
      *) ok "field run: obligation-check.sh, run against real producer output, does not list Demo as NOT DONE: $VF" ;;
    esac
  fi
fi

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
