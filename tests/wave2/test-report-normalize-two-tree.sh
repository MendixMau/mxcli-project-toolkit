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
# Case 1 is that shape in miniature; case 2 is the single-tree regression guard; case 3 reads
# per-BRD conformance reports (report-<date>-<BRD>.tsv, PR #307). Case 4 (#659) reads verify-module
# summary rows, in both layouts: a FAULT row's reason from its `(…)` cell or, failing that, from
# the last SETUP line of its log; `0s` is elapsed, not the log path.
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

# --- 3. per-BRD conformance reports (conformance-check writes report-<date>-<BRD>.tsv) ---------
# Golden: fixtures/conformance-per-brd/ — conformance-check.sh's real output on PR #307's own
# per-BRD fixture layout (see its CAPTURE.txt), including a BRD id with a space. The newest date
# wins and every file of that date is read; the older single-file report is not mixed in (it
# used to be the ONLY file read, shown as measured although stale).
GOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/conformance-per-brd"
P="$WORK/perbrd"; lay_out "$P" "$P"
rm -f "$P/docs/conformance/"report-*.tsv
cp "$GOLD"/report-*.tsv "$P/docs/conformance/"
printf 'module\tpointer\tstored\tobserved\tverdict\nStale\t`/old`\tbuilt\tPRESENT\tOK\n' > "$P/docs/conformance/report-2026-09-26.tsv"
( cd "$P/tests/e2e" && node report-normalize.js --out docs/report.json ) >"$WORK/out3" 2>&1
if [ -s "$P/docs/report.json" ]; then
  got="$(node -e 'const r=require(process.argv[1]); const c=r.checks.filter(c=>c.instrument==="conformance"&&c.kind==="conformance");
    console.log([c.length, [...new Set(c.map(x=>x.module))].sort().join(","), c.every(x=>x.requirement && x.requirement.startsWith("/")), c.some(x=>/shipping/i.test(x.id))].join("|"))' "$P/docs/report.json")"
  [ "$got" = "6|Orders,Shipping|true|true" ] \
    && ok "all 3 per-BRD reports of the newest date read (6 rows, incl. 'F003 shipping'); every row keeps its /pointer requirement; the stale file is not read" \
    || bad "per-BRD conformance reports not read as captured (rows|modules|requirements set|space BRD read)" "$got"
else
  bad "per-BRD: no docs/report.json" "$(tr '\n' ' ' < "$WORK/out3" | cut -c1-300)"
fi

# --- 4. verify-module FAULT rows carry their reason (#659) --------------------------------------
# Golden: fixtures/verify-659/ — the real verify-module.sh's summary.tsv for the hoisted credentials
# FAULT, and for the real journey-runner aborting in its preflight (reason only in 20-journeys.log),
# see its CAPTURE.txt. Before: 2 FAULT rows printed "no reason recorded", and every `0s` elapsed
# cell was read as the log path.
G659="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/verify-659"
for layout in one two; do
  L="$WORK/v659-$layout"
  if [ "$layout" = two ]; then lay_out "$L/app" "$L"; else lay_out "$L" "$L"; fi
  mkdir -p "$L/.claude/loop/verify/MyFirstModule" "$L/.claude/loop/verify/Cred"
  cp "$G659/runner-setup.summary.tsv" "$L/.claude/loop/verify/MyFirstModule/summary.tsv"
  cp "$G659/20-journeys.log.txt" "$L/.claude/loop/verify/MyFirstModule/20-journeys.log"
  cp "$G659/credentials.summary.tsv" "$L/.claude/loop/verify/Cred/summary.tsv"
  ( cd "$L/tests/e2e" && node report-normalize.js --out docs/report.json ) >"$WORK/out4" 2>&1
  if [ ! -s "$L/docs/report.json" ]; then bad "$layout-tree: no docs/report.json" "$(tr '\n' ' ' < "$WORK/out4" | cut -c1-300)"; continue; fi
  got="$(node -e 'const r=require(process.argv[1]); const f=n=>r.instruments.find(i=>i.name===n)||{};
    const c=f("verify-loop/Cred/e2e credentials"), j=f("verify-loop/MyFirstModule/journeys (UI + ordered spans + data effects)"),
          s=f("verify-loop/MyFirstModule/stack (test-stack-up --check)"), k=f("verify-loop/Cred/journeys");
    console.log(JSON.stringify({c:[c.verdict,c.reason], j:[j.verdict,j.reason,j.log,j.elapsedSec], s:[s.log,s.elapsedSec], k:[k.verdict,k.log,k.reason]}))' "$L/docs/report.json")"
  case "$got" in *'"c":["fault","credentials: TEST_PASS unset, template placeholder password"]'*)
    ok "$layout-tree: a fault() row's (reason) cell is the instrument reason" ;; *) bad "$layout-tree: credentials FAULT reason" "$got" ;; esac
  case "$got" in *'"j":["fault","SETUP  env: missing MXTK_FIXTURE_UNSET_VAR (needed by J-01)'*'",".claude/loop/verify/MyFirstModule/20-journeys.log",0]'*)
    ok "$layout-tree: a FAULT row with only a log path gets the log's last SETUP line as its reason; log and elapsed intact" ;;
    *) bad "$layout-tree: journeys FAULT reason from log" "$got" ;; esac
  case "$got" in *'"s":[".claude/loop/verify/MyFirstModule/00-stack.log",0]'*) ok "$layout-tree: \`0s\` is elapsed (0), not the log path" ;;
    *) bad "$layout-tree: elapsed with a trailing s read as the log" "$got" ;; esac
  case "$got" in *'"k":["skipped",null,"not run: credentials, see the e2e credentials row"]'*) ok "$layout-tree: a SKIPPED row's (reason) cell is its reason, not its log" ;;
    *) bad "$layout-tree: SKIPPED row reason/log" "$got" ;; esac
  if grep -q 'no reason recorded' "$WORK/out4"; then bad "$layout-tree: a FAULT still prints 'no reason recorded'" "$(grep 'no reason recorded' "$WORK/out4")"
  else ok "$layout-tree: no FAULT prints 'no reason recorded'"; fi
done

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
