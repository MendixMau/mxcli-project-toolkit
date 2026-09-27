#!/usr/bin/env bash
# Fixture for wave-2 #7, #7b, #8 — project-bin/exec.sh build-log fidelity and the
# stale mxbuild errors file.
#
#   #7   build-log rows stamp `%m-%d %H:%M` — no year, no seconds, unorderable —
#        and GATE_STATE drives the on-screen verdict but is never written down,
#        so a zero exit does not imply the gate ran.
#   #7b  the "empty errors file / no errors file" success branch prints
#        "✓ Script applied" and logs NOTHING. That is the NORMAL clean path on
#        Mendix 11.13, so the log records failures and omits successes.
#   #8   last-mxbuild-errors.json is copied in on the failure paths and removed
#        nowhere, so a stale CE survives every clean run that follows while the
#        build loop still points readers at it as "full error detail".
#
# Usage: test-bug07-08.sh /path/to/exec.sh
#
# Run it against the PRE-fix script and cases C, E, F, I, J and the #7 block
# must FAIL — that is the positive control. A suite that has only ever seen the
# fix cannot show that it discriminates. Cases A, B, D, G, H2 pass on both; they
# are regression guards, not discriminators, and are labelled [guard]. Case H
# (gate cannot run -> refuse) discriminates against every script before 2026-09-17.
# Case K (mxbuild refused the model: exit 3, errors[], empty problems[]) discriminates
# against every script before 2026-09-27 — the pre-fix row reads "pass · mxbuild clean".
# Case L (failed gate on a v1 single-file model is rolled back) discriminates against every
# exec.sh with the inline mprcontents/-only restore.
#
# NOTHING here touches a real .mpr, a real mxcli or a real mxbuild. The fixture
# is a throwaway git repo in /tmp with stubs for all three.
set -uo pipefail

EXEC_SH="${1:?usage: test-bug07-08.sh /path/to/exec.sh}"
case "$EXEC_SH" in /*) ;; *) EXEC_SH="$PWD/$EXEC_SH" ;; esac
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d /tmp/bug0708.XXXXXX)"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# ── Fixture project ──────────────────────────────────────────────────────────
P="$WORK/proj"
mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/a.mxunit"
printf 'CREATE MODULE "Nope";\n' > "$P/mdlsource/test.mdl"
cp "$TOOLKIT/project-bin/_common.sh" "$P/bin/_common.sh"
cp "$EXEC_SH" "$P/bin/exec.sh"
cp "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/restore-mpr.sh"   # installed beside exec.sh
chmod +x "$P/bin/exec.sh" "$P/bin/restore-mpr.sh"

# snapshot-mpr.sh stub. SNAP_SLEEP stalls it, which is where case I interrupts:
# stalling inside the fake `mxcli exec` instead would leave an orphan process
# that the NEXT run's "raw mxcli exec elsewhere" guard refuses on.
cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
sleep "${SNAP_SLEEP:-0}"
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$D"
cp Fixture.mpr "$D/Fixture.mpr"
[ -d mprcontents ] && cp -r mprcontents "$D/mprcontents"   # v1 single-file: the .mpr is the model
echo "Snapshot saved: $D"
SNAP
chmod +x "$P/bin/snapshot-mpr.sh"

# Fake mxcli. MODE_EXEC = exit code for `exec`, MODE_CHECK = exit code for `check`.
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
case "${1:-}" in
  check) echo "fake mxcli check: ${MODE_CHECK:-0}"; exit "${MODE_CHECK:-0}" ;;
  exec)  echo "fake mxcli exec"; [ -n "${MUTATE_MPR:-}" ] && echo "written by the script" >> "$MUTATE_MPR"
         exit "${MODE_EXEC:-0}" ;;
esac
exit 0
MXCLI
chmod +x "$P/mxcli"

# Fake mxbuild. MODE_BUILD = clean | empty | nofile | errors.
# MODE_BUILD_EXIT = the exit code to report.
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
OUT=""
for a in "$@"; do case "$a" in --write-errors=*) OUT="${a#--write-errors=}" ;; esac; done
case "${MODE_BUILD:-clean}" in
  clean)  [ -n "$OUT" ] && printf '{"problems":[]}' > "$OUT" ;;
  empty)  [ -n "$OUT" ] && : > "$OUT" ;;
  nofile) [ -n "$OUT" ] && rm -f "$OUT" ;;
  errors) [ -n "$OUT" ] && printf '{"problems":[{"severity":"Error","errorCode":"CE1234","message":"boom"}]}' > "$OUT" ;;
  refused) [ -n "$OUT" ] && cp "$GOLDEN_REFUSED" "$OUT" ;;
  # errors only while the script's write is in the model: a restored model builds clean
  written) if grep -q 'written by the script' "$MUTATE_MPR" 2>/dev/null; then
             printf '{"problems":[{"severity":"Error","errorCode":"CE1234","message":"boom"}]}' > "$OUT"
           else printf '{"problems":[]}' > "$OUT"; fi ;;
esac
echo "fake mxbuild ${MODE_BUILD:-clean}"
exit "${MODE_BUILD_EXIT:-0}"
MXB
chmod +x "$WORK/mxbuild"
# Verbatim errors file of mxbuild 11.14.0 refusing an 11.12.2 model (marketplace-rnd, 2026-09-26).
export GOLDEN_REFUSED="$TOOLKIT/tests/wave2/fixtures/mxbuild-version-mismatch.errors.json"

( cd "$P" && git init -q . && git add -A && \
  git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1

LOG="$P/docs/BUILD-LOG.md"
ERRS="$P/.mpr-snapshots/last-mxbuild-errors.json"

# run <case-label> — everything else comes from the exported MODE_* vars.
run() {
  ( cd "$P" && SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXBUILD_PATH="${MXB_OVERRIDE:-$WORK/mxbuild}" \
      ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/out.$1" 2>&1
  echo $?
}
# Any data row, ISO-stamped or not: counting only ISO rows would report the
# pre-fix script as writing NO rows and mislabel the guard cases as failures.
# `grep -c` exits 1 on zero matches, so it must not sit in an && || chain.
rows() { if [ -f "$LOG" ]; then grep -c '^| [0-9]' "$LOG"; else echo 0; fi; }

# ── A: clean build, errors file with {"problems":[]} ─────────────────────────
echo "== A: clean build (errors file, 0 problems) =="
BEFORE=$(rows)
RC=$(MODE_BUILD=clean run A)
[ "$RC" -eq 0 ] && ok "[guard] exit 0" || bad "[guard] exit $RC, expected 0"
[ "$(rows)" -gt "$BEFORE" ] && ok "[guard] row logged" || bad "no row logged"

# ── B: mxbuild reports a real error ──────────────────────────────────────────
echo "== B: mxbuild errors -> gate fails, errors file written =="
BEFORE=$(rows)
RC=$(MODE_BUILD=errors run B)
[ "$RC" -eq 1 ] && ok "[guard] exit 1" || bad "[guard] exit $RC, expected 1"
[ "$(rows)" -gt "$BEFORE" ] && ok "[guard] row logged" || bad "no row logged"
[ -f "$ERRS" ] && ok "[guard] last-mxbuild-errors.json written" || bad "no errors file written"
grep -q CE1234 "$ERRS" 2>/dev/null && ok "[guard] it holds this run's CE" || bad "errors file has no CE1234"

# ── C: #8 — the next clean run must not inherit B's errors file ──────────────
echo "== C: #8 the stale errors file does not survive a clean run =="
RC=$(MODE_BUILD=clean run C)
if [ ! -f "$ERRS" ]; then
  ok "stale errors file cleared"
elif grep -q CE1234 "$ERRS" 2>/dev/null; then
  bad "STALE: B's CE1234 still on disk after a clean run"
else
  ok "errors file replaced, no stale CE"
fi
[ -f "$ERRS.prev" ] && ok "previous failure archived as .prev" \
                    || bad "no .prev archive of the failure detail"

# ── D: mxcli exec fails, gate still runs ─────────────────────────────────────
echo "== D: exec exit 3 -> PARTIAL, gate still runs =="
BEFORE=$(rows)
RC=$(MODE_EXEC=3 MODE_BUILD=clean run D)
[ "$RC" -eq 3 ] && ok "[guard] exit 3 propagated" || bad "[guard] exit $RC, expected 3"
[ "$(rows)" -gt "$BEFORE" ] && ok "[guard] PARTIAL row logged" || bad "no PARTIAL row"

# ── E/F: #7b — the clean paths that write no errors file ─────────────────────
echo "== E: #7b empty (0-byte) errors file is still a logged clean build =="
BEFORE=$(rows)
RC=$(MODE_BUILD=empty run E)
[ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC, expected 0"
[ "$(rows)" -gt "$BEFORE" ] && ok "row logged" || bad "SILENT SUCCESS — exit 0, '✓ Script applied', no row"

echo "== F: #7b no errors file at all is still a logged clean build =="
BEFORE=$(rows)
RC=$(MODE_BUILD=nofile run F)
[ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC, expected 0"
[ "$(rows)" -gt "$BEFORE" ] && ok "row logged" || bad "SILENT SUCCESS — exit 0, '✓ Script applied', no row"

# ── G: mxbuild itself failed to run ──────────────────────────────────────────
echo "== G: mxbuild exit 9, no errors file -> gate could not run =="
BEFORE=$(rows)
RC=$(MODE_BUILD=nofile MODE_BUILD_EXIT=9 run G)
[ "$RC" -eq 1 ] && ok "[guard] exit 1" || bad "[guard] exit $RC, expected 1"
[ "$(rows)" -gt "$BEFORE" ] && ok "[guard] row logged" || bad "no row logged"

# ── H: mxbuild absent -> the write is REFUSED before the snapshot ────────────
# Until 2026-09-17 this case expected exit 0 and an UNVERIFIED row: the script
# applied the MDL anyway and merely noted that nobody had checked it. That is the
# path a CE0117 took to the Team Server on a field project. Now the gate must be able to
# run, or nothing is written — and the refusal is itself a logged row.
echo "== H: mxbuild missing -> REFUSED, exit 1, nothing written =="
BEFORE=$(rows)
RC=$(MXB_OVERRIDE="$WORK/no-such-mxbuild" run H)
[ "$RC" -eq 1 ] && ok "exit 1 (refused)" || bad "exit $RC, expected 1 — a missing gate must refuse the write"
[ "$(rows)" -gt "$BEFORE" ] && ok "refused row logged" || bad "no row logged"
grep -q 'refused' "$LOG" 2>/dev/null && ok "row says refused" || bad "no 'refused' row in the log"
grep -q 'REFUSING' "$WORK/out.H" && ok "refusal named on screen" || bad "no REFUSING line on screen"
grep -q 'Snapshot saved' "$WORK/out.H" && bad "snapshot taken despite refusal" || ok "no snapshot taken"

# ── H2: ALLOW_UNVERIFIED=1 is the explicit "write anyway" — exit 0, UNVERIFIED row
echo "== H2: mxbuild missing + ALLOW_UNVERIFIED=1 -> UNVERIFIED, exit 0 =="
BEFORE=$(rows)
RC=$(ALLOW_UNVERIFIED=1 MXB_OVERRIDE="$WORK/no-such-mxbuild" run H2)
[ "$RC" -eq 0 ] && ok "[guard] exit 0" || bad "[guard] exit $RC, expected 0"
[ "$(rows)" -gt "$BEFORE" ] && ok "[guard] UNVERIFIED row logged" || bad "no row logged"
grep -q 'UNVERIFIED' "$LOG" 2>/dev/null && ok "row says UNVERIFIED" || bad "no UNVERIFIED row"

# ── #7: every row is orderable and carries an explicit gate verdict ──────────
echo "== #7: ISO-8601 stamps and a gate column that is never blank =="
ROWS=$(grep '^| [0-9]' "$LOG" 2>/dev/null)
NROWS=$(rows)
[ "$NROWS" -ge 8 ] && ok "8 runs produced $NROWS rows" \
                   || bad "8 runs produced only $NROWS rows (silent successes)"
if printf '%s\n' "$ROWS" | grep -qE '^\| [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}'; then
  BADSTAMP=$(printf '%s\n' "$ROWS" | grep -cvE '^\| [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}')
  [ "$BADSTAMP" -eq 0 ] && ok "every stamp is ISO-8601 with year and seconds" \
                        || bad "$BADSTAMP row(s) without a full ISO-8601 stamp"
else
  bad "no ISO-8601 stamps at all (year and seconds missing)"
fi
if grep -q '| gate |' "$LOG" 2>/dev/null; then
  ok "the table has a gate column"
  BLANK=$(printf '%s\n' "$ROWS" | awk -F'|' 'NF>4 { g=$4; gsub(/ /,"",g); if (g=="") n++ } END { print n+0 }')
  [ "$BLANK" -eq 0 ] && ok "no row has a blank gate cell" || bad "$BLANK row(s) with a blank gate cell"
  # "not run", "passed" and "failed" must be three DISTINCT visible values.
  GV=$(printf '%s\n' "$ROWS" | awk -F'|' 'NF>4 { g=$4; gsub(/ /,"",g); print g }' | sort -u | tr '\n' ' ')
  case "$GV" in
    *pass*) ok "gate verdicts present: $GV" ;;
    *)      bad "no 'pass' verdict among [$GV]" ;;
  esac
  case "$GV" in
    *skipped*|*not-run*|*fail*) ok "a non-pass verdict is visibly distinct: $GV" ;;
    *) bad "every row says the same thing — the column carries no information" ;;
  esac
else
  bad "no gate column — GATE_STATE never reaches the log"
fi

# ── I: an interrupted run must not leave a lying errors file ─────────────────
echo "== I: a run killed mid-exec leaves no stale errors file =="
printf '{"problems":[{"severity":"Error","errorCode":"CE9999","message":"old"}]}' > "$ERRS"
# `exec` so $KID IS exec.sh, not a wrapper subshell: killing the wrapper leaves
# the script running, which then holds the lock and silently voids the next case.
# SIGKILL, because a crash does not run the EXIT trap either.
( cd "$P" && exec env SKIP_BASELINE=1 SP_RESTART=0 SNAP_SLEEP=8 \
    MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/out.I" 2>&1 &
KID=$!
sleep 2
kill -KILL $KID 2>/dev/null
wait $KID 2>/dev/null
if grep -q 'Script applied' "$WORK/out.I" 2>/dev/null; then
  bad "[setup] the run was not actually interrupted — case I proves nothing"
else
  ok "[setup] run killed mid-exec"
fi
rm -f "$P/.mpr-snapshots/.exec.lock"
if [ -f "$ERRS" ] && grep -q CE9999 "$ERRS" 2>/dev/null; then
  bad "CE9999 from a PREVIOUS run survived an interrupted run — reads as its report"
else
  ok "no stale errors file after an interrupted run"
fi

# ── J: the pre-exec syntax gate rejects before touching the model ────────────
echo "== J: #10 mxcli check runs BEFORE exec and blocks on failure =="
rm -f "$P/.mpr-snapshots/.exec.lock"
BEFORE=$(rows)
OUT=$( cd "$P" && SKIP_BASELINE=1 SP_RESTART=0 MODE_CHECK=1 MXBUILD_PATH="$WORK/mxbuild" \
       ./bin/exec.sh mdlsource/test.mdl 2>&1 ); RC=$?
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'mxcli check failed' \
   && ! printf '%s' "$OUT" | grep -q 'fake mxcli exec'; then
  ok "check failure blocked the exec (nothing written)"
else
  bad "a failing mxcli check did not stop the exec (rc $RC)"
fi
[ "$(rows)" -gt "$BEFORE" ] && ok "the block is logged" || bad "blocked run left no trace in the log"

# ── K: mxbuild REFUSED the model (version mismatch) -> UNVERIFIED, never clean ─
# Field shape (marketplace-rnd, 2026-09-26): exit 3, reason in errors[], problems[] empty.
# Before the fix this counted 0 Error problems and logged "pass · mxbuild clean" for 29 of
# 29 execs, one of which carried a CE0066 the matching mxbuild found.
echo "== K: mxbuild exit 3 + errors[] + empty problems[] -> UNVERIFIED, not clean =="
rm -f "$P/.mpr-snapshots/.exec.lock"
BEFORE=$(rows)
RC=$(MODE_BUILD=refused MODE_BUILD_EXIT=3 run K)
LAST=$(grep '^| [0-9]' "$LOG" 2>/dev/null | tail -1)
[ "$(rows)" -gt "$BEFORE" ] && ok "row logged" || bad "no row logged"
case "$LAST" in
  *"mxbuild clean"*|*"| pass |"*) bad "FALSE GREEN: a refused build logged as clean: $LAST" ;;
  *) ok "refused build not logged as clean" ;;
esac
printf '%s' "$LAST" | grep -q 'unverified' && ok "row says gate unverified" || bad "row lacks 'unverified': $LAST"
printf '%s' "$LAST" | grep -q 'does not exactly match MxBuild version' \
  && ok "row carries mxbuild's own reason" || bad "row does not say why: $LAST"
grep -q 'mxbuild setup\|setup mxbuild\|MXBUILD_PATH' "$WORK/out.K" && ok "remedy named on screen" || bad "no remedy on screen"

# ── L: a failed gate on a v1 single-file model is rolled back ────────────────
# Field (marketplace-rnd, 152 MB v1 .mpr, 2026-09-26): the inline restore had only the
# mprcontents/ arm, printed "Snapshot has no mprcontents/ — refusing to restore from it."
# and left the broken model in place. Restore now goes through restore-mpr.sh.
echo "== L: v1 model (no mprcontents/) + failed gate -> .mpr byte-identical to the snapshot =="
P1="$WORK/proj-v1"
mkdir -p "$P1/bin" "$P1/mdlsource"
printf 'v1 single-file model, pre-exec\n' > "$P1/Fixture.mpr"
cp "$P/mdlsource/test.mdl" "$P1/mdlsource/"
cp "$P/bin/_common.sh" "$P/bin/exec.sh" "$P/bin/restore-mpr.sh" "$P/bin/snapshot-mpr.sh" "$P1/bin/"
cp "$P/mxcli" "$P1/mxcli"
cp "$P1/Fixture.mpr" "$WORK/v1-original.mpr"
( cd "$P1" && git init -q . && git add -A && \
  git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
( cd "$P1" && SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXBUILD_PATH="$WORK/mxbuild" \
    MODE_BUILD=written MUTATE_MPR="$P1/Fixture.mpr" ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/out.L" 2>&1
RC=$?
[ "$RC" -eq 1 ] && ok "[guard] gate failed, exit 1" || bad "[guard] exit $RC, expected 1"
if cmp -s "$P1/Fixture.mpr" "$WORK/v1-original.mpr"; then
  ok "v1 .mpr restored byte-identical to the pre-exec snapshot"
else
  bad "v1 .mpr NOT restored — the script's write is still in the model"
fi
grep -q 'refusing to restore' "$WORK/out.L" && bad "still refuses a v1 snapshot" || ok "no v1 refusal"
L1ROW=$(grep '^| [0-9]' "$P1/docs/BUILD-LOG.md" 2>/dev/null | tail -1)
case "$L1ROW" in
  *PRE-EXISTING*) bad "blamed PRE-EXISTING — the attribution rebuild saw the script's own write: $L1ROW" ;;
  *"rolled back"*) ok "row says rolled back" ;;
  *) bad "unexpected row: $L1ROW" ;;
esac

echo ""
echo "PASS=$PASS FAIL=$FAIL   ($WORK)"
[ "$FAIL" -eq 0 ]
