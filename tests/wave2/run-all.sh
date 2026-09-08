#!/bin/bash
# run-all.sh — run every wave-2 fixture against the right subject.
#
# Exists because each fixture takes its subject-under-test as $1 and several take something
# other than gate-check.sh (exec.sh, sync-project.sh, check-docs-numbering.sh, a skill file).
# Running them all with the same argument silently tests the wrong thing and reports failures
# that are purely the runner's fault — which has now happened twice, and both times cost a
# round of chasing regressions that did not exist.
#
# Each fixture declares its own subject in a `usage:` line; this reads that rather than
# hardcoding a mapping that would rot the moment a fixture is added.
#
# Usage: bash tests/wave2/run-all.sh [-v]

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="$(cd "$DIR/../.." && pwd)"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

FAILED=0; RAN=0; SKIPPED=0

# Belt for the denylist pollution (2026-09-08): fixtures scaffold through init-project.sh, which
# registers the project name in the toolkit's gitignored denylist unless told otherwise. Send it
# to scratch here for every fixture, and refuse at the end if the real one appeared anyway.
export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-runall-denylist.$$"
ROOT_DENY="$TOOLKIT/.leakguard-deny"; ROOT_DENY_BEFORE=0; [ -f "$ROOT_DENY" ] && ROOT_DENY_BEFORE=1

echo "### SYNTAX — every shell script in the toolkit"
syn=0
for f in "$TOOLKIT"/bin/*.sh "$TOOLKIT"/tests/wave2/*.sh "$TOOLKIT"/project-bin/*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" 2>&1 | sed "s|^|  |" | grep . && syn=$((syn+1))
done
echo "syntax failures: $syn"
[ "$syn" -gt 0 ] && FAILED=$((FAILED+syn))

echo ""
echo "### FIXTURES"
for t in "$DIR"/test-*.sh; do
  name="$(basename "$t")"

  # Read the subject out of the fixture's own usage line, e.g.
  #   # Usage: bash test-bug05.sh [path-to-gate-check.sh]
  # Both spellings appear in the fixtures: `/path/to/gate-check.sh` and `[path-to-init-project.sh]`.
  # The second one matches the filename pattern whole, so the prefix has to come off explicitly.
  subj_name=$(grep -iEm1 '^# *usage:' "$t" \
              | grep -oE '[A-Za-z0-9_.-]+\.(sh|md)' | grep -v "^${name}$" | head -1 \
              | sed 's|^path-to-||')
  if [ -z "$subj_name" ]; then
    # Fall back to the "usage:" line the fixture prints when run with no argument.
    subj_name=$("$t" 2>&1 </dev/null | grep -oE '/path/to/[A-Za-z0-9_.-]+\.(sh|md)' \
                | head -1 | sed 's|/path/to/||')
  fi

  subject=""
  if [ -n "$subj_name" ]; then
    for cand in "$TOOLKIT/bin/$subj_name" "$TOOLKIT/project-bin/$subj_name" \
                "$TOOLKIT/skills/$subj_name" "$TOOLKIT/claude-hooks/hooks/$subj_name" \
                "$TOOLKIT/$subj_name"; do
      [ -f "$cand" ] && { subject="$cand"; break; }
    done
    if [ -z "$subject" ]; then
      # Counted as a failure, not a skip. A fixture whose subject cannot be resolved is not
      # being run, and a runner that reports "all green" while quietly not running two
      # fixtures is the same false-green this suite exists to catch.
      echo "  FAIL  $name — declares subject '$subj_name', which is not in the toolkit"
      SKIPPED=$((SKIPPED+1)); FAILED=$((FAILED+1)); continue
    fi
  fi

  out=$(bash "$t" $subject 2>&1); rc=$?
  RAN=$((RAN+1))
  tail_line=$(printf '%s' "$out" | grep -E 'PASS=|SCORE:|ok,|FAIL' | tail -1)
  if [ "$rc" -eq 0 ]; then
    printf "  ok    %-34s %s\n" "$name" "$tail_line"
  else
    printf "  FAIL  %-34s rc=%s  %s\n" "$name" "$rc" "$tail_line"
    FAILED=$((FAILED+1))
    printf '%s\n' "$out" | grep -E '^\s*FAIL' | sed 's/^/          /'
  fi
  [ "$VERBOSE" = "1" ] && printf '%s\n' "$out" | sed 's/^/        /'
done

echo ""
echo "ran $RAN fixture(s), skipped $SKIPPED, failing $FAILED"
rm -f "$MXTK_LEAKGUARD_DENYFILE"
if [ "$ROOT_DENY_BEFORE" -eq 0 ] && [ -f "$ROOT_DENY" ]; then
  echo "FAIL  a fixture wrote $ROOT_DENY — the real toolkit denylist (the pollution MXTK_LEAKGUARD_DENYFILE exists to stop)"
  FAILED=$((FAILED+1))
fi
[ "$FAILED" -eq 0 ]
