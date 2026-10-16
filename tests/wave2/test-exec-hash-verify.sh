#!/usr/bin/env bash
# Fixture for #295: project-bin/exec.sh --patch brackets the patch script with
# `mxcli fix hashes` (read-only) — a baseline before, a verify after a zero exit, and a
# restore when the script left a ContentsHash issue the baseline did not have.
#
# usage: bash tests/wave2/test-exec-hash-verify.sh /path/to/exec.sh
#
# Golden input is captured, never written: the stub mxcli below REPLAYS verbatim
# `mxcli fix hashes` runs of v0.25.0 and v0.26.0 (stdout, stderr and exit code) from
# tests/wave2/fixtures/mxpatch/ — clean, a corrupted ContentsHash, MISSING + ORPHAN,
# "project not found", the real MISMATCH master's wf-*.py patchers leave — and the
# `mxcli fix --help` captures of v0.24.0 / v0.26.0 from fixtures/property-sets/. Provenance:
# fixtures/mxpatch/CAPTURE.txt. No real .mpr, mxcli, mxbuild or java runs here.
#
# Positive control: against master's exec.sh (before 2026-10-14) cases B, D, E, I fail — the
# patch is kept (exit 0) although the index is stale — and C, F, G, H, J fail on their
# messages / call counts (there is no verify at all): 12 pass, 31 fail. Against this PR's
# exec.sh before the field-run fixes (01b9b42, #390) the BUILD-LOG hash cell (A, B, C, K, L,
# F2), the fresh-hash baseline line (C), the repaired-by-rewrite line (K), the
# MXPATCH_BACKUP_DIR hand-off (K) and case M fail: 29 pass, 14 fail. Against 4878984 only
# case M fails (38 pass, 5 fail): a rewritten unit left stale again was "pre-existing".
# Exit codes alone in A, C, F, G, H, J, K, L are guards.
set -uo pipefail

EXEC_SH="${1:?usage: test-exec-hash-verify.sh /path/to/exec.sh}"
case "$EXEC_SH" in /*) ;; *) EXEC_SH="$PWD/$EXEC_SH" ;; esac
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
FX="$TOOLKIT/tests/wave2/fixtures/mxpatch"
PSFX="$TOOLKIT/tests/wave2/fixtures/property-sets"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/exec-hv.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }

P="$WORK/proj"
mkdir -p "$P/bin" "$P/mprcontents/84/77" "$WORK/jdk/bin"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/84/77/84776610-13b2-48cb-a265-d5e984d63129.mxunit"
cp "$TOOLKIT/project-bin/_common.sh" "$P/bin/_common.sh"
cp "$EXEC_SH" "$P/bin/exec.sh"
cp "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/restore-mpr.sh"
chmod +x "$P/bin/exec.sh" "$P/bin/restore-mpr.sh"
cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
mkdir -p "$D"; cp Fixture.mpr "$D/Fixture.mpr"; cp -r mprcontents "$D/mprcontents"
echo "Snapshot saved: $D"
SNAP
chmod +x "$P/bin/snapshot-mpr.sh"

# The patch: writes into the model, exits $PATCH_EXIT. PATCH_UNIT=1 also rewrites the
# DomainModel unit, the one the captured verify-stale run reports as MISMATCH. It records the
# MXPATCH_BACKUP_DIR exec.sh handed it in $BAKDIR_OUT.
cat > "$P/patch.sh" <<'PATCH'
#!/usr/bin/env bash
echo "written by the patch" >> "$1"
[ -n "${PATCH_UNIT:-}" ] && echo "rewritten" >> "$(dirname "$1")/mprcontents/84/77/84776610-13b2-48cb-a265-d5e984d63129.mxunit"
[ -n "${BAKDIR_OUT:-}" ] && printf '%s\n' "${MXPATCH_BACKUP_DIR:-<unset>}" > "$BAKDIR_OUT"
exit "${PATCH_EXIT:-0}"
PATCH

# Stub mxcli. `fix --help` replays the captured help of $STUB_VER. Each `fix hashes -p` call
# replays the next capture named in $HV_SEQ (comma list of fixtures/mxpatch/<name> stems).
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
echo "$*" >> "$D/.stub-log"
case "$1 ${2:-}" in
  "fix --help") cat "$PSFX/fix-help-${STUB_VER:-v0.26.0}.txt"; exit 0 ;;
  "fix hashes")
    n=$(( $(cat "$D/.stub-n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$D/.stub-n"
    stem="$(printf '%s\n' "$HV_SEQ" | tr ',' '\n' | sed -n "${n}p")"
    [ -n "$stem" ] || { echo "stub: no capture for call $n" >&2; exit 99; }
    cat "$FX/$stem.out"; cat "$FX/$stem.err" >&2; exit "$(cat "$FX/$stem.exit")" ;;
esac
exit 0
MXCLI
chmod +x "$P/mxcli"

cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --write-errors=*) printf '{"problems":[]}' > "${a#--write-errors=}" ;; esac; done
echo x >> "$MXB_LOG"; exit 0
MXB
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/jdk/bin/java"
chmod +x "$WORK/mxbuild" "$WORK/jdk/bin/java"

( cd "$P" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
LOG="$P/docs/BUILD-LOG.md"
export FX PSFX MXB_LOG="$WORK/mxb-log"

# run <label> — HV_SEQ, STUB_VER, PATCH_EXIT come from the caller's environment.
run() {
  rm -f "$P/.stub-n" "$P/.stub-log" "$MXB_LOG"; rm -rf "$WORK/tmp"; mkdir -p "$WORK/tmp"
  ( cd "$P" && git checkout -q -- Fixture.mpr mprcontents && TMPDIR="$WORK/tmp" SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 \
      MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" ./bin/exec.sh --patch patch.sh ) >"$WORK/out.$1" 2>&1
  echo $?
}
kept()     { grep -q 'written by the patch' "$P/Fixture.mpr"; }
verifies() { _n=$(grep -c '^fix hashes -p ' "$P/.stub-log" 2>/dev/null) || true; echo "${_n:-0}"; }
built()    { [ -s "$MXB_LOG" ]; }
lastrow()  { tail -1 "$LOG" 2>/dev/null; }

echo "== A: clean -> clean: kept, gate runs [guard] =="
RC=$(HV_SEQ=verify-clean-v0.26.0,verify-clean-v0.26.0 run A)
[ "$RC" -eq 0 ] && kept && ok "exit 0, patch kept" || bad "A rc=$RC" "$(tail -20 "$WORK/out.A")"
built && ok "mxbuild gate ran" || bad "gate did not run"
lastrow | grep -q '✅ applied .* · hashes: baseline clean, verify clean' && ok "BUILD-LOG row: hashes baseline clean, verify clean (#390)" || bad "A: row" "$(lastrow)"

echo "== B: clean -> the stale hash master's patchers leave: restored, exit 1 =="
RC=$(HV_SEQ=verify-clean-v0.26.0,after-master-patchers-v0.26.0 run B)
[ "$RC" -eq 1 ] && ok "exit 1" || bad "B rc=$RC (expected 1: the patch left a stale ContentsHash)" "$(tail -8 "$WORK/out.B")"
kept && bad "B: the stale-hash patch was KEPT" || ok "patch rolled back"
grep -q 'MISMATCH  056b39ea-2e14-4d12-8ae1-87fa4b3c038a' "$WORK/out.B" && ok "names the mismatched unit" || bad "B: unit not named"
grep -q 'bin/mxpatch.py' "$WORK/out.B" && ok "names the remedy" || bad "B: no remedy"
built && bad "B: mxbuild ran on a model the verify had already refused" || ok "gate not spent"
grep -q 'patch refused.*ContentsHash: 1 new issue' "$LOG" 2>/dev/null && ok "BUILD-LOG row" || bad "B: no BUILD-LOG row" "$(tail -3 "$LOG" 2>/dev/null)"
lastrow | grep -q 'hashes: baseline clean, verify 1 new' && ok "BUILD-LOG row carries the hash cell" || bad "B: hash cell" "$(lastrow)"

echo "== C: stale -> the same stale row: a baseline issue is not this patch's [guard] =="
RC=$(HV_SEQ=verify-stale-v0.26.0,verify-stale-v0.26.0 run C)
[ "$RC" -eq 0 ] && kept && ok "exit 0, kept" || bad "C rc=$RC" "$(tail -12 "$WORK/out.C")"
grep -q 'ALREADY out of step' "$WORK/out.C" && ok "baseline issue reported" || bad "C: baseline issue not reported"
grep -q 'fix hashes -p Fixture.mpr --repair' "$WORK/out.C" && ok "with its repair line" || bad "C: no repair line"
grep -q 'that write gives it a fresh hash' "$WORK/out.C" && ok "baseline says a unit this patch rewrites gets a fresh hash (#390)" || bad "C: no fresh-hash line"
lastrow | grep -q 'hashes: baseline 1 mismatch (pre-existing), verify 1 mismatch left (pre-existing), none new' \
  && ok "BUILD-LOG row: baseline 1 mismatch, 1 left, none new" || bad "C: row" "$(lastrow)"

echo "== D: stale -> MISSING + ORPHAN: only the NEW rows fail it =="
RC=$(HV_SEQ=verify-stale-v0.26.0,verify-orphan-missing-v0.26.0 run D)
[ "$RC" -eq 1 ] && ! kept && ok "exit 1, restored" || bad "D rc=$RC"
grep -q '2 new issue' "$WORK/out.D" && ok "2 new issues (MISSING, ORPHAN), the baseline MISMATCH not counted" || bad "D count" "$(grep -n 'new issue' "$WORK/out.D")"

echo "== E: clean -> exit 1 without a summary (project not found): an error, restored =="
RC=$(HV_SEQ=verify-clean-v0.26.0,verify-notfound-v0.26.0 run E)
[ "$RC" -eq 1 ] && ! kept && ok "exit 1, restored" || bad "E rc=$RC"
grep -q 'could not verify.*project not found' "$WORK/out.E" && ok "says it could not verify, and why" || bad "E message" "$(grep -n 'verify' "$WORK/out.E")"

echo "== F: v0.24.0 has no 'fix hashes': NOT RUN, patch goes on to the gate [guard] =="
RC=$(STUB_VER=v0.24.0 HV_SEQ= run F)
[ "$RC" -eq 0 ] && kept && built && ok "exit 0, kept, gated" || bad "F rc=$RC"
grep -q "NOT RUN — this mxcli has no 'fix hashes'" "$WORK/out.F" && ok "loud NOT RUN" || bad "F: silent"
[ "$(verifies)" -eq 0 ] && ok "never called fix hashes" || bad "F: called fix hashes on v0.24"

echo "== G: patch exits 2: restored, no verify after it [guard] =="
RC=$(PATCH_EXIT=2 HV_SEQ=verify-clean-v0.26.0 run G)
[ "$RC" -eq 2 ] && ! kept && ok "exit 2, restored" || bad "G rc=$RC"
[ "$(verifies)" -eq 1 ] && ok "baseline only" || bad "G: $(verifies) verify calls"

echo "== H: baseline unclassifiable (project not found): NOT RUN, kept on the gate [guard] =="
RC=$(HV_SEQ=verify-notfound-v0.26.0 run H)
[ "$RC" -eq 0 ] && kept && built && ok "exit 0, kept, gated" || bad "H rc=$RC" "$(tail -10 "$WORK/out.H")"
[ "$(verifies)" -eq 1 ] && ok "no post-verify without a baseline" || bad "H: $(verifies) calls"
LEFT="$(find "$WORK/tmp" -name 'exec-hv-*' | wc -l | tr -d ' ')"
[ "$LEFT" = 0 ] && ok "the errored baseline's temp file is removed" || bad "H: $LEFT exec-hv temp file(s) left in TMPDIR"

echo "== I: the v0.25.0 contract is the same: clean -> stale fails =="
RC=$(HV_SEQ=verify-clean-v0.25.0,verify-stale-v0.25.0 run I)
[ "$RC" -eq 1 ] && ! kept && ok "exit 1, restored" || bad "I rc=$RC"

echo "== J: clean -> clean after the PORTED patchers' real run [guard] =="
RC=$(HV_SEQ=verify-clean-v0.26.0,after-ported-patchers-v0.26.0 run J)
[ "$RC" -eq 0 ] && kept && ok "exit 0, kept" || bad "J rc=$RC"
grep -q '^fix hashes -p .*Fixture.mpr$' "$P/.stub-log" && ok "verify is the read-only form (no --repair)" || bad "J: form" "$(cat "$P/.stub-log")"

echo "== K: stale -> clean, and the patch rewrote that unit: repaired by the rewrite, said so (#390) =="
RC=$(PATCH_UNIT=1 BAKDIR_OUT="$WORK/bakdir" HV_SEQ=verify-stale-v0.26.0,verify-clean-v0.26.0 run K)
[ "$RC" -eq 0 ] && kept && ok "exit 0, kept" || bad "K rc=$RC" "$(tail -12 "$WORK/out.K")"
grep -q 'this patch rewrote unit 84776610-13b2-48cb-a265-d5e984d63129 with a fresh hash: its pre-existing MISMATCH is repaired' "$WORK/out.K" \
  && ok "names the unit the rewrite repaired" || bad "K: no repaired line" "$(grep -n 'MISMATCH\|repaired' "$WORK/out.K")"
lastrow | grep -q "hashes: baseline 1 mismatch (pre-existing), verify clean (1 pre-existing repaired by this patch's rewrite)" \
  && ok "BUILD-LOG row: baseline 1 mismatch, verify clean, 1 repaired by the rewrite" || bad "K: row" "$(lastrow)"
case "$(cat "$WORK/bakdir" 2>/dev/null)" in
  "$P"/.mpr-snapshots/[0-9]*/mxpatch-bak) ok "MXPATCH_BACKUP_DIR handed to the patch: inside the snapshot just taken, outside mprcontents/" ;;
  *) bad "K: MXPATCH_BACKUP_DIR=$(cat "$WORK/bakdir" 2>/dev/null)" ;;
esac

echo "== L: stale -> clean, the patch did NOT rewrite that unit: gone, not credited to the rewrite [guard] =="
RC=$(HV_SEQ=verify-stale-v0.26.0,verify-clean-v0.26.0 run L)
[ "$RC" -eq 0 ] && kept && ok "exit 0, kept" || bad "L rc=$RC"
grep -q 'this patch rewrote unit' "$WORK/out.L" && bad "L: credited a rewrite that did not happen" || ok "no rewrite claimed"
lastrow | grep -q 'hashes: baseline 1 mismatch (pre-existing), verify clean (1 other pre-existing gone)' && ok "BUILD-LOG row: 1 other gone" || bad "L: row" "$(lastrow)"

echo "== M: stale -> the same unit still stale AFTER the patch rewrote it: a NEW stale hash, restored (#374 review) =="
# Matching issues by KIND+ID alone read this as "pre-existing, none new" and kept the patch:
# the patch rewrote the unit and left its hash stale again, which is #390's field state.
RC=$(PATCH_UNIT=1 HV_SEQ=verify-stale-v0.26.0,verify-stale-v0.26.0 run M)
[ "$RC" -eq 1 ] && ok "exit 1" || bad "M rc=$RC (expected 1: the patch rewrote a stale unit and left it stale)" "$(tail -10 "$WORK/out.M")"
kept && bad "M: the patch was KEPT" || ok "patch rolled back"
grep -q '1 new issue' "$WORK/out.M" && ok "counted as 1 new issue" || bad "M: not counted new" "$(grep -n 'new\|MISMATCH' "$WORK/out.M")"
lastrow | grep -q 'patch refused.*hashes: baseline 1 mismatch (pre-existing), verify 1 new' && ok "BUILD-LOG row: verify 1 new" || bad "M: row" "$(lastrow)"
built && bad "M: mxbuild ran on a model the verify had already refused" || ok "gate not spent"

echo "== F2: NOT RUN is in the BUILD-LOG row too [guard] =="
RC=$(STUB_VER=v0.24.0 HV_SEQ= run F2)
lastrow | grep -q 'hashes: NOT RUN (mxcli has no fix hashes' && ok "row says NOT RUN" || bad "F2: row" "$(lastrow)"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
