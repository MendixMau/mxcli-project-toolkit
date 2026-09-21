#!/usr/bin/env bash
# routing_baseline_pack (bin/lib/skill-routing.sh) is the ONE place that sizes a stage's
# baseline reading — shared by bin/gate-check.sh's ADVISORY line and by
# bin/render-routing.sh --check's per-stage summary. Its whole claim is that a stage-5 row is
# absent from a stage-3 pack and present in a stage-5 pack, while every "-" (every-stage) row
# is in both. Nothing checked that before this fixture.
#
# It also pins the unrecognised-stage repair (review of PR #99, 2026-09): the function used to
# treat ANY stage token the same as a real one, because a row with stages="-" matches
# regardless of what <stage> is — so a typo'd or stale stage silently got back the every-stage
# rows' total, mislabelled as if it were that (bogus) stage's whole pack, and the caller's own
# "stage unknown, skipped" fallback could never fire. Fixed by having the function check <stage>
# against the known token set itself (P, 0-7) and, on a miss, return the FULL baseline pack with
# an explicit fourth field ("full") instead of a partial number with no way to tell it apart.
# Note: bin/gate-check.sh's own CLI already rejects an unrecognised stage argument before this
# function is ever called from it (see its `case "$REQUESTED_STAGE" in ""|P|p|0-7|build-ready)`
# guard), so this path is unreachable from the command line today. It matters for
# routing_baseline_pack as a SHARED library function: bin/render-routing.sh --check and any
# future caller get the same protection without re-deriving gate-check's guard.
#
# Scaffolding through the real init-project.sh registers the throwaway project name in the
# toolkit leak-guard denylist; send that to scratch, never to the developer's real list.
export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
trap 'rm -f "$MXTK_LEAKGUARD_DENYFILE"' EXIT

set -uo pipefail
SKILL_ROUTING="${1:?usage: test-baseline-pack.sh <path-to-bin/lib/skill-routing.sh>}"
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
OK=0; BAD=0
ok(){ echo "  ok   $1"; OK=$((OK+1)); }
bad(){ echo "  FAIL $1"; BAD=$((BAD+1)); }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
ROOT="$W/root"
mkdir -p "$ROOT/skills"

# Three baseline .md rows: one every-stage ("-"), one stage-3-only, one stage-5-only — plus a
# non-baseline row and a non-.md baseline row that must never be counted. Word counts are
# distinct and easy to eyeball (10 / 20 / 30 words).
words() { i=0; while [ "$i" -lt "$1" ]; do printf 'w '; i=$((i+1)); done; }
words 10 > "$ROOT/skills/always.md"
words 20 > "$ROOT/skills/stage3-only.md"
words 30 > "$ROOT/skills/stage5-only.md"
words 99 > "$ROOT/skills/not-baseline.md"      # tier=ondemand — must be excluded
printf 'script not prose\n' > "$ROOT/skills/stage5.sh"  # baseline but not .md — must be excluded

TSV="$W/scratch-routing.tsv"
cat > "$TSV" <<'EOF'
# name	path	when	agents	stages	tier	group
always	skills/always.md	always relevant	all	-	baseline	spine
stage3only	skills/stage3-only.md	relevant at stage 3	all	3	baseline	spine
stage5only	skills/stage5-only.md	relevant at stage 5	all	5	baseline	spine
situational	skills/not-baseline.md	only when asked	all	-	ondemand	spine
stage5script	skills/stage5.sh	a script, not prose	all	5	baseline	spine
EOF

run_pack() { # run_pack <stage> -> prints the four (or three) tab-separated fields
  MXTK_ROUTING_TSV="$TSV" bash -c '
    source "'"$SKILL_ROUTING"'"
    routing_baseline_pack "$1" "$2"
  ' _ "$1" "$ROOT"
}

echo "== the stage slice (the whole claim of the feature) =="
OUT3="$(run_pack 3)"
OUT5="$(run_pack 5)"
printf '%s' "$OUT3" | grep -qF 'stage3-only.md' \
  && ok "stage-3 row is present in the stage-3 pack" \
  || bad "stage-3 row missing from the stage-3 pack: $OUT3"
printf '%s' "$OUT3" | grep -qF 'stage5-only.md' \
  && bad "stage-5 row leaked into the stage-3 pack: $OUT3" \
  || ok "stage-5 row is absent from the stage-3 pack"
printf '%s' "$OUT5" | grep -qF 'stage5-only.md' \
  && ok "stage-5 row is present in the stage-5 pack" \
  || bad "stage-5 row missing from the stage-5 pack: $OUT5"
printf '%s' "$OUT5" | grep -qF 'stage3-only.md' \
  && bad "stage-3 row leaked into the stage-5 pack: $OUT5" \
  || ok "stage-3 row is absent from the stage-5 pack"
printf '%s' "$OUT3" | grep -qF 'always.md' && printf '%s' "$OUT5" | grep -qF 'always.md' \
  && ok "the every-stage row appears in both packs" \
  || bad "the every-stage row is missing from one of the packs (3: $OUT3 | 5: $OUT5)"

echo "== non-baseline / non-prose rows never counted =="
printf '%s' "$OUT3$OUT5" | grep -qF 'not-baseline.md' \
  && bad "an ondemand-tier row was counted as baseline" \
  || ok "the ondemand row is excluded from every pack"
printf '%s' "$OUT3$OUT5" | grep -qF 'stage5.sh' \
  && bad "a non-.md baseline row was counted" \
  || ok "the .sh baseline row is excluded (not prose)"

echo "== word/file totals =="
W3="$(printf '%s' "$OUT3" | cut -f1)"; F3="$(printf '%s' "$OUT3" | cut -f2)"
W5="$(printf '%s' "$OUT5" | cut -f1)"; F5="$(printf '%s' "$OUT5" | cut -f2)"
[ "$W3" = "30" ] && ok "stage 3 totals 30 words (10 always + 20 stage3-only)" \
  || bad "stage 3 word total wrong: got $W3, wanted 30"
[ "$F3" = "2" ] && ok "stage 3 totals 2 files" || bad "stage 3 file total wrong: got $F3, wanted 2"
[ "$W5" = "40" ] && ok "stage 5 totals 40 words (10 always + 30 stage5-only)" \
  || bad "stage 5 word total wrong: got $W5, wanted 40"
[ "$F5" = "2" ] && ok "stage 5 totals 2 files (the .sh row does not count)" \
  || bad "stage 5 file total wrong: got $F5, wanted 2"

echo "== unrecognised stage: full pack, explicitly labelled, not a silent partial =="
OUTX="$(run_pack GARBAGE)"
WX="$(printf '%s' "$OUTX" | cut -f1)"; FX="$(printf '%s' "$OUTX" | cut -f2)"
MODEX="$(printf '%s' "$OUTX" | cut -f4)"
[ "$MODEX" = "full" ] && ok "an unrecognised stage token is flagged with the 'full' field" \
  || bad "unrecognised-stage output has no 'full' marker: $OUTX"
[ "$WX" = "60" ] && ok "an unrecognised stage returns the FULL pack (10+20+30=60 words), not a partial" \
  || bad "unrecognised-stage word total wrong: got $WX, wanted 60 (the every-stage-only total, 10, would mean the old silent-partial bug is back)"
[ "$FX" = "3" ] && ok "an unrecognised stage counts all 3 baseline .md rows" \
  || bad "unrecognised-stage file total wrong: got $FX, wanted 3"

echo "== a real stage token never carries the 'full' marker =="
MODE3="$(printf '%s' "$OUT3" | cut -f4)"
MODE5="$(printf '%s' "$OUT5" | cut -f4)"
[ -z "$MODE3" ] && [ -z "$MODE5" ] \
  && ok "known stages 3 and 5 report no 'full' marker (three fields only)" \
  || bad "a known stage carried a 'full' marker (3: '$MODE3', 5: '$MODE5')"

echo "== field run: the real toolkit table at every runbook stage returns a non-empty pack =="
FIELD_OK=1
for st in P 0 1 2 3 4 5 6 7; do
  OUT="$(MXTK_ROUTING_TSV="$TOOLKIT/bin/lib/skill-routing.tsv" bash -c '
    source "'"$SKILL_ROUTING"'"
    routing_baseline_pack "$1" "$2"
  ' _ "$st" "$TOOLKIT")"
  W="$(printf '%s' "$OUT" | cut -f1)"
  MODE="$(printf '%s' "$OUT" | cut -f4)"
  case "$W" in ''|*[!0-9]*|0) FIELD_OK=0; bad "stage $st: no words counted against the real table ($OUT)";; esac
  [ -n "$MODE" ] && { FIELD_OK=0; bad "stage $st: real runbook stage carried a 'full' marker ($OUT)"; }
done
[ "$FIELD_OK" -eq 1 ] && ok "every real runbook stage (P,0-7) returns a non-empty, non-'full' pack"

echo ""
echo "$(basename "$0"): $OK ok, $BAD FAIL"
[ "$BAD" -eq 0 ]
