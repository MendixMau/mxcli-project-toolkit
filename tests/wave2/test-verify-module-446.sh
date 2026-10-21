#!/usr/bin/env bash
# Usage: bash test-verify-module-446.sh [path-to-verify-module.sh]
#
# Fixture for the verify-module.sh instrument faults in #446. Every instrument is a stub in the
# project's own bin/ (the copy _tool() prefers), so a full run takes seconds and needs no app,
# no mxcli and no browser. The page scope is a real page-scope.sh output, captured from a public
# mxcli test model with a page-less module added (fixtures/verify-446/page-scope.json; only the
# machine paths in provenance.commands were replaced).
#
#   V1  a module with 0 pages in the page scope and no journey JSON: journeys is N/A (SKIPPED),
#       not a FAULT
#   V2  a module with pages, no journey JSON, and tests/<module>*.test.sh: the FAULT names the
#       tests that exist in another shape
#   V3  playwright not resolvable from tests/e2e: ONE fault row naming the one fix; journeys and
#       monkey are SKIPPED as its dependents; the design audit runs static-only
#   V4  the coverage rung's default budget is 1200 s, not 300 s (by inspection)
#   V5  no watchdog `sleep` outlives the run (they held fd 3, so `| tee` waited up to 30 min)
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="${1:-$TK/project-bin/verify-module.sh}"
[ -f "$SUT" ] || { echo "usage: $0 /path/to/verify-module.sh" >&2; exit 2; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
GOLD="$TK/tests/wave2/fixtures/verify-446/page-scope.json"
SD="$(cd "$(dirname "$SUT")" && pwd)"

PASS=0; FAIL=0
ok()  { echo "  ok   — $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL — $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/         /'; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/vm446.XXXXXX")"; WORK="$(cd "$WORK" && pwd -P)"; trap 'rm -rf "$WORK"' EXIT
P="$WORK/proj"
mkdir -p "$P/bin" "$P/app" "$P/tests/e2e" "$P/journeys" "$P/node_modules/playwright" "$WORK/stub"
: > "$P/app/App.mpr"; printf '# PROJECT\n' > "$P/PROJECT.md"
cp "$SD/_common.sh" "$SUT" "$P/bin/"
printf '#!/usr/bin/env bash\necho "App serving on http://localhost:8080"\nexit 0\n' > "$P/bin/test-stack-up.sh"
for s in conformance-check.sh graph-sweep.sh coverage-preflight.sh review-module.sh; do
  printf '#!/usr/bin/env bash\necho "stub %s: clean"\nexit 0\n' "$s" > "$P/bin/$s"
done
printf '#!/usr/bin/env bash\nmkdir -p "$PROJECT_ROOT/.claude/loop" && cp "%s" "$PROJECT_ROOT/.claude/loop/page-scope.json"\n' "$GOLD" > "$P/bin/page-scope.sh"
chmod +x "$P"/bin/*.sh
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/stub/cov.sh"; chmod +x "$WORK/stub/cov.sh"
for j in journey-runner monkey design-audit; do printf 'console.log("stub %s", process.argv.slice(2).join(" "));\n' "$j" > "$P/tests/e2e/$j.js"; done
printf 'const fs=require("fs");fs.mkdirSync("docs",{recursive:true});fs.writeFileSync("docs/report.json","{}");\n' > "$WORK/stub/norm.js"
printf 'const fs=require("fs");fs.mkdirSync("docs/verification",{recursive:true});fs.writeFileSync("docs/verification/report.html","<p>");\n' > "$WORK/stub/rend.js"
printf '{"name":"playwright","main":"index.js"}\n' > "$P/node_modules/playwright/package.json"
printf 'module.exports = {};\n' > "$P/node_modules/playwright/index.js"

# Sleeping processes left behind with their cwd in the project (Linux /proc only; else "skip").
leftover() {
  [ -d /proc/self ] || { echo skip; return; }
  local n=0 p
  for p in /proc/[0-9]*; do
    [ "$(readlink "$p/cwd" 2>/dev/null)" = "$P" ] && [ "$(cat "$p/comm" 2>/dev/null)" = sleep ] && n=$((n+1))
  done
  echo "$n"
}
reap() {  # a run on the old subject leaves watchdog sleeps behind: end them, never anyone else's
  [ -d /proc/self ] || return 0
  local p; for p in /proc/[0-9]*; do
    [ "$(readlink "$p/cwd" 2>/dev/null)" = "$P" ] && [ "$(cat "$p/comm" 2>/dev/null)" = sleep ] && kill "${p#/proc/}" 2>/dev/null
  done; return 0
}
trap 'reap; rm -rf "$WORK"' EXIT

vm() {  # $1 module -> out, rc, sum. Output goes to a file: on the pre-#446 subject a $(...) here
        # waited for the orphaned watchdog sleeps, up to 30 minutes.
  ( cd "$P" && PROJECT_ROOT="$P" COVERAGE_CHECK="$WORK/stub/cov.sh" REPORT_NORMALIZE_JS="$WORK/stub/norm.js" \
    REPORT_RENDER_JS="$WORK/stub/rend.js" bash "$P/bin/verify-module.sh" "$1" ) > "$WORK/out" 2>&1; rc=$?
  out="$(cat "$WORK/out")"
  sum="$(cat "$P/.claude/loop/verify/$1/summary.tsv" 2>/dev/null)"
}
row() { printf '%s\n' "$sum" | awk -F'\t' -v n="$1" '$1 ~ n { print $2 "\t" $5 }'; }

vm Svc
left="$(leftover)"
case "$left" in
  skip) echo "  skip — V5: no /proc on this platform" ;;
  0)    ok "V5: no watchdog sleep outlives the run (a pipe on its output closes with the verdict)" ;;
  *)    bad "V5: $left watchdog sleep(s) still running after the run, holding its output open" ;;
esac
reap
{ row '^journeys$' | grep -q '^SKIPPED	(N/A: Svc has 0 pages' && ! printf '%s' "$sum" | grep -q '^journeys	FAULT'; } \
  && ok "V1: page-less module, journeys N/A (SKIPPED), not FAULT (rc $rc)" || bad "V1: journeys row" "$(row '^journeys')"

printf '#!/usr/bin/env bash\n# playwright-cli checks\n' > "$P/tests/myfirstmodule.test.sh"
vm MyFirstModule
{ row '^journeys$' | grep -q '^FAULT' && printf '%s' "$out" | grep -q 'another shape.*tests/myfirstmodule.test.sh'; } \
  && ok "V2: no journey JSON, the FAULT names tests/myfirstmodule.test.sh (another shape)" \
  || bad "V2: other-shape tests not named" "$(printf '%s\n' "$out" | grep -A2 'journeys')"

printf '{"name":"golden"}\n' > "$P/journeys/MyFirstModule.journey.json"
rm -rf "$P/node_modules"
vm MyFirstModule
pw="$(printf '%s\n' "$sum" | grep -c '^playwright')"
{ [ "$pw" = 1 ] && row '^playwright' | grep -q '^FAULT' && printf '%s' "$out" | grep -q 'npm install playwright' \
    && row '^journeys$' | grep -q '^SKIPPED	(not run: needs playwright' && row '^monkey$' | grep -q '^SKIPPED	(not run: needs playwright' \
    && printf '%s' "$sum" | grep -q '^design audit.*static-only'; } \
  && ok "V3: one playwright FAULT with the fix; journeys + monkey SKIPPED as dependents; design audit static-only" \
  || bad "V3: playwright rows=$pw" "$sum"

grep -q 'VM_TMO_COVERAGE:-1200' "$SUT" && ! grep -q 'VM_TMO_COVERAGE:-300' "$SUT" \
  && ok "V4: coverage rung default budget is 1200 s" || bad "V4: coverage budget still 300 s"

echo ""
echo "SCORE: $PASS/$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
