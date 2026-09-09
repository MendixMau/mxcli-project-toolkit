#!/usr/bin/env bash
# test-doctor-docker-probe.sh — doctor.sh's docker probe must never hang, and must say what
# it is doing. Field report 2026-09-09: with Docker Desktop installed but stopped, `docker info`
# sat silent for minutes at the end of init-project.sh and the whole scaffold read as hung.
#
#   usage: bash tests/wave2/test-doctor-docker-probe.sh bin/doctor.sh
#
# Three fake `docker` binaries on PATH: one that hangs, one that answers "down" at once, one
# that answers "up". Plus --no-docker / MXTK_DOCTOR_SKIP_DOCKER=1 skipping the section.
set -u
DOCTOR="${1:?usage: $0 bin/doctor.sh}"
DOCTOR="$(cd "$(dirname "$DOCTOR")" && pwd)/$(basename "$DOCTOR")"
T="$(mktemp -d "${TMPDIR:-/tmp}/mxtk-doctor-docker.XXXXXX")"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*"; }
assert_contains() { if grep -q -- "$2" "$1"; then ok "$3"; else fail "$3 — expected: $2"; fi; }
assert_missing()  { if grep -q -- "$2" "$1"; then fail "$3 — unexpected: $2"; else ok "$3"; fi; }

mkfake() { # mkfake <dir> <body>
  mkdir -p "$1"; printf '#!/usr/bin/env bash\n%s\n' "$2" > "$1/docker"; chmod +x "$1/docker"
}
mkfake "$T/hang" 'sleep 120'
mkfake "$T/down" 'echo "error during connect: Docker Desktop is not running" >&2; exit 1'
mkfake "$T/up"   'echo "Server Version: 27.0.0"; exit 0'

echo "doctor docker probe — $DOCTOR"

# 1. hanging daemon: bounded, and says so
S0=$(date +%s)
PATH="$T/hang:$PATH" MXTK_DOCKER_PROBE_SECS=2 bash "$DOCTOR" > "$T/hang.out" 2>&1
S1=$(date +%s)
if [ $((S1 - S0)) -lt 40 ]; then ok "hanging docker: doctor finished in $((S1 - S0)) s (bound 2 s)"; else fail "hanging docker: doctor took $((S1 - S0)) s — the bound is not biting"; fi
assert_contains "$T/hang.out" "probing the docker daemon (bounded: 2 s" "hanging docker: announces the probe and its bound before waiting"
assert_contains "$T/hang.out" "gave no answer within 2 s" "hanging docker: reports the timeout as 'not running'"
assert_contains "$T/hang.out" "MXTK_DOCKER_PROBE_SECS=30" "hanging docker: tells how to raise the bound"
assert_contains "$T/hang.out" "Then re-run: bin/doctor.sh" "hanging docker: says how to re-check after starting it"
assert_missing  "$T/hang.out" "docker daemon responding" "hanging docker: not reported as up"

# 2. daemon down, answering at once
PATH="$T/down:$PATH" bash "$DOCTOR" > "$T/down.out" 2>&1
assert_contains "$T/down.out" "daemon is not responding" "down docker: reported as not responding"
assert_contains "$T/down.out" "To start it:" "down docker: carries a start command"
assert_missing  "$T/down.out" "gave no answer within" "down docker: a fast 'down' is not called a timeout"

# 3. daemon up
PATH="$T/up:$PATH" bash "$DOCTOR" > "$T/up.out" 2>&1
assert_contains "$T/up.out" "docker daemon responding" "up docker: reported as responding"

# 4. skipping the section entirely
PATH="$T/hang:$PATH" bash "$DOCTOR" --no-docker > "$T/skip.out" 2>&1
assert_contains "$T/skip.out" "docker probe skipped" "--no-docker: section skipped (hanging fake never called)"
S0=$(date +%s); PATH="$T/hang:$PATH" MXTK_DOCTOR_SKIP_DOCKER=1 bash "$DOCTOR" > "$T/skip2.out" 2>&1; S1=$(date +%s)
assert_contains "$T/skip2.out" "docker probe skipped" "MXTK_DOCTOR_SKIP_DOCKER=1: section skipped"
if [ $((S1 - S0)) -lt 40 ]; then ok "MXTK_DOCTOR_SKIP_DOCKER=1: no wait ($((S1 - S0)) s)"; else fail "MXTK_DOCTOR_SKIP_DOCKER=1 still waited $((S1 - S0)) s"; fi

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
