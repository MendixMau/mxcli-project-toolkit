#!/usr/bin/env bash
# Fixture: the company brain — templates/company-brain/ instantiated by init-company-brain.sh,
# wired into a project by wire-company-brain.sh / init-project.sh --company, and the CI rule
# that the public toolkit never cites a private tier (check-no-private-citations.sh).
#
#   tests/wave2/test-company-brain.sh /path/to/init-company-brain.sh
#
# Asserts (all mechanical; the retrieval claim — a build session finds and uses an approved MPK
# through the pointer — is the agent eval in evals/scenarios/company-brain-design-module/):
#   T1 instantiate: every template file lands, placeholders substituted, re-run keeps edits
#   T2 wire via init-project.sh --company: exactly one marked block, ≤ 70 words, path resolves,
#      project registered once in projects.tsv, second wire = still one block
#   T3 wire refuses an unshaped folder; wire on a project without CLAUDE.local.md refuses
#   T4 check-no-private-citations: positive control (planted pointer) exits 1, clean tree exits 0,
#      the toolkit's own templates/company-brain/ path is not a hit
#   T5 leak-check wrapper runs the toolkit guard over the brain, probes-only, exit 0 on the template
#   T6 harvest-learnings.sh --to lands drafts in the brain's inbox, not the toolkit's
set -uo pipefail
INIT="${1:?usage: test-company-brain.sh /path/to/init-company-brain.sh}"
BIN="$(cd "$(dirname "$INIT")" && pwd)"; TOOLKIT="$(cd "$BIN/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/cbrain.XXXXXX")"
export MXTK_LEAKGUARD_DENYFILE="$WORK/denylist"; export MXTK_NO_GUIDE=1
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

echo "== T1: instantiate =="
B="$WORK/acme-brain"
out="$("$INIT" "$B" --name Acme 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "exit 0" || bad "exit $rc: $out"
for f in README.md ROUTING.md projects.tsv skills/PROMOTED.md components/TEMPLATE.md inbox/TEMPLATE.md bin/leak-check.sh .gitignore; do
  [ -f "$B/$f" ] && ok "created $f" || bad "missing $f"
done
grep -q '{{' "$B/README.md" && bad "placeholder left in README" || ok "placeholders substituted"
grep -q "^# Acme company brain" "$B/README.md" && ok "--name applied" || bad "--name not applied"
grep -qF "$TOOLKIT" "$B/README.md" && ok "toolkit root substituted" || bad "toolkit root missing"
[ -x "$B/bin/leak-check.sh" ] && ok "leak-check.sh executable" || bad "leak-check.sh not executable"
echo "hardened" >> "$B/README.md"
out="$("$INIT" "$B" 2>&1)"
grep -q "hardened" "$B/README.md" && ok "re-run keeps edited README" || bad "re-run overwrote README"
echo "$out" | grep -q "0 created" && ok "re-run created nothing" || bad "re-run created files: $out"

echo "== T2: wire via init-project.sh --company =="
P="$WORK/acme-app"; mkdir -p "$P"
"$BIN/init-project.sh" "$P" --ignore-sources --company "$B" >/dev/null 2>&1
CL="$P/CLAUDE.local.md"
n=$(grep -c 'COMPANY-BRAIN:BEGIN' "$CL" 2>/dev/null || echo 0)
[ "$n" -eq 1 ] && ok "exactly one block" || bad "blocks: $n"
words=$(awk '/COMPANY-BRAIN:BEGIN/{f=1;next} /COMPANY-BRAIN:END/{f=0} f' "$CL" | wc -w)
[ "$words" -le 70 ] && ok "pointer is $words words (≤ 70)" || bad "pointer too long: $words words"
grep -qF "$B/ROUTING.md" "$CL" && ok "names ROUTING.md by path" || bad "ROUTING.md path missing"
[ -f "$(grep -o "$B/ROUTING.md" "$CL" | head -1)" ] && ok "path resolves" || bad "path does not resolve"
grep -q "house-page-conventions" "$CL" && bad "company routing table was COPIED into the project" || ok "nothing copied from the brain"
r=$(grep -c "^$P	" "$B/projects.tsv"); [ "$r" -eq 1 ] && ok "registered once" || bad "registry rows: $r"
"$BIN/wire-company-brain.sh" "$P" "$B" >/dev/null 2>&1
n=$(grep -c 'COMPANY-BRAIN:BEGIN' "$CL"); [ "$n" -eq 1 ] && ok "re-wire: still one block" || bad "re-wire blocks: $n"
r=$(grep -c "^$P	" "$B/projects.tsv"); [ "$r" -eq 1 ] && ok "re-wire: still registered once" || bad "re-wire registry rows: $r"
B2="$WORK/acme-brain-2"; "$INIT" "$B2" >/dev/null 2>&1; "$BIN/wire-company-brain.sh" "$P" "$B2" >/dev/null 2>&1
grep -qF "$B2/ROUTING.md" "$CL" && ! grep -qF "$B/ROUTING.md" "$CL" && ok "re-point rewrites in place" || bad "re-point left the old path"

echo "== T3: refusals =="
U="$WORK/not-a-brain"; mkdir -p "$U"
"$BIN/wire-company-brain.sh" "$P" "$U" >/dev/null 2>&1 && bad "wired an unshaped folder" || ok "refuses an unshaped folder"
Q="$WORK/no-claude-local"; mkdir -p "$Q"
"$BIN/wire-company-brain.sh" "$Q" "$B" >/dev/null 2>&1 && bad "wired a project without CLAUDE.local.md" || ok "refuses without CLAUDE.local.md"

echo "== T4: check-no-private-citations =="
C="$WORK/pub"; mkdir -p "$C/skills"
printf 'See `~/Mendix/personal-toolkit/skills/x.md` for the pattern.\n' > "$C/skills/a.md"
"$BIN/check-no-private-citations.sh" "$C" >/dev/null 2>&1 && bad "positive control passed" || ok "planted pointer caught (exit 1)"
printf 'Instantiate `templates/company-brain/` then wire.\n' > "$C/skills/a.md"
printf 'Clone to `~/Mendix/mxcli-project-toolkit/`.\n' > "$C/skills/b.md"
"$BIN/check-no-private-citations.sh" "$C" >/dev/null 2>&1 && ok "toolkit's own paths are not hits" || bad "false positive on templates/company-brain/ or the toolkit clone path"
printf 'Also `~/Mendix/some-company-brain/skills/y.md`.\n' > "$C/skills/c.md"
"$BIN/check-no-private-citations.sh" "$C" >/dev/null 2>&1 && bad "company-brain path passed" || ok "company-brain path caught"

echo "== T5: leak-check wrapper on the template =="
out="$(MXTK_TOOLKIT_ROOT="$TOOLKIT" bash "$B/bin/leak-check.sh" 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "template is leak-clean (probes only)" || bad "leak-check exit $rc: $(echo "$out" | tail -3)"

echo "== T6: harvest --to =="
mkdir -p "$P/bug-logs"; printf '## BUG-LOCAL-1 — something\nrepro\n' > "$P/bug-logs/mxcli-bugs.md"
before=$(ls "$TOOLKIT/contrib/inbox" | wc -l)
"$BIN/harvest-learnings.sh" "$P" --to "$B/inbox" >/dev/null 2>&1
after=$(ls "$TOOLKIT/contrib/inbox" | wc -l)
[ "$before" -eq "$after" ] && ok "toolkit inbox untouched" || bad "toolkit inbox grew ($before → $after)"
ls "$B/inbox" | grep -q "acme-app" && ok "draft landed in the brain's inbox" || bad "no draft in brain inbox: $(ls "$B/inbox")"

echo ""; echo "PASS $PASS  FAIL $FAIL"
rm -rf "$WORK"
[ "$FAIL" -eq 0 ]
