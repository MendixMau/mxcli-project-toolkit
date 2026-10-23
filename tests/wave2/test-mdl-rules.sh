#!/usr/bin/env bash
# Fixture for bin/mdl-rules.sh — the per-statement-kind MDL rules lookup (lazy-load PR 2).
#
# Usage: bash tests/wave2/test-mdl-rules.sh bin/mdl-rules.sh
#
# Golden input is real: the skills themselves (their headings, STOP table and register), and for
# --for the repo's own .mdl files — a native-bughunt repro captured from a real 9.24.2 app (entity +
# page), the workflow example, an mdl-scan STOP-16 fixture (access) and an app-analysis microflow.
# Read-only on the toolkit tree: the drift and coverage cases run on a copy in a temp dir.
#   T1  each kind prints its own sections, none of another kind's, and a closing n/n that adds up;
#       the output equals skills/generated/rules-<kind>.md byte for byte
#   T2  --for on a mixed page+entity script finds both kinds and prints what `entity page` prints
#   T3  --for on workflow, access and microflow scripts finds those kinds
#   T4  unknown kind / missing --for file: exit 2, nothing on stdout
#   T5  a heading the table names that is gone: exit 1, loud on stderr, NOTHING on stdout
#   T6  --check: clean on the tree; DRIFTED after a skill edit; COVERAGE after a new unmapped gotcha
set -uo pipefail

SUT="${1:?usage: test-mdl-rules.sh /path/to/bin/mdl-rules.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
TK="$(cd "$(dirname "$SUT")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-mdl-rules.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
has() { grep -qF -- "$2" <<<"$1"; }   # here-string: a pipe into grep -q dies of SIGPIPE under pipefail

# STOP rows of one Kind, counted straight from the table (the fixture's own denominator).
stop_rows() { awk -v k="$1" '/^## The checklist/{on=1;next} on&&/^## /{exit}
  on&&/^\|/{n=split($0,c,"|"); x=c[n-1]; gsub(/^[ \t]+|[ \t]+$/,"",x); if(x==k)t++} END{print t+0}' \
  "$TK/skills/learned-mdl-preflight.md"; }
ANY="$(stop_rows any)"

echo "== T1: each kind — its own sections, nothing of another kind's, n/n adds up, equals the generated file =="
#        kind      must contain (a source line)                           must not contain
for spec in "page|skills/ui-preflight-pages.md|skills/microflow-preflight.md" \
            "microflow|skills/microflow-preflight.md|skills/ui-preflight-pages.md" \
            "access|skills/security-is-not-a-later-script.md|skills/ui-preflight-pages.md" \
            "workflow|| 18 | Write **any workflow MDL**|skills/microflow-preflight.md" \
            "entity|**Enumeration values named with reserved words**|skills/ui-preflight-pages.md" \
            "any|skills/retesting-learned-rules.md|skills/security-is-not-a-later-script.md"; do
  k="${spec%%|*}"; rest="${spec#*|}"; want="${rest%|*}"; not="${rest##*|}"
  [ "$k" = workflow ] && { want="| 18 | Write **any workflow MDL**"; }
  OUT="$(bash "$SUT" "$k" 2>&1)"; RC=$?
  n=0; [ "$k" = any ] || n="$(stop_rows "$k")"; exp=$((ANY + n))
  last="$(printf '%s\n' "$OUT" | tail -1)"
  if [ "$RC" -eq 0 ] && has "$OUT" "$want" && ! has "$OUT" "> Source: \`$not\`" \
     && [ "$last" = "Rules for kinds any$([ "$k" = any ] || printf ', %s' "$k"): STOP rows $exp/$exp listed" ]; then
    ok "$k: exit 0, has '$want', lacks $not, closes '$last'"
  else
    bad "$k: rc=$RC last='$last' expected $exp/$exp" "$(printf '%s\n' "$OUT" | grep -E '^mdl-rules|^> Source' | head -12)"
  fi
  if [ "$OUT" = "$(cat "$TK/skills/generated/rules-$k.md" 2>/dev/null)" ]; then
    : # equality is reported once below
  else
    bad "$k: output differs from skills/generated/rules-$k.md (run bin/mdl-rules.sh --render)"
  fi
  # every core part is in every kind's output
  for core in "## Step 0 — choose the write mode" "## Final self-check" "| 21 |" "| 22 |" "| 23 |" "## The ladder"; do
    has "$OUT" "$core" || bad "$k: core part missing: $core"
  done
done
[ "$FAIL" -eq 0 ] && ok "all six outputs equal their generated files and carry the core"

echo "== T2: --for on a real mixed page+entity script =="
MIX="$TK/pipelines/mendix-mpr/samples/fsm-template-9.24.2/native-bughunt/D2-page-repeater-content.mdl"
OUT="$(bash "$SUT" --for "$MIX" 2>&1)"; RC=$?
REF="$(bash "$SUT" entity page 2>&1)"
body() { printf '%s\n' "$1" | sed -n '/^> Source/,$p'; }
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | head -1)" = "# MDL rules for kinds: any, entity, page" ] \
   && has "$OUT" "writes: entity page. Also: module (core rules only)." && [ "$(body "$OUT")" = "$(body "$REF")" ]; then
  ok "--for $(basename "$MIX"): kinds entity+page (module named as core-only), same rules as 'entity page'"
else
  bad "--for mixed: rc=$RC" "$(printf '%s\n' "$OUT" | head -5)"
fi
has "$OUT" "skills/ui-preflight-pages.md" && has "$OUT" "**Enumeration values named with reserved words**" \
  && ! has "$OUT" "> Source: \`skills/microflow-preflight.md\`" \
  && ok "mixed: page and entity sections present, microflow sections absent" \
  || bad "mixed: wrong sections"

echo "== T3: --for finds workflow, access and microflow on real scripts =="
for spec in "skills/build/workflow-example.mdl|workflow" \
            "tests/wave2/fixtures/mdl-scan/STOP-16.bad.mdl|access" \
            "fixtures/app-analysis/facts/mdl/Orders.SUB_TxPerItem.mdl|microflow"; do
  f="${spec%%|*}"; k="${spec##*|}"
  H="$(bash "$SUT" --for "$TK/$f" 2>/dev/null | head -1)"
  case "$H" in "# MDL rules for kinds: any"*", $k"*|"# MDL rules for kinds: any, $k") ok "$f → $H" ;;
    *) bad "$f: expected kind $k, got '$H'" ;; esac
done

SE="$TK/tests/wave2/fixtures/mxpatch/capture-se.mdl"   # a real capture: one scheduled event, no rule kind
O="$(bash "$SUT" --for "$SE" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$O" | head -1)" = "# MDL rules for kinds: any" ] && has "$O" "Also: event (core rules only)." \
  && ok "a script with no rule kind (scheduled event): core only, and the event is named" || bad "core-only --for: rc=$RC" "$(printf '%s\n' "$O" | head -4)"

echo "== T4: usage errors print nothing to stdout =="
O="$(bash "$SUT" bogus 2>/dev/null)"; RC=$?
[ "$RC" -eq 2 ] && [ -z "$O" ] && ok "unknown kind: exit 2, stdout empty" || bad "unknown kind: rc=$RC out=${O:0:80}"
E="$(bash "$SUT" bogus 2>&1 >/dev/null)"
has "$E" "one of: page microflow access workflow entity any" && ok "unknown kind names the valid kinds" || bad "no kind list: $E"
O="$(bash "$SUT" --for "$WORK/nope.mdl" 2>/dev/null)"; RC=$?
[ "$RC" -eq 2 ] && [ -z "$O" ] && ok "--for a missing file: exit 2, stdout empty" || bad "--for missing: rc=$RC"

echo "== T5: a missing heading fails loudly and never prints empty =="
sed 's/^page	skills\/design-spacing.md	section	2. The rhythm hierarchy$/page	skills\/design-spacing.md	section	2. A heading that was renamed/' \
  "$TK/bin/lib/mdl-rule-kinds.tsv" > "$WORK/bad.tsv"
grep -q 'A heading that was renamed' "$WORK/bad.tsv" || bad "fixture setup: substitution did not apply"
O="$(MXTK_MDL_RULES_TSV="$WORK/bad.tsv" bash "$SUT" page 2>"$WORK/err")"; RC=$?
if [ "$RC" -eq 1 ] && [ -z "$O" ] && grep -q 'heading not found: "2. A heading that was renamed"' "$WORK/err"; then
  ok "renamed heading: exit 1, stdout empty, stderr names the heading"
else
  bad "renamed heading: rc=$RC stdout=${#O} chars" "$(cat "$WORK/err")"
fi
O="$(MXTK_MDL_RULES_TSV="$WORK/bad.tsv" bash "$SUT" microflow 2>/dev/null)"; RC=$?
[ "$RC" -eq 0 ] && [ -n "$O" ] && ok "a kind that does not use the broken row still prints" || bad "microflow broke too: rc=$RC"
sed 's/MDL gotchas::\*\*Demo users:\*\*/MDL gotchas::**A bullet nobody wrote**/' "$TK/bin/lib/mdl-rule-kinds.tsv" > "$WORK/bad2.tsv"
O="$(MXTK_MDL_RULES_TSV="$WORK/bad2.tsv" bash "$SUT" access 2>"$WORK/err")"; RC=$?
[ "$RC" -eq 1 ] && [ -z "$O" ] && grep -q 'no bullet under "MDL gotchas"' "$WORK/err" \
  && ok "a bullet lead that selects nothing: exit 1, stdout empty" || bad "bad bullet: rc=$RC" "$(cat "$WORK/err")"

echo "== T6: --check — clean, then drift, then a coverage gap (on a copy) =="
O="$(bash "$SUT" --check 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "--check on the tree: clean" || bad "--check on the tree: rc=$RC" "$O"
C="$WORK/tk"; mkdir -p "$C/bin/lib" "$C/project-bin" "$C/skills/generated"
cp "$TK/bin/mdl-rules.sh" "$C/bin/"; cp "$TK/bin/lib/mdl-rule-kinds.tsv" "$C/bin/lib/"; cp "$TK/project-bin/exec.sh" "$C/project-bin/"
for f in $(awk -F'\t' '!/^#/ && NF >= 4 { print $2 }' "$TK/bin/lib/mdl-rule-kinds.tsv" | sort -u); do
  mkdir -p "$C/$(dirname "$f")"; cp "$TK/$f" "$C/$f"
done
cp "$TK"/skills/generated/rules-*.md "$C/skills/generated/"
bash "$C/bin/mdl-rules.sh" --check >/dev/null 2>&1 && ok "the copy starts clean" || bad "the copy is not clean"
awk '{print} /^## 3\. The page scaffold/{print "A new line under the scaffold heading."}' "$C/skills/design-spacing.md" > "$C/x" && mv "$C/x" "$C/skills/design-spacing.md"
O="$(bash "$C/bin/mdl-rules.sh" --check 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "$O" "DRIFTED:" && has "$O" "rules-page.md" && ! has "$O" "rules-microflow.md" \
  && ok "a skill edit: exit 1, DRIFTED names rules-page.md and not rules-microflow.md" || bad "drift: rc=$RC" "$O"
bash "$C/bin/mdl-rules.sh" --render >/dev/null && bash "$C/bin/mdl-rules.sh" --check >/dev/null 2>&1 \
  && ok "--render repairs it" || bad "--render did not repair the drift"
awk '{print} /^- \*\*Demo users:\*\*/{print "- **A new gotcha:** nobody mapped it to a kind."}' "$C/skills/learned-mdl-preflight.md" > "$C/x" && mv "$C/x" "$C/skills/learned-mdl-preflight.md"
bash "$C/bin/mdl-rules.sh" --render >/dev/null 2>&1
O="$(bash "$C/bin/mdl-rules.sh" --check 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "$O" "bullet reaches no kind: - **A new gotcha:**" \
  && ok "an unmapped new gotcha: exit 1, COVERAGE names it" || bad "coverage: rc=$RC" "$O"
printf '| A **brand-new construct** nobody classified | rungs 1-3 | mx check | fix | ref |\n' > "$C/row"
awk -v r="$(cat "$C/row")" '{print} /^\| `get workflows for/{print r}' "$C/skills/learned-detection-gaps.md" > "$C/x" && mv "$C/x" "$C/skills/learned-detection-gaps.md"
O="$(bash "$C/bin/mdl-rules.sh" --check 2>&1)"
has "$O" "register row reaches no kind: A **brand-new construct**" && ok "an unmapped register row is named" || bad "register coverage" "$O"
awk '{ if ($0 ~ /^\| 29 \|/) sub(/\| microflow \|$/, "| nanoflow |"); print }' "$C/skills/learned-mdl-preflight.md" > "$C/x" && mv "$C/x" "$C/skills/learned-mdl-preflight.md"
O="$(bash "$C/bin/mdl-rules.sh" --check 2>&1)"
has "$O" 'STOP row 29: Kind "nanoflow"' && ok "a STOP row with an unknown Kind is named" || bad "stop-kind coverage" "$O"

echo ""
echo "test-mdl-rules: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
