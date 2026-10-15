#!/usr/bin/env bash
# test-bug-lookup.sh — bin/bug-lookup.sh: ranked lookup of a pasted error, and the one-word path.
#
# Usage: bash tests/wave2/test-bug-lookup.sh [path-to-bug-lookup.sh]
#
# Field-proof (CLAUDE.md "Shipping an instrument", rule 1): every query in fixtures/bug-lookup/
# is a real error string — mxcli's public source and test data, or raw tool output quoted in the
# ledger — with module/widget names swapped. Columns: id, query, expected header keys
# (|-separated; NONE = no entry should match confidently), source.
#   dev.tsv      40 queries the ranker was tuned on (IDF, boosts, the 40% floor, the
#                unknown-CE rule were all chosen after seeing them) — a regression floor only
#   heldout.tsv  18 queries written before the ranker ever ran on them — the honest number
# A no-match row carrying a CE code passes mainly because no entry mentions that code. Once
# the ledger gains an entry for it the row is stale: it is skipped with a printed note and
# the floors are computed over the remaining rows. Rows with no CE code (dev q43, held-out
# h16-h18) exercise the 40% coverage floor instead.
# Runs against the live ledger: a new entry can move a label. If a floor drops, read the
# printed per-query table before touching a floor.
#
#   Q  dev and held-out scores (top-1, top-3, confident-wrong) are at or above their floors
#   W  a ranked answer stays short: at most 200 words per query
#   X  every other awk on PATH (mawk, gawk, original-awk = BWK) prints the same ranking
#   L  one word keeps the full-entry path: BUG-n, CE code, keyword, --index, --exact
#   F  --full N prints the N-th ranked entry in full and stops at the next entry
#   U  usage: no query exits 1; --full 0 exits 2; a backslash in the query survives (`\\n` is
#      not read as a newline: same ranking as the query with the backslashes spaced out)
set -uo pipefail

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBJ="${1:-$TOOLKIT/bin/bug-lookup.sh}"
case "$SUBJ" in /*) ;; *) SUBJ="$PWD/$SUBJ" ;; esac
FX="$TOOLKIT/tests/wave2/fixtures/bug-lookup"
export MXTK_BUG_LOG="$TOOLKIT/bug-logs/mxcli-bugs.md"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/buglookup.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

# Floors: measured 2026-10-15 — dev 89/94/8, held-out 92/100/17 (top-1/top-3/confident-wrong %),
# identical under gawk, mawk and BWK awk — minus a margin: held-out allows 3 misses of 12 at
# top-1, 2 at top-3, and 4 confident-wrong of 18. KNOWN GAP: the 40% coverage floor caught none
# of the 4 no-match rows without a CE code (q43, h16-h18 all answered confidently); coverage
# does not separate them from correct answers (32-68% vs 45-67%). A fix needs a new held-out set.
DEV_TOP1=80;  DEV_TOP3=88;  DEV_CW=12
HO_TOP1=75;   HO_TOP3=80;   HO_CW=22

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
[ -f "$SUBJ" ] || { echo "no subject at $SUBJ"; exit 2; }

# run_set <tsv> <tag> [awk-dir]: one output file per query in $WORK/<tag>/
run_set() {
  mkdir -p "$WORK/$2"
  grep -v '^#' "$1" | while IFS="$(printf '\t')" read -r id q _exp _src; do
    [ -n "$id" ] || continue
    if [ -n "${3:-}" ]; then PATH="$3:$PATH" bash "$SUBJ" "$q"; else bash "$SUBJ" "$q"; fi \
      > "$WORK/$2/$id" 2>&1
  done
}
# score <tsv> <tag>: prints "top1% top3% cw% maxwords" and the per-query table to $WORK/<tag>.table
score() {
  grep -v '^#' "$1" | while IFS="$(printf '\t')" read -r id q exp _src; do
    [ -n "$id" ] || continue
    if [ "$exp" = NONE ]; then ce="$(printf '%s' "$q" | grep -oE 'CE[0-9]{4}' | head -1)"
      if [ -n "$ce" ] && grep -q "$ce" "$MXTK_BUG_LOG"; then
        echo "  note: $id skipped — $ce is in the ledger now, so the no-match label is stale" >&2; continue; fi
    fi
    printf '%s\t%s\t' "$id" "$exp"; tr '\n' '\036' < "$WORK/$2/$id"; echo
  done | awk -F'\t' -v T="$WORK/$2.table" '
    { id = $1; n = split($2, K, "|"); none = ($2 == "NONE"); out = $3
      conf = (index(out, "likely not a known tool quirk") == 0)
      m = split(out, L, "\036"); h = 0; w = 0
      for (i = 1; i <= m; i++) { w += split(L[i], junk, " ")
        if (L[i] ~ /^[0-9]+\. \[[0-9.]+\] /) { h++; H[h] = L[i]; sub(/^[0-9]+\. \[[0-9.]+\] /, "", H[h]) } }
      if (w > MW) MW = w
      if (none) { NN++; r = (h && conf) ? "FALSE-HIT" : "ok"; if (r != "ok") CW++ }
      else { NP++; r = "-"
        for (i = 1; i <= h && i <= 3; i++) for (j = 1; j <= n; j++) if (index(H[i], K[j])) { if (r == "-") r = i; break }
        if (r == 1) T1++; if (r != "-") T3++; if (r == "-" && h && conf) { CW++; r = "CW" } }
      printf "%s\t%s\t%s\n", id, r, conf ? "confident" : "banner" > T }
    END { printf "%d %d %d %d %d %d\n", int(100*T1/NP+.5), int(100*T3/NP+.5), int(100*CW/(NP+NN)+.5), MW, NP, NN }'
}

echo "== Q: scores against the labelled sets"
run_set "$FX/dev.tsv" dev; run_set "$FX/heldout.tsv" ho
read -r d1 d3 dcw dmw dnp dnn <<EOF
$(score "$FX/dev.tsv" dev)
EOF
read -r h1 h3 hcw hmw hnp hnn <<EOF
$(score "$FX/heldout.tsv" ho)
EOF
echo "  dev      ($dnp positive, $dnn no-match): top-1 $d1%  top-3 $d3%  confident-wrong $dcw%"
echo "  held-out ($hnp positive, $hnn no-match): top-1 $h1%  top-3 $h3%  confident-wrong $hcw%"
[ "$d1" -ge "$DEV_TOP1" ] && ok "dev top-1 $d1% >= $DEV_TOP1%" || bad "dev top-1 $d1% < $DEV_TOP1%"
[ "$d3" -ge "$DEV_TOP3" ] && ok "dev top-3 $d3% >= $DEV_TOP3%" || bad "dev top-3 $d3% < $DEV_TOP3%"
[ "$dcw" -le "$DEV_CW" ] && ok "dev confident-wrong $dcw% <= $DEV_CW%" || bad "dev confident-wrong $dcw% > $DEV_CW%"
[ "$h1" -ge "$HO_TOP1" ] && ok "held-out top-1 $h1% >= $HO_TOP1%" || bad "held-out top-1 $h1% < $HO_TOP1%"
[ "$h3" -ge "$HO_TOP3" ] && ok "held-out top-3 $h3% >= $HO_TOP3%" || bad "held-out top-3 $h3% < $HO_TOP3%"
[ "$hcw" -le "$HO_CW" ] && ok "held-out confident-wrong $hcw% <= $HO_CW%" || bad "held-out confident-wrong $hcw% > $HO_CW%"
if [ "$FAIL" -gt 0 ]; then echo "  per query (rank of first correct header, '-' none in top 3, CW confident-wrong):"
  paste - - - - - < <(cat "$WORK/dev.table" "$WORK/ho.table" | tr '\t' ' ') | sed 's/^/    /'; fi

echo "== W: context cost"
mw=$dmw; [ "$hmw" -gt "$mw" ] && mw=$hmw
[ "$mw" -le 200 ] && ok "longest ranked answer: $mw words (<= 200)" || bad "longest ranked answer: $mw words (> 200)"

echo "== X: the same ranking under every awk on PATH (default: $(awk --version 2>&1 </dev/null | head -1))"
# BUG_LOOKUP_AWKS="/path/to/awk ..." adds builds that are not on PATH (an older BWK, say).
nx=0; seen="$(command -v awk)"
for a in mawk gawk original-awk nawk ${BUG_LOOKUP_AWKS:-}; do
  p="$(command -v "$a" 2>/dev/null)" || continue
  dup=0; for s in $seen; do [ "$p" -ef "$s" ] && dup=1; done; [ "$dup" = 1 ] && continue; seen="$seen $p"
  a="awk$nx"
  mkdir -p "$WORK/bin-$a"; ln -s "$p" "$WORK/bin-$a/awk"
  run_set "$FX/dev.tsv" "dev-$a" "$WORK/bin-$a"; run_set "$FX/heldout.tsv" "ho-$a" "$WORK/bin-$a"
  if diff -r "$WORK/dev" "$WORK/dev-$a" >/dev/null && diff -r "$WORK/ho" "$WORK/ho-$a" >/dev/null; then
    ok "$p ($("$p" --version 2>&1 </dev/null | head -1)): identical output on all queries"
  else bad "$p: output differs — $(diff -r "$WORK/dev" "$WORK/dev-$a" | head -3 | tr '\n' ' ')"; fi
  nx=$((nx+1))
done
[ "$nx" -gt 0 ] || echo "  (no other awk on PATH: X not run)"

echo "== L: one word keeps the full-entry path"
o="$(bash "$SUBJ" BUG-102)"
[ "$(printf '%s\n' "$o" | head -1 | cut -c1-11)" = "## BUG-102:" ] && [ "$(printf '%s\n' "$o" | grep -c '^## ')" = 1 ] \
  && [ "$(printf '%s\n' "$o" | wc -l)" -gt 10 ] && ok "BUG-102: that one entry, in full" || bad "BUG-102: $(printf '%s\n' "$o" | head -2)"
o="$(bash "$SUBJ" CE0053)"
printf '%s\n' "$o" | grep -q '^## ' && ! printf '%s\n' "$o" | grep -qE '^[0-9]+\. \[' \
  && ok "CE0053: entries in full, not ranked" || bad "CE0053: $(printf '%s\n' "$o" | head -2)"
n_hdr=$(grep '^## ' "$MXTK_BUG_LOG" | grep -vc '^## Provenance')
[ "$(bash "$SUBJ" --index | wc -l | tr -d ' ')" = "$n_hdr" ] && ok "--index: $n_hdr lines, one per entry" || bad "--index line count"
o="$(bash "$SUBJ" --exact "widget name")"; rc=$?
! printf '%s\n' "$o" | grep -qE '^[0-9]+\. \[' && ok "--exact: literal path, not ranked (exit $rc)" || bad "--exact ranked"

echo "== F: --full N"
q='[error] [CE0710] "The main flow cannot join an error flow or end in an error event."'
o="$(bash "$SUBJ" --full 1 "$q")"
[ "$(printf '%s\n' "$o" | head -1 | cut -c1-10)" = "## BUG-73:" ] && [ "$(printf '%s\n' "$o" | grep -c '^## ')" = 1 ] \
  && [ "$(printf '%s\n' "$o" | wc -l)" -gt 10 ] && ok "--full 1: BUG-73 in full, one entry" || bad "--full 1: $(printf '%s\n' "$o" | head -1)"
second=$(bash "$SUBJ" "$q" | grep '^2\. \[' | sed 's/^2\. \[[0-9.]*\] //' | cut -c1-40)
[ -n "$second" ] && [ "$(bash "$SUBJ" --full 2 "$q" | head -1 | cut -c4-43)" = "$second" ] \
  && ok "--full 2: the entry ranked 2nd" || bad "--full 2 is not the 2nd ranked entry"

echo "== U: usage"
bash "$SUBJ" >/dev/null 2>&1; [ $? = 1 ] && ok "no query: exit 1" || bad "no query: wrong exit"
bash "$SUBJ" --full 0 x >/dev/null 2>&1; [ $? = 2 ] && ok "--full 0: exit 2" || bad "--full 0: wrong exit"
o="$(bash "$SUBJ" 'see C:\nanoflow\nanoflow' 2>&1)"; rc=$?
o2="$(bash "$SUBJ" 'see C: nanoflow nanoflow' 2>&1)"
[ "$rc" = 0 ] && [ -n "$o" ] && [ "$o" = "$o2" ] && ok "backslashes in the query survive: \\nanoflow ranks as nanoflow" \
  || bad "backslash query: exit $rc, or ranked differently from the spaced-out query"

echo
echo "bug-lookup: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
