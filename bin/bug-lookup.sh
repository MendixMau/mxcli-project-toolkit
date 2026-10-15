#!/usr/bin/env bash
# bug-lookup.sh — find the bug-log entry that matches an error, so a session reads the ONE
# entry it needs instead of the whole ledger.
#
#   bin/bug-lookup.sh CE0117                      # every entry mentioning CE0117, in full
#   bin/bug-lookup.sh BUG-102                     # that entry, in full
#   bin/bug-lookup.sh '<pasted error message>'    # ranked: top 3 — header, score, one excerpt line
#   bin/bug-lookup.sh --full 2 '<same message>'   # the 2nd ranked entry, in full
#   bin/bug-lookup.sh --exact "widget name"       # literal phrase match, case-insensitive
#   bin/bug-lookup.sh --index                     # one line per entry: id, title, status flags
#
# WHY. bug-logs/mxcli-bugs.md is far too large to read on every session (`wc -w` it for the
# current size; a number written here goes stale). Nobody needs all of it; they need the entry
# that matches the error in front of them. The routing row for the ledger points here.
#
# ONE WORD (a CE code, a BUG id, a keyword) or --exact: matching entries in full, headers only
# above 6 matches. SEVERAL WORDS (a pasted error): ranked. All arguments are joined ("$*"), so
# an unquoted multi-word query is ranked too (before ranking, only $1 was read). Each `## ` entry scores the distinct
# query terms it contains, weighted by IDF (rare terms count more); CE codes and BUG ids x3, a
# term in the header x1.5, an exact BUG id in the header +100. "No confident match" is printed
# when the best entry covers < MXTK_BUG_MINCOV (default 0.40) of the query's term weight, or
# when the query's CE code is in no entry. Measured on tests/wave2/fixtures/bug-lookup/.
# Exit: 0 entries printed (the "no confident match" banner too: it still lists the nearest 3),
# 1 nothing matches or no query, 2 no ledger or a bad --full rank.
# Bash 3.2 + POSIX awk (mawk, gawk, BWK awk); no gawk-isms.
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${MXTK_BUG_LOG:-$ROOT/bug-logs/mxcli-bugs.md}"
[ -f "$LOG" ] || { echo "bug-lookup: no ledger at $LOG" >&2; exit 2; }
usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

index() {
  grep -n '^## ' "$LOG" | grep -v '^[0-9]*:## Provenance' | sed -E 's/^([0-9]+):## /\1\t/' \
    | awk -F'\t' '{ flags=""; if ($2 ~ /RESOLVED|NOT REPRODUCED|RETIRED|SUPERSEDED/) flags=" [closed]"; if ($2 ~ /NOT YET FILED|unfiled/) flags=flags " [unfiled]"; print $2 flags }'
}
FULL=""; EXACT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --index) index; exit 0 ;;
    --exact) EXACT=1; shift ;;
    --full)  [ "$#" -ge 2 ] || usage; FULL="$2"; shift 2
             case "$FULL" in ''|*[!0-9]*|0) echo "bug-lookup: --full takes a rank (1, 2, 3)" >&2; exit 2 ;; esac ;;
    --) shift; break ;;
    *) break ;;
  esac
done
Q="$*"
[ -n "$Q" ] || usage

# --- Ranked path: several words, or --full ------------------------------------------------
case "$Q" in *[[:space:]]*) MULTI=1 ;; *) MULTI=0 ;; esac
if [ -n "$FULL" ] || { [ "$MULTI" = 1 ] && [ "$EXACT" = 0 ]; }; then
  TOP="${MXTK_BUG_TOP:-3}"; [ -n "$FULL" ] && [ "$FULL" -gt "$TOP" ] && TOP="$FULL"
  # The query goes in through ENVIRON, not -v: -v expands backslash escapes (a pasted Windows
  # path would change). LC_ALL=C: byte semantics, so every awk tokenises and truncates alike.
  OUT="$(BUGQ="$Q" LC_ALL=C awk -v TOP="$TOP" -v MINCOV="${MXTK_BUG_MINCOV:-0.40}" -v FULL="${FULL:-0}" '
function toks(s, out,   n, i, a, t, m) {        # s -> out[token]=1 ; returns count
  s = tolower(s); n = 0
  while (index(s, "bug-") && match(s, /(bug-[a-z]+[0-9]+|bug-[0-9]+|bug-draft-[a-z0-9-]+)/)) {
    t = substr(s, RSTART, RLENGTH); sub(/[-]+$/, "", t)
    if (!(t in out)) { out[t] = 1; n++ }
    s = substr(s, 1, RSTART-1) " " substr(s, RSTART+RLENGTH)
  }
  m = split(s, a, /[^a-z0-9_]+/)
  for (i = 1; i <= m; i++) { t = a[i]
    if (length(t) < 3 || (t in STOP) || t ~ /^[0-9]+$/) continue
    if (!(t in out)) { out[t] = 1; n++ } }
  return n
}
BEGIN {
  ns = split("the and for are was were with this that not from into its has have had but can " \
             "cannot could should would will been being which when where what who how than then " \
             "there their they them you your our out any all one two per via value error errors " \
             "warning failed fail error_ at", sw, " ")
  for (i = 1; i <= ns; i++) STOP[sw[i]] = 1
  nq = toks(ENVIRON["BUGQ"], QT)
}
/^## / { if ($0 ~ /^## Provenance/) { cur = 0; next }
         N++; cur = N; HDR[N] = substr($0, 4); START[N] = NR
         delete H; toks(HDR[N], H); for (t in H) HT[N SUBSEP t] = 1 }
cur {
  delete L; toks($0, L)
  for (t in L) if (t in QT) {
      if (!((cur SUBSEP t) in ET)) { ET[cur SUBSEP t] = 1; DF[t]++ }
      if ($0 !~ /^## / && $0 ~ /[a-zA-Z]/ && !((cur SUBSEP t) in EX)) EX[cur SUBSEP t] = $0 }
}
END {
  for (t in QT) if (t ~ /^ce[0-9]+$/ && !(t in DF)) UNK = UNK " " toupper(t)
  for (t in QT) if (DF[t] > 0) { IDF[t] = log((N + 1) / DF[t]); if (t ~ /^(ce[0-9]+|bug-)/) IDF[t] *= 3; TOT += IDF[t] }
  for (e = 1; e <= N; e++) { s = 0; best = ""; bw = -1
    for (t in QT) if ((e SUBSEP t) in ET) { w = IDF[t]; if ((e SUBSEP t) in HT) w *= 1.5
      if (t ~ /^bug-/ && ((e SUBSEP t) in HT)) w += 100
      s += w
      # excerpt: the rarest matched term; ties by term text, so every awk picks the same line
      if (((e SUBSEP t) in EX) && (IDF[t] > bw || (IDF[t] == bw && t < best))) { bw = IDF[t]; best = t } }
    SC[e] = s; BT[e] = best }
  for (k = 1; k <= TOP; k++) { m = 0; mi = 0
    for (e = 1; e <= N; e++) if (!(e in USED) && SC[e] > m) { m = SC[e]; mi = e }
    if (!mi) break; USED[mi] = 1; R[k] = mi }
  if (!(1 in R)) { print "bug-lookup: no ledger entry shares a term with the query — likely not a known tool quirk."; exit 1 }
  if (FULL > 0) { if (FULL in R) { print "@" START[R[FULL]]; exit 0 }
                  print "bug-lookup: fewer than " FULL " entries share a term with the query."; exit 1 }
  cov = (TOT > 0) ? SC[R[1]] / (TOT * 1.5) : 0; if (cov > 1) cov = 1
  if (UNK != "") printf "bug-lookup: no ledger entry mentions%s — likely not a known tool quirk. Nearest by wording:\n", UNK
  else if (cov < MINCOV) printf "bug-lookup: no confident match (best covers %.0f%% of query weight) — likely not a known tool quirk. Nearest:\n", cov * 100
  for (k = 1; k <= TOP && (k in R); k++) { e = R[k]
    x = EX[e SUBSEP BT[e]]; gsub(/^[ \t>*`-]+/, "", x)
    if (length(x) > 160) { x = substr(x, 1, 157); sub(/[\300-\377][\200-\277]*$/, "", x); x = x "..." }
    printf "%d. [%.1f] %s\n     %s\n", k, SC[e], HDR[e], x }
  print "(--full N with the same query prints entry N in full)"
}' "$LOG")" || { printf '%s\n' "$OUT"; exit 1; }
  case "$OUT" in
    @*) awk -v S="${OUT#@}" 'NR >= S { if (NR > S && /^## /) exit; print }' "$LOG" ;;
    *)  printf '%s\n' "$OUT" ;;
  esac
  exit 0
fi

# --- One word, or --exact: literal case-insensitive match, entries in full ----------------
# Entry boundaries: line numbers of every `## ` header.
HDR=()   # no mapfile: macOS ships bash 3.2 (bin/lib/portable.sh)
while IFS= read -r _n; do HDR+=("$_n"); done < <(grep -n '^## ' "$LOG" | cut -d: -f1)
TOTAL=$(wc -l < "$LOG")
entry_range() { # $1 = header line no → prints "start end"
  local i n=${#HDR[@]} start=$1 end=$TOTAL
  for ((i=0;i<n;i++)); do if [ "${HDR[$i]}" -gt "$start" ]; then end=$((HDR[$i]-1)); break; fi; done
  echo "$start $end"
}
# Which entries match: header match first, then body match.
matches=""
for h in "${HDR[@]}"; do
  read -r a b < <(entry_range "$h")
  if sed -n "${a},${b}p" "$LOG" | grep -qiF -- "$Q"; then matches="$matches $h"; fi
done
set -- $matches
if [ "$#" -eq 0 ]; then echo "bug-lookup: nothing in the ledger mentions '$Q' — it may be a modelling mistake, not a tool quirk. Try a shorter keyword or the CE code."; exit 1; fi
if [ "$#" -gt 6 ]; then
  echo "bug-lookup: $# entries mention '$Q' — headers only; narrow the query to read one:"
  for h in "$@"; do sed -n "${h}p" "$LOG" | sed 's/^## /  /'; done; exit 0
fi
for h in "$@"; do read -r a b < <(entry_range "$h"); sed -n "${a},${b}p" "$LOG"; echo; done
