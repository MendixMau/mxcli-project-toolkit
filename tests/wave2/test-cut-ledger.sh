#!/bin/bash
# test-cut-ledger.sh — pin bin/cut-ledger.sh against a CAPTURED slice (fixtures/cut-ledger/, see
# CAPTURE.txt there): a verbatim subset of #293's field run on a public field-service template app.
# No mxcli, no .mpr: the --refs form of the input, plus a catalog.db built from the same rows.
#
#   1. THE CAPTURED LEDGER IS REPRODUCED. 43 refs -> 57 rows whose columns 2-8 equal the field run's
#      own rows, in the field run's order; E-numbers restart at E001. Counts on the summary line.
#   2. EVERY ROW HAS A DECISION. No UNRESOLVED, no unused rule; System is `platform` without a rule.
#   3. MX CHECK NAMES THE CATALOG NEVER SAW become check-only rows; names it did see do not.
#   4. THE EXPORTER IS RECONCILED. The fixed exporter JSON adds no note; the pre-fix transcript flags
#      Technician exactly as the field run did.
#   5. NO DECISION, NO PASS. Drop the retire rule -> that row is UNRESOLVED and the run exits 1.
#      A rule without evidence, an unknown resolution, a bad --extra row, an empty slice: exit 2.
#   6. --catalog READS THE SAME EDGES as --refs (single-tree and two-tree catalog paths);
#      a database without a refs table is exit 2. --dump-refs writes the input back byte for byte.
#   7. DETERMINISTIC.
#
# Usage: bash test-cut-ledger.sh [path-to-cut-ledger.sh]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
CL="${1:-$TOOLKIT/bin/cut-ledger.sh}"
FIX="$TOOLKIT/tests/wave2/fixtures/cut-ledger"
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "no '$3' in: $2" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "unexpected '$3' in: $2" ;; *) ok "$1" ;; esac; }

BASE="--slice $FIX/slice.txt --check-log $FIX/mx-check.txt --extra $FIX/cut-extra.tsv"
# shellcheck disable=SC2086
run() { bash "$CL" $BASE "$@"; }
col() { awk -F'\t' -v c="$2" 'NR>1{print $c}' "$1"; }

echo "== 1. the captured ledger is reproduced =="
run --refs "$FIX/crossing-refs.tsv" --rules "$FIX/cut-rules.tsv" --exporter-json "$FIX/exporter.json" \
  --dump-refs "$TMP/dump.tsv" -o "$TMP/l1.tsv" >"$TMP/o1" 2>&1; RC=$?
check "exits 0" "$RC" "0"
OUT="$(cat "$TMP/o1")"
has "summary counts" "$OUT" "43 crossing refs -> 57 ledger rows (20 out, 22 in from the catalog; 2 check-only; 13 extra)"
has "by-resolution counts" "$OUT" "by resolution: handoff 20, platform 1, resolved 24, retire 1, stub 11"
check "header" "$(head -1 "$TMP/l1.tsv")" "$(printf 'edge\tdirection\tkind\tsource_doc\ttarget_doc\trefs\tresolution\tevidence')"
check "57 rows" "$(($(wc -l <"$TMP/l1.tsv") - 1))" "57"
cut -f2- "$TMP/l1.tsv" >"$TMP/got"; cut -f2- "$FIX/expected-ledger.tsv" >"$TMP/want"
if cmp -s "$TMP/got" "$TMP/want"; then ok "columns 2-8 equal the field run's rows, same order"
else bad "columns 2-8 equal the field run's rows" "$(diff "$TMP/want" "$TMP/got" | head -4)"; fi
check "E-numbers run E001..E057" "$(col "$TMP/l1.tsv" 1 | head -1)..$(col "$TMP/l1.tsv" 1 | tail -1)" "E001..E057"
check "the 42 catalog rows carry all 43 crossing refs (the denominator)" \
  "$(awk -F'\t' 'NR>1 && NR<=43 {s+=$6} END{print s+0}' "$TMP/l1.tsv")" "43"

echo "== 2. every row has a decision =="
check "no UNRESOLVED rows" "$(col "$TMP/l1.tsv" 7 | grep -c '^UNRESOLVED')" "0"
hasnt "no rule left unused" "$OUT" "rules never used"
check "System rows are platform" "$(awk -F'\t' 'NR>1 && $5 ~ /^System\./ {print $7}' "$TMP/l1.tsv" | sort -u)" "platform"
check "out rows 20+2+13, in rows 22" "$(col "$TMP/l1.tsv" 2 | sort | uniq -c | awk '{printf "%s=%s ", $2, $1}')" "in=22 out=35 "

echo "== 3. mx check names the catalog never saw =="
check "2 check-only rows" "$(awk -F'\t' '$3=="check-only"' "$TMP/l1.tsv" | wc -l | tr -d ' ')" "2"
check "they name the two catalog-blind docs" \
  "$(awk -F'\t' '$3=="check-only"{print $5}' "$TMP/l1.tsv" | tr '\n' ' ')" "FSM_Specific.Material_Design_Icons General.ACT_DoNothing_NF "
check "names the catalog already has are not repeated" \
  "$(awk -F'\t' '$3=="check-only" && $5 ~ /^(NativeTechnician|NativeMobile|Administration)\./' "$TMP/l1.tsv" | wc -l | tr -d ' ')" "0"

echo "== 4. the exporter is reconciled =="
hasnt "fixed exporter JSON: no exporter-only note" "$OUT" "exporter-only"
run --refs "$FIX/crossing-refs.tsv" --rules "$FIX/cut-rules.tsv" --exporter-json "$FIX/exporter-prefix.txt" \
  -o "$TMP/l4.tsv" >"$TMP/o4" 2>&1
check "pre-fix exporter: exactly one note" "$(grep -c 'exporter-only' "$TMP/o4")" "1"
has "it is the field run's Technician note" "$(cat "$TMP/o4")" \
  "exporter-only: Technician: exporter counts 2 unit(s) naming it, ledger has 0 out-edges to it"

echo "== 5. no decision, no pass =="
grep -v 'NativeModelCheck' "$FIX/cut-rules.tsv" >"$TMP/rules-noretire.tsv"
run --refs "$FIX/crossing-refs.tsv" --rules "$TMP/rules-noretire.tsv" -o "$TMP/l5.tsv" >"$TMP/o5" 2>&1; RC=$?
check "a crossing edge without a rule: exit 1" "$RC" "1"
check "that one row reads UNRESOLVED" "$(col "$TMP/l5.tsv" 7 | grep -c '^UNRESOLVED')" "1"
has "the run names the count" "$(cat "$TMP/o5")" "UNRESOLVED rows: 1"
has "the row says no rule matched" "$(awk -F'\t' '$7=="UNRESOLVED"{print $8}' "$TMP/l5.tsv")" "no rule in rules-noretire.tsv matches NativeModelCheck."
# a captured rule with its evidence blanked / its resolution replaced
awk -F'\t' 'BEGIN{OFS="\t"} !/^#/ && !d {$4=""; d=1} {print}' "$FIX/cut-rules.tsv" >"$TMP/rules-noev.tsv"
run --refs "$FIX/crossing-refs.tsv" --rules "$TMP/rules-noev.tsv" -o "$TMP/x.tsv" >"$TMP/o5b" 2>&1; RC=$?
check "a rule without evidence: exit 2" "$RC" "2"
has "refusal says why" "$(cat "$TMP/o5b")" "a resolution without evidence is a claim"
awk -F'\t' 'BEGIN{OFS="\t"} !/^#/ && !d {$3="maybe"; d=1} {print}' "$FIX/cut-rules.tsv" >"$TMP/rules-badres.tsv"
run --refs "$FIX/crossing-refs.tsv" --rules "$TMP/rules-badres.tsv" -o "$TMP/x.tsv" >/dev/null 2>&1; RC=$?
check "an unknown resolution: exit 2" "$RC" "2"
awk -F'\t' 'BEGIN{OFS="\t"} !/^#/ && !d {$7=""; d=1} {print}' "$FIX/cut-extra.tsv" >"$TMP/extra-noev.tsv"
bash "$CL" --refs "$FIX/crossing-refs.tsv" --slice "$FIX/slice.txt" --rules "$FIX/cut-rules.tsv" \
  --extra "$TMP/extra-noev.tsv" -o "$TMP/x.tsv" >/dev/null 2>&1; RC=$?
check "an --extra row without evidence: exit 2" "$RC" "2"
grep '^#' "$FIX/slice.txt" >"$TMP/slice-empty.txt"
bash "$CL" --refs "$FIX/crossing-refs.tsv" --slice "$TMP/slice-empty.txt" --rules "$FIX/cut-rules.tsv" -o "$TMP/x.tsv" >/dev/null 2>&1; RC=$?
check "a slice that names nothing: exit 2" "$RC" "2"
bash "$CL" >/dev/null 2>&1; RC=$?
check "no arguments: exit 2" "$RC" "2"
bash "$CL" --refs "$FIX/crossing-refs.tsv" --slice "$FIX/slice.txt" -o "$TMP/x.tsv" >/dev/null 2>&1; RC=$?
check "missing --rules: exit 2" "$RC" "2"

echo "== 5b. an unreadable input is exit 2, never the UNRESOLVED exit 1 (review of #345) =="
run --refs "$FIX/crossing-refs.tsv" --rules "$TMP/no-such-rules.tsv" -o "$TMP/x.tsv" >"$TMP/o5c" 2>&1; RC=$?
check "a missing --rules file: exit 2" "$RC" "2"
has "it names the unreadable input" "$(cat "$TMP/o5c")" "cannot read an input"
run --catalog "$TMP/no-such-catalog.db" --rules "$FIX/cut-rules.tsv" -o "$TMP/x.tsv" >/dev/null 2>&1; RC=$?
check "a nonexistent --catalog: exit 2" "$RC" "2"
printf 'not json at all\n' >"$TMP/bad-exporter.json"
run --refs "$FIX/crossing-refs.tsv" --rules "$FIX/cut-rules.tsv" --exporter-json "$TMP/bad-exporter.json" -o "$TMP/x.tsv" >/dev/null 2>&1; RC=$?
check "an invalid --exporter-json: exit 2" "$RC" "2"
# a captured refs file with one line cut short (its last field dropped)
awk -F'\t' 'BEGIN{OFS="\t"} NR==5 {NF=4} {print}' "$FIX/crossing-refs.tsv" >"$TMP/short-line.tsv"
run --refs "$TMP/short-line.tsv" --rules "$FIX/cut-rules.tsv" -o "$TMP/x.tsv" >"$TMP/o5d" 2>&1; RC=$?
check "a --refs line with the wrong field count: exit 2" "$RC" "2"
has "the refusal counts it and names the line" "$(cat "$TMP/o5d")" "1 line(s) without 5 tab-separated fields (first: line 5)"

echo "== 6. --catalog reads the same edges; --dump-refs round-trips =="
if cmp -s "$TMP/dump.tsv" "$FIX/crossing-refs.tsv"; then ok "--dump-refs writes the input back byte for byte"
else bad "--dump-refs round-trip" "$(diff "$FIX/crossing-refs.tsv" "$TMP/dump.tsv" | head -4)"; fi
for layout in single two; do
  if [ "$layout" = single ]; then DB="$TMP/p-$layout/.mxcli/catalog.db"; else DB="$TMP/p-$layout/app/.mxcli/catalog.db"; fi
  mkdir -p "$(dirname "$DB")"
  "$PY" -c 'import sqlite3, sys
db = sqlite3.connect(sys.argv[2])
db.execute("create table refs (SourceType text, SourceName text, TargetType text, TargetName text, RefKind text, ModuleName text)")
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8")][1:]
db.executemany("insert into refs values (?,?,?,?,?,?)", [r + [r[1].split(".")[0]] for r in rows])
db.commit()' "$FIX/crossing-refs.tsv" "$DB"
  run --catalog "$DB" --rules "$FIX/cut-rules.tsv" --exporter-json "$FIX/exporter.json" -o "$TMP/l6-$layout.tsv" >/dev/null 2>&1; RC=$?
  check "$layout-tree catalog path: exit 0" "$RC" "0"
  if cmp -s "$TMP/l6-$layout.tsv" "$TMP/l1.tsv"; then ok "$layout-tree: --catalog ledger equals the --refs ledger"
  else bad "$layout-tree: --catalog ledger equals the --refs ledger" "$(diff "$TMP/l1.tsv" "$TMP/l6-$layout.tsv" | head -3)"; fi
done
"$PY" -c 'import sqlite3, sys; sqlite3.connect(sys.argv[1]).execute("create table other (x)")' "$TMP/norefs.db"
run --catalog "$TMP/norefs.db" --rules "$FIX/cut-rules.tsv" -o "$TMP/x.tsv" >"$TMP/o6" 2>&1; RC=$?
check "a database without a refs table: exit 2" "$RC" "2"
has "refusal names the missing table" "$(cat "$TMP/o6")" "has no refs table"
printf 'Source\tTarget\n' >"$TMP/badhead.tsv"
run --refs "$TMP/badhead.tsv" --rules "$FIX/cut-rules.tsv" -o "$TMP/x.tsv" >/dev/null 2>&1; RC=$?
check "a refs TSV with the wrong header: exit 2" "$RC" "2"

echo "== 7. deterministic =="
run --refs "$FIX/crossing-refs.tsv" --rules "$FIX/cut-rules.tsv" --exporter-json "$FIX/exporter.json" -o "$TMP/l7.tsv" >/dev/null 2>&1
if cmp -s "$TMP/l7.tsv" "$TMP/l1.tsv"; then ok "two runs are byte-identical"; else bad "two runs are byte-identical"; fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
