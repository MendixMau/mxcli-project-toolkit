#!/usr/bin/env bash
# test-progress-harness-verify.sh: a HARNESS row whose Step runs `verify-module.sh <Module>` is read
# from evidence as well as from its State cell, in architecture/progress-report.html
# (project-bin/build-plan-status.sh --html, which embeds project-bin/progress-report.py).
#
# Review case (MendixMau, 2026-10-21): the agent ran `bin/verify-module.sh <Module>` and never
# edited State. The row's Pass (brd-to-build-plan.md, the module-close row) is a clean summary AND
# LOOK + CONFIRM, so the report promotes only on both, and flags everything short of that.
#
#   H1  clean + fresh summary and a LOOK report "2 of 2" with 2 PROOF-OF-LOOK screenshots:
#       "built (verified 2026-10-20, LOOK 2/2)", flagged against State, counted (4 of 9 built)
#   H2  State built, no summary: "built? no verify summary"
#   H3  a summary with a FINDING: not promoted
#   H4  a --skip-journeys summary: not promoted
#   H5  a clean summary older than a BUILD-LOG row of a script the row depends on:
#       "verify stale (summary 2026-10-20, 1 execs since)", not promoted
#   H6  clean and fresh, but the module's LOOK report says 1 of 2: "LOOK + CONFIRM owed", not promoted
#   H7  H1 on a two-tree checkout (.mpr under app/)
#
# Captured inputs (fixtures/verify-446/): the summaries were written by project-bin/verify-module.sh
# itself (instruments stubbed, CAPTURE=<dir> bash test-verify-module-446.sh); BUILD-LOG.captured.md
# was written by project-bin/exec.sh (stubbed mxcli/mxbuild), and its one data row is reused here
# with only the time and the script name replaced. The plan and the LOOK reports are authored by
# agents, not output of a tool, so they are written here.
#
# Usage: bash tests/wave2/test-progress-harness-verify.sh /path/to/build-plan-status.sh
set -uo pipefail
SCRIPT="${1:?usage: bash tests/wave2/test-progress-harness-verify.sh /path/to/build-plan-status.sh}"
case "$SCRIPT" in /*) ;; *) SCRIPT="$PWD/$SCRIPT" ;; esac
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FX="$TK/tests/wave2/fixtures/verify-446"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/progress-harness.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export TZ=UTC
# shellcheck disable=SC1091
. "$TK/bin/lib/portable.sh"
PY="$(resolve_py 2>/dev/null || true)"
if [ -z "$PY" ]; then echo "SKIP: no Python 3 found"; echo "PASS=0 FAIL=0"; exit 0; fi
EMPTY="$WORK/cfg"; mkdir -p "$EMPTY/projects"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; }

summary() {  # $1 root, $2 module, $3 golden
  mkdir -p "$1/.claude/loop/verify/$2"; cp "$FX/$3.summary.tsv" "$1/.claude/loop/verify/$2/summary.tsv"
  touch -t 202610200900 "$1/.claude/loop/verify/$2/summary.tsv"
}
logrow() {  # $1 ISO time, $2 script: the captured exec.sh row with its time and script replaced
  grep '^| 20' "$FX/BUILD-LOG.captured.md" | head -1 \
    | sed -e "s/^| [^|]* | \`[^\`]*\` |/| $1 | \`$2\` |/"
}
shot() { mkdir -p "$(dirname "$1")"; head -c 12000 /dev/zero > "$1"; }

mkproj() {  # $1 root, $2 mpr relpath -> writes the page, sets H
  local R="$1"
  mkdir -p "$R/architecture" "$R/docs" "$(dirname "$R/$2")"; : > "$R/$2"
  cat > "$R/architecture/build-plan.md" <<'MD'
# Build plan

### Phase 1 - Orders

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 1 | BUILD | `01-orders.mdl` | entities | - | - | built |
| 2 | HARNESS | `bin/verify-module.sh Orders`, then LOOK + CONFIRM per `module-review.md` | summary has no FAULT; N of N pages reviewed | 1 | `module-review.md` | not built |
| 3 | HARNESS | `bin/verify-module.sh Billing`, then LOOK + CONFIRM per `module-review.md` | summary has no FAULT; N of N pages reviewed | 1 | `module-review.md` | built |
| 4 | HARNESS | `bin/verify-module.sh Stock`, then LOOK + CONFIRM per `module-review.md` | summary has no FAULT; N of N pages reviewed | 1 | `module-review.md` | not built |
| 5 | HARNESS | `bin/verify-module.sh Shipping`, then LOOK + CONFIRM per `module-review.md` | summary has no FAULT; N of N pages reviewed | 1 | `module-review.md` | not built |
| 6 | BUILD | `05-invoices.mdl` | invoice pages | 1 | - | built |
| 7 | HARNESS | `bin/verify-module.sh Invoices`, then LOOK + CONFIRM per `module-review.md` | summary has no FAULT; N of N pages reviewed | 6 | `module-review.md` | not built |
| 8 | HARNESS | `bin/verify-module.sh Returns`, then LOOK + CONFIRM per `module-review.md` | summary has no FAULT; N of N pages reviewed | 1 | `module-review.md` | not built |
| 9 | HARNESS | `process-coherence-pass.md` on Orders, Stock | chains hold | 2, 4 | `process-coherence-pass.md` | not built |
MD
  summary "$R" Orders clean; summary "$R" Stock finding; summary "$R" Shipping skip-journeys
  summary "$R" Invoices clean; summary "$R" Returns clean
  { sed -n '1,/^|---|/p' "$FX/BUILD-LOG.captured.md"
    logrow 2026-10-19T09:00:00+0000 01-orders.mdl
    logrow 2026-10-20T10:00:00+0000 05-invoices.mdl; } > "$R/docs/BUILD-LOG.md"
  local U="$R/design/ui-reviews"
  shot "$U/shots/orders-a.png"; shot "$U/shots/orders-b.png"; shot "$U/shots/returns-a.png"
  printf '<p>2 of 2 pages reviewed: Orders. VALID AT: 1234567</p>\n<p>PROOF-OF-LOOK: Orders.Order_List = shots/orders-a.png</p>\n<p>PROOF-OF-LOOK: Orders.Order_Edit = shots/orders-b.png</p>\n' > "$U/ui-review-2026-10-20.html"
  printf '<p>1 of 2 pages reviewed: Returns. VALID AT: 1234567</p>\n<p>PROOF-OF-LOOK: Returns.Return_List = shots/returns-a.png</p>\n' > "$U/ui-review-2026-10-20-returns.html"
  CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$R" --html --quiet >/dev/null 2>&1
  H="$(cat "$R/architecture/progress-report.html" 2>/dev/null)"
}
cell() { printf '%s' "$H" | grep -o "<td>$1</td><td>HARNESS</td>.*" | head -1; }
nopromo() { ! printf '%s' "$1" | grep -q 'verified\|st-built'; }

for layout in single two; do
  R="$WORK/$layout"; [ "$layout" = single ] && mkproj "$R" App.mpr || mkproj "$R" app/App.mpr
  c2="$(cell 2)"
  id=H1; [ "$layout" = two ] && id=H7
  { printf '%s' "$c2" | grep -q 'built (verified 2026-10-20, LOOK 2/2)' && printf '%s' "$c2" | grep -q 'drift.*State says not built' \
      && printf '%s' "$H" | grep -q '4 of 9 rows built'; } \
    && ok "$id ($layout tree): clean + fresh + LOOK 2/2 promotes the close row, flagged, 4 of 9 built" \
    || bad "$id ($layout tree): row 2" "$c2 $(printf '%s' "$H" | grep -o '[0-9]* of 9 rows built' | head -1)"
  [ "$layout" = single ] || continue
  c3="$(cell 3)"; c4="$(cell 4)"; c5="$(cell 5)"; c7="$(cell 7)"; c8="$(cell 8)"
  printf '%s' "$c3" | grep -q 'built? no verify summary' \
    && ok "H2: State built with no summary reads 'built? no verify summary'" || bad "H2: row 3" "$c3"
  nopromo "$c4" && ok "H3: a FINDING summary does not promote" || bad "H3: row 4 promoted" "$c4"
  nopromo "$c5" && ok "H4: a --skip-journeys summary does not promote" || bad "H4: row 5 promoted" "$c5"
  { nopromo "$c7" && printf '%s' "$c7" | grep -q 'verify stale (summary 2026-10-20, 1 execs since)'; } \
    && ok "H5: a summary older than its dependency's exec reads 'verify stale', not promoted" || bad "H5: row 7" "$c7"
  { nopromo "$c8" && printf '%s' "$c8" | grep -q 'verify clean 2026-10-20 .* LOOK + CONFIRM owed'; } \
    && ok "H6: clean and fresh, LOOK 1 of 2: 'LOOK + CONFIRM owed', not promoted" || bad "H6: row 8" "$c8"
done

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
