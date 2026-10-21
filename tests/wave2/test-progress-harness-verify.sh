#!/usr/bin/env bash
# test-progress-harness-verify.sh: a HARNESS row whose Step runs `verify-module.sh <Module>` is read
# from that module's verify summary as well as from its State cell, in architecture/progress-report.html
# (project-bin/build-plan-status.sh --html, which embeds project-bin/progress-report.py).
#
# Review case (MendixMau, 2026-10-21): the agent ran `bin/verify-module.sh <Module>` and never
# edited State, so the report kept the module-close row "not built" with a clean summary on disk.
#
#   H1  State "not built" + a summary with no FAULT: shown "built (verified <date>)" with a drift
#       flag, and counted built (3 of 5); a FAULT summary and a non-verify HARNESS row keep State
#   H2  State "built" + no summary: shown "built? no verify summary"
#   H3  the same on a two-tree checkout (.mpr under app/)
#
# The summaries are captured: written by project-bin/verify-module.sh itself (instruments stubbed,
# see test-verify-module-446.sh), fixtures/verify-446/{clean,fault}.summary.tsv. The plan is
# hand-written, which is allowed: build-plan.md is authored by agents, not output of a tool.
#
# Usage: bash tests/wave2/test-progress-harness-verify.sh /path/to/build-plan-status.sh
set -uo pipefail
SCRIPT="${1:?usage: bash tests/wave2/test-progress-harness-verify.sh /path/to/build-plan-status.sh}"
case "$SCRIPT" in /*) ;; *) SCRIPT="$PWD/$SCRIPT" ;; esac
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FX="$TK/tests/wave2/fixtures/verify-446"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/progress-harness.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# shellcheck disable=SC1091
. "$TK/bin/lib/portable.sh"
PY="$(resolve_py 2>/dev/null || true)"
if [ -z "$PY" ]; then echo "SKIP: no Python 3 found"; echo "PASS=0 FAIL=0"; exit 0; fi
EMPTY="$WORK/cfg"; mkdir -p "$EMPTY/projects"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; }

mkproj() {  # $1 root, $2 mpr relpath -> writes the page, sets H
  local R="$1"
  mkdir -p "$R/architecture" "$(dirname "$R/$2")"; : > "$R/$2"
  cat > "$R/architecture/build-plan.md" <<'MD'
# Build plan

### Phase 1 - Orders

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 1 | BUILD | `01-orders.mdl` | entities | - | - | built |
| 2 | HARNESS | `bin/verify-module.sh Orders`, then LOOK + CONFIRM per `module-review.md` | summary has no FAULT | 1 | `module-review.md` | not built |
| 3 | HARNESS | `bin/verify-module.sh Billing`, then LOOK + CONFIRM per `module-review.md` | summary has no FAULT | 1 | `module-review.md` | built |
| 4 | HARNESS | `bin/verify-module.sh Stock`, then LOOK + CONFIRM per `module-review.md` | summary has no FAULT | 1 | `module-review.md` | not built |
| 5 | HARNESS | `process-coherence-pass.md` on Orders, Stock | chains hold | 2, 4 | `process-coherence-pass.md` | not built |
MD
  mkdir -p "$R/.claude/loop/verify/Orders" "$R/.claude/loop/verify/Stock"
  cp "$FX/clean.summary.tsv" "$R/.claude/loop/verify/Orders/summary.tsv"
  cp "$FX/fault.summary.tsv" "$R/.claude/loop/verify/Stock/summary.tsv"
  touch -t 202610200930 "$R/.claude/loop/verify/Orders/summary.tsv"
  CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$R" --html --quiet >/dev/null 2>&1
  H="$(cat "$R/architecture/progress-report.html" 2>/dev/null)"
}
cell() { printf '%s' "$H" | grep -o "<td>$1</td><td>HARNESS</td>.*" | head -1; }

for layout in single two; do
  R="$WORK/$layout"; [ "$layout" = single ] && mkproj "$R" App.mpr || mkproj "$R" app/App.mpr
  c2="$(cell 2)"; c3="$(cell 3)"; c4="$(cell 4)"; c5="$(cell 5)"
  id=H1; [ "$layout" = two ] && id=H3
  { printf '%s' "$c2" | grep -q 'built (verified 2026-10-20)' && printf '%s' "$c2" | grep -q 'drift.*State says not built' \
      && printf '%s' "$H" | grep -q '3 of 5 rows built' \
      && ! printf '%s' "$c4" | grep -q verified && ! printf '%s' "$c5" | grep -q verified; } \
    && ok "$id ($layout tree): clean summary turns a not-built close row into built (verified 2026-10-20), flagged, 3 of 5 built" \
    || bad "$id ($layout tree): row 2 not read from its summary" "$c2"
  if [ "$layout" = single ]; then
    printf '%s' "$c3" | grep -q 'built? no verify summary' \
      && ok "H2: State built with no summary reads 'built? no verify summary'" || bad "H2: row 3" "$c3"
  fi
done

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
