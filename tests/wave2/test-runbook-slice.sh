#!/usr/bin/env bash
# Fixture for bin/runbook-slice.sh — the helper roles' replacement for reading the whole runbook.
#
# Usage: bash tests/wave2/test-runbook-slice.sh bin/runbook-slice.sh
#
# Runs against the REAL runbook (its headings are the golden input — a hand-written one would
# encode the same heading assumption the code makes). Read-only: nothing under the toolkit is
# written.
#   T1  every stage token (P, 0-7, build-ready) prints §1b and exactly its own stage section
#   T2  the spans agree with gate-check.sh's "Read for this gate" line (one lib, one answer)
#   T3  Stage 0 is the "### Stage 0 — " section, not "### Stage 0 runs in every entry mode"
#   T4  usage errors: no stage / unknown stage exit 1 and print nothing to stdout
#   T5  the per-role word count counts the slice's OUTPUT for helpers, the runbook for lead
#   T6  every stage also prints the gate-verdict table (all five verdicts with exit codes) and
#       §3b's "a helper ... reports it to the lead" paragraph (review of PR #378)
set -uo pipefail

SUT="${1:?usage: test-runbook-slice.sh /path/to/bin/runbook-slice.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
TK="$(cd "$(dirname "$SUT")/.." && pwd)"
RB="$TK/skills/conversion-runbook.md"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

echo "== T1: §1b plus exactly the requested stage section, for every stage token =="
for st in P 0 1 2 3 4 5 6 7 build-ready; do
  want="$st"; [ "$st" = "build-ready" ] && want=5
  OUT="$(bash "$SUT" "$st" 2>&1)"; RC=$?
  n_1b="$(printf '%s\n' "$OUT" | grep -c '^## 1b\.')"
  n_own="$(printf '%s\n' "$OUT" | grep -c "^### Stage $want — ")"
  n_any="$(printf '%s\n' "$OUT" | grep -c '^### Stage [P0-9] — ')"
  n_2="$(printf '%s\n' "$OUT" | grep -c '^## [0-9]')"
  if [ "$RC" -eq 0 ] && [ "$n_1b" -eq 1 ] && [ "$n_own" -eq 1 ] && [ "$n_any" -eq 1 ] && [ "$n_2" -eq 1 ]; then
    ok "stage $st: exit 0, §1b once, Stage $want once, no other stage, no other ## section"
  else
    bad "stage $st: rc=$RC 1b=$n_1b own=$n_own stages=$n_any top-sections=$n_2"
  fi
done

echo "== T2: the spans match gate-check.sh's line (both read lib/runbook-span.sh) =="
SP="$(bash "$SUT" --spans 2)"
S2="$(grep -n '^### Stage 2 — ' "$RB" | head -1 | cut -d: -f1)"
S1B="$(grep -n '^## 1b\.' "$RB" | head -1 | cut -d: -f1)"
case "$SP" in
  "skills/conversion-runbook.md §1b lines $S1B–"*" + Stage 2 lines $S2–"*) ok "--spans starts each span at its real heading ($S1B, $S2)" ;;
  *) bad "--spans wrong: $SP" ;;
esac
E2="${SP##*–}"
NEXT="$(sed -n "$((E2 + 1))p" "$RB")"
case "$NEXT" in '## '*|'### '*) ok "Stage 2's span ends right before the next heading" ;;
  *) bad "line after Stage 2's span is not a heading: $NEXT" ;; esac
if grep -q 'runbook_stage_span\|runbook_1b_span' "$TK/bin/gate-check.sh" && ! grep -q '^runbook_span()' "$TK/bin/gate-check.sh"; then
  ok "gate-check.sh sources the shared span lib rather than carrying its own copy"
else
  bad "gate-check.sh still defines its own runbook_span"
fi

echo "== T3: Stage 0 is the §2 section, not the Entry Modes subsection =="
OUT0="$(bash "$SUT" 0)"
printf '%s\n' "$OUT0" | grep -q '^### Stage 0 runs in every entry mode' \
  && bad "stage 0 printed the Entry Modes subsection" \
  || ok "stage 0 does not print '### Stage 0 runs in every entry mode'"

echo "== T4: usage errors =="
O="$(bash "$SUT" 2>/dev/null)"; RC=$?
[ "$RC" -eq 1 ] && ok "no stage: exit 1" || bad "no stage: exit $RC"
O="$(bash "$SUT" 9 2>/dev/null)"; RC=$?
[ "$RC" -eq 1 ] && [ -z "$O" ] && ok "unknown stage: exit 1, empty stdout" || bad "unknown stage: exit $RC, stdout '$O'"

echo "== T5: the per-role count reads the slice's output for helpers, the runbook for lead =="
PACK() { MXTK_ROUTING_TSV="$TK/bin/lib/skill-routing.tsv" bash -c '. "$1/bin/lib/skill-routing.sh"; routing_baseline_pack 5 "$1" "$2"' _ "$TK" "$1"; }
for role in mdl gate test review; do
  OUT="$(PACK "$role")"
  W="$(printf '%s' "$OUT" | cut -f1)"; PATHS="$(printf '%s' "$OUT" | cut -f3)"
  case " $PATHS " in *" bin/runbook-slice.sh "*) : ;; *) bad "$role: slice not in its stage-5 pack ($PATHS)"; continue ;; esac
  case " $PATHS " in *" skills/conversion-runbook.md "*) bad "$role: still counts the whole runbook"; continue ;; esac
  SUM=0
  for p in $PATHS; do
    if [ "$p" = "bin/runbook-slice.sh" ]; then n="$(bash "$SUT" 5 | LC_ALL=C wc -w | tr -d ' ')"
    else n="$(LC_ALL=C wc -w < "$TK/$p" | tr -d ' ')"; fi
    SUM=$((SUM + n))
  done
  [ "$SUM" = "$W" ] && ok "$role: stage-5 count ($W) = its .md files + the slice's printed words" \
    || bad "$role: count $W, recomputed $SUM"
done
OUT="$(PACK lead)"; PATHS="$(printf '%s' "$OUT" | cut -f3)"
case " $PATHS " in
  *" bin/runbook-slice.sh "*) bad "lead counts the slice; it reads the runbook" ;;
  *" skills/conversion-runbook.md "*) ok "lead keeps the whole runbook" ;;
  *) bad "lead has no runbook in its pack ($PATHS)" ;;
esac

echo "== T6: the gate-verdict table and §3b's helper-reports-to-lead paragraph, every stage =="
for st in P 0 1 2 3 4 5 6 7; do
  OUT="$(bash "$SUT" "$st" 2>/dev/null)"; MISS=""
  for v in "PASS\` | Checked, and it holds. | 0" "PENDING\`" "FAIL\`" "WAIVED\`" "MANUAL\`"; do
    printf '%s\n' "$OUT" | grep -q "^| \`$v" || MISS="$MISS verdict:${v%%\`*}"
  done
  printf '%s\n' "$OUT" | grep -q 'Exit code on a stage query' || MISS="$MISS exit-code-column"
  printf '%s\n' "$OUT" | grep -q 'A helper that hits a BRD-touching decision reports it to the lead' || MISS="$MISS 3b-helper-reports"
  [ -z "$MISS" ] && ok "stage $st: verdict table (5 verdicts + exit codes) and §3b helper paragraph present" \
    || bad "stage $st: missing$MISS"
done
# Located by heading/anchor through the shared lib, not by line number.
if grep -q 'runbook_verdicts_span' "$SUT" && grep -q 'runbook_3b_owner_span' "$SUT" \
   && ! grep -Eq 'sed -n ["'"'"']?[0-9]+,[0-9]+p["'"'"']? "?\$\{?RB' "$SUT"; then
  ok "runbook-slice.sh finds both spans through lib/runbook-span.sh, no hard-coded line numbers"
else
  bad "runbook-slice.sh does not use runbook_verdicts_span/runbook_3b_owner_span, or hard-codes a line range"
fi

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
