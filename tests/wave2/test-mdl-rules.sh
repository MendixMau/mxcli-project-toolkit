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
#   T7  --for whose classifier fails (no project-bin/exec.sh): exit 1, NOTHING on stdout   (review F1)
#   T8  a register ERE that matches no row: --check and the kind lookup both fail          (review F2)
#   T9  a new `##` section no kind selects, or an exclusion naming a gone heading: --check fails (F3)
#   T10 --for maps exec.sh's `action` and `mapping` subjects to microflow, a demo user to access
#   T11 a `# comment` inside a code fence does not end a section; a repeated kind is labelled once
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
# mkcopy <dir> — a minimal copy of the tree mdl-rules.sh reads: the script, its table, exec.sh,
# every skill the table names, and the generated files.
mkcopy() {
  local c="$1" f
  mkdir -p "$c/bin/lib" "$c/project-bin" "$c/skills/generated"
  cp "$TK/bin/mdl-rules.sh" "$c/bin/"; cp "$TK/bin/lib/mdl-rule-kinds.tsv" "$c/bin/lib/"; cp "$TK/project-bin/exec.sh" "$c/project-bin/"
  for f in $(awk -F'\t' '!/^#/ && NF >= 4 { print $2 }' "$TK/bin/lib/mdl-rule-kinds.tsv" | sort -u); do
    mkdir -p "$c/$(dirname "$f")"; cp "$TK/$f" "$c/$f"
  done
  cp "$TK"/skills/generated/rules-*.md "$c/skills/generated/"
}
C="$WORK/tk"; mkcopy "$C"
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

echo "== T7: --for with a failing classifier fails loudly and never prints the core alone (review F1) =="
C7="$WORK/tk7"; mkcopy "$C7"; rm -f "$C7/project-bin/exec.sh"
O="$(bash "$C7/bin/mdl-rules.sh" --for "$TK/skills/build/workflow-example.mdl" 2>"$WORK/err")"; RC=$?
[ "$RC" -eq 1 ] && [ -z "$O" ] && grep -q 'classifier failed' "$WORK/err" \
  && ok "no exec.sh: exit 1, stdout empty, stderr names the classifier" || bad "failing classifier: rc=$RC stdout=${#O} chars" "$(cat "$WORK/err")"

echo "== T8: a register ERE that matches no row fails, though its kind's other EREs match (review F2) =="
C8="$WORK/tk8"; mkcopy "$C8"
printf 'workflow\tskills/learned-detection-gaps.md\trows\tThe register::zzznomatch\n' >> "$C8/bin/lib/mdl-rule-kinds.tsv"
O="$(bash "$C8/bin/mdl-rules.sh" --check 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "$O" "zzznomatch" && ok "--check: exit 1, names the dead ERE" || bad "dead ERE --check: rc=$RC" "$O"
O="$(bash "$C8/bin/mdl-rules.sh" workflow 2>"$WORK/err")"; RC=$?
[ "$RC" -eq 1 ] && [ -z "$O" ] && grep -q 'zzznomatch' "$WORK/err" \
  && ok "'workflow': exit 1, stdout empty, stderr names the dead ERE" || bad "dead ERE lookup: rc=$RC stdout=${#O} chars" "$(cat "$WORK/err")"

echo "== T9: every ## section is selected by some kind or excluded with a reason (review F3) =="
C9="$WORK/tk9"; mkcopy "$C9"
printf '\n## 5. A brand-new rule section\n\nA rule nobody mapped to a kind.\n' >> "$C9/skills/learned-mdl-preflight.md"
bash "$C9/bin/mdl-rules.sh" --render >/dev/null 2>&1
O="$(bash "$C9/bin/mdl-rules.sh" --check 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "$O" "5. A brand-new rule section" && ! has "$O" "DRIFTED" \
  && ok "an unselected new section: exit 1, COVERAGE names it" || bad "new section: rc=$RC" "$O"
C9b="$WORK/tk9b"; mkcopy "$C9b"
sed 's/^## Related$/## See also/' "$C9b/skills/design-spacing.md" > "$C9b/x" && mv "$C9b/x" "$C9b/skills/design-spacing.md"
grep -q '^## See also$' "$C9b/skills/design-spacing.md" || bad "fixture setup: design-spacing.md has no '## Related' to rename"
O="$(bash "$C9b/bin/mdl-rules.sh" --check 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "$O" "Related" && has "$O" "See also" \
  && ok "a renamed excluded heading: exit 1, names the stale exclusion and the unselected heading" || bad "stale exclusion: rc=$RC" "$O"

echo "== T10: --for maps action and mapping to microflow, a demo user to access =="
MAP="$TK/fixtures/import-mapping-range-repro/maptest.mdl"   # a real repro: module, entities, JSON structure, import mapping
O="$(bash "$SUT" --for "$MAP" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$O" | head -1)" = "# MDL rules for kinds: any, entity, microflow" ] \
  && has "$O" "Also: module structure (core rules only)." \
  && ok "$(basename "$MAP"): import mapping → microflow, beside entity" || bad "mapping: rc=$RC" "$(printf '%s\n' "$O" | sed -n '1p;4p')"
# No .mdl file in the repo writes a Java action or a demo user, so these are minimal one-statement
# scripts, in the spellings the skills document (learned-mdl-preflight.md, manage-security.md).
printf 'create java action Test.JA_DoIt () returns boolean;\n' > "$WORK/ja.mdl"
printf "create demo user 'demo.user' password 'Throwaway-Pass-1!' (User);\n" > "$WORK/du.mdl"
printf "create demo user 'n' password 'P1!' entity Administration.Account (Role);\n" > "$WORK/du2.mdl"
for spec in "ja.mdl|# MDL rules for kinds: any, microflow" \
            "du.mdl|# MDL rules for kinds: any, access" \
            "du2.mdl|# MDL rules for kinds: any, access"; do
  f="${spec%%|*}"; want="${spec#*|}"
  O="$(bash "$SUT" --for "$WORK/$f" 2>&1)"; RC=$?
  H="$(printf '%s\n' "$O" | head -1)"
  [ "$RC" -eq 0 ] && [ "$H" = "$want" ] && ! has "$O" "(core rules only)" \
    && ok "$f ($(cut -c1-40 "$WORK/$f")…) → $H" || bad "$f: rc=$RC got '$H', want '$want'" "$(printf '%s\n' "$O" | sed -n '4p')"
done

echo "== T11: a # line inside a code fence does not end a section; a repeated kind is labelled once =="
C11="$WORK/tk11"; mkcopy "$C11"
awk '{print} /^## 3\. The page scaffold/{print ""; print "```"; print "# a shell comment in a fence"; print "```"; print "LINE-AFTER-THE-FENCE"}' \
  "$C11/skills/design-spacing.md" > "$C11/x" && mv "$C11/x" "$C11/skills/design-spacing.md"
O="$(bash "$C11/bin/mdl-rules.sh" page 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && has "$O" "LINE-AFTER-THE-FENCE" && has "$O" "building the body without the header is the escape" \
  && ok "fenced # comment: the section runs on past it" || bad "fenced comment truncated the section: rc=$RC"
O="$(bash "$SUT" page page 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$O" | head -1)" = "# MDL rules for kinds: any, page" ] \
  && [ "$(printf '%s\n' "$O" | tail -1)" = "$(tail -1 "$TK/skills/generated/rules-page.md")" ] \
  && ok "'page page': labelled 'any, page', same closing line as 'page'" || bad "page page: rc=$RC" "$(printf '%s\n' "$O" | sed -n '1p;$p')"

echo ""
echo "test-mdl-rules: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
