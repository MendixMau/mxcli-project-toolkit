#!/usr/bin/env bash
# Usage: bash test-report-normalize-two-tree.sh [path-to-report-normalize.js]
#
# Fixture for project-tests/e2e/report-normalize.js's path resolution in the two-tree layout
# (model under app/, docs/ architecture/ tests/e2e/ .claude/loop/ at the repo root — F-042).
#
# The defect (card-disbursement requirements-driven build, 2026-09-26): every INPUT resolved
# against project.config's ROOT, which is app/ in a two-tree checkout. verify-module's report
# step then showed 8 of 9 instruments FAULT ("design-audit.json does not exist", "no
# coverage-ledger.md under architecture/modules/*/") over artefacts that were on disk, and wrote
# the report into a stray app/docs/report.json — so the render step found nothing to render.
# Case 1 is that shape in miniature; case 2 is the single-tree regression guard.
#
# The artefacts here are SYNTHETIC and minimal. That is deliberate and allowed: the field-proof
# rule's "golden input is captured" governs parsers of tool output, and nothing below exercises a
# parser — it lays out files and asserts WHERE the script reads and writes. The field run that
# motivated it (0 checks → 205 checks read) is cited in CHANGELOG.md.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/report-normalize.js"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
CFG="$(cd "$(dirname "$SUT")" && pwd)/project.config.template.js"
[ -f "$CFG" ] || CFG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/project.config.template.js"
[ -f "$CFG" ] || { echo "FAIL — project.config.template.js not found beside $SUT"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rn-two-tree.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# lay_out <model-dir> <project-dir>: the harness and every non-model artefact under <project-dir>.
lay_out() {
  local m="$1" p="$2"
  mkdir -p "$m" "$p/tests/e2e/artifacts" "$p/tests/e2e/journeys" "$p/architecture/modules/Orders" "$p/docs/conformance"
  : > "$m/Orders.mpr"
  cp "$SUT" "$p/tests/e2e/report-normalize.js"
  cp "$CFG" "$p/tests/e2e/project.config.js"
  echo '{"checks":[]}' > "$p/tests/e2e/artifacts/design-audit.json"
  printf '# Coverage ledger — Orders\n' > "$p/architecture/modules/Orders/coverage-ledger.md"
  printf 'module\tclaim\tstatus\n' > "$p/docs/conformance/report-2026-09-26.tsv"
  echo '{"id":"J-01","steps":[]}' > "$p/tests/e2e/journeys/Orders.journey.json"
}
# reason <report.json> <instrument> → "<verdict>|<reason>"
reason() { node -e 'const r=require(process.argv[1]); const x=r.instruments.find(i=>i.name===process.argv[2]); console.log(x ? `${x.verdict}|${x.reason||""}` : "ABSENT|")' "$1" "$2"; }

# --- 1. two-tree: inputs found beside app/, output written at the repo root ------------------
T="$WORK/two"; lay_out "$T/app" "$T"
( cd "$T/tests/e2e" && JOURNEY_DIR="$T/tests/e2e/journeys" node report-normalize.js --out docs/report.json ) >"$WORK/out1" 2>&1
if [ -s "$T/docs/report.json" ]; then ok "report written at the repo root's docs/report.json"
else bad "no docs/report.json at the repo root" "$(tr '\n' ' ' < "$WORK/out1" | cut -c1-300)"; fi
if [ -e "$T/app/docs" ]; then bad "stray app/docs/ created (the 2026-09-26 misplaced report)"; else ok "no stray app/docs/"; fi
# Wherever it landed, still measure what it read — the misplaced write and the missed reads are
# two defects, and the old code shows both.
R="$T/docs/report.json"; [ -s "$R" ] || R="$T/app/docs/report.json"
if [ -s "$R" ]; then
  v="$(reason "$R" design-audit)"
  case "$v" in *"does not exist"*|ABSENT*) bad "design-audit.json beside app/ read as missing" "$v" ;;
                *) ok "tests/e2e/artifacts/design-audit.json found beside app/ ($v)" ;; esac
  v="$(reason "$R" coverage-ledger)"
  case "$v" in *"no coverage-ledger.md"*|ABSENT*) bad "architecture/modules ledger read as missing" "$v" ;;
                *) ok "architecture/modules/*/coverage-ledger.md found beside app/" ;; esac
  v="$(reason "$R" conformance)"
  case "$v" in *"does not exist"*|ABSENT*) bad "docs/conformance report read as missing" "$v" ;;
                *) ok "docs/conformance report found beside app/" ;; esac
  node -e 'const r=require(process.argv[1]); process.exit(r.project && r.project.mprModifiedAt ? 0 : 1)' "$R" \
    && ok "the .mpr is still resolved inside app/ (mprModifiedAt set)" || bad "the .mpr under app/ was lost"
  node -e 'const r=require(process.argv[1]); const c=(r.coverage||[]).find(m=>m.module==="Orders"); process.exit(c && (c.journeys||[]).includes("J-01") ? 0 : 1)' "$R" \
    && ok "JOURNEY_DIR (absolute, as verify-module passes it) is read: Orders lists J-01" \
    || bad "journey contracts under JOURNEY_DIR not read"
else
  bad "no report to inspect — the five two-tree read assertions did not run"
fi

# --- 2. single tree (regression): everything at the root, nothing moves ----------------------
S="$WORK/one"; lay_out "$S" "$S"
( cd "$S/tests/e2e" && node report-normalize.js --out docs/report.json ) >"$WORK/out2" 2>&1
if [ -s "$S/docs/report.json" ]; then
  v="$(reason "$S/docs/report.json" design-audit)"
  case "$v" in *"does not exist"*|ABSENT*) bad "single tree: design-audit.json read as missing" "$v" ;;
                *) ok "single tree: report at docs/, design-audit.json found" ;; esac
else
  bad "single tree: no docs/report.json" "$(tr '\n' ' ' < "$WORK/out2" | cut -c1-300)"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
