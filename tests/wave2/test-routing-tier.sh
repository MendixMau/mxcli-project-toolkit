#!/usr/bin/env bash
# test-routing-tier.sh — demoting a skill from baseline to ondemand in bin/lib/skill-routing.tsv
# must actually remove it from every baseline-tier surface, and the baseline word budget report
# must drop to match. Missing until now: render-routing.sh's own SURFACES list and view logic
# were never exercised by a fixture, only read by a human next to a "Routing surfaces in sync"
# line. The gap was named directly in review of the PR that demoted learned-stylegallery.md from
# baseline to ondemand (baseline pack 79,993 -> 72,001 words): the only proof that change did
# what it claimed was a human reading one --check line.
#
# render-routing.sh resolves its own ROOT from $0's location (SCRIPT_DIR/..), not from a $1
# project path, and --only render mode WRITES into ROOT in place — so this cannot point the real
# script at a project directory the way other project-shaped fixtures do. Instead it copies the
# real render-routing.sh and its real lib/skill-routing.sh verbatim into a throwaway scratch
# tree that mimics this repo's own shape (bin/, bin/lib/, the SURFACES files with real markers,
# skills/), so ROOT resolves inside the scratch tree and nothing under the real repo is touched.
#
# Since 2026-10-14 skills/conversion-runbook.md is NOT a surface: it carried a fourth rendered
# copy of the baseline table inside a baseline file. The scratch runbook below therefore carries
# a pointer and no markers, and T1/T3 assert the table never reaches it.
#
# Usage: bash tests/wave2/test-routing-tier.sh [path-to-render-routing.sh]
#   (lib/skill-routing.sh is taken from alongside it: $(dirname SUT)/lib/skill-routing.sh)

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUT="${1:-$TOOLKIT/bin/render-routing.sh}"
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"   # fixtures cd away; a relative $1 must survive
LIB="$(dirname "$SUT")/lib/skill-routing.sh"

[ -r "$SUT" ] || { echo "test-routing-tier: no render-routing.sh at $SUT"; exit 2; }
[ -r "$LIB" ] || { echo "test-routing-tier: no lib/skill-routing.sh alongside $SUT"; exit 2; }

PASS=0; FAIL=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/routing-tier.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

printf 'test-routing-tier: %s\n' "$SUT"

# ── Build a scratch repo shaped like this one, so render-routing.sh's own ROOT resolution
#    (SCRIPT_DIR/..) lands inside $TMP/repo, not the real toolkit checkout. ─────────────────
R="$TMP/repo"
mkdir -p "$R/bin/lib" "$R/skills" "$R/agents"
cp "$SUT" "$R/bin/render-routing.sh"
cp "$LIB" "$R/bin/lib/skill-routing.sh"
chmod +x "$R/bin/render-routing.sh"

# Two baseline rows: an anchor that never moves, and the probe skill this test demotes.
# `demo-tier.md`'s body is sized so its word count is unambiguous in the budget delta below.
cat > "$R/skills/anchor.md" <<'EOF'
# Anchor

Always loaded. This is the skill that must never move tier in this test, so any surface it
should still appear on after the demotion is a real assertion and not an artifact of an empty
table.
EOF
# Fixed-size body (60 space-separated words) built with a plain shell loop — no python3
# dependency, so this runs the same under Git Bash/MSYS as anywhere else.
{
  echo "# Demo Tier"
  echo
  i=0
  while [ "$i" -lt 60 ]; do
    printf 'word'
    i=$((i+1))
    [ "$i" -lt 60 ] && printf ' '
  done
  echo
} > "$R/skills/demo-tier.md"
DEMO_WORDS="$(LC_ALL=C wc -w < "$R/skills/demo-tier.md")"

cat > "$R/bin/lib/skill-routing.tsv" <<EOF
# name	path	when	agents	stages	tier	group
anchor	skills/anchor.md	Always relevant — anchor skill	all	-	baseline	reference
demo	skills/demo-tier.md	Doing the thing this probes — tier-demotion target	all	-	baseline	reference
conversion-runbook	skills/conversion-runbook.md	Any pipeline work — every session	all	-	baseline	spine
EOF

# ── The SURFACES render-routing.sh hard-codes, each with real markers, minimal otherwise ────
cat > "$R/ROUTING.md" <<'EOF'
# Routing

<!-- ROUTING:BEGIN full -->
<!-- ROUTING:END -->
EOF
cat > "$R/README.md" <<'EOF'
# README

## Situational

<!-- ROUTING:BEGIN readme-situational -->
<!-- ROUTING:END -->

## Baseline

<!-- ROUTING:BEGIN readme-baseline -->
<!-- ROUTING:END -->
EOF
mkdir -p "$R/skills"
cat > "$R/skills/conversion-runbook.md" <<'EOF'
# Runbook

The baseline set lives in CLAUDE.local.md and ROUTING.md; it is not copied into this file.
EOF
RB_BEFORE="$(cat "$R/skills/conversion-runbook.md")"
for a in ba architect mdl gate test review; do
  cat > "$R/agents/${a}-agent.md" <<EOF
# ${a}-agent

<!-- ROUTING:BEGIN agent:${a} -->
<!-- ROUTING:END -->
EOF
done
cat > "$R/bin/gate-check.sh" <<'EOF'
#!/usr/bin/env bash
# <!-- ROUTING:BEGIN stage-map -->
# <!-- ROUTING:END -->
EOF

# ── First render: populate every surface from the table while `demo` is still baseline ─────
OUT1="$("$R/bin/render-routing.sh" 2>&1)"
RC1=$?
if [ "$RC1" -ne 0 ]; then
  bad "initial render (demo=baseline) exited 0" "rc=$RC1: $OUT1"
else
  ok "initial render (demo=baseline) exited 0"
fi

CHECK1="$("$R/bin/render-routing.sh" --check 2>&1)"
RCC1=$?
if [ "$RCC1" -ne 0 ]; then
  bad "--check after the first render reports in sync" "rc=$RCC1: $CHECK1"
else
  ok "--check after the first render reports in sync"
fi

echo "== T1: while baseline, demo-tier.md appears on the README baseline surface, never in the runbook =="
case "$(sed -n '/ROUTING:BEGIN readme-baseline/,/ROUTING:END/p' "$R/README.md")" in
  *demo-tier.md*) ok "README.md readme-baseline block lists demo-tier.md before demotion" ;;
  *) bad "README.md readme-baseline block missing demo-tier.md before demotion" ;;
esac
case "$(cat "$R/skills/conversion-runbook.md")" in
  *demo-tier.md*|*ROUTING:BEGIN*) bad "conversion-runbook.md received a rendered baseline table (it is no longer a surface)" ;;
  *) ok "conversion-runbook.md carries no rendered baseline table (not a surface)" ;;
esac
[ "$(cat "$R/skills/conversion-runbook.md")" = "$RB_BEFORE" ] \
  && ok "render left conversion-runbook.md byte-identical" \
  || bad "render rewrote conversion-runbook.md, which is not a surface" "$(cat "$R/skills/conversion-runbook.md")"
if grep -qx 'skills/conversion-runbook.md' "$R/bin/render-routing.sh"; then
  bad "render-routing.sh still lists skills/conversion-runbook.md in SURFACES"
else
  ok "render-routing.sh SURFACES no longer lists skills/conversion-runbook.md"
fi
case "$(sed -n '/ROUTING:BEGIN readme-situational/,/ROUTING:END/p' "$R/README.md")" in
  *demo-tier.md*) bad "README.md readme-situational block already lists demo-tier.md before demotion (should be baseline-only)" ;;
  *) ok "README.md readme-situational block does not list demo-tier.md before demotion" ;;
esac

BASE1="$(printf '%s\n' "$CHECK1" | sed -n 's/.*Baseline: \([0-9]*\) words.*/\1/p')"
if [ -z "$BASE1" ]; then
  bad "could not read a Baseline word count out of --check output" "$CHECK1"
fi

echo "== T2: demote demo from baseline to ondemand, re-render =="
sed -i.bak 's/^demo\tskills\/demo-tier\.md\t\(.*\)\tbaseline\treference$/demo\tskills\/demo-tier.md\t\1\tondemand\treference/' \
  "$R/bin/lib/skill-routing.tsv"
rm -f "$R/bin/lib/skill-routing.tsv.bak"
if ! grep -q $'\tondemand\treference' "$R/bin/lib/skill-routing.tsv"; then
  bad "the sed that demotes demo's tier column did not take" "$(cat "$R/bin/lib/skill-routing.tsv")"
fi

OUT2="$("$R/bin/render-routing.sh" 2>&1)"
RC2=$?
if [ "$RC2" -ne 0 ]; then
  bad "re-render after demotion exited 0" "rc=$RC2: $OUT2"
else
  ok "re-render after demotion exited 0"
fi

echo "== T3: after demotion, demo-tier.md is gone from every baseline surface =="
case "$(sed -n '/ROUTING:BEGIN readme-baseline/,/ROUTING:END/p' "$R/README.md")" in
  *demo-tier.md*) bad "README.md readme-baseline block still lists demo-tier.md after demotion" ;;
  *) ok "README.md readme-baseline block no longer lists demo-tier.md after demotion" ;;
esac
[ "$(cat "$R/skills/conversion-runbook.md")" = "$RB_BEFORE" ] \
  && ok "conversion-runbook.md still byte-identical after the demotion re-render" \
  || bad "the demotion re-render rewrote conversion-runbook.md" "$(cat "$R/skills/conversion-runbook.md")"
# The anchor skill must still be there — proves the disappearance is the demoted row, not an
# empty table wiping every surface.
case "$(sed -n '/ROUTING:BEGIN readme-baseline/,/ROUTING:END/p' "$R/README.md")" in
  *anchor.md*) ok "README.md readme-baseline block still lists the untouched anchor skill" ;;
  *) bad "README.md readme-baseline block lost the anchor skill too (table render is broken, not the tier logic)" ;;
esac

echo "== T4: demo-tier.md re-appears on the situational (ondemand) surface instead =="
case "$(sed -n '/ROUTING:BEGIN readme-situational/,/ROUTING:END/p' "$R/README.md")" in
  *demo-tier.md*) ok "README.md readme-situational block now lists demo-tier.md" ;;
  *) bad "README.md readme-situational block does not list demo-tier.md after demotion" ;;
esac

echo "== T5: the reported baseline word budget drops by the demoted skill's own word count =="
CHECK2="$("$R/bin/render-routing.sh" --check 2>&1)"
RCC2=$?
if [ "$RCC2" -ne 0 ]; then
  bad "--check after demotion + re-render reports in sync" "rc=$RCC2: $CHECK2"
else
  ok "--check after demotion + re-render reports in sync"
fi
BASE2="$(printf '%s\n' "$CHECK2" | sed -n 's/.*Baseline: \([0-9]*\) words.*/\1/p')"
if [ -z "$BASE2" ]; then
  bad "could not read a Baseline word count out of the post-demotion --check output" "$CHECK2"
elif [ -z "$BASE1" ]; then
  bad "skipped: no BASE1 to compare against" ""
else
  # Exactly demo-tier.md's own word count. Before 2026-10-14 the runbook (itself a summed
  # baseline doc) carried a rendered copy of the baseline table, so a demotion also shrank the
  # runbook by the demoted row and this could only assert a range. With the runbook out of
  # SURFACES nothing else moves: any other delta means some surface still copies the table into
  # a counted file.
  DELTA=$((BASE1 - BASE2))
  if [ "$DELTA" -eq "$DEMO_WORDS" ]; then
    ok "baseline word count dropped by exactly demo-tier.md's body ($BASE1 -> $BASE2, -$DELTA)"
  else
    bad "baseline word count delta is not exactly the demoted skill's body" \
      "before=$BASE1 after=$BASE2 delta=$DELTA demo_body_words=$DEMO_WORDS"
  fi
fi

# ── T6–T8 (2026-10-14): the per-role on-demand token "<role>?" in the agents column ───────────
# A baseline row whose cell says "mdl?,review" is baseline for review and on demand for mdl:
# out of mdl's word count, still in mdl's stub (below the baseline rows, trigger only, so it
# stays findable — CLAUDE.md skill rule 8), and named in the Role(s) column.
echo "== T6: a 'mdl?' token keeps the row in mdl's stub, on demand, and out of mdl's count =="
{ echo "# Per Role"; echo; i=0; while [ "$i" -lt 40 ]; do printf 'pr '; i=$((i+1)); done; echo; } > "$R/skills/per-role.md"
PR_WORDS="$(LC_ALL=C wc -w < "$R/skills/per-role.md" | tr -d ' ')"
printf 'perrole\tskills/per-role.md\tPer-role probe trigger — tail that only baseline readers see\tmdl?,review\t-\tbaseline\treference\n' >> "$R/bin/lib/skill-routing.tsv"
printf 'allbut\tskills/anchor.md\tAll-but probe — tail\tall,mdl?\t-\tbaseline\treference\n' >> "$R/bin/lib/skill-routing.tsv"
OUT6="$("$R/bin/render-routing.sh" 2>&1)" || bad "render with a '?' token exited 0" "$OUT6"
CHECK6="$("$R/bin/render-routing.sh" --check 2>&1)"; RC6=$?
[ "$RC6" -eq 0 ] && ok "--check accepts 'mdl?,review' and 'all,mdl?'" || bad "--check rejected a valid '?' token" "$CHECK6"
MDL_LINE="$(grep -n 'skills/per-role.md' "$R/agents/mdl-agent.md" | head -1)"
ANCHOR_LINE="$(grep -n 'skills/anchor.md' "$R/agents/mdl-agent.md" | head -1 | cut -d: -f1)"
case "$MDL_LINE" in
  *'| Per-role probe trigger |') ok "mdl stub lists the row with its trigger only (on-demand form)" ;;
  '') bad "mdl stub lost the row — an on-demand row must stay findable" ;;
  *) bad "mdl stub lists the row in baseline form" "$MDL_LINE" ;;
esac
[ -n "$ANCHOR_LINE" ] && [ "${MDL_LINE%%:*}" -gt "$ANCHOR_LINE" ] 2>/dev/null \
  && ok "mdl stub places it below the baseline rows" || bad "mdl stub row order wrong" "$MDL_LINE / anchor $ANCHOR_LINE"
grep -q 'skills/per-role.md` | Per-role probe trigger — tail that only baseline readers see |' "$R/agents/review-agent.md" \
  && ok "review stub keeps the full baseline row" || bad "review stub lost the baseline form" "$(grep per-role "$R/agents/review-agent.md")"
grep -q 'per-role' "$R/agents/gate-agent.md" && bad "gate stub got a row it is not named on" || ok "gate stub does not get the row"
role_words() { printf '%s\n' "$CHECK6" | grep '^  stage 5:' | sed -n "s/.* $1 \([0-9]*\)\/.*/\1/p"; }
RB_W="$(LC_ALL=C wc -w < "$R/skills/conversion-runbook.md" | tr -d ' ')"
A_W="$(LC_ALL=C wc -w < "$R/skills/anchor.md" | tr -d ' ')"
MW="$(role_words mdl)"; RW="$(role_words review)"
# Baseline rows at this point: anchor, runbook, perrole (mdl?,review), allbut (all,mdl? — it
# points at anchor.md again, so a role it reaches counts anchor twice). demo was demoted in T2.
[ "$RW" = "$((2 * A_W + RB_W + PR_WORDS))" ] && ok "review's count includes both rows ($RW)" \
  || bad "review count $RW, wanted $((2 * A_W + RB_W + PR_WORDS))" "$CHECK6"
[ "$MW" = "$((A_W + RB_W))" ] && ok "mdl's count excludes the 'mdl?,review' and 'all,mdl?' rows ($MW)" \
  || bad "mdl count $MW, wanted $((A_W + RB_W))" "$CHECK6"

echo "== T7: the Role(s) column names the on-demand roles =="
case "$(sed -n '/ROUTING:BEGIN readme-baseline/,/ROUTING:END/p' "$R/README.md")" in
  *'skills/per-role.md` | every stage | review (mdl: on demand) |'*) ok "Role(s) reads 'review (mdl: on demand)'" ;;
  *) bad "Role(s) cell for 'mdl?,review' wrong" "$(grep per-role "$R/README.md")" ;;
esac
case "$(sed -n '/ROUTING:BEGIN readme-baseline/,/ROUTING:END/p' "$R/README.md")" in
  *'| every stage | every role except mdl (on demand for those) |'*) ok "Role(s) reads 'every role except mdl (on demand for those)'" ;;
  *) bad "Role(s) cell for 'all,mdl?' wrong" "$(grep 'All-but' "$R/README.md")" ;;
esac

echo "== T8: the agent audit refuses a '?' token that cannot mean anything =="
cp "$R/bin/lib/skill-routing.tsv" "$TMP/tsv.good"
printf 'odrow\tskills/anchor.md\tOn-demand row probe\tmdl?\t-\tondemand\treference\n' >> "$R/bin/lib/skill-routing.tsv"
O="$("$R/bin/render-routing.sh" --check 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && printf '%s' "$O" | grep -q 'odrow.*on-demand token on a ondemand row' \
  && ok "'mdl?' on an ondemand row fails --check, named" || bad "'mdl?' on an ondemand row not refused" "$O"
cp "$TMP/tsv.good" "$R/bin/lib/skill-routing.tsv"
printf 'dup\tskills/anchor.md\tDup probe\tmdl,mdl?\t-\tbaseline\treference\n' >> "$R/bin/lib/skill-routing.tsv"
O="$("$R/bin/render-routing.sh" --check 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && printf '%s' "$O" | grep -q 'dup.*also listed plain' \
  && ok "'mdl,mdl?' fails --check, named" || bad "'mdl,mdl?' not refused" "$O"
cp "$TMP/tsv.good" "$R/bin/lib/skill-routing.tsv"
printf 'bogus\tskills/anchor.md\tBogus probe\tmdx?\t-\tbaseline\treference\n' >> "$R/bin/lib/skill-routing.tsv"
O="$("$R/bin/render-routing.sh" --check 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && printf '%s' "$O" | grep -q 'bad token: mdx?' \
  && ok "an unknown role with '?' fails --check" || bad "'mdx?' not refused" "$O"
cp "$TMP/tsv.good" "$R/bin/lib/skill-routing.tsv"

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
