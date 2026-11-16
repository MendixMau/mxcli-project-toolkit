#!/usr/bin/env bash
# test-change-log.sh — the PROJECT.md "## Change log" (skills/change-intake.md): init writes it,
# sync appends it once to an older project, gate-check counts what it owes as WARN and never blocks,
# and exec.sh's --cr tag lands in the BUILD-LOG detail cell.
#
# Usage: bash tests/wave2/test-change-log.sh bin/gate-check.sh
#
# GOLDEN INPUT IS THE REAL SCAFFOLD. Every PROJECT.md here is written by the real
# bin/init-project.sh; rows are appended under the table header that init itself wrote, never
# into a hand-typed register. A "pre-change-log" project is the real scaffold with the section
# cut out — exactly what a project scaffolded before this section existed looks like.
#
#   T1  init writes the section: heading, legend, the 9-column header, no rows
#   T2  scan counts: open/refined/agreed pending, applied/proven with no Closed-by, unknown status,
#       rejected and evidenced rows not owed; escaped pipe kept; comment + other-section rows ignored
#   T3  gate-check prints "Change log: WARN — 3 of 8 …" and lists the owed rows
#   T4  WARN never blocks: exit codes of a full run and of a Stage 5 query are identical with and
#       without owed rows
#   T5  all rows closed → PASS line naming the count
#   T6  no section → WARN naming sync-project.sh, still not blocking
#   T7  sync appends the section to an older project exactly once; second run writes nothing;
#       --dry-run writes nothing
#   T8  exec.sh --cr: a malformed id is refused (exit 2) before anything needs a project; a
#       well-formed one passes through to --change-class; the BUILD-LOG detail carries "cr:"
#   T9  CRLF PROJECT.md (saved on Windows): the section is found, the scan and the gate line
#       match the LF copy exactly, and sync does not append a second section

export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
export MXTK_NO_GUIDE=1
export MXTK_SYNC_SKIP_CLONE_CHECK=1
# No pipefail, on purpose: every pipeline here is `printf "$OUT" | grep -q …`, and under pipefail a
# grep -q that matches early can SIGPIPE printf on a long $OUT, turning a hit into a FAIL. Seen as
# an intermittent "no sync message" in T7 (2026-10-13). No assertion reads an upstream exit code.
set -u

GATE="${1:?usage: test-change-log.sh /path/to/gate-check.sh}"
case "$GATE" in /*) ;; *) GATE="$PWD/$GATE" ;; esac
TK="$(cd "$(dirname "$GATE")/.." && pwd)"
INIT="$TK/bin/init-project.sh"
SYNC="$TK/bin/sync-project.sh"
EXEC="$TK/project-bin/exec.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/chglog.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"; rm -f "$MXTK_LEAKGUARD_DENYFILE"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

. "$TK/bin/lib/change-log.sh"

mkproj() {
  local d="$WORK/$1"; mkdir -p "$d"; : > "$d/Fixture.mpr"
  "$INIT" "$d" >/dev/null 2>&1
  echo "$d"
}
# Append rows (stdin) directly under the change-log table's separator row that init wrote.
add_rows() {
  local f="$1" rows; rows="$(cat)"
  MXTK_ROWS="$rows" awk '
    { print }
    /^## +Change log/ { sec = 1 }
    sec && /^\|---/ && !done { print ENVIRON["MXTK_ROWS"]; done = 1 }
  ' "$f" > "$f.new" && mv "$f.new" "$f"
}
cut_section() {  # remove "## Change log" up to the next "## " heading
  awk '/^## +Change log/ { skip = 1; next } skip && /^## / { skip = 0 } !skip { print }' "$1" > "$1.new" && mv "$1.new" "$1"
}
count_heading() { grep -c '^## Change log' "$1" | tr -d ' '; }

echo "== T1: init writes the change-log section =="
P="$(mkproj t1)"
R="$P/PROJECT.md"
[ "$(count_heading "$R")" = "1" ] && ok "exactly one '## Change log' heading" || bad "heading count $(count_heading "$R")"
grep -qF '| CR | Date | Source | Verbatim ask | Class | Size | Entry artifact | Status | Closed-by |' "$R" \
  && ok "9-column header row present" || bad "header row missing"
grep -q 'skills/change-intake.md' "$R" && ok "legend points at skills/change-intake.md" || bad "legend missing"
S="$(mxtk_change_log_scan "$R" | head -n 1)"
[ "$S" = "$(printf 'SUMMARY\t0\t0\t0\t0\t0\t0')" ] && ok "fresh scaffold: 0 rows, nothing owed" || bad "fresh scan: $S"
# Section order: after Decisions, before Open questions (the register reads top-down).
ORDER="$(grep -n '^## ' "$R" | sed 's/^[0-9]*:## //' | tr '\n' '|')"
case "$ORDER" in *"Decisions|Change log|Open questions"*) ok "sits between Decisions and Open questions" ;;
  *) bad "section order: $ORDER" ;; esac

echo "== T2: scan counts =="
P="$(mkproj t2)"
R="$P/PROJECT.md"
add_rows "$R" <<'EOF'
| CR-01 | 2026-10-13 | user | Customer also needs a VAT number | requirement | S | F003.brd.json | proven | abc1234, journey customer-edit |
| CR-02 | 2026-10-13 | user | Orders overview should be a gallery, not a grid | visual | S | design/ui-reviews/orders | applied | |
| CR-03 | 2026-10-13 | stakeholder (finance lead) | Approvals over 10k need a second approver | decision | L | PROJECT.md new row | open | |
| CR-04 | 2026-10-13 | user | Search \| Reset buttons do nothing | bug | S | none | **agreed** | |
| CR-05 | 2026-10-13 | user | Drop the export button | visual | S | wireframe orders | rejected — export is contractual | |
| CR-06 | 2026-10-13 | user | Rename the status labels | impl | S | none | done | abc1234 |
| CR-07 | 2026-10-13 | stakeholder (ops) | Two-step approval for refunds | requirement | M | F005.brd.json | refined 2026-10-13 | |
| CR-08 | 2026-10-13 | user | Default sort newest first | visual | S | design/ui-reviews/orders | applied | — |
EOF
# Rows the scan must NOT count: one inside an HTML comment in the section, one in another section.
printf '\n<!-- | CR-90 | 2026-10-13 | user | example | visual | S | x | open | | -->\n' >> "$R"
printf '\n## Notes\n\n| CR-91 | 2026-10-13 | user | not in the change log | visual | S | x | open | |\n' >> "$R"
OUT="$(mxtk_change_log_scan "$R")"
S="$(printf '%s\n' "$OUT" | head -n 1)"
# total 8 | open 1 | refined 1 | agreed 1 | no evidence 2 (CR-02 blank, CR-08 em-dash) | unknown 1
[ "$S" = "$(printf 'SUMMARY\t8\t1\t1\t1\t2\t1')" ] && ok "SUMMARY 8 total, 1/1/1 pending, 2 no-evidence, 1 unknown" \
  || bad "SUMMARY wrong" "$S"
for id in CR-02 CR-03 CR-04 CR-06 CR-07 CR-08; do
  printf '%s\n' "$OUT" | grep -q "^ROW	$id	" && ok "$id listed as owing" || bad "$id not listed" "$OUT"
done
for id in CR-01 CR-05 CR-90 CR-91; do
  printf '%s\n' "$OUT" | grep -q "	$id	" && bad "$id listed but owes nothing / is out of scope" "$OUT" || ok "$id not listed"
done
printf '%s\n' "$OUT" | grep -q 'Search | Reset buttons' && ok "escaped pipe kept in the ask, status still read" \
  || bad "escaped pipe mangled" "$OUT"
printf '%s\n' "$OUT" | grep -q "^ROW	CR-06	done	unrecognised status" && ok "'done' reported as unrecognised" \
  || bad "unknown status not reported" "$OUT"

echo "== T3: gate-check prints the WARN line and the rows =="
OUT="$("$GATE" --no-html "$P" 2>&1)"; RC_OWED=$?
LINE="$(printf '%s\n' "$OUT" | grep '^Change log:' | head -1)"
case "$LINE" in
  "Change log: WARN — 3 of 8 change request(s) not yet applied (open 1, refined 1, agreed 1); 2 applied/proven with no Closed-by; 1 with an unrecognised status — warn-only"*)
    ok "WARN line with exact counts" ;;
  *) bad "WARN line wrong" "$LINE" ;;
esac
N="$(printf '%s\n' "$OUT" | grep -cE '^  CR-0[0-9] ')"
[ "$N" = "6" ] && ok "6 owed rows listed under it" || bad "listed $N rows, want 6" "$(printf '%s\n' "$OUT" | grep -A8 '^Change log:')"

echo "== T4: WARN never blocks =="
Q="$(mkproj t4)"   # same scaffold, no rows
OUT0="$("$GATE" --no-html "$Q" 2>&1)"; RC_CLEAN=$?
[ "$RC_OWED" = "$RC_CLEAN" ] && ok "full run exit $RC_OWED with owed rows = $RC_CLEAN without" \
  || bad "full-run exit differs: owed=$RC_OWED clean=$RC_CLEAN"
"$GATE" --no-html "$P" 5 >/dev/null 2>&1; R5A=$?
"$GATE" --no-html "$Q" 5 >/dev/null 2>&1; R5B=$?
[ "$R5A" = "$R5B" ] && ok "Stage 5 query exit $R5A with owed rows = $R5B without" \
  || bad "Stage 5 exit differs: owed=$R5A clean=$R5B"
# Stage 5 exits 2 on a scaffold with no BRDs (open questions NOT EVALUATED), so it cannot show a
# pass surviving. Stage P can: its gate reads only intake/PROJECT.md, which T2 left untouched.
"$GATE" --no-html "$P" P >/dev/null 2>&1; RPA=$?
"$GATE" --no-html "$Q" P >/dev/null 2>&1; RPB=$?
[ "$RPA" = "$RPB" ] && ok "Stage P query exit $RPA with owed rows = $RPB without" \
  || bad "Stage P exit differs: owed=$RPA clean=$RPB"
printf '%s\n' "$("$GATE" --no-html "$P" 5 2>&1)" | grep -qi 'BLOCKED.*change' \
  && bad "a change-log row produced a BLOCKED line" || ok "no BLOCKED line mentions the change log"
L0="$(printf '%s\n' "$OUT0" | grep '^Change log:')"
case "$L0" in "Change log: PASS — 0 change requests logged"*) ok "empty table: PASS, says 0 logged and that unlogged changes are invisible" ;;
  *) bad "empty-table line" "$L0" ;; esac

echo "== T5: everything closed → PASS =="
P5="$(mkproj t5)"
add_rows "$P5/PROJECT.md" <<'EOF'
| CR-01 | 2026-10-13 | user | Customer also needs a VAT number | requirement | S | F003.brd.json | proven | abc1234, journey customer-edit |
| CR-02 | 2026-10-13 | user | Drop the export button | visual | S | wireframe orders | rejected (contractual) | |
| CR-03 | 2026-10-13 | user | Default sort newest first | visual | S | design/ui-reviews/orders | applied | def5678 |
EOF
L="$("$GATE" --no-html "$P5" 2>&1 | grep '^Change log:')"
[ "$L" = "Change log: PASS — 3 change request(s); every one applied with evidence, proven, or rejected" ] \
  && ok "PASS line names 3" || bad "PASS line" "$L"

echo "== T6: no section → WARN naming sync-project.sh =="
P6="$(mkproj t6)"; cut_section "$P6/PROJECT.md"
L="$("$GATE" --no-html "$P6" 2>&1 | grep '^Change log:')"
case "$L" in "Change log: WARN — no '## Change log' section in PROJECT.md — run bin/sync-project.sh"*) ok "missing section is a WARN that names the fix" ;;
  *) bad "missing-section line" "$L" ;; esac

echo "== T7: sync appends once =="
P7="$(mkproj t7)"; cut_section "$P7/PROJECT.md"
[ "$(count_heading "$P7/PROJECT.md")" = "0" ] && ok "precondition: an older project with no section" || bad "cut_section failed"
B="$(cat "$P7/PROJECT.md")"
"$SYNC" "$P7" --dry-run >/dev/null 2>&1
[ "$B" = "$(cat "$P7/PROJECT.md")" ] && ok "--dry-run wrote nothing" || bad "--dry-run modified PROJECT.md"
OUT="$("$SYNC" "$P7" 2>&1)"
[ "$(count_heading "$P7/PROJECT.md")" = "1" ] && ok "first sync: section appended" || bad "first sync: $(count_heading "$P7/PROJECT.md") headings"
printf '%s\n' "$OUT" | grep -q "appended the '## Change log' section" && ok "sync says what it appended" || bad "no sync message"
mxtk_change_log_has_section "$P7/PROJECT.md" && [ "$(mxtk_change_log_scan "$P7/PROJECT.md" | head -n 1)" = "$(printf 'SUMMARY\t0\t0\t0\t0\t0\t0')" ] \
  && ok "appended section parses (0 rows)" || bad "appended section does not parse"
A1="$(cat "$P7/PROJECT.md")"
OUT2="$("$SYNC" "$P7" 2>&1)"
[ "$A1" = "$(cat "$P7/PROJECT.md")" ] && ok "second sync: PROJECT.md unchanged" || bad "second sync rewrote PROJECT.md"
printf '%s\n' "$OUT2" | grep -q "Change log" && bad "second sync still reports the section" || ok "second sync silent about it"
# The init'd project (section present) is not touched by sync either.
P7b="$(mkproj t7b)"; B="$(cat "$P7b/PROJECT.md")"
"$SYNC" "$P7b" >/dev/null 2>&1
[ "$B" = "$(cat "$P7b/PROJECT.md")" ] && ok "fresh scaffold: sync leaves PROJECT.md alone" || bad "sync modified a fresh PROJECT.md"

echo "== T8: exec.sh --cr =="
mkdir -p "$WORK/empty"
OUT="$(cd "$WORK/empty" && bash "$EXEC" --cr bogus x.mdl 2>&1)"; RC=$?
[ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'CR-07' && ok "malformed id refused, exit 2, example given" || bad "bad id: rc=$RC" "$OUT"
OUT="$(cd "$WORK/empty" && bash "$EXEC" --cr CR-7x x.mdl 2>&1)"; RC=$?
[ "$RC" = "2" ] && ok "CR-7x refused" || bad "CR-7x: rc=$RC" "$OUT"
MDL="$TK/skills/agents-examples/single-call.example.mdl"
OUT="$(cd "$WORK/empty" && bash "$EXEC" --cr CR-07 --change-class "$MDL" 2>&1)"; RC=$?
[ "$RC" = "0" ] && printf '%s' "$OUT" | grep -qE '^(logic|ui-only)	' && ok "--cr CR-07 passes through to --change-class" \
  || bad "--cr then --change-class: rc=$RC" "$OUT"
grep -q 'cr: \$CR_ID' "$EXEC" && ok "BUILD-LOG detail carries 'cr: <id>'" || bad "BUILD-LOG detail has no cr tag"

echo "== T9: CRLF register =="
# Same rows as T2 on a fresh real scaffold, then every line ended in CRLF — what an editor on
# Windows writes. Before the fix the heading regex never matched: has_section failed, the scan
# counted 0 rows, gate-check said "no section", and sync-project.sh appended a second one.
P9="$(mkproj t9)"; R9="$P9/PROJECT.md"
add_rows "$R9" <<'EOF2'
| CR-01 | 2026-10-13 | user | Customer also needs a VAT number | requirement | S | F003.brd.json | proven | abc1234, journey customer-edit |
| CR-02 | 2026-10-13 | user | Orders overview should be a gallery, not a grid | visual | S | design/ui-reviews/orders | applied | |
| CR-03 | 2026-10-13 | stakeholder (finance lead) | Approvals over 10k need a second approver | decision | L | PROJECT.md new row | open | |
| CR-04 | 2026-10-13 | user | Search \| Reset buttons do nothing | bug | S | none | **agreed** | |
EOF2
LF_SCAN="$(mxtk_change_log_scan "$R9")"
LF_LINE="$("$GATE" --no-html "$P9" 2>&1 | grep '^Change log:')"
case "$LF_LINE" in "Change log: WARN — 2 of 4 change request(s) not yet applied (open 1, refined 0, agreed 1); 1 applied/proven with no Closed-by"*) ok "LF baseline: WARN, 2 of 4 pending + 1 without evidence" ;;
  *) bad "LF baseline line" "$LF_LINE" ;; esac
awk '{ printf "%s\r\n", $0 }' "$R9" > "$R9.crlf" && mv "$R9.crlf" "$R9"
grep -q $'\r$' "$R9" && ok "precondition: PROJECT.md is CRLF" || bad "CRLF conversion failed"
mxtk_change_log_has_section "$R9" && ok "has_section finds the heading in a CRLF file" || bad "has_section misses the CRLF heading"
CR_SCAN="$(mxtk_change_log_scan "$R9")"
[ "$CR_SCAN" = "$LF_SCAN" ] && ok "scan of the CRLF file = scan of the LF file" \
  || bad "CRLF scan differs" "$(printf 'LF:\n%s\nCRLF:\n%s' "$LF_SCAN" "$CR_SCAN" | cat -A)"
printf '%s\n' "$CR_SCAN" | grep -q $'\r' && bad "a \\r leaked into the scan output" || ok "no \\r in the scan output"
CR_LINE="$("$GATE" --no-html "$P9" 2>&1 | grep '^Change log:')"
[ "$CR_LINE" = "$LF_LINE" ] && ok "gate line on CRLF = gate line on LF ($LF_LINE)" \
  || bad "gate line differs on CRLF" "$(printf 'LF:   %s\nCRLF: %s' "$LF_LINE" "$CR_LINE")"
OUT="$("$SYNC" "$P9" 2>&1)"
[ "$(count_heading "$R9")" = "1" ] && ok "sync on CRLF: still exactly one '## Change log'" \
  || bad "sync on CRLF: $(count_heading "$R9") headings"
printf '%s\n' "$OUT" | grep -q "appended the '## Change log' section" && bad "sync claims it appended a section to a CRLF file that has one" \
  || ok "sync does not append to a CRLF file"

echo "== T10 (issue #767): an exec script since Stage 5 with no cr: and no build-plan row is listed, warn-only =="
# GOLDEN INPUT: every BUILD-LOG row is the verbatim exec.sh capture in fixtures/verify-446, with
# only its timestamp, script name and (for one row) the cr tag exec.sh appends substituted.
CAP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/verify-446/BUILD-LOG.captured.md"
ROW="$(grep -m1 '^| 2026-' "$CAP")"
row() { # row <time> <script> [cr]  — the captured row with three cells substituted
  local r="${ROW/2026-10-21T05:41:52/$1}"; r="${r/\`test.mdl\`/\`$2\`}"
  [ -n "${3:-}" ] && r="${r/ · change: logic/ · change: logic · cr: $3}"
  printf '%s\n' "$r"
}
P10="$(mkproj t10)"; mkdir -p "$P10/docs" "$P10/architecture"
cat > "$P10/architecture/build-plan.md" <<'EOF3'
# Build plan

| # | Kind | Step | What | Depends on |
|---|---|---|---|---|
| 10 | BUILD | 010-crm-domain.mdl | CRM domain model | |
| 21 | BUILD | UC-F002-01 Browse customers: 020-…-customer_overview.mdl | Customer list | 10 |
EOF3
{ sed -n '1,/^|---/p' "$CAP"
  row 2026-10-20T09:00:00 001-scaffold.mdl                 # before Stage 5: not listed
  row 2026-10-21T09:00:00 010-crm-domain.mdl               # in the plan: Stage 5 starts here
  row 2026-10-21T10:00:00 020-crm-page-customer_overview.mdl   # matches the abbreviated plan row
  row 2026-10-22T09:00:00 070-admin-account.mdl            # the unlogged ask
  row 2026-10-22T10:00:00 071-vat-number.mdl CR-01         # logged: cr tag
  row 2026-10-22T11:00:00 070-admin-account.mdl            # re-run: listed once
} > "$P10/docs/BUILD-LOG.md"
[ "$(grep -c '^| 2026-' "$P10/docs/BUILD-LOG.md")" = "6" ] && ok "precondition: 6 captured-shape rows" || bad "row build failed"
OUT10="$("$GATE" --no-html "$P10" 2>&1)"; RC10=$?
BLK="$(printf '%s\n' "$OUT10" | sed -n '/^Change log:/,/^[^ ]/p')"
printf '%s\n' "$BLK" | grep -q "WARN — 1 exec script(s) since Stage 5 started with no cr: tag and no build-plan row" \
  && ok "nudge line under Change log: names 1 script" || bad "no nudge line" "$BLK"
printf '%s\n' "$BLK" | grep -qx '    070-admin-account.mdl' && ok "070-admin-account.mdl listed" || bad "unlogged script not listed" "$BLK"
for s in 001-scaffold.mdl 010-crm-domain.mdl 020-crm-page-customer_overview.mdl 071-vat-number.mdl; do
  printf '%s\n' "$BLK" | grep -q "^    $s" && bad "$s listed" "$BLK" || ok "$s not listed"
done
[ "$(printf '%s\n' "$BLK" | grep -c '^    070-admin-account.mdl')" = "1" ] && ok "re-run listed once" || bad "duplicate listing" "$BLK"
printf '%s\n' "$OUT10" | grep -q '^Change log: PASS — 0 change requests logged' && ok "verdict unchanged: still PASS (warn line is separate)" \
  || bad "Change log verdict changed" "$(printf '%s\n' "$OUT10" | grep '^Change log:')"
rm -f "$P10/docs/BUILD-LOG.md"; "$GATE" --no-html "$P10" >/dev/null 2>&1; RC10b=$?
[ "$RC10" = "$RC10b" ] && ok "exit $RC10 with the unlogged row = $RC10b without" || bad "exit differs: $RC10 vs $RC10b"

echo ""
echo "test-change-log: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
