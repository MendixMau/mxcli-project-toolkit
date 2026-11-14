#!/usr/bin/env bash
# test-snapshot-gitignore.sh — project-bin/snapshot-mpr.sh keeps /.mpr-snapshots/ in .gitignore
# without duplicating it in a CRLF file, and appends in the file's own line ending.
#
# Usage: bash tests/wave2/test-snapshot-gitignore.sh [path-to-snapshot-mpr.sh]
#
# WHY (issue #739, field run on a Windows-made repo): a CRLF line `/.mpr-snapshots/\r` was missed by
# the newline-delimited match, so the 3-line block was appended again with LF endings (duplicate
# entry, mixed endings). The CRLF input below is the issue's own capture:
#   printf 'node_modules/\r\n/.mpr-snapshots/\r\n' > .gitignore
# The producer is the real snapshot-mpr.sh run in a throwaway git project, never a stub.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/snapshot-mpr.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
echo "== subject: $SUBJECT"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/snapgi.XXXXXX")" || exit 2
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

# $1 = case name, $2 = .gitignore content as a printf format. Prints the project dir.
mkproj() {
  local P="$WORK/$1"
  mkdir -p "$P/bin" "$P/mprcontents/aa"
  cp "$TOOLKIT/project-bin/_common.sh" "$P/bin/"
  cp "$SUBJECT" "$P/bin/snapshot-mpr.sh"
  printf 'index v2\n' > "$P/App.mpr"
  printf 'unit\n' > "$P/mprcontents/aa/one.mxunit"
  ( cd "$P" && git init -q . 2>/dev/null )
  printf "$2" > "$P/.gitignore"
  echo "$P"
}
run() { ( cd "$1" && PROJECT_ROOT="$1" bash ./bin/snapshot-mpr.sh 2>&1 >/dev/null ); }
count() { grep -c "^/\.mpr-snapshots/$(printf '\r')\{0,1\}\$" "$1/.gitignore"; }
lf_lines() { tr -d '\r' < "$1/.gitignore" | wc -l | tr -d ' '; }   # all lines
crlf_lines() { grep -c "$(printf '\r')\$" "$1/.gitignore"; }

echo "-- CRLF file, entry already present (the issue's capture): nothing changes"
P="$(mkproj crlf-present 'node_modules/\r\n/.mpr-snapshots/\r\n')"
cp "$P/.gitignore" "$WORK/before"
out="$(run "$P")"; run "$P" >/dev/null
cmp -s "$WORK/before" "$P/.gitignore" && ok ".gitignore byte-identical after two runs" || bad ".gitignore changed: $(od -c "$P/.gitignore" | head -5)"
case "$out" in *"added /.mpr-snapshots/"*) bad "claimed to add an entry that was present" ;; *) ok "no 'added' message" ;; esac

echo "-- CRLF file, entry missing, trailing newline: appended once, in CRLF"
P="$(mkproj crlf-missing 'node_modules/\r\n')"
out="$(run "$P")"; run "$P" >/dev/null
case "$out" in *"added /.mpr-snapshots/"*) ok "added message on first run" ;; *) bad "no added message: $out" ;; esac
[ "$(count "$P")" = 1 ] && ok "entry present exactly once after two runs" || bad "entry count $(count "$P")"
[ "$(crlf_lines "$P")" = "$(lf_lines "$P")" ] && ok "every line CRLF (no bare LF)" || bad "mixed endings: $(crlf_lines "$P") CRLF of $(lf_lines "$P") lines"

echo "-- CRLF file, entry missing, no trailing newline: separator is CRLF too"
P="$(mkproj crlf-nonl 'node_modules/\r\nbuild/')"
run "$P" >/dev/null
[ "$(count "$P")" = 1 ] && ok "entry present once" || bad "entry count $(count "$P")"
[ "$(crlf_lines "$P")" = "$(lf_lines "$P")" ] && ok "every line CRLF (no bare LF)" || bad "mixed endings"

echo "-- LF file: unchanged behaviour"
P="$(mkproj lf-present 'node_modules/\n/.mpr-snapshots/\n')"
cp "$P/.gitignore" "$WORK/before"; run "$P" >/dev/null
cmp -s "$WORK/before" "$P/.gitignore" && ok "LF file with entry untouched" || bad "LF file with entry changed"
P="$(mkproj lf-missing 'node_modules/\n')"
run "$P" >/dev/null; run "$P" >/dev/null
[ "$(count "$P")" = 1 ] && ok "LF file: entry appended once" || bad "entry count $(count "$P")"
[ "$(crlf_lines "$P")" = 0 ] && ok "LF file: no CR introduced" || bad "CR introduced into LF file"

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
