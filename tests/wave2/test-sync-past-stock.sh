#!/usr/bin/env bash
# Fixtures for sync-project.sh's past-stock refresh (bin/lib/past-stock.sh): a bin/ or tests/e2e/
# copy that is byte-for-byte an OLDER toolkit version is refreshed without a flag; a hand-edited
# copy is still only reported.
#
# Run against the pre-change sync-project.sh and T2/T7 must fail (it reported every older copy
# as drift and refreshed none of them — field run 2026-10-07, existing project).
#
# The history the refresh relies on is built here, not borrowed: the toolkit tree under test is
# copied into a throwaway git repo with two commits (v1 = the tree as-is, v2 = one bin/ and one
# tests/e2e/ file changed), so "an older version" is known exactly and a shallow CI clone cannot
# change the result. Every project is scaffolded by that copy's REAL bin/init-project.sh, under
# /tmp. No real project is touched.
#
# usage: test-sync-past-stock.sh /path/to/bin/sync-project.sh
export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
# The throwaway toolkit is a fresh repo on no branch anyone tracks; the stale-clone check would
# warn about that on every run. Real users never set this.
export MXTK_SYNC_SKIP_CLONE_CHECK=1

set -uo pipefail

SRC="${1:?usage: test-sync-past-stock.sh /path/to/sync-project.sh}"
case "$SRC" in /*) ;; *) SRC="$PWD/$SRC" ;; esac
SRC_TK="$(cd "$(dirname "$SRC")/.." && pwd)"
WORK="$(mktemp -d /tmp/paststock.XXXXXX)"
trap 'rm -f "$MXTK_LEAKGUARD_DENYFILE"; rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

fingerprint() {
  find "$1" -type f 2>/dev/null | LC_ALL=C sort | while read -r f; do
    if [ -x "$f" ]; then x=x; else x=-; fi
    printf '%s %s %s\n' "${f#$1}" "$x" "$(md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1)"
  done
}

G() { git -C "$TK" -c user.name=fixture -c user.email=fixture -c commit.gpgsign=false "$@"; }

# --- the throwaway toolkit, with known history ------------------------------------------
TK="$WORK/tk"
mkdir -p "$TK"
if git -C "$SRC_TK" rev-parse --git-dir >/dev/null 2>&1; then
  # Tracked + untracked-not-ignored: the tree under test, uncommitted changes included.
  (cd "$SRC_TK" && git ls-files -z --cached --others --exclude-standard \
     | xargs -0 -I{} sh -c '[ -f "$1" ] && printf "%s\0" "$1"' _ {} \
     | tar --null -T - -cf -) | (cd "$TK" && tar xf -)
else
  (cd "$SRC_TK" && tar --exclude=.git --exclude=node_modules -cf - .) | (cd "$TK" && tar xf -)
fi
SYNC="$TK/bin/sync-project.sh"
INIT="$TK/bin/init-project.sh"
BINF=exec.sh              # a crash-net script that sources _common.sh
E2EF=page-audit.js        # an engine file that is neither hold file (helpers.js, config.js)
[ -x "$SYNC" ] && [ -f "$TK/project-bin/$BINF" ] && [ -f "$TK/project-tests/e2e/$E2EF" ] \
  || { echo "FIXTURE ERROR: toolkit copy incomplete under $TK"; exit 2; }

git init -q "$TK"
# Pre-split history: project-bin/X used to live at bin/X. One commit puts an "old" exec.sh
# there and the next removes it, so the fallback path has something real to find.
mkdir -p "$TK/bin"
printf '#!/usr/bin/env bash\n# exec.sh from before the project-bin split (fixture)\n' > "$TK/bin/$BINF"
G add -A >/dev/null && G commit -qm "v0: pre-split" || { echo "FIXTURE ERROR: v0 commit"; exit 2; }
PRESPLIT="$(cat "$TK/bin/$BINF")"
G rm -q "bin/$BINF" && G commit -qm "v1: tree under test" || { echo "FIXTURE ERROR: v1 commit"; exit 2; }
V1_BIN="$WORK/v1-$BINF";  cp "$TK/project-bin/$BINF" "$V1_BIN"
V1_E2E="$WORK/v1-$E2EF";  cp "$TK/project-tests/e2e/$E2EF" "$V1_E2E"
printf '# fixture v2\n' >> "$TK/project-bin/$BINF"
printf '// fixture v2\n' >> "$TK/project-tests/e2e/$E2EF"
G commit -qam "v2: newer exec.sh and $E2EF" || { echo "FIXTURE ERROR: v2 commit"; exit 2; }

mkproj() {
  d="$WORK/$1"; mkdir -p "$d"; : > "$d/Fixture.mpr"
  MXTK_NO_GUIDE=1 "$INIT" "$d" >/dev/null 2>&1
  [ -f "$d/bin/$BINF" ] && [ -f "$d/tests/e2e/$E2EF" ] || { echo "FIXTURE ERROR: init did not install $BINF/$E2EF"; exit 2; }
  echo "$d"
}
# Put the v1 (older, unedited) copies into project $1, exec bit kept as init left it.
age() { cp "$V1_BIN" "$1/bin/$BINF"; chmod +x "$1/bin/$BINF"; cp "$V1_E2E" "$1/tests/e2e/$E2EF"; }

echo "== T1: --dry-run names both older copies and writes nothing =="
P="$(mkproj t1)"; age "$P"
B="$(fingerprint "$P")"
OUT="$("$SYNC" "$P" --dry-run 2>&1)"
A="$(fingerprint "$P")"
[ "$B" = "$A" ] && ok "dry run wrote nothing" || bad "dry run WROTE to the project" "$(diff <(echo "$B") <(echo "$A"))"
printf '%s' "$OUT" | grep -q "Would refresh: bin/$BINF" && ok "dry run names bin/$BINF" || bad "dry run did not name bin/$BINF" "$OUT"
printf '%s' "$OUT" | grep -q "Would refresh: tests/e2e/$E2EF" && ok "dry run names tests/e2e/$E2EF" || bad "dry run did not name tests/e2e/$E2EF" "$OUT"

echo "== T2: a real run refreshes both, keeps the exec bit =="
OUT="$("$SYNC" "$P" 2>&1)"
cmp -s "$P/bin/$BINF" "$TK/project-bin/$BINF" && ok "bin/$BINF refreshed to v2" || bad "bin/$BINF NOT refreshed" "$OUT"
[ -x "$P/bin/$BINF" ] && ok "bin/$BINF still executable" || bad "bin/$BINF lost its exec bit"
cmp -s "$P/tests/e2e/$E2EF" "$TK/project-tests/e2e/$E2EF" && ok "tests/e2e/$E2EF refreshed to v2" || bad "tests/e2e/$E2EF NOT refreshed" "$OUT"
printf '%s' "$OUT" | grep -q "Refreshed: bin/$BINF (was an unedited toolkit copy of 20" \
  && ok "run says what it refreshed and which version it was" || bad "no dated Refreshed line" "$OUT"

echo "== T3: the rerun is clean =="
OUT="$("$SYNC" "$P" 2>&1)"
printf '%s' "$OUT" | grep -qE "Refreshed:|bin/$BINF is LOCALLY MODIFIED|differ from the toolkit engine:.*$E2EF" \
  && bad "rerun still refreshes or reports $BINF/$E2EF" "$OUT" || ok "rerun refreshes and reports nothing for either file"

echo "== T4: a hand-edited copy is reported, never overwritten =="
P="$(mkproj t4)"
{ cat "$V1_BIN"; printf '# local hardening\n'; } > "$P/bin/$BINF"
{ cat "$V1_E2E"; printf '// local hardening\n'; } > "$P/tests/e2e/$E2EF"
B="$(fingerprint "$P")"
OUT="$("$SYNC" "$P" 2>&1)"
grep -q 'local hardening' "$P/bin/$BINF" && ok "edited bin/$BINF kept" || bad "edited bin/$BINF OVERWRITTEN"
grep -q 'local hardening' "$P/tests/e2e/$E2EF" && ok "edited tests/e2e/$E2EF kept" || bad "edited tests/e2e/$E2EF OVERWRITTEN"
printf '%s' "$OUT" | grep -q "bin/$BINF is LOCALLY MODIFIED" && ok "edited bin/$BINF reported as modified" || bad "edited bin/$BINF not reported" "$OUT"
printf '%s' "$OUT" | grep -q "Refreshed:" && bad "something was refreshed on an edited project" "$OUT" || ok "nothing refreshed"

echo "== T5: a hand-edited shared library holds its older dependants back =="
P="$(mkproj t5)"; age "$P"
printf '# local edit\n' >> "$P/bin/_common.sh"
printf '// local edit\n' >> "$P/tests/e2e/helpers.js"
OUT="$("$SYNC" "$P" 2>&1)"
cmp -s "$P/bin/$BINF" "$V1_BIN" && ok "bin/$BINF held at v1 (bin/_common.sh is edited)" || bad "bin/$BINF refreshed over an edited _common.sh"
printf '%s' "$OUT" | grep -q "NOT refreshed: bin/_common.sh is" && ok "hold is explained" || bad "hold not explained" "$OUT"
cmp -s "$P/tests/e2e/$E2EF" "$V1_E2E" && ok "tests/e2e/$E2EF held at v1 (helpers.js is edited)" || bad "tests/e2e/$E2EF refreshed over an edited helpers.js"
printf '%s' "$OUT" | grep -q "Held back because tests/e2e/helpers.js" && ok "e2e hold is explained" || bad "e2e hold not explained" "$OUT"

echo "== T6: --no-refresh reports instead =="
P="$(mkproj t6)"; age "$P"
OUT="$("$SYNC" "$P" --no-refresh 2>&1)"
cmp -s "$P/bin/$BINF" "$V1_BIN" && ok "bin/$BINF kept under --no-refresh" || bad "bin/$BINF refreshed despite --no-refresh"
cmp -s "$P/tests/e2e/$E2EF" "$V1_E2E" && ok "tests/e2e/$E2EF kept under --no-refresh" || bad "tests/e2e/$E2EF refreshed despite --no-refresh"
printf '%s' "$OUT" | grep -q -- "--no-refresh kept it" && ok "kept copy is named as unedited" || bad "no --no-refresh note" "$OUT"

echo "== T7: a copy from before the project-bin split is found under its old path =="
P="$(mkproj t7)"
printf '%s\n' "$PRESPLIT" > "$P/bin/$BINF"; chmod +x "$P/bin/$BINF"
OUT="$("$SYNC" "$P" 2>&1)"
cmp -s "$P/bin/$BINF" "$TK/project-bin/$BINF" && ok "pre-split copy refreshed" || bad "pre-split copy NOT refreshed" "$OUT"

echo "== T8: a toolkit that is not a git checkout falls back to report-only =="
P="$(mkproj t8)"; age "$P"
mv "$TK/.git" "$WORK/tk.git"
OUT="$("$SYNC" "$P" 2>&1)"
mv "$WORK/tk.git" "$TK/.git"
cmp -s "$P/bin/$BINF" "$V1_BIN" && ok "no history -> bin/$BINF not touched" || bad "bin/$BINF refreshed with no history to prove it"
printf '%s' "$OUT" | grep -q "bin/$BINF is LOCALLY MODIFIED" && ok "no history -> reported as before" || bad "no history -> not reported" "$OUT"

echo
echo "past-stock: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
