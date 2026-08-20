#!/usr/bin/env bash
# run-tests.sh — fixture tests for the toolkit's guard scripts.
#
# Why this exists: on 2026-08-03 an audit found eight ways for a guard in this
# toolkit to report green without looking at the thing it guards — four in
# gate-check.sh, two in check-no-client-data.sh, one in coverage-check.sh, and
# one script advertised in the README that does not exist. Every one of them had
# shipped clean for months. None had ever been run against a case it was
# supposed to FAIL.
#
# The rule this file enforces: a guard is not fixed until a fixture proves it
# fails. Each test below asserts an exit code, and the FAIL cases are the point
# — a suite where everything passes is the thing we are trying to stop shipping.
#
# Fixtures are generated at runtime, never committed. A committed fixture
# containing CJK or a client-shaped name would be flagged by this repo's own
# leak guard, which is correct behaviour and would make the suite unrunnable.
#
# Usage: tests/run-tests.sh [-v]
# Exit 0 only if every assertion holds.
#
# Keep this bash-3.2 compatible: `env bash` on stock macOS is 3.2.57 and has no
# mapfile/readarray/associative arrays.

set -uo pipefail

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/bin/gate-check.sh"
LEAK="$ROOT/bin/check-no-client-data.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/toolkit-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0

# assert <name> <expected-exit> <command...>
assert() {
  local name="$1" want="$2"; shift 2
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    PASSED=$((PASSED + 1))
    printf '  ok    %-46s exit=%s\n' "$name" "$rc"
    [ "$VERBOSE" -eq 1 ] && printf '%s\n' "$out" | sed 's/^/          /'
  else
    FAILED=$((FAILED + 1))
    printf '  FAIL  %-46s exit=%s (want %s)\n' "$name" "$rc" "$want"
    printf '%s\n' "$out" | sed 's/^/          /'
  fi
  return 0
}

TOOLKIT_SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

# Build a minimal project fixture. $1=name $2=status cell for the stage-7 row.
mkproject() {
  local d="$WORK/$1"
  mkdir -p "$d/analysis/alpha/knowledge-base"
  {
    echo "# Project"
    echo
    echo "Toolkit commit: $TOOLKIT_SHA"
    echo
    echo "| Stage | Decision | Status | Notes |"
    echo "|---|---|---|---|"
    echo "| 7 | cutover approach | $2 | note |"
  } > "$d/PROJECT.md"
  echo "$d"
}

# Build a git repo fixture for the leak guard. $1=name
mkrepo() {
  local d="$WORK/$1"
  mkdir -p "$d"
  ( cd "$d" && git init -q . && git config user.email t@example.com && git config user.name t )
  printf 'AcmeCorp\n' > "$d/.leakguard-deny"
  echo "$d"
}

echo "toolkit tests — $ROOT (HEAD $TOOLKIT_SHA)"
echo

# ---------------------------------------------------------------------------
echo "gate-check.sh — hard gates must not be passable by accident"
# ---------------------------------------------------------------------------

# A status of UNCONFIRMED contains the substring CONFIRMED. The old check used
# `.*CONFIRMED`, so a row explicitly marked as not decided passed the ✋ gate.
assert "UNCONFIRMED does not pass stage 7"   1 "$GATE" "$(mkproject unconf 'UNCONFIRMED')" 7
assert "NOT CONFIRMED does not pass stage 7" 1 "$GATE" "$(mkproject notconf 'NOT CONFIRMED')" 7
assert "CONFIRMED passes stage 7"            0 "$GATE" "$(mkproject conf 'CONFIRMED')" 7
assert "lowercase confirmed still passes"    0 "$GATE" "$(mkproject lower 'confirmed')" 7

# Stage 5 (Build) is not machine-checkable. It must not answer 0, because "the
# checker exited 0" is read as a passed gate — and Stage 5 holds the most work.
assert "stage 5 MANUAL is not a pass"        2 "$GATE" "$(mkproject manual 'CONFIRMED')" 5

# bash evaluates array subscripts arithmetically, so a non-numeric stage used to
# abort the script under set -u and was observed exiting 0.
assert "typo'd stage argument is rejected"   2 "$GATE" "$(mkproject typo 'CONFIRMED')" Stage3

# With two workstreams a single verdict describes only whichever sorts first.
TWO="$WORK/two"
mkdir -p "$TWO/analysis/alpha/knowledge-base" "$TWO/analysis/beta/knowledge-base"
printf '# P\n\nToolkit commit: %s\n' "$TOOLKIT_SHA" > "$TWO/PROJECT.md"
assert "two workstreams refuse a bare run"   2 "$GATE" "$TWO"
assert "GATE_WORKSTREAM resolves ambiguity"  0 env GATE_WORKSTREAM=beta "$GATE" "$TWO"

echo

# ---------------------------------------------------------------------------
echo "check-no-client-data.sh — the leak guard must detect its own positives"
# ---------------------------------------------------------------------------

# grep -P is GNU-only; on BSD the probe errored into /dev/null and the whole
# CJK check was skipped while the script still printed a clean pass.
( cd "$(mkrepo cjk)" && printf 'label: \xe6\xa0\xaa\xe5\xbc\x8f\xe4\xbc\x9a\xe7\xa4\xbe\n' > a.md )
assert "CJK is detected"                     1 bash -c "cd '$WORK/cjk' && '$LEAK'"

# The original probe covered Kana and Han only; engagements have included Korean
# stacks, so Hangul text would have passed even had the probe worked.
( cd "$(mkrepo hangul)" && printf 'x: \xed\x9a\x8c\xec\x82\xac\n' > a.md )
assert "Hangul is detected"                  1 bash -c "cd '$WORK/hangul' && '$LEAK'"

( cd "$(mkrepo name)" && printf 'built for AcmeCorp\n' > a.md )
assert "denylisted name is detected"         1 bash -c "cd '$WORK/name' && '$LEAK'"

# A path with a space truncated the old whitespace-split file list.
( cd "$(mkrepo space)" && printf 'x: \xe6\xa0\xaa\xe5\xbc\x8f\n' > 'my file.md' )
assert "path with a space is scanned"        1 bash -c "cd '$WORK/space' && '$LEAK'"

# A path beginning with '-' was read by grep/perl as a flag.
( cd "$(mkrepo dash)" && printf 'x: \xe6\xa0\xaa\xe5\xbc\x8f\n' > -weird.md )
assert "dash-prefixed path is scanned"       1 bash -c "cd '$WORK/dash' && '$LEAK'"

# .leakguard-deny is gitignored by design, so it is absent on every clone but
# the author's. The old code warned, then printed ✅ and exited 0 — the name
# check was off by default for everyone else.
D="$(mkrepo nodeny)"; rm -f "$D/.leakguard-deny"; printf 'harmless\n' > "$D/a.md"
assert "missing denylist is not a pass"      2 bash -c "cd '$WORK/nodeny' && '$LEAK'"
assert "missing denylist can be opted out"   0 bash -c "cd '$WORK/nodeny' && LEAKGUARD_ALLOW_NO_DENYLIST=1 '$LEAK'"

( cd "$(mkrepo clean)" && printf 'entirely generic content\n' > a.md )
assert "clean repo passes"                   0 bash -c "cd '$WORK/clean' && '$LEAK'"

echo

# ---------------------------------------------------------------------------
echo "jq leaf enumeration — false and null are requirements too"
# ---------------------------------------------------------------------------
# `paths(scalars)` is `paths | select(getpath(.)|scalars)`, and only false and
# null are falsy in jq — so every leaf whose value was false or null vanished.
# Across four PROJECT-C BRDs that hid 292 requirement leaves, including the
# `allowedInUrl: false` flags in a deep-link contract.
echo '{"a":false,"b":true,"c":null}' > "$WORK/leaf.json"
LEAVES=$(jq -r 'paths as $p | select(getpath($p)|type|IN("object","array")|not)
                | "/" + ($p|map(tostring)|join("/"))' "$WORK/leaf.json" | sort | tr '\n' ' ')
if [ "$LEAVES" = "/a /b /c " ]; then
  PASSED=$((PASSED + 1)); printf '  ok    %-46s\n' "false and null count as leaves"
else
  FAILED=$((FAILED + 1)); printf '  FAIL  %-46s got: %s\n' "false and null count as leaves" "$LEAVES"
fi

echo

# ---------------------------------------------------------------------------
echo "portability — a script that only runs on a Mac is a broken script"
# ---------------------------------------------------------------------------
# The toolkit is handed to customers, partners and colleagues on Windows and Linux. Portability
# regresses the moment someone authors a new script on a Mac, which is every time, so the guard
# runs in the suite rather than living in a document nobody re-reads.
#
# This deliberately checks the REAL scripts, not a fixture: the thing being asserted is a
# property of what ships. A new violation therefore fails the suite for whoever introduces it.
if bash "$ROOT/bin/check-portability.sh" > "$WORK/port.out" 2>&1; then
  PASSED=$((PASSED + 1)); printf '  ok    %-46s\n' "no macOS-only assumptions in shipped scripts"
else
  FAILED=$((FAILED + 1)); printf '  FAIL  %-46s\n' "macOS-only assumptions found"
  sed 's/^/        /' "$WORK/port.out"
fi

echo

# ---------------------------------------------------------------------------
echo "doctor.sh — the environment probe must run on a machine with nothing installed"
# ---------------------------------------------------------------------------
# doctor.sh exists to tell a user what they are missing. It is the one script that must survive
# a bare environment, so it may not itself depend on what it is checking for — most obviously,
# it must be able to report "you have no Python" while having no Python.
NOPY="$WORK/nopy"; mkdir -p "$NOPY"
for c in bash sed grep awk cat cut tr sort head wc find ls basename dirname mkdir rm cmp printf uname git; do
  p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$NOPY/$c"
done
if env -i PATH="$NOPY" HOME="$WORK" bash "$ROOT/bin/doctor.sh" > "$WORK/doc.out" 2>&1; then :; fi
if grep -q "No working Python 3 found" "$WORK/doc.out"; then
  PASSED=$((PASSED + 1)); printf '  ok    %-46s\n' "reports a missing Python instead of crashing"
else
  FAILED=$((FAILED + 1)); printf '  FAIL  %-46s\n' "did not report the missing Python"
  sed 's/^/        /' "$WORK/doc.out" | head -20
fi

echo
echo "passed=$PASSED failed=$FAILED"
[ "$FAILED" -eq 0 ]
