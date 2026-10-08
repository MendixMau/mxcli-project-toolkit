#!/usr/bin/env bash
# Fixture for #228 — project-bin/exec.sh step 3, the raw `mxcli exec` guard.
#
# Before: `pgrep -fl "mxcli exec" | grep -qv "$$"` matched the STRING anywhere on the machine
# (the caller's own command line, other projects' execs), hid the refusal from BUILD-LOG, and
# did nothing under Git Bash. Now: argv0 is mxcli, `exec` is an argument, the args name THIS
# model, the shell's own ancestry is skipped, a refusal writes a log row, and a missing process
# list warns and carries on.
#
# Usage: test-exec-raw-guard.sh /path/to/exec.sh
#
# NOTHING here touches a real .mpr, mxcli or mxbuild; decoy "raw execs" are `sleep` processes
# started with a forged argv0 (bash `exec -a`), because that is all `ps` ever shows of one.
# Positive control: against the pre-fix exec.sh, cases A and B FAIL (pgrep matches the
# parent's / the other model's string) and C leaves no log row.
set -uo pipefail

EXEC_SH="${1:?usage: test-exec-raw-guard.sh /path/to/exec.sh}"
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

# decoy <argv0-string> — a long-lived process whose ps args begin with that string
decoy() { ( exec -a "$1" sleep 60 ) >/dev/null 2>&1 & DECOYS="$DECOYS $!"; sleep 0.3; }
run() {
  ( cd "$P" && PATH="$WORK/fakebin:$PATH" SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXBUILD_PATH="$WORK/mxbuild" \
      "$@" ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/out" 2>&1
  echo $?
}
stop_decoys() { for d in $DECOYS; do kill "$d" 2>/dev/null; done; DECOYS=""; sleep 0.2; }
refusals() { if [ -f "$LOG" ]; then grep -c "raw mxcli exec" "$LOG"; else echo 0; fi; }
# Capture-based sanity: the platform's real ps output must parse into pid<TAB>args rows.
LIST="$( . "$P/bin/_common.sh" 2>/dev/null; mxtk_proc_list )"
printf '%s\n' "$LIST" | grep -qE "^[0-9]+	." && ok "mxtk_proc_list yields pid<TAB>args rows ($(printf '%s\n' "$LIST" | wc -l | tr -d ' ') processes)" \
  || bad "mxtk_proc_list produced no parseable rows"

echo "== A: a parent whose argv merely says 'mxcli exec Fixture.mpr' does not refuse =="
RC=$( ( cd "$P" && PATH="$WORK/fakebin:$PATH" SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXBUILD_PATH="$WORK/mxbuild" \
        bash -c 'exec -a "mxcli -p Fixture.mpr exec" bash ./bin/exec.sh mdlsource/test.mdl' ) >"$WORK/out" 2>&1; echo $? )
[ "$RC" -eq 0 ] && ok "exit 0 (own ancestry excluded)" || bad "exit $RC: $(head -3 "$WORK/out")"

echo "== B: a raw exec on ANOTHER model does not refuse =="
decoy "mxcli -p Other.mpr exec other.mdl"
RC=$(run env)
[ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC: $(head -3 "$WORK/out")"
stop_decoys

echo "== C: a raw exec on THIS model refuses, names the pid, and logs a row =="
decoy "mxcli -p $P/Fixture.mpr exec other.mdl"
BEFORE=$(refusals)
RC=$(run env)
[ "$RC" -eq 1 ] && ok "exit 1" || bad "exit $RC, expected 1"
grep -q "raw 'mxcli exec'" "$WORK/out" && ok "refusal on screen" || bad "no refusal text"
[ "$(refusals)" -gt "$BEFORE" ] && ok "BUILD-LOG row written" || bad "refusal left no BUILD-LOG row"

echo "== D: FORCE_EXEC=1 and MXTK_NO_RAW_GUARD=1 both let it through =="
RC=$(run env FORCE_EXEC=1); [ "$RC" -eq 0 ] && ok "FORCE_EXEC proceeds" || bad "FORCE_EXEC exit $RC"
RC=$(run env MXTK_NO_RAW_GUARD=1); [ "$RC" -eq 0 ] && ok "opt-out proceeds" || bad "opt-out exit $RC"
stop_decoys

echo "== E: no process list -> warn once, carry on =="
cat > "$WORK/fakebin/ps" <<'PS'
#!/usr/bin/env bash
exit 1
PS
chmod +x "$WORK/fakebin/ps"
decoy "mxcli -p $P/Fixture.mpr exec other.mdl"
RC=$(run env)
[ "$RC" -eq 0 ] && ok "exit 0 (cannot-run check does not block)" || bad "exit $RC"
grep -q 'raw-exec guard skipped' "$WORK/out" && ok "warned" || bad "no warning"
rm -f "$WORK/fakebin/ps"

echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
