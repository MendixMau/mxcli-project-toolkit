#!/usr/bin/env bash
# Fixture for sync-project.sh exiting 1, silently, in its CLAUDE.md duplicate-routing check when
# CLAUDE.md cites a Baseline-only skill (skills/query-the-model.md) but has NO
# "mxcli-project-toolkit Integration" heading — the shape every CLAUDE.md written by mxcli init
# v0.25 has. `grep -n heading | head | cut` returned grep's exit 1 through pipefail, errexit ended
# the script, and every step after it (bin/ crash-net refresh, tests/e2e install, lint rules)
# never ran. Field: three consuming projects of one organisation, every sync since 9a0350b.
#
# Run against the pre-fix script and T1-T3 must fail (exit 1, no bin/ line, no summary).
#
# Every fixture is built by the REAL bin/init-project.sh, under /tmp. No real project is touched.
#
# usage: test-sync-dup-heading-exit.sh /path/to/bin/sync-project.sh
export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
export MXTK_SYNC_SKIP_CLONE_CHECK=1

set -uo pipefail

SYNC="${1:?usage: test-sync-dup-heading-exit.sh /path/to/sync-project.sh}"
case "$SYNC" in /*) ;; *) SYNC="$PWD/$SYNC" ;; esac
TK="$(cd "$(dirname "$SYNC")/.." && pwd)"
INIT="$TK/bin/init-project.sh"
WORK="$(mktemp -d /tmp/dupheading.XXXXXX)"
trap 'rm -f "$MXTK_LEAKGUARD_DENYFILE"; rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

mkproj() {
  d="$WORK/$1"; mkdir -p "$d"; : > "$d/Fixture.mpr"
  MXTK_NO_GUIDE=1 "$INIT" "$d" >/dev/null 2>&1
  [ -f "$d/CLAUDE.local.md" ] && [ -f "$d/bin/exec.sh" ] || { echo "FIXTURE ERROR: init did not scaffold $d"; exit 2; }
  echo "$d"
}

# --- no heading: the case that died -----------------------------------------------------
P="$(mkproj noheading)"
grep -q 'mxcli-project-toolkit Integration' "$P/CLAUDE.md" && { echo "FIXTURE ERROR: init's CLAUDE.md already has the heading"; exit 2; }
printf '\nRead skills/query-the-model.md before asking the user.\n' >> "$P/CLAUDE.md"
rm -f "$P/bin/exec.sh"     # something the bin/ step, past the check, must report
OUT="$("$SYNC" "$P" --dry-run 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "T1 no heading: sync exits 0" || bad "T1 no heading: sync exits 0 (got $RC)" "$(printf '%s\n' "$OUT" | tail -5)"
printf '%s\n' "$OUT" | grep -q 'Would install: bin/exec.sh' \
  && ok "T2 no heading: the bin/ step past the check still runs" \
  || bad "T2 no heading: the bin/ step past the check still runs" "$(printf '%s\n' "$OUT" | tail -5)"
printf '%s\n' "$OUT" | grep -qE 'artifact\(s\) would be updated|All copied artifacts up to date' \
  && ok "T3 no heading: sync reaches its summary line" \
  || bad "T3 no heading: sync reaches its summary line"
printf '%s\n' "$OUT" | grep -q 'cites Baseline-only skills' \
  && ok "T4 no heading: the duplicate-routing warning is still raised" \
  || bad "T4 no heading: the duplicate-routing warning is still raised"

# --- heading present: the case the check was written for keeps working ------------------
P2="$(mkproj withheading)"
printf '\n## mxcli-project-toolkit Integration\n\nRead skills/query-the-model.md first.\n' >> "$P2/CLAUDE.md"
OUT2="$("$SYNC" "$P2" --dry-run 2>&1)"; RC2=$?
[ "$RC2" -eq 0 ] && ok "T5 heading: sync exits 0" || bad "T5 heading: sync exits 0 (got $RC2)"
printf '%s\n' "$OUT2" | grep -qE 'section \(~[0-9]+ word' \
  && ok "T6 heading: warning sizes the section" \
  || bad "T6 heading: warning sizes the section"

echo ""
echo "test-sync-dup-heading-exit: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
