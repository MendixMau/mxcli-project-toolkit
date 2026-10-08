#!/usr/bin/env bash
# Fixture for #232 (supersedes #188) — project-bin/exec.sh step 4b, the LOOK-debt guard, and
# look-ledger.sh `unseen` / `creates`.
#
# Before: a page built and never looked at was a printed notice; only Stage 5's "done" claim
# read the ledger, so unattended builds wrote every page and opened no screenshot.
# Now exec.sh refuses a script that CREATEs pages while more than LOOK_OWED_MAX (default 5)
# built pages are unseen. ALTER-only scripts, a `-- PROOF-OF-LOOK` header, a register waiver,
# FORCE_EXEC=1 and MXTK_NO_LOOK_GUARD=1 all pass; with no Read hook installed it warns once
# and continues.
#
# Usage: test-exec-look-guard.sh /path/to/exec.sh
#
# NOTHING here touches a real .mpr, mxcli or mxbuild. The ledger rows are written the way
# look-ledger.sh `owe` writes them (epoch, iso, Module.Page, script). Against the pre-fix
# exec.sh the refusal cases (A, F) FAIL.
set -uo pipefail

EXEC_SH="${1:?usage: test-exec-look-guard.sh /path/to/exec.sh}"
case "$EXEC_SH" in /*) ;; *) EXEC_SH="$PWD/$EXEC_SH" ;; esac
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d /tmp/rawguard.XXXXXX)"
PASS=0; FAIL=0
DECOYS=""
cleanup() { for d in $DECOYS; do kill "$d" 2>/dev/null; done; rm -rf "$WORK"; }
trap cleanup EXIT
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

command -v ps >/dev/null 2>&1 || { echo "SKIP: no ps"; exit 0; }

P="$WORK/proj"
mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource" "$WORK/fakebin"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/a.mxunit"
printf 'CREATE MODULE "Nope";\n' > "$P/mdlsource/test.mdl"
cp "$TOOLKIT/project-bin/_common.sh" "$P/bin/_common.sh"
cp "$EXEC_SH" "$P/bin/exec.sh"
cp "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/restore-mpr.sh"
chmod +x "$P/bin/exec.sh" "$P/bin/restore-mpr.sh"
cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
cd "$(dirname "$0")/.."; D=".mpr-snapshots/snap-$$"; mkdir -p "$D"; cp Fixture.mpr "$D/"; echo "Snapshot saved: $D"
SNAP
chmod +x "$P/bin/snapshot-mpr.sh"
# fake mxcli, both in the project and first on PATH: nothing real can run
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
case "${1:-}" in check) exit 0 ;; exec) echo "fake mxcli exec" ;; esac
exit 0
MXCLI
chmod +x "$P/mxcli"; cp "$P/mxcli" "$WORK/fakebin/mxcli"
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --write-errors=*) printf '{"problems":[]}' > "${a#--write-errors=}" ;; esac; done
exit 0
MXB
chmod +x "$WORK/mxbuild"
( cd "$P" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
LOG="$P/docs/BUILD-LOG.md"
mkdir -p "$P/.claude/loop/look" "$P/design/ui-reviews"
cp "$TOOLKIT/project-bin/look-ledger.sh" "$P/bin/look-ledger.sh"
printf '{"hooks":{"PostToolUse":[{"hooks":[{"command":"bash bin/look-ledger.sh seen || true"}]}]}}\n' > "$P/.claude/settings.json"
OWEDF="$P/.claude/loop/look/owed.tsv"
for i in 1 2 3 4 5 6 7; do printf '1000\t2026-01-01T00:00:00Z\tShop.Page%s\tmdlsource/old.mdl\n' "$i" >> "$OWEDF"; done
printf 'CREATE PAGE Shop.Brand_New (Title: "x") { }\n' > "$P/mdlsource/create.mdl"
printf 'ALTER PAGE Shop.Page1 { SET Title = "y" }\n' > "$P/mdlsource/alter.mdl"
printf -- '-- PROOF-OF-LOOK: Shop.Page1..7 opened in screenshots 2026-10-08\nCREATE PAGE Shop.Brand_New (Title: "x") { }\n' > "$P/mdlsource/proof.mdl"
printf 'CREATE MODULE "Nope";\n' > "$P/mdlsource/nopage.mdl"
( cd "$P" && git add -A && git -c user.email=t@t -c user.name=t commit -qm ledger ) >/dev/null 2>&1

run() {  # run <script> [env...]
  local s="$1"; shift
  ( cd "$P" && PATH="$WORK/fakebin:$PATH" MXTK_NO_RAW_GUARD=1 SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXBUILD_PATH="$WORK/mxbuild" \
      env "$@" ./bin/exec.sh "$s" ) >"$WORK/out" 2>&1
  echo $?
}
blocked_rows() { if [ -f "$LOG" ]; then grep -c 'never looked at' "$LOG"; else echo 0; fi; }

echo "== ledger: unseen lists the 7 owed pages; creates ignores ALTER =="
U=$(cd "$P" && bash bin/look-ledger.sh unseen | wc -l | tr -d ' ')
[ "$U" -eq 7 ] && ok "unseen = 7" || bad "unseen = $U, expected 7"
[ -z "$(bash "$P/bin/look-ledger.sh" creates "$P/mdlsource/alter.mdl")" ] && ok "creates: ALTER-only script lists nothing" || bad "creates listed an ALTER"
[ "$(bash "$P/bin/look-ledger.sh" creates "$P/mdlsource/create.mdl")" = "Shop.Brand_New" ] && ok "creates: names the CREATEd page" || bad "creates missed the page"

echo "== A: CREATE PAGE with 7 unseen (> 5) is refused, exit 3, logged, pages named =="
B=$(blocked_rows); RC=$(run mdlsource/create.mdl)
[ "$RC" -eq 3 ] && ok "exit 3" || bad "exit $RC, expected 3: $(head -3 "$WORK/out")"
grep -q 'Shop.Page1' "$WORK/out" && ok "unseen pages named" || bad "pages not named"
[ "$(blocked_rows)" -gt "$B" ] && ok "BUILD-LOG row" || bad "no BUILD-LOG row"

echo "== B: ALTER PAGE script passes (a fix must be applicable) =="
RC=$(run mdlsource/alter.mdl); [ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC"
echo "== B2: a script with no pages passes =="
RC=$(run mdlsource/nopage.mdl); [ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC"

echo "== C: PROOF-OF-LOOK in the script header is accepted evidence =="
RC=$(run mdlsource/proof.mdl); [ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC"

echo "== D: FORCE_EXEC=1, MXTK_NO_LOOK_GUARD=1, LOOK_OWED_MAX=20 each pass =="
RC=$(run mdlsource/create.mdl FORCE_EXEC=1); [ "$RC" -eq 0 ] && ok "FORCE_EXEC" || bad "FORCE_EXEC exit $RC"
RC=$(run mdlsource/create.mdl MXTK_NO_LOOK_GUARD=1); [ "$RC" -eq 0 ] && ok "opt-out" || bad "opt-out exit $RC"
RC=$(run mdlsource/create.mdl LOOK_OWED_MAX=20); [ "$RC" -eq 0 ] && ok "raised threshold" || bad "threshold exit $RC"

echo "== E: a register waiver clears pages =="
printf '# Register\nWaived obligation look/Shop: no UI in this slice\n' > "$P/PROJECT.md"
[ "$(cd "$P" && bash bin/look-ledger.sh unseen | wc -l | tr -d ' ')" -eq 0 ] && ok "waiver clears the module" || bad "waiver ignored"
RC=$(run mdlsource/create.mdl); [ "$RC" -eq 0 ] && ok "refusal lifted" || bad "exit $RC"
rm -f "$P/PROJECT.md"

echo "== F: no Read hook installed -> warn once and continue =="
rm -f "$P/.claude/settings.json"
RC=$(run mdlsource/create.mdl); [ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC"
grep -q 'LOOK guard off' "$WORK/out" && ok "warned" || bad "no warning"
RC=$(run mdlsource/create.mdl); grep -q 'LOOK guard off' "$WORK/out" && bad "warned twice" || ok "second run is quiet"

echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
