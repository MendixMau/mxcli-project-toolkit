#!/usr/bin/env bash
# test-project-facts.sh: pin project-bin/project-facts.sh against the review defects of PR #707.
# usage: test-project-facts.sh /path/to/project-facts.sh
#
#   T1 exit 0 on success with no docs/BUILD-LOG.md
#   T2 a password/token on a 'Roles and ports' line is never printed; role names and ports are
#   T3 'Reports' / 'Imports' headings are not mistaken for the ports section
#   T4 a stale run record (dead pid) reads "not running"; a live pid reads RUNNING
#   T5 --out into an unwritable path exits non-zero and does not say "wrote"; a good --out says it
# Subject project = captured tree under fixtures/project-facts (see PROVENANCE.txt).
SUBJ="${1:-}"; [ -f "$SUBJ" ] || { echo "usage: test-project-facts.sh /path/to/project-facts.sh"; exit 2; }
SUBJ="$(cd "$(dirname "$SUBJ")" && pwd)/$(basename "$SUBJ")"
HERE="$(cd "$(dirname "$0")" && pwd)"; FX="$HERE/fixtures/project-facts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cp -R "$FX/." "$T/"; rm -f "$T/PROVENANCE.txt"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }
cat >> "$T/PROJECT.md" <<'EOF'

## Roles and ports
- admin 8180 password: hunter2-SECRET
- | buyer | 8181 | token=abc123TOKEN |
- api_key_holder 8182

## Reports
- weekly 9999 figures
EOF
out=$(cd "$T" && bash "$SUBJ" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "T1 exit 0 without docs/BUILD-LOG.md" || bad "T1 exit $rc"
echo "$out" | grep -q 'role admin: port 8180' && echo "$out" | grep -q 'role buyer: port 8181' && ok "T2 role names and ports listed" || bad "T2 roles/ports missing"
echo "$out" | grep -qE 'hunter2|abc123|SECRET|TOKEN|password:' && bad "T2 secret leaked" || ok "T2 secret absent from output"
echo "$out" | grep -q 'role \[redacted\]: port 8182' && ok "T2 secret-looking role name redacted" || bad "T2 redaction"
echo "$out" | grep -q '9999' && bad "T3 Reports section dumped" || ok "T3 Reports heading not matched"
echo "$out" | grep -q 'not running (record .*stale' && ok "T4 dead pid reads not running" || bad "T4 stale record trusted"
echo "$out" | grep -q 'http://localhost:8180' && bad "T4 stale url printed" || ok "T4 no url for stale record"
sleep 30 & lp=$!
sed -i.bak "s/\"pid\": *[0-9]*/\"pid\": $lp/" "$T/.mxcli/run-local.json"
out=$(cd "$T" && bash "$SUBJ" 2>&1)
kill $lp 2>/dev/null
echo "$out" | grep -q 'RUNNING app http://localhost:8180' && ok "T4 live pid reads RUNNING" || bad "T4 live pid"
mkdir -p "$T/docs"; echo x > "$T/docs/BUILD-LOG.md"
(cd "$T" && bash "$SUBJ" 2>&1) | grep -q 'docs/BUILD-LOG.md' && ok "T1 BUILD-LOG line when present" || bad "T1 BUILD-LOG line"
(cd "$T" && bash "$SUBJ" --out /dev/null/x/facts.md >"$T/o.txt" 2>&1); rc=$?
{ [ $rc -ne 0 ] && ! grep -q '^wrote' "$T/o.txt" && grep -q ERROR "$T/o.txt"; } && ok "T5 failed --out is an error (rc $rc)" || bad "T5 failed --out rc=$rc: $(cat "$T/o.txt")"
(cd "$T" && bash "$SUBJ" --out "$T/sub/facts.md" >"$T/o.txt" 2>&1); rc=$?
{ [ $rc -eq 0 ] && grep -q '^wrote' "$T/o.txt" && [ -s "$T/sub/facts.md" ]; } && ok "T5 good --out writes" || bad "T5 good --out"
echo "project-facts: $PASS passed, $FAIL failed"; [ $FAIL -eq 0 ]
