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
# tree that mimics this repo's own shape (bin/, bin/lib/, the 9 SURFACES files with real markers,
# skills/), so ROOT resolves inside the scratch tree and nothing under the real repo is touched.
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

# ── The 9 SURFACES render-routing.sh hard-codes, each with real markers, minimal otherwise ──
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

<!-- ROUTING:BEGIN readme-baseline -->
<!-- ROUTING:END -->
EOF
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

echo "== T1: while baseline, demo-tier.md appears on both baseline surfaces =="
case "$(sed -n '/ROUTING:BEGIN readme-baseline/,/ROUTING:END/p' "$R/README.md")" in
  *demo-tier.md*) ok "README.md readme-baseline block lists demo-tier.md before demotion" ;;
  *) bad "README.md readme-baseline block missing demo-tier.md before demotion" ;;
esac
case "$(cat "$R/skills/conversion-runbook.md")" in
  *demo-tier.md*) ok "conversion-runbook.md readme-baseline block lists demo-tier.md before demotion" ;;
  *) bad "conversion-runbook.md readme-baseline block missing demo-tier.md before demotion" ;;
esac
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
case "$(cat "$R/skills/conversion-runbook.md")" in
  *demo-tier.md*) bad "conversion-runbook.md readme-baseline block still lists demo-tier.md after demotion" ;;
  *) ok "conversion-runbook.md readme-baseline block no longer lists demo-tier.md after demotion" ;;
esac
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
  # The delta is demo-tier.md's own word count PLUS the words its now-removed row contributed
  # to the readme-baseline block rendered *inside* conversion-runbook.md — conversion-runbook.md
  # is itself one of the summed baseline docs, and it lists itself and its siblings in its own
  # body, so demoting any baseline skill shrinks two things at once. An exact-equals assertion
  # against DEMO_WORDS alone is therefore too strict; assert the drop is at least demo-tier.md's
  # own body (the table-row contribution is extra, never negative) and bounded well below a
  # whole extra file's worth, so a real regression (e.g. the demoted skill not actually dropping,
  # or an unrelated surface losing content) still fails this.
  DELTA=$((BASE1 - BASE2))
  if [ "$DELTA" -ge "$DEMO_WORDS" ] && [ "$DELTA" -le "$((DEMO_WORDS + 40))" ]; then
    ok "baseline word count dropped by demo-tier.md's body plus its table row ($BASE1 -> $BASE2, -$DELTA, body=$DEMO_WORDS)"
  else
    bad "baseline word count delta out of the expected range for demoting one skill" \
      "before=$BASE1 after=$BASE2 delta=$DELTA demo_body_words=$DEMO_WORDS expected range=[$DEMO_WORDS, $((DEMO_WORDS + 40))]"
  fi
fi

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
