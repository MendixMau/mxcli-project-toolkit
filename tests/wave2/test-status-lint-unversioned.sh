#!/usr/bin/env bash
# test-status-lint-unversioned.sh — bin/status.sh WATCHes when the lint debt under .claude/ is
# git-ignored (#523).
#
# Usage: bash tests/wave2/test-status-lint-unversioned.sh bin/status.sh
#
# The defect: a project .gitignore with `/.claude/` keeps lint-baseline.json, lint-acceptances.tsv
# and project-local lint rules out of git; a fresh clone then takes whatever it sees as a new
# baseline and the record of accepted rises is lost, and no toolkit check said so.
#
#   T1  `/.claude/` ignores all three          -> WATCH names each, with .gitignore:<line> '/.claude/'
#   T2  `/.claude/*` + three `!` negations     -> no lint-debt WATCH (the recommended layout)
#   T3  not a git repo                         -> no lint-debt WATCH (nothing to version against)
#   T4  the full screen carries the same WATCH
#
# GOLDEN INPUT: PROJECT.md is the real bin/init-project.sh scaffold; the check-ignore output is
# whatever this machine's git prints. gate-check.sh is stubbed silent in the toolkit copy.
export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
export MXTK_NO_GUIDE=1 MXTK_SYNC_SKIP_CLONE_CHECK=1
set -uo pipefail
SUT="${1:?usage: test-status-lint-unversioned.sh /path/to/bin/status.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
SRC="$(cd "$(dirname "$SUT")/.." && pwd)"

W="$(mktemp -d "${TMPDIR:-/tmp}/statuslu.XXXXXX")" || exit 2
trap 'rm -rf "$W"; rm -f "$MXTK_LEAKGUARD_DENYFILE"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

mkdir -p "$W/tk"
(cd "$SRC" && tar --exclude=.git --exclude=node_modules -cf - .) | (cd "$W/tk" && tar -xf -)
cp "$SUT" "$W/tk/bin/status.sh"
mkproj() {  # mkproj <name> <git:1|0> <gitignore text>
  local d="$W/proj-$1"; mkdir -p "$d"; : > "$d/Fixture.mpr"
  "$W/tk/bin/init-project.sh" "$d" >/dev/null 2>&1
  mkdir -p "$d/.claude/lint-rules"
  echo '{}' > "$d/.claude/lint-baseline.json"
  printf 'ts\trule\n' > "$d/.claude/lint-acceptances.tsv"
  echo '# rule' > "$d/.claude/lint-rules/local_rule.star"
  if [ "$2" = 1 ]; then git -C "$d" init -q; printf '%b' "$3" > "$d/.gitignore"; fi
  echo "$d"
}
printf '#!/usr/bin/env bash\nexit 0\n' > "$W/tk/bin/gate-check.sh"

echo "== bin/status.sh lint-debt WATCH (#523) =="
P1="$(mkproj ignored 1 'node_modules/\n/.claude/\n')"
out="$(bash "$W/tk/bin/status.sh" "$P1" --brief 2>&1)"
w="$(grep '^WATCH' <<<"$out")"
case "$w" in
  *"lint debt is not versioned"*".claude/lint-baseline.json (.gitignore:2 '/.claude/')"*".claude/lint-acceptances.tsv"*".claude/lint-rules"*) ok "T1 /.claude/ ignored: WATCH names all three with .gitignore:2" ;;
  *) bad "T1 want the lint-debt WATCH naming three paths" "$out" ;;
esac

P2="$(mkproj negated 1 '/.claude/*\n!/.claude/lint-baseline.json\n!/.claude/lint-acceptances.tsv\n!/.claude/lint-rules/\n')"
out="$(bash "$W/tk/bin/status.sh" "$P2" --brief 2>&1)"
if grep -q 'lint debt is not versioned' <<<"$out"; then bad "T2 negated layout must not WATCH" "$out"; else ok "T2 '/.claude/*' plus negations: no lint-debt WATCH"; fi

P3="$(mkproj nogit 0 '')"
out="$(bash "$W/tk/bin/status.sh" "$P3" --brief 2>&1)"
if grep -q 'lint debt is not versioned' <<<"$out"; then bad "T3 no git repo must not WATCH" "$out"; else ok "T3 not a git repo: no lint-debt WATCH"; fi

out="$(bash "$W/tk/bin/status.sh" "$P1" 2>&1)"
if grep -q '^WATCH .*lint debt is not versioned' <<<"$out"; then ok "T4 full screen: same WATCH"; else bad "T4 full screen lacks the WATCH" "$out"; fi

echo "-- $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
