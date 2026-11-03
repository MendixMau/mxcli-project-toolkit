#!/usr/bin/env bash
# test-check-moved-text.sh — bin/check-moved-text.sh must fail loudly, never green-by-absence.
#
# Born in review of the T4 stub-diet trim (#369): a mistyped source path produced "0 of 0" and
# exit 0. Builds a throwaway git repo (base commit tagged `base`), edits its working tree, and
# runs the real script there with --base base. Cases: every moved line found (exit 0) · a removed
# line not in the destination (exit 1, line named) · a mistyped or unchanged source (exit 2) ·
# lines carrying regex/shell metacharacters and a leading dash · short lines listed as trivial.
#
# Usage: bash tests/wave2/test-check-moved-text.sh [path-to-check-moved-text.sh]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUT="${1:-$TOOLKIT/bin/check-moved-text.sh}"
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"
[ -r "$SUT" ] || { echo "test-check-moved-text: no script at $SUT"; exit 2; }

PASS=0; FAIL=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/moved-text.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

printf 'test-check-moved-text: %s\n' "$SUT"

# fresh repo: src.md and other.md at base, dest.md empty-ish
setup() {
  rm -rf "$TMP/r"; mkdir -p "$TMP/r"; cd "$TMP/r" || exit 2
  git init -q . && git config user.email t@t && git config user.name t
  cat > src.md <<'SRC'
# Skill
The rule stays here and is long enough.
This story line moves to the history file.
- a leading dash line with $HOME and `backticks` moves too
Regex chars [a-z]* .+ ? ^ $ \d and "quotes" 'single' move
|---|
A line that is deleted and found nowhere else at all.
SRC
  printf 'unchanged file\n' > other.md
  printf '# History\n' > dest.md
  git add src.md other.md dest.md && git commit -q -m base && git tag base
}
run() { OUT="$("$SUT" --base base "$@" 2>&1)"; RC=$?; }

# 1 — found: move four lines verbatim (special characters included)
setup
grep -v -e 'story line' -e 'leading dash' -e 'Regex chars' -e '^|---|$' -e 'deleted and found nowhere' src.md > s && mv s src.md
printf '%s\n' 'This story line moves to the history file.' \
  '- a leading dash line with $HOME and `backticks` moves too' \
  'Regex chars [a-z]* .+ ? ^ $ \d and "quotes" '"'"'single'"'"' move' '|---|' \
  'A line that is deleted and found nowhere else at all.' >> dest.md
run dest.md src.md
[ "$RC" -eq 0 ] && ok "all moved lines found -> exit 0" || bad "found case exit $RC" "$OUT"
printf '%s' "$OUT" | grep -q '5 of 5' && ok "count reads 5 of 5" || bad "count" "$OUT"
printf '%s' "$OUT" | grep -q 'Trivially found' && printf '%s' "$OUT" | grep -qF '|---|' \
  && ok "short line listed as trivially found" || bad "short line not listed" "$OUT"

# 2 — missing: one removed line absent from dest -> exit 1 and the line is named
setup
grep -v -e 'story line' -e 'deleted and found nowhere' src.md > s && mv s src.md
printf '%s\n' 'This story line moves to the history file.' >> dest.md
run dest.md src.md
[ "$RC" -eq 1 ] && ok "missing line -> exit 1" || bad "missing case exit $RC" "$OUT"
printf '%s' "$OUT" | grep -qF 'A line that is deleted and found nowhere else at all.' \
  && ok "missing line is named" || bad "missing line not named" "$OUT"

# 2b — missing line with special characters is named verbatim, not treated as a regex
setup
grep -v -e 'Regex chars' src.md > s && mv s src.md
printf '%s\n' 'Regex chars [a-z] different text' >> dest.md
run dest.md src.md
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -qF 'Regex chars [a-z]* .+ ? ^ $ \d and "quotes"' \
  && ok "special-character line missing -> exit 1, named verbatim" || bad "special missing" "rc=$RC $OUT"

# 3 — typo path -> exit 2, even alongside a valid source
setup
grep -v -e 'story line' src.md > s && mv s src.md
printf '%s\n' 'This story line moves to the history file.' >> dest.md
run dest.md src.md srcc.md
[ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'srcc.md' \
  && ok "mistyped source -> exit 2, path named" || bad "typo case exit $RC" "$OUT"

# 4 — unchanged source only -> exit 2 (never "0 of 0" green)
setup
run dest.md other.md
[ "$RC" -eq 2 ] && ok "unchanged source -> exit 2" || bad "unchanged case exit $RC" "$OUT"
printf '%s' "$OUT" | grep -q '0 of 0' && bad "printed a 0 of 0 verdict" "$OUT" || ok "no '0 of 0' verdict printed"

# 5 — usage
cd "$TMP" || exit 2
"$SUT" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "no arguments -> exit 2" || bad "usage exit $RC"

printf '\ntest-check-moved-text.sh: %d ok, %d FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
