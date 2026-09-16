#!/usr/bin/env bash
# test-doctor-gate-selftest.sh — bin/doctor.sh's "Gate self-test" section must actually prove
# the mxbuild gate can SEE an error, not just that mxbuild is present and runs.
#
# Background: exec.sh's mxbuild gate has, in the field, silently reported "?" and applied real
# errors with exit 0 — a wrong-architecture mxbuild once reported 0 errors for several commits
# before anyone noticed. Every OTHER doctor.sh section answers "is mxbuild present and does it
# run"; this one answers "if the model had a real error, would the gate see it".
#
#   usage: bash tests/wave2/test-doctor-gate-selftest.sh bin/doctor.sh
#
# Five fake mxbuild behaviours (MODE_GATE_STUB), a fake project mxcli that marks the scratch
# model "bad" when it sees the self-test's injected MDL, and a fake project with a throwaway
# .mpr. NOTHING here touches a real .mpr, a real mxcli or a real mxbuild — java is the real
# system java (find_java's PATH fallback), since no stubbing is needed there.
set -u

DOCTOR="${1:?usage: $0 bin/doctor.sh}"
DOCTOR="$(cd "$(dirname "$DOCTOR")" && pwd)/$(basename "$DOCTOR")"
T="$(mktemp -d "${TMPDIR:-/tmp}/mxtk-doctor-gate.XXXXXX")"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*"; }
assert_contains() { if grep -q -- "$2" "$1"; then ok "$3"; else fail "$3 — expected in output: $2"; fi; }
assert_missing()  { if grep -q -- "$2" "$1"; then fail "$3 — unexpected in output: $2"; else ok "$3"; fi; }

# ── Fixture project ──────────────────────────────────────────────────────────
P="$T/proj"
mkdir -p "$P/mprcontents"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/a.mxunit"

# Fake project mxcli: `--version` for the ordinary probe, `exec <mdl> -p <mpr>` marks the
# scratch model "bad" (a file beside it) when the mdl text names this self-test's own
# microflow — standing in for "the model now actually contains that broken microflow".
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "mxcli-stub 0.0.0"; exit 0 ;;
  exec)
    mdl="$2"; mpr=""; prev=""
    for a in "$@"; do
      [ "$prev" = "-p" ] && mpr="$a"
      prev="$a"
    done
    if [ -n "$mpr" ] && grep -q GateSelftest "$mdl" 2>/dev/null; then
      : > "$(dirname "$mpr")/.gate-selftest-bad-applied"
    fi
    exit 0 ;;
esac
exit 0
MXCLI
chmod +x "$P/mxcli"

# Fake mxbuild. MODE_GATE_STUB selects the behaviour:
#   healthy       — reports 0 unless the exec stub's marker file is present beside the model
#                   being built, then reports 1 (CE0117). The only mode that should PASS.
#   no-file       — never writes an errors file AND exits non-zero, every time: the original
#                   "gate cannot tell '?' from a real error" defect.
#   always-clean  — always writes {"problems":[]}, exit 0, regardless of the marker: the gate
#                   that cannot see a known-bad model.
#   slow          — sleeps past the timeout given to it.
cat > "$T/mxbuild" <<'MXB'
#!/usr/bin/env bash
OUT=""; MPR=""
for a in "$@"; do
  case "$a" in
    --write-errors=*) OUT="${a#--write-errors=}" ;;
    --*) ;;
    *) MPR="$a" ;;
  esac
done
MARKER=""
[ -n "$MPR" ] && MARKER="$(dirname "$MPR")/.gate-selftest-bad-applied"
case "${MODE_GATE_STUB:-healthy}" in
  healthy)
    if [ -n "$MARKER" ] && [ -f "$MARKER" ]; then
      [ -n "$OUT" ] && printf '{"problems":[{"severity":"Error","errorCode":"CE0117","message":"type mismatch"}]}' > "$OUT"
    else
      [ -n "$OUT" ] && printf '{"problems":[]}' > "$OUT"
    fi
    exit 0 ;;
  no-file)
    [ -n "$OUT" ] && rm -f "$OUT"
    exit 9 ;;
  always-clean)
    [ -n "$OUT" ] && printf '{"problems":[]}' > "$OUT"
    exit 0 ;;
  slow)
    sleep "${MODE_GATE_STUB_SLEEP:-6}"
    [ -n "$OUT" ] && printf '{"problems":[]}' > "$OUT"
    exit 0 ;;
esac
exit 0
MXB
chmod +x "$T/mxbuild"

scratch_count() { find /tmp -maxdepth 1 -name 'doctor-gate-selftest.*' 2>/dev/null | wc -l | tr -d ' '; }

echo "doctor gate self-test — $DOCTOR"

# ── 1: healthy stub -> PASS ───────────────────────────────────────────────────
echo "== 1: healthy stub (0 then >=1) -> PASS =="
BEFORE=$(scratch_count)
MXBUILD_PATH="$T/mxbuild" MODE_GATE_STUB=healthy \
  bash "$DOCTOR" --quick --gate-selftest --no-docker "$P" > "$T/out.healthy" 2>&1
assert_contains "$T/out.healthy" "Gate self-test" "healthy: section header present"
assert_contains "$T/out.healthy" "baseline: gate read 0 error" "healthy: baseline reads 0"
assert_contains "$T/out.healthy" "known-bad control: gate read" "healthy: known-bad control ran"
assert_missing  "$T/out.healthy" "gate self-test:" "healthy: no gate-self-test FAIL line"
[ "$(scratch_count)" -eq "$BEFORE" ] && ok "healthy: scratch dir removed" || fail "healthy: scratch dir left behind"
assert_contains "$P/.claude/.doctor-receipt" "gate-selftest: pass" "healthy: receipt records pass"
rm -f "$P/.gate-selftest-bad-applied"

# ── 2: no-file stub (never writes errors, non-zero exit) -> FAIL, error file ──
echo "== 2: mxbuild never writes an errors file, exits non-zero -> FAIL (error file) =="
MXBUILD_PATH="$T/mxbuild" MODE_GATE_STUB=no-file \
  bash "$DOCTOR" --quick --gate-selftest --no-docker "$P" > "$T/out.nofile" 2>&1
assert_contains "$T/out.nofile" "cannot read mxbuild's error file" "no-file: FAIL mentions the error file"
assert_contains "$P/.claude/.doctor-receipt" "gate-selftest: fail (unreadable error file)" "no-file: receipt records the reason"

# ── 3: always-clean stub -> FAIL, blind ───────────────────────────────────────
echo "== 3: mxbuild always reports 0 (even on the known-bad model) -> FAIL (blind) =="
MXBUILD_PATH="$T/mxbuild" MODE_GATE_STUB=always-clean \
  bash "$DOCTOR" --quick --gate-selftest --no-docker "$P" > "$T/out.blind" 2>&1
assert_contains "$T/out.blind" "gate is blind" "always-clean: FAIL says the gate is blind"
assert_contains "$P/.claude/.doctor-receipt" "gate-selftest: fail (blind)" "always-clean: receipt records the reason"
rm -f "$P/.gate-selftest-bad-applied"

# ── 4: slow stub past DOCTOR_GATE_TIMEOUT -> FAIL, timeout ───────────────────
echo "== 4: mxbuild sleeps past a 2 s DOCTOR_GATE_TIMEOUT -> FAIL (timeout) =="
S0=$(date +%s)
MXBUILD_PATH="$T/mxbuild" MODE_GATE_STUB=slow DOCTOR_GATE_TIMEOUT=2 \
  bash "$DOCTOR" --quick --gate-selftest --no-docker "$P" > "$T/out.slow" 2>&1
S1=$(date +%s)
assert_contains "$T/out.slow" "did not return within 2s" "slow: FAIL names the timeout"
[ $((S1 - S0)) -lt 30 ] && ok "slow: doctor returned promptly ($((S1 - S0))s, bound 2s)" \
                        || fail "slow: doctor took $((S1 - S0))s — the bound is not biting"

# ── 5: no mxbuild resolvable -> NOT RUN ───────────────────────────────────────
# MXCLI_HOME redirected to an empty dir: this machine may have a real download cache at
# ~/.mxcli/mxbuild (find_mxcli_cache), which would otherwise resolve a REAL mxbuild here and
# make this case indistinguishable from case 1.
echo "== 5: no mxbuild anywhere -> NOT RUN =="
MXCLI_HOME="$T/no-mxcli-home" \
  bash "$DOCTOR" --quick --gate-selftest --no-docker "$P" > "$T/out.notrun" 2>&1
assert_contains "$T/out.notrun" "NOT RUN" "no-mxbuild: reported as NOT RUN, not FAIL"
assert_missing  "$T/out.notrun" "gate self-test:" "no-mxbuild: no gate-self-test FAIL line"

# ── 6: --quick alone (no --gate-selftest) -> section absent ──────────────────
echo "== 6: --quick without --gate-selftest -> section absent =="
MXBUILD_PATH="$T/mxbuild" MODE_GATE_STUB=healthy \
  bash "$DOCTOR" --quick --no-docker "$P" > "$T/out.quickonly" 2>&1
assert_missing "$T/out.quickonly" "Gate self-test" "--quick alone: section not present"
rm -f "$P/.gate-selftest-bad-applied"

# ── 7: a full (non-quick) run includes it without the flag ───────────────────
echo "== 7: a full run includes the section without --gate-selftest =="
MXBUILD_PATH="$T/mxbuild" MODE_GATE_STUB=healthy \
  bash "$DOCTOR" --no-docker "$P" > "$T/out.full" 2>&1
assert_contains "$T/out.full" "Gate self-test" "full run: section present without the flag"
rm -f "$P/.gate-selftest-bad-applied"

echo; echo "$PASS passed, $FAIL failed   ($T)"
[ "$FAIL" -eq 0 ]
