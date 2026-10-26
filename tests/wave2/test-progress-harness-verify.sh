#!/usr/bin/env bash
# test-progress-harness-verify.sh: a HARNESS row whose Step runs `verify-module.sh <Module>` is the
# module's sign-off. In architecture/progress-report.html (project-bin/build-plan-status.sh --html,
# which embeds project-bin/progress-report.py) it is read from evidence as well as from its State
# cell, and shown ONCE, as that module's status on the phase card, never as a build row.
#
# Review case (MendixMau, 2026-10-21): the agent ran `bin/verify-module.sh <Module>` and never
# edited State. The row's Pass (brd-to-build-plan.md, the module-close row) is a clean summary AND
# LOOK + CONFIRM, so the status says Verified only on both, and names everything short of that.
# Decision (MendixMau, 2026-10-21): HARNESS rows are not counted as built rows, and the verify row
# is a module status, not a row of the list. build-plan.json keeps every row for the agents.
#
# Every case runs on a single-tree and a two-tree checkout (.mpr under app/):
#   H1  clean + fresh summary and a LOOK report "2 of 2" with 2 PROOF-OF-LOOK screenshots:
#       "Verified ✓ 2026-10-20 (LOOK 2/2)", flagged against State (not built)
#   H2  State built, no summary: "built? no verify summary"
#   H3  a summary with a FINDING: "Verify not clean", never Verified
#   H4  a --skip-journeys summary: "Verify not clean", never Verified
#   H5  a clean summary older than a BUILD-LOG row of a script the row depends on:
#       "Verify stale (1 build since)"
#   H6  clean and fresh, but the module's LOOK report says 1 of 2: "Verify owed - LOOK + CONFIRM"
#       (the page writes every em dash as " - ")
#   H8  no summary, State not built: "Verify not run"
#   H9  clean + fresh + LOOK 2/2 but State "pending a person": "held", never Verified, not counted
#   H10 stale only by a done- file newer than the summary (no BUILD-LOG row):
#       "Verify stale (a script was marked done- after it)", never "0 builds since"
#   N1  counts leave HARNESS rows out: 4 of 5 rows built (plan card, lede, Phase 1 2 of 2)
#   N2  one status per module, 9 in all, and none for Catalog, a module with no HARNESS row
#   N3  no verify-module.sh row in the rendered row lists; the coherence HARNESS row stays, "(not counted)"
#   N4  agent-facing output keeps the step: build-plan.json lists all 10 HARNESS rows with their Step,
#       and its phase state still counts them (the JSON is not changed by the display rule)
#   N5  the Phase state badge reads the build rows only: Phase 1 built, Phase 2 in progress,
#       Phase 3 (HARNESS only) "sign-off only"; its card says "Sign-off phase: no build rows"
#   N6  the Stage 5 counts name the sign-offs: ", 1 of 9 modules signed off" (Stage 5 card, KPI)
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
trap '[ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT
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
| 10 | HARNESS | `bin/verify-module.sh Payments`, then LOOK + CONFIRM per `module-review.md` | summary has no FAULT; N of N pages reviewed | 1 | `module-review.md` | not built |

### Phase 2 - Catalog

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 11 | BUILD | `11-catalog.mdl` | catalog entities | - | - | built |
| 12 | BUILD | `12-catalog-pages.mdl` | catalog pages | 11 | - | not built |
| 14 | BUILD | `14-pricing.mdl` | pricing entities | - | - | built |
| 15 | HARNESS | `bin/verify-module.sh Pricing`, then LOOK + CONFIRM per `module-review.md` | summary has no FAULT; N of N pages reviewed | 14 | `module-review.md` | not built |

### Phase 3 - Close

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 13 | HARNESS | `bin/verify-module.sh Holds`, then LOOK + CONFIRM per `module-review.md` | summary has no FAULT; N of N pages reviewed | 11 | `module-review.md` | pending a person |
MD
  summary "$R" Orders clean; summary "$R" Stock finding; summary "$R" Shipping skip-journeys
  summary "$R" Invoices clean; summary "$R" Returns clean; summary "$R" Holds clean; summary "$R" Pricing clean
  mkdir -p "$R/mdlsource"; : > "$R/mdlsource/done-14-pricing.mdl"; touch -t 202610201000 "$R/mdlsource/done-14-pricing.mdl"
  { sed -n '1,/^|---|/p' "$FX/BUILD-LOG.captured.md"
    logrow 2026-10-19T09:00:00+0000 01-orders.mdl
    logrow 2026-10-20T10:00:00+0000 05-invoices.mdl; } > "$R/docs/BUILD-LOG.md"
  local U="$R/design/ui-reviews"
  shot "$U/shots/orders-a.png"; shot "$U/shots/orders-b.png"; shot "$U/shots/returns-a.png"; shot "$U/shots/holds-a.png"
  printf '<p>1 of 1 pages reviewed: Holds. VALID AT: 1234567</p>\n<p>PROOF-OF-LOOK: Holds.Hold_List = shots/holds-a.png</p>\n' > "$U/ui-review-2026-10-19-holds.html"
  printf '<p>2 of 2 pages reviewed: Orders. VALID AT: 1234567</p>\n<p>PROOF-OF-LOOK: Orders.Order_List = shots/orders-a.png</p>\n<p>PROOF-OF-LOOK: Orders.Order_Edit = shots/orders-b.png</p>\n' > "$U/ui-review-2026-10-20.html"
  printf '<p>1 of 2 pages reviewed: Returns. VALID AT: 1234567</p>\n<p>PROOF-OF-LOOK: Returns.Return_List = shots/returns-a.png</p>\n' > "$U/ui-review-2026-10-20-returns.html"
  CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$R" --html --json --quiet >/dev/null 2>&1
  H="$(cat "$R/architecture/progress-report.html" 2>/dev/null)"
}
# the module's sign-off line on its phase card (one div per module, data-module=<Module>)
status() { printf '%s' "$H" | grep -o "<div class='k signoff' data-module='$1'>.*" | sed 's#<div class=k>Click.*##' | head -1; }
nstatus() { printf '%s' "$H" | grep -o "data-module='$1'" | wc -l | tr -d ' '; }
neverok() { ! printf '%s' "$1" | grep -q 'Verified\|st-built'; }
# the rendered row lists: the phase cards' <table class=steps> rows
rowlist() { printf '%s' "$H" | sed -n '/<table class=steps>/,/<\/table>/p'; }

for layout in single two; do
  R="$WORK/$layout"; [ "$layout" = single ] && mkproj "$R" App.mpr || mkproj "$R" app/App.mpr
  L="($layout tree)"
  s="$(status Orders)"
  id=H1; [ "$layout" = two ] && id=H7
  { printf '%s' "$s" | grep -q 'Verified ✓ 2026-10-20 (LOOK 2/2)' && printf '%s' "$s" | grep -q 'drift.*State says not built: update State'; } \
    && ok "$id $L: clean + fresh + LOOK 2/2: Orders 'Verified ✓ 2026-10-20 (LOOK 2/2)', flagged against State" || bad "$id $L: Orders" "$s"
  s="$(status Billing)"
  printf '%s' "$s" | grep -q 'built? no verify summary' \
    && ok "H2 $L: State built with no summary: 'built? no verify summary'" || bad "H2 $L: Billing" "$s"
  s="$(status Stock)"
  { neverok "$s" && printf '%s' "$s" | grep -q 'Verify not clean 2026-10-20 (FINDING'; } \
    && ok "H3 $L: a FINDING summary: 'Verify not clean', never Verified" || bad "H3 $L: Stock" "$s"
  s="$(status Shipping)"
  { neverok "$s" && printf '%s' "$s" | grep -q 'Verify not clean 2026-10-20 (SKIPPED'; } \
    && ok "H4 $L: a --skip-journeys summary: 'Verify not clean', never Verified" || bad "H4 $L: Shipping" "$s"
  s="$(status Invoices)"
  { neverok "$s" && printf '%s' "$s" | grep -q 'Verify stale (1 build since)'; } \
    && ok "H5 $L: a summary older than its dependency's exec: 'Verify stale (1 build since)'" || bad "H5 $L: Invoices" "$s"
  s="$(status Returns)"
  { neverok "$s" && printf '%s' "$s" | grep -q 'Verify owed - LOOK + CONFIRM' && printf '%s' "$s" | grep -q 'reviewed 1 of 2'; } \
    && ok "H6 $L: clean and fresh, LOOK 1 of 2: 'Verify owed - LOOK + CONFIRM'" || bad "H6 $L: Returns" "$s"
  s="$(status Payments)"
  { neverok "$s" && printf '%s' "$s" | grep -q 'Verify not run'; } \
    && ok "H8 $L: no summary, State not built: 'Verify not run'" || bad "H8 $L: Payments" "$s"
  s="$(status Holds)"
  { neverok "$s" && printf '%s' "$s" | grep -q "<span class='st-person'>Verify clean 2026-10-20, LOOK 1/1 - held: State says pending a person</span>"; } \
    && ok "H9 $L: clean + LOOK 1/1, State pending a person: 'held', never Verified" || bad "H9 $L: Holds" "$s"
  s="$(status Pricing)"
  { neverok "$s" && printf '%s' "$s" | grep -q 'Verify stale (a script was marked done- after it)' && ! printf '%s' "$s" | grep -q '0 builds'; } \
    && ok "H10 $L: stale by a newer done- file only: 'a script was marked done- after it'" || bad "H10 $L: Pricing" "$s"

  # N1: 4 build rows (1, 6, 11, 12), 3 built; the 8 HARNESS rows are in no count
  { printf '%s' "$H" | grep -q '<b>4 of 5 rows built</b>' && printf '%s' "$H" | grep -q '2 of 2 rows built' \
      && printf '%s' "$H" | grep -q '2 of 3 rows built' && printf '%s' "$H" | grep -q '5 build rows: <b class=st-built>4 built</b>' \
      && printf '%s' "$H" | grep -q 'Not counted: 10 HARNESS rows (sign-offs of 9 modules, 1 harness pass)' \
      && ! printf '%s' "$H" | grep -q 'of 15 rows built\|of 14 rows built\|0 of 0 rows built'; } \
    && ok "N1 $L: counts leave HARNESS out: 4 of 5 rows built, Phase 1 2 of 2, Phase 2 2 of 3, lede 5 build rows (sign-offs of 9 modules)" \
    || bad "N1 $L: counts" "$(printf '%s' "$H" | grep -o '[0-9]* of [0-9]* rows built\|[0-9]* build rows[^.]*\|Not counted[^.]*' | sort -u)"
  # N2: one status per module, 7 in all, none for the module without a HARNESS row
  n=0; for m in Orders Billing Stock Shipping Invoices Returns Payments Holds Pricing; do [ "$(nstatus "$m")" = 1 ] && n=$((n+1)); done
  { [ "$n" = 9 ] && [ "$(nstatus Catalog)" = 0 ] && [ "$(printf '%s' "$H" | grep -o "class='k signoff'" | wc -l | tr -d ' ')" = 9 ] \
      && printf '%s' "$H" | grep -q 'Module sign-offs: 1 of 9 modules verified'; } \
    && ok "N2 $L: one sign-off status per module (9), none for Catalog (no HARNESS row), rollup 1 of 9 verified (held not counted)" \
    || bad "N2 $L: per-module status" "$n of 9 once; Catalog $(nstatus Catalog); $(printf '%s' "$H" | grep -o 'Module sign-offs[^.]*')"
  # N3: no verify-module.sh row in the row lists; the harness pass stays, marked not counted
  RL="$(rowlist)"
  { [ -n "$RL" ] && ! printf '%s' "$RL" | grep -q 'verify-module' \
      && printf '%s' "$RL" | grep -q '<td>9</td><td>HARNESS <span class=mut>(not counted)</span></td>' \
      && printf '%s' "$RL" | grep -q '<td>11</td><td>BUILD</td>'; } \
    && ok "N3 $L: no verify-module.sh row in the row lists; row 9 (coherence) listed, '(not counted)'" \
    || bad "N3 $L: row lists" "$(printf '%s' "$RL" | grep -o '<td>[0-9]*</td><td>HARNESS[^/]*' | head)"
  # N4: the agents' copy of the plan still carries every HARNESS row and its Step
  J="$R/architecture/build-plan.json"
  nj="$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(1 for p in d["phases"] for x in p["steps"] if x["kind"]=="HARNESS" and ("verify-module.sh" in x["step"] or "coherence" in x["step"])), d["phases"][0]["state"])' "$J" 2>/dev/null)"
  { [ "$nj" = "10 in progress" ] && grep -q 'bin/verify-module.sh Orders' "$J" && grep -q '| 2 | HARNESS | `bin/verify-module.sh Orders`' "$R/architecture/build-plan.md"; } \
    && ok "N4 $L: build-plan.json lists all 10 HARNESS rows with their Step, Phase 1 state still in progress; build-plan.md untouched" \
    || bad "N4 $L: agent-facing plan" "json HARNESS rows, phase 1 state: ${nj:-none}"
  # N5: the badge reads build rows only; a HARNESS-only phase is a sign-off phase
  bd="$(printf '%s' "$H" | grep -o 'Phase state: <span class="badge [^"]*">[^<]*' | sed 's/.*">//' | tr '\n' ',')"
  { [ "$bd" = "built,in progress,sign-off only," ] && printf '%s' "$H" | grep -q 'Sign-off phase: no build rows'; } \
    && ok "N5 $L: Phase state badges built / in progress / sign-off only; Phase 3 card 'Sign-off phase: no build rows'" \
    || bad "N5 $L: badges" "$bd $(printf '%s' "$H" | grep -o 'Sign-off phase[^<]*')"
  # N6: the Stage 5 counts say how many modules are signed off (held is not)
  { printf '%s' "$H" | grep -q "4 of 5 rows built, 1 of 9 modules signed off</a>" \
      && printf '%s' "$H" | grep -q "from architecture/build-plan.md, 1 of 9 modules signed off"; } \
    && ok "N6 $L: Stage 5 card and KPI: ', 1 of 9 modules signed off'" \
    || bad "N6 $L: sign-off suffix" "$(printf '%s' "$H" | grep -o '[^>]*modules signed off' | sort -u)"
done

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
