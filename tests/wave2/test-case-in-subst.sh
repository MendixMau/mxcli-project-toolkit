#!/usr/bin/env bash
# test-case-in-subst.sh — a case pattern without a leading "(" inside $( ... ) is flagged (#763).
#
# Usage: bash tests/wave2/test-case-in-subst.sh bin/check-portability.sh
#
# bash 3.2 (macOS /bin/bash) reads the unmatched ")" of a case pattern as the end of an enclosing
# $( ... ) command substitution. bash -n does not see it (3.2 parses the substitution only when it
# runs), and this runner has no bash 3.2, so the proof is static: the portability check must
# flag the shape. #552 (script-owners.sh) and #763 (marketplace-check.sh _mkt_locate) shipped it.
#
#   T1  the reporter's minimal repro from #763, verbatim: flagged, rc 1, at the pattern's line
#   T2  one-line, multi-line (one bare pattern after a parenthesised one), and nested
#       $( ... $(case ...) ... ): 3 of 3 flagged, at the right lines
#   T3  not flagged: the (pat) form inside $( ), a case outside any $( ) (even with $( ) in its
#       subject and body), a commented-out line, a '...' string, a heredoc body, $(( << )),
#       and a `# portability-ok:` line
#   T4  the shipped bin/lib/marketplace-check.sh (same toolkit as the SUT): 0 hits (passes
#       trivially on a check-portability.sh without the rule; T1/T2 are the ones that bite)
#
# GOLDEN INPUT: T1 is copied from the issue as reported on macOS /bin/bash 3.2.57, and T4 is the
# real file the issue was filed against.
set -uo pipefail
SUT="${1:?usage: test-case-in-subst.sh /path/to/bin/check-portability.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
SRC="$(cd "$(dirname "$SUT")/.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/caseinsubst.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }
RULE='case pattern without a leading ( inside'
hits() { printf '%s\n' "$1" | grep -F "$RULE" | sed 's/^[^:]*:\([0-9]*\):.*/\1/' | tr '\n' ' '; }

echo "== check-portability.sh: case pattern inside \$(...) (#763) =="
mkdir -p "$W/t1" "$W/t2" "$W/t3" "$W/t4"

cat > "$W/t1/repro.sh" <<'X'
#!/usr/bin/env bash
f() { out="$( m="x refusing to guess"; false || {
        case "$m" in *"refusing to guess"*) printf 'A\n' ;; esac; }
        exit 0 )"; echo "OUT=[$out]"; }
f
X
out="$(bash "$SUT" "$W/t1" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(hits "$out")" = "3 " ]; then ok "T1 reporter's repro flagged at line 3"
else bad "T1 want rc 1, hit at line 3; got rc $rc, lines [$(hits "$out")]" "$out"; fi

cat > "$W/t2/shapes.sh" <<'X'
#!/usr/bin/env bash
y="$(case "$a" in b) echo 1 ;; esac)"
z="$(
  case "$a" in
    (a) echo a ;;
    b|c) echo b ;;
  esac
)"
w="$(echo "$(case $q in x) :;; esac)")"
X
out="$(bash "$SUT" "$W/t2" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(hits "$out")" = "2 6 9 " ]; then ok "T2 one-line, multi-line and nested: 3 of 3 flagged (lines 2 6 9)"
else bad "T2 want rc 1, lines [2 6 9 ]; got rc $rc, lines [$(hits "$out")]" "$out"; fi

cat > "$W/t3/good.sh" <<'X'
#!/usr/bin/env bash
out="$( case "$m" in (*"refusing to guess"*) printf 'A\n' ;; esac; exit 0 )"
case "$(basename "$1")" in a) x="$(echo a)" ;; *) : ;; esac
case "$x" in
  a) y="$(case "$x" in (a) echo ;; esac)" ;;
esac
# out="$( case x in a) ;; esac )"
s='$( case x in a) ;; esac )'
cat <<'EOF'
v="$( case x in a) ;; esac )"
EOF
n=$(( (a + 1) << 2 ))
u="$(case "$x" in a) echo ;; esac)" # portability-ok: fixture opt-out
X
out="$(bash "$SUT" "$W/t3" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "T3 (pat) form, case outside \$( ), comment, '...', heredoc, \$(( << )), portability-ok: 0 hits"
else bad "T3 want rc 0, got $rc, lines [$(hits "$out")]" "$out"; fi

cp "$SRC/bin/lib/marketplace-check.sh" "$W/t4/"
out="$(bash "$SUT" "$W/t4" 2>&1)"
if [ -z "$(hits "$out")" ]; then ok "T4 shipped marketplace-check.sh: 0 hits"
else bad "T4 shipped marketplace-check.sh still has a bare pattern in \$( ) at [$(hits "$out")]" "$out"; fi

echo "-- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
