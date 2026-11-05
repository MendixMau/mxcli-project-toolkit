#!/usr/bin/env bash
# Fixture for issue #107: the Stage-3 wireframe check in bin/gate-check.sh (check_stage_3) used
# to only confirm design/wireframes/*.html was non-empty, which read a 1-wireframe, 22-screen app
# as done. Where design/target-ui.md carries the "## Screen Inventory" table that
# skills/design-artifacts.md Step 2 defines (one row per screen, a Notes cell recording
# "reuse"/"same as"/"shares" for a screen that shares another's wireframe), the gate now counts
# that table against design/wireframes/*.html and reports MANUAL when the build falls short.
# Absent target-ui.md, or a target-ui.md without that heading, is unchanged presence-only
# behaviour — this fixture asserts both the new count and that old behaviour.
#
#   tests/wave2/test-wireframe-count.sh /path/to/gate-check.sh
#
# Golden input: the Screen Inventory table below is copied verbatim from the worked example added
# to skills/design-artifacts.md Step 2/3 by this same change (heading, columns, reuse wording) —
# not hand-invented shape.
set -uo pipefail
GATE="${1:?usage: test-wireframe-count.sh /path/to/gate-check.sh}"
WORK="$(mktemp -d /tmp/wfcount.XXXXXX)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
export MXTK_NO_FETCH=1

# Full Stage-3 PASS scaffold (fit-gap, blueprint.md/.html with correct mtime order, design
# system, a CONFIRMED stage-3 decision row) so the wireframe check is the only thing that can
# still fail. $1 = how many wireframe files to write, $2 = extra content for target-ui.md ("" =
# no file at all).
mkproj() {
  d="$WORK/$1"; mkdir -p "$d/architecture" "$d/design/wireframes" "$d/knowledge-base/brd"
  printf '{"openQuestions":[]}\n' > "$d/knowledge-base/brd/F001.brd.json"
  cat > "$d/PROJECT.md" <<'MD'
# PROJECT.md — fixture
Toolkit commit: none
Entry mode: requirements-driven

## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|
| 3 | Module structure: one module | CONFIRMED 2026-09-02 | matches the BRD |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|
MD
  printf '# fit-gap\nrow\n' > "$d/architecture/fit-gap.md"
  printf '# bp\nx\n' > "$d/architecture/blueprint.md"
  sleep 1
  printf '<html>\n' > "$d/architecture/blueprint.html"
  printf '<html>\n' > "$d/design/design-system.html"
  n="${3:-0}"
  i=1
  while [ "$i" -le "$n" ]; do printf '<html>\n' > "$d/design/wireframes/s$i.html"; i=$((i+1)); done
  if [ -n "${2:-}" ]; then printf '%s' "$2" > "$d/design/target-ui.md"; fi
  echo "$d"
}

verdict() { "$GATE" --no-html "$1" 3 2>&1; }
stage3() { "$GATE" --no-html "$1" 3 2>&1 | grep "^Stage 3 " | head -1; }

echo "== T1: no target-ui.md at all — unchanged presence-only behaviour, one wireframe passes =="
P="$(mkproj t1 "" 1)"
V="$(verdict "$P")"
case "$V" in *"is NOT machine-checkable"*) bad "MANUAL fired with no target-ui.md: $V" ;; *) ok "no target-ui.md leaves the old presence-only check in force" ;; esac

echo "== T2: target-ui.md present but no Screen Inventory heading — unchanged behaviour =="
P="$(mkproj t2 '# Target UI

## UX pattern notes

Just prose, no inventory table.
' 1)"
V="$(verdict "$P")"
case "$V" in *"is NOT machine-checkable"*) bad "MANUAL fired with no Screen Inventory heading: $V" ;; *) ok "no Screen Inventory heading leaves the old presence-only check in force" ;; esac

TARGET_UI='# Target UI

## Screen Inventory

| Screen | Basis | Notes |
|---|---|---|
| OrderList | FAITHFUL | |
| OrderDetail | FAITHFUL | |
| OrderEditPopup | GENERATIVE | reuses OrderDetail'"'"'s wireframe |
'

echo "== T3: inventory of 3, 1 reuse row, only 1 wireframe built — MANUAL, both numbers named =="
P="$(mkproj t3 "$TARGET_UI" 1)"
V="$(verdict "$P")"
case "$V" in
  *"1 wireframes for 3 inventoried screens"*) ok "MANUAL names built-vs-inventoried counts" ;;
  *) bad "wrong or missing MANUAL message: $V" ;;
esac
case "$V" in *"MANUAL"*) ok "verdict word is MANUAL" ;; *) bad "verdict word missing: $V" ;; esac

echo "== T4: same inventory, 2 wireframes built (3 screens - 1 reuse = 2 required) — PASS =="
P="$(mkproj t4 "$TARGET_UI" 2)"
V="$(verdict "$P")"
case "$V" in *"is NOT machine-checkable"*) bad "still MANUAL once the reuse-adjusted count is met: $V" ;; *) ok "reuse row correctly lowers the required wireframe count to PASS" ;; esac

# ---- 2026-11-05 regression experiment: a wireframe the architecture points at was deleted and
# Stage 3 stayed PASS, because the inventory count above is skipped without design/target-ui.md.
# The two reference forms are the field forms: a path in prose/table, and a bare file name in a
# module definition's "Source screen" column.
echo "== T5: no target-ui.md, a module definition names a wireframe that is not there — FAIL =="
P="$(mkproj t5 "" 1)"
mkdir -p "$P/architecture/modules/Approval"
printf '%s\n' '# Module: Approval' '' '## Pages / snippets' '| Page | Type | Source screen |' '|---|---|---|' \
  '| Approval_Inbox | Overview | s1.html |' '| Approval_Decide | NewEdit | approval-decide.html |' \
  > "$P/architecture/modules/Approval/definition.md"
V="$(stage3 "$P")"
case "$V" in *FAIL*'architecture/modules/Approval/definition.md: approval-decide.html'*) ok "bare name in a Source screen column, file absent: FAIL names doc and file" ;; *) bad "bare-name reference not caught: $V" ;; esac
mkdir -p "$P/design/wireframes/approval"; printf '<html>\n' > "$P/design/wireframes/approval/approval-decide.html"
V="$(stage3 "$P")"
case "$V" in *FAIL*'wireframe'*) bad "a wireframe in a per-flow subfolder was not found: $V" ;; *) ok "a bare name may live in a per-flow subfolder" ;; esac
printf '%s\n' '' '| Page | Wireframe |' '|---|---|' '| Request_List | `design/wireframes/request-list.html` |' '| Request_Edit | `design/wireframes/<kebab-case page>.html` |' > "$P/design/screens.md"
V="$(stage3 "$P")"
case "$V" in *FAIL*'design/screens.md: request-list.html'*) case "$V" in *kebab*) bad "a placeholder was read as a reference: $V" ;; *) ok "a design/wireframes/ path that is absent FAILs; a <placeholder> is not a reference" ;; esac ;; *) bad "path reference not caught: $V" ;; esac
printf '\nWaived artifact wireframes: request list is drawn in the client deck, not here\n' >> "$P/PROJECT.md"
V="$(stage3 "$P")"
case "$V" in *PASS*'waived — request list is drawn in the client deck'*) ok "'Waived artifact wireframes: <reason>' excuses it and the PASS line says so" ;; *) bad "wireframes waiver: $V" ;; esac

echo "== T6: an assembled prototype is checked by check-prototype-links.js (design-artifacts.md Step 3b) =="
if command -v node >/dev/null 2>&1; then
  P="$(mkproj t6 "" 1)"
  printf '%s\n' '<html><body>' '<section data-route="home"><a href="#/list">List</a></section>' \
    '<section data-route="list"><a href="#/home">Home</a></section>' '</body></html>' > "$P/design/prototype.html"
  V="$(stage3 "$P")"
  case "$V" in *PASS*) ok "a clean prototype passes" ;; *) bad "clean prototype: $V" ;; esac
  printf '%s\n' '<html><body>' '<section data-route="home"><a href="#/list">List</a><a href="#/gone">Gone</a></section>' \
    '<section data-route="list"><a href="#/home">Home</a></section>' '</body></html>' > "$P/design/prototype.html"
  V="$(stage3 "$P")"
  case "$V" in *FAIL*'design/prototype.html'*'gone'*) ok "a dead link FAILs Stage 3 and names the route" ;; *) bad "dead link not caught: $V" ;; esac
  printf '\nWaived artifact prototype: dead link is the out-of-scope reporting screen\n' >> "$P/PROJECT.md"
  V="$(stage3 "$P")"
  case "$V" in *PASS*'prototype link findings waived'*) ok "'Waived artifact prototype: <reason>' excuses it" ;; *) bad "prototype waiver: $V" ;; esac
else
  echo "  (node not available: T6 skipped)"
fi

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
rm -rf "$WORK"
[ "$FAIL" -eq 0 ]
