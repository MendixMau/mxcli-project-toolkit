#!/usr/bin/env bash
# Fixture for issue #291 part 2: the Stage-3 interaction-model facts. bin/gate-check.sh <p> 3
# (via bin/lib/interaction-model-check.sh) FAILs, once design/interaction-model.md exists, on
#   (b) a BRD approval/review/sign-off/user-task use case not named on any line under an Inbox
#       heading (table row or bullet),
#   (c) a design/wireframes/*.html without a valid `Page parameter:` line in its wf-contract block;
# reports MANUAL (never FAIL) for (a) a BRD actor with no "Role homes" row — BRD actors are not
# the confirmed role model; a `none — <reason>` row covers one;
# reports the artifact PENDING (artifact-manifest.tsv row `interaction-model`) when it is absent;
# honours "Waived artifact interaction-model[/<unit>]" register lines; and reports ADOPTED for a
# project adopted above stage 3.
#
#   tests/wave2/test-interaction-model-gate.sh /path/to/gate-check.sh
#
# Positive control: run it against the base branch's gate-check.sh too — every FAIL case and the
# PENDING/ADOPTED/WAIVED lines are absent there, so those assertions fail.
#
# T9–T12 are the independent review's probe trees for #332, reproduced verbatim.
#
# Input shapes are copied from the skills, not invented: the Role homes table and the per-page
# table from skills/interaction-model.md Steps 1 and 3, the wf-contract block from
# skills/design-artifacts.md Step 3, the BRD keys from skills/brd-generation.md. Synthetic trees
# only — no field run is claimed here.
set -uo pipefail
GATE="${1:?usage: test-interaction-model-gate.sh /path/to/gate-check.sh}"
WORK="$(mktemp -d /tmp/imgate.XXXXXX)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
export MXTK_NO_FETCH=1

ROLE_HOMES='## Role homes

| Role | Home page | Comes to do |
|---|---|---|
| Manager | `Order_Overview` | Find an order and follow it |
| Reviewer | `Review_Inbox` | Work through the reviews waiting for them |
'
INBOXES='## Inboxes and object hubs

| User task | Role | Inbox page | Grouping | Row opens |
|---|---|---|---|---|
| UC002 Approve order | Reviewer | `Review_Inbox` | by due date | `Order_Review` with its `Sales.Order` |
'
PAGES='## Per-page table

| Page | How reached | Page parameter / context object | Data view source | Nav entry | Role(s) |
|---|---|---|---|---|---|
| `Order_Overview` | menu; home for Manager | none — list page | grid: database `Sales.Order` | Orders | Manager |
| `Order_Detail` | row of `Order_Overview` | `Sales.Order` | page parameter | — | Manager, Reviewer |
'

wf() { # wf <file> <contract-inner-html | NOBLOCK>
  if [ "$2" = "NOBLOCK" ]; then
    printf '<html><body data-route="x">\n<h1>Screen</h1>\n</body></html>\n' > "$1"
  else
    printf '<html><body data-route="x">\n<div class="wf-contract">\n%s\n  <p>Reached from: menu</p>\n  <p>Drawn as role: Manager</p>\n</div>\n<h1>Screen</h1>\n</body></html>\n' "$2" > "$1"
  fi
}

# Full Stage-3 PASS scaffold (as test-wireframe-count.sh builds it) plus a BRD with two actors
# and one approval use case, and a passing interaction model. $2 = "nested" puts everything
# under analysis/app/ (the two-tree layout gate-check's ANALYSIS_BASE serves).
mkproj() {
  local d="$WORK/$1" b
  b="$d"; [ "${2:-}" = "nested" ] && b="$d/analysis/app"
  mkdir -p "$b/architecture" "$b/design/wireframes" "$b/knowledge-base/brd"
  cat > "$b/knowledge-base/brd/F001-orders.brd.json" <<'JSON'
{ "id": "F001", "title": "Orders", "modules": ["Sales"],
  "actors": ["Manager", "Reviewer"],
  "useCases": [
    { "id": "UC001", "title": "View order list", "actors": ["Manager"] },
    { "id": "UC002", "title": "Approve order", "actors": ["Reviewer"] }
  ],
  "openQuestions": [] }
JSON
  cat > "$d/PROJECT.md" <<'MD'
# PROJECT.md — fixture
Toolkit commit: none
Entry mode: requirements-driven

## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|
| 3 | Module structure: one module | CONFIRMED 2026-10-14 | matches the BRD |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|
MD
  printf '# fit-gap\nrow\n' > "$b/architecture/fit-gap.md"
  printf '# bp\nx\n' > "$b/architecture/blueprint.md"
  sleep 1
  printf '<html>\n' > "$b/architecture/blueprint.html"
  printf '<html>\n' > "$b/design/design-system.html"
  wf "$b/design/wireframes/Order_Overview.html" '  <p>Page parameter: none — list page</p>'
  wf "$b/design/wireframes/Order_Detail.html"   '  <p>Page parameter: Sales.Order</p>          <!-- Module.Entity, or: none — list page -->'
  printf '# Interaction model\n\n%s\n%s\n%s' "$ROLE_HOMES" "$INBOXES" "$PAGES" > "$b/design/interaction-model.md"
  echo "$d"
}
base_of() { if [ -d "$1/analysis/app" ]; then echo "$1/analysis/app"; else echo "$1"; fi; }

run() { "$GATE" --no-html "$1" 3 2>&1; }
stage3() { printf '%s\n' "$1" | grep '^Stage 3 ' | head -1; }
imline() { printf '%s\n' "$1" | grep '^Interaction model (stage 3 facts):' | head -1; }

echo "== T1: complete interaction model — Stage 3 PASS, facts PASS with denominators =="
P="$(mkproj t1)"; OUT="$(run "$P")"; RC=$?
case "$(stage3 "$OUT")" in *": PASS"*) ok "stage 3 passes" ;; *) bad "stage 3 not PASS: $(stage3 "$OUT")" ;; esac
[ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC on a passing project"
case "$(imline "$OUT")" in
  *"PASS"*"2 of 2 BRD actors"*"1 of 1 BRD approval"*"2 of 2 wireframes"*) ok "facts PASS, every denominator stated" ;;
  *) bad "facts line wrong: $(imline "$OUT")" ;;
esac
case "$OUT" in *"Artifact interaction-model"*"PRESENT"*) ok "artifact check sees it PRESENT" ;; *) bad "no PRESENT artifact row" ;; esac

echo "== T2: artifact absent — PENDING out loud, Stage 3 verdict untouched =="
P="$(mkproj t2)"; rm "$(base_of "$P")/design/interaction-model.md"; OUT="$(run "$P")"
case "$OUT" in *"Artifact interaction-model"*"PENDING — owed at stage 3"*) ok "manifest row reports it owed and absent" ;;
  *) bad "no loud PENDING artifact row: $(printf '%s\n' "$OUT" | grep 'Artifact interaction-model')" ;; esac
case "$(imline "$OUT")" in *PENDING*) ok "facts PENDING, not PASS" ;; *) bad "facts line: $(imline "$OUT")" ;; esac
case "$(stage3 "$OUT")" in *": PASS"*) ok "absence alone does not fail stage 3" ;; *) bad "stage 3: $(stage3 "$OUT")" ;; esac

echo "== T3a: a BRD actor with no row in Role homes — MANUAL, not FAIL =="
P="$(mkproj t3a)"; B="$(base_of "$P")"
grep -v '^| Reviewer |' "$B/design/interaction-model.md" > "$B/x" && mv "$B/x" "$B/design/interaction-model.md"
OUT="$(run "$P")"; RC=$?
case "$(stage3 "$OUT")" in *": MANUAL"*"interaction model"*) ok "stage 3 MANUAL" ;; *) bad "stage 3: $(stage3 "$OUT")" ;; esac
case "$OUT" in *"MANUAL role Reviewer"*"confirm it is a user role"*"none — <reason>"*) ok "finding names the actor and the remedy" ;; *) bad "no role finding" ;; esac
case "$OUT" in *"FAIL   role"*) bad "an actor without a home is still a FAIL" ;; *) ok "no role FAIL" ;; esac
[ "$RC" -eq 2 ] && ok "exit 2 (manual)" || bad "exit $RC"

echo "== T3b: a role row with an empty Home page cell — MANUAL =="
P="$(mkproj t3b)"; B="$(base_of "$P")"
sed 's/^| Reviewer | `Review_Inbox` |/| Reviewer |  |/' "$B/design/interaction-model.md" > "$B/x" && mv "$B/x" "$B/design/interaction-model.md"
OUT="$(run "$P")"
case "$OUT" in *"MANUAL role Reviewer"*) ok "empty home cell is no home" ;; *) bad "empty home accepted: $(imline "$OUT")" ;; esac

echo "== T3c: a 'none — <reason>' row covers a non-user actor — PASS =="
P="$(mkproj t3c)"; B="$(base_of "$P")"
sed 's/^| Reviewer | `Review_Inbox` |/| Reviewer | none — merged into Manager |/' "$B/design/interaction-model.md" > "$B/x" && mv "$B/x" "$B/design/interaction-model.md"
OUT="$(run "$P")"
case "$(stage3 "$OUT")" in *": PASS"*) ok "none-row discharges the actor" ;; *) bad "stage 3: $(stage3 "$OUT") / $(imline "$OUT")" ;; esac

echo "== T4a: an approval use case with no inbox row — FAIL =="
P="$(mkproj t4a)"; B="$(base_of "$P")"
grep -v '^| UC002' "$B/design/interaction-model.md" > "$B/x" && mv "$B/x" "$B/design/interaction-model.md"
OUT="$(run "$P")"
case "$(stage3 "$OUT")" in *": FAIL"*) ok "stage 3 FAILs" ;; *) bad "stage 3: $(stage3 "$OUT")" ;; esac
case "$OUT" in *"FAIL   task F001/UC002"*) ok "finding names BRD/use case" ;; *) bad "no task finding" ;; esac
case "$OUT" in *"task F001/UC001"*) bad "a non-approval use case was demanded an inbox" ;; *) ok "non-approval use case not demanded" ;; esac

echo "== T4b: a stated reason instead of an inbox — PASS =="
P="$(mkproj t4b)"; B="$(base_of "$P")"
sed 's/^| UC002 Approve order .*/| UC002 | Reviewer | — | — | none — approved inline on Order_Detail |/' "$B/design/interaction-model.md" > "$B/x" && mv "$B/x" "$B/design/interaction-model.md"
OUT="$(run "$P")"
case "$(stage3 "$OUT")" in *": PASS"*) ok "reason row discharges the task" ;; *) bad "stage 3: $(stage3 "$OUT") / $(imline "$OUT")" ;; esac

echo "== T5a: a wireframe with no wf-contract block — FAIL =="
P="$(mkproj t5a)"; wf "$(base_of "$P")/design/wireframes/Review_Inbox.html" NOBLOCK
OUT="$(run "$P")"
case "$OUT" in *"FAIL   wireframe Review_Inbox.html — no wf-contract block"*) ok "missing block named" ;; *) bad "$(imline "$OUT")" ;; esac
case "$(stage3 "$OUT")" in *": FAIL"*) ok "stage 3 FAILs" ;; *) bad "stage 3: $(stage3 "$OUT")" ;; esac
case "$OUT" in *"remedy: add <p>Page parameter:"*"Waived artifact interaction-model/<file>.html"*) ok "remedy line printed once" ;; *) bad "no remedy line" ;; esac

echo "== T5b: a wf-contract block with no Page parameter line — FAIL =="
P="$(mkproj t5b)"; wf "$(base_of "$P")/design/wireframes/Review_Inbox.html" '  <p>Parameter: Sales.Order</p>'
OUT="$(run "$P")"
case "$OUT" in *"FAIL   wireframe Review_Inbox.html — its wf-contract block has no"*) ok "missing line named" ;; *) bad "$(imline "$OUT")" ;; esac

echo "== T5c: a Page parameter outside the contract block does not count — FAIL =="
P="$(mkproj t5c)"
printf '<html><body>\n<div class="wf-contract"><p>Reached from: menu</p></div>\n<p>Page parameter: Sales.Order</p>\n</body></html>\n' \
  > "$(base_of "$P")/design/wireframes/Review_Inbox.html"
OUT="$(run "$P")"
case "$OUT" in *"FAIL   wireframe Review_Inbox.html"*) ok "line outside the block rejected" ;; *) bad "$(imline "$OUT")" ;; esac

echo "== T5d: values that are neither Module.Entity nor 'none — <reason>' — FAIL each =="
P="$(mkproj t5d)"; B="$(base_of "$P")"
wf "$B/design/wireframes/A.html" '  <p>Page parameter: the order</p>'
wf "$B/design/wireframes/B.html" '  <p>Page parameter: none</p>'
wf "$B/design/wireframes/C.html" '  <p>Page parameter: Order</p>'
OUT="$(run "$P")"
n="$(printf '%s\n' "$OUT" | grep -c '^  FAIL   wireframe [ABC]\.html')"
[ "$n" = 3 ] && ok "3 of 3 malformed values FAIL" || bad "$n of 3 malformed values FAIL: $(imline "$OUT")"

echo "== T5e: none &mdash; <reason> is the same character — PASS =="
P="$(mkproj t5e)"; wf "$(base_of "$P")/design/wireframes/Review_Inbox.html" '  <p>Page parameter: none &mdash; home</p>'
OUT="$(run "$P")"
case "$(stage3 "$OUT")" in *": PASS"*) ok "entity em dash accepted" ;; *) bad "$(imline "$OUT")" ;; esac

echo "== T6a: findings waived in the register — WAIVED lines, stage 3 PASS =="
P="$(mkproj t6a)"; B="$(base_of "$P")"
grep -v '^| Reviewer |' "$B/design/interaction-model.md" > "$B/x" && mv "$B/x" "$B/design/interaction-model.md"
wf "$B/design/wireframes/Legacy.html" NOBLOCK
printf '\nWaived artifact interaction-model/reviewer: technical role in this fixture, never signs in\nWaived artifact interaction-model/legacy.html: drawn before the interaction model\n' >> "$P/PROJECT.md"
OUT="$(run "$P")"
case "$OUT" in *"WAIVED role Reviewer — technical role"*) ok "waiver read, case-insensitive, reason printed" ;; *) bad "no WAIVED line: $(imline "$OUT")" ;; esac
case "$OUT" in *"WAIVED wireframe Legacy.html — drawn before"*) ok "per-wireframe waiver" ;; *) bad "no wireframe WAIVED line" ;; esac
case "$(stage3 "$OUT")" in *": PASS"*) ok "stage 3 passes with the finding waived" ;; *) bad "stage 3: $(stage3 "$OUT")" ;; esac

echo "== T6b: the whole artifact waived — facts WAIVED =="
P="$(mkproj t6b)"; wf "$(base_of "$P")/design/wireframes/Review_Inbox.html" NOBLOCK
printf '\nWaived artifact interaction-model: decided in the client UX workshop\n' >> "$P/PROJECT.md"
OUT="$(run "$P")"
case "$(imline "$OUT")" in *"WAIVED — decided in the client UX workshop"*) ok "whole-artifact waiver" ;; *) bad "$(imline "$OUT")" ;; esac
case "$(stage3 "$OUT")" in *": PASS"*) ok "stage 3 passes" ;; *) bad "stage 3: $(stage3 "$OUT")" ;; esac

echo "== T7: adopted above stage 3 — ADOPTED, no FAIL =="
P="$(mkproj t7)"; B="$(base_of "$P")"
grep -v '^| Reviewer |' "$B/design/interaction-model.md" > "$B/x" && mv "$B/x" "$B/design/interaction-model.md"
printf '\nAdopted at stage: 5 — joined mid-build\n' >> "$P/PROJECT.md"
OUT="$(run "$P")"; RC=$?
case "$(imline "$OUT")" in *ADOPTED*) ok "facts ADOPTED" ;; *) bad "$(imline "$OUT")" ;; esac
case "$(stage3 "$OUT")" in *": FAIL"*) bad "adopted project failed stage 3: $(stage3 "$OUT")" ;; *) ok "stage 3 not FAIL" ;; esac
[ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC"

echo "== T8: nested analysis/<name>/ layout — same facts, same FAIL =="
P="$(mkproj t8 nested)"; B="$(base_of "$P")"
grep -v '^| Reviewer |' "$B/design/interaction-model.md" > "$B/x" && mv "$B/x" "$B/design/interaction-model.md"
OUT="$(run "$P")"
case "$OUT" in *"MANUAL role Reviewer"*) ok "nested layout read" ;; *) bad "nested layout not read: $(imline "$OUT")" ;; esac

echo "== T9: inbox written as bullets (the skill's own Step 2 form) — covered =="
P="$(mkproj t9)"; B="$(base_of "$P")"
sed 's/^| UC002 Approve order .*/- **UC002 Approve order** → Reviewer, `Review_Inbox`, grouped by due date, row opens `Order_Review` with its order./' \
  "$B/design/interaction-model.md" > "$B/x" && mv "$B/x" "$B/design/interaction-model.md"
grep -q '^- \*\*UC002' "$B/design/interaction-model.md" && ok "fixture: inbox entry is a bullet now" || bad "fixture setup: bullet not written"
OUT="$(run "$P")"
case "$(stage3 "$OUT")" in *": PASS"*) ok "bullet line under the Inbox heading covers the task" ;; *) bad "stage 3: $(stage3 "$OUT") / $(imline "$OUT")" ;; esac

echo "== T10: task selection — approval-ish titles that are not user tasks are not demanded =="
P="$(mkproj t10)"; B="$(base_of "$P")"
cat > "$B/knowledge-base/brd/F002-admin.brd.json" <<'JSON'
{ "id": "F002", "title": "Admin", "actors": ["Manager"],
  "useCases": [
    { "id": "UC010", "title": "View approval history" },
    { "id": "UC011", "title": "Configure approval thresholds" },
    { "id": "UC012", "title": "Disapprove nothing" },
    { "id": "UC013", "title": "UC013: Review supplier" },
    { "id": "UC014", "title": "Sign off release" },
    { "id": "UC015", "title": "Escalate stuck case", "mdlRefs": ["Sales.WF_Case/UserTask_Escalate"] }
  ],
  "openQuestions": [] }
JSON
OUT="$(run "$P")"
for u in UC010 UC011 UC012; do
  case "$OUT" in *"task F002/$u"*) bad "$u demanded an inbox (false positive)" ;; *) ok "$u not demanded" ;; esac
done
for u in UC013 UC014 UC015; do
  case "$OUT" in *"FAIL   task F002/$u"*) ok "$u demanded (id-prefixed review / sign off / mdlRefs user task)" ;; *) bad "$u missed" ;; esac
done

echo "== T11: wireframe markup variants from the review probe — all valid =="
P="$(mkproj t11)"; W="$(base_of "$P")/design/wireframes"
printf '<div class="wf-contract"><p><b>Page parameter:</b> Sales.Order</p></div>\n' > "$W/bold.html"
printf "<div class='wf-contract'><p>Page parameter: Sales.Order</p></div>\n" > "$W/cls.html"
printf '<div class="wf-contract"><p>Page parameter: <code>Sales.Order</code></p></div>\n' > "$W/code.html"
printf '<div class="wf-contract">\r\n<p>Page parameter: none \342\200\224 home</p>\r\n</div>\r\n' > "$W/crlf.html"
printf '<div class="wf-contract"><p>Page parameter: none &mdash; list page</p></div>\n' > "$W/ent.html"
printf '<div class="wf-contract"><p>Page parameter: none - list page</p></div>\n' > "$W/hyph.html"
printf '<div class="wf-contract"><p>Page parameter: none \342\200\223 list page</p></div>\n' > "$W/endash.html"
printf '<div class="wf-contract">\n  <p>Page parameter:\n     Sales.Order</p></div>\n' > "$W/multi.html"
printf '<div class="wf-contract"><div class="row"><span>Reached from: menu</span></div><p>Page parameter: Sales.Order</p></div>\n' > "$W/nested.html"
OUT="$(run "$P")"
case "$(imline "$OUT")" in *"11 of 11 wireframes"*) ok "11 of 11 wireframes valid" ;; *) bad "$(imline "$OUT"); $(printf '%s\n' "$OUT" | grep 'FAIL   wireframe')" ;; esac
case "$(stage3 "$OUT")" in *": PASS"*) ok "stage 3 passes" ;; *) bad "stage 3: $(stage3 "$OUT")" ;; esac

echo "== T12: a CRLF interaction model reads like an LF one =="
P="$(mkproj t12)"; B="$(base_of "$P")"
sed 's/$/\r/' "$B/design/interaction-model.md" > "$B/x" && mv "$B/x" "$B/design/interaction-model.md"
OUT="$(run "$P")"
case "$(stage3 "$OUT")" in *": PASS"*) ok "CRLF artifact passes" ;; *) bad "stage 3: $(stage3 "$OUT") / $(imline "$OUT")" ;; esac

rm -rf "$WORK"
echo ""
echo "test-interaction-model-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
