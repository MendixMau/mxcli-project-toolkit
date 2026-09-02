#!/usr/bin/env bash
# retest-bug22-settings-writes.sh — does `alter project security level` (and the two sibling
# settings statements) still corrupt the Settings unit?
#
# BUG-22 / preflight STOP rule 2 said yes: "deterministic BSON stream-desync … confirmed corrupt
# on every retry", found on mxcli v0.13.0 / Mendix 11.12.0 Beta. The rule sent every project to
# the Studio Pro GUI for a statement mxcli implements.
#
# The bug report names its own detector: "On the next SP open OR `mx check`, the project fails to
# load with AggregateException / Expected '$ID'". `mx check` is runnable headlessly, so the rule
# is falsifiable without Studio Pro — this script runs exactly that test, 18 times.
#
# Usage:  tests/retests/retest-bug22-settings-writes.sh /path/to/mxcli [/path/to/content-model.mpr]
#         The second argument is optional and makes the test much stronger: an empty model has
#         almost no Settings unit to desync.
#
# Exit 0 the rule does not reproduce · 1 it reproduces (keep the STOP) · 2 could not run.
set -uo pipefail
MXCLI="${1:-./mxcli}"
CONTENT_MPR="${2:-}"
VER="${MX_VERSION:-11.12.1}"
MX="$HOME/.mxcli/mxbuild/$VER/modeler/mx"
MXBUILD="$HOME/.mxcli/mxbuild/$VER/modeler/mxbuild"

[ -x "$MXCLI" ] || { echo "retest: no mxcli at $MXCLI"; exit 2; }
[ -x "$MX" ]    || { echo "retest: no mx at $MX — run 'mxcli setup mxbuild' first"; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
( cd "$WORK" && "$(cd "$(dirname "$MXCLI")" && pwd)/$(basename "$MXCLI")" new RetestBug22 --version "$VER" --theme none ) >/dev/null 2>&1
MPR="$WORK/RetestBug22/RetestBug22.mpr"
[ -f "$MPR" ] || { echo "retest: could not create a scratch app"; exit 2; }

FAILS=0
chk() { # $1 = model; echoes a one-word verdict
  local out; out="$("$MX" check "$1" 2>&1)"
  case "$out" in
    *"AggregateException"*|*"Expected '\$ID'"*|*"Unexpected"*) echo "CORRUPT" ;;
    *"contains: "*"errors"*) echo "$(printf '%s' "$out" | grep -oE 'contains: [0-9]+ errors' | tail -1)" ;;
    *) echo "UNKNOWN" ;;
  esac
}
run() { printf '%s\n' "$2" > "$WORK/s.mdl"; "$MXCLI" exec "$WORK/s.mdl" -p "$1" >/dev/null 2>&1; }
step() { # $1 model, $2 label, $3 statement
  run "$1" "$3"; local v; v="$(chk "$1")"
  printf '  %-46s %s\n' "$2" "$v"
  case "$v" in "contains: 0 errors") ;; *) FAILS=$((FAILS+1)) ;; esac
}

echo "── the three statements STOP rule 2 forbids, on an empty model ──"
printf '  %-46s %s\n' "baseline" "$(chk "$MPR")"
for lvl in PROTOTYPE PRODUCTION OFF PRODUCTION PROTOTYPE OFF; do
  step "$MPR" "alter project security level $lvl" "alter project security level $lvl;"
done
step "$MPR" "alter settings configuration" \
     "alter settings configuration 'Default' DatabaseType = 'POSTGRESQL', DatabaseUrl = 'localhost:5432/x';"
step "$MPR" "alter settings model" "alter settings model AfterStartupMicroflow = '';"

echo "── does the value round-trip? (a clean check over a lost write is not a pass) ──"
run "$MPR" "alter project security level PRODUCTION;"
LVL="$("$MXCLI" -p "$MPR" -c "SHOW PROJECT SECURITY" 2>/dev/null | grep -oiE 'Security Level: *[A-Za-z]+' | head -1)"
printf '  %-46s %s\n' "SHOW PROJECT SECURITY" "${LVL:-<not reported>}"
case "$LVL" in *[Pp]roduction*) ;; *) echo "  round-trip FAILED"; FAILS=$((FAILS+1)) ;; esac

if [ -n "$CONTENT_MPR" ] && [ -f "$CONTENT_MPR" ]; then
  echo "── 10 consecutive toggles on a model that HAS content ──"
  cp -r "$(dirname "$CONTENT_MPR")" "$WORK/content" 2>/dev/null || true
  CM="$WORK/content/$(basename "$CONTENT_MPR")"
  if [ -f "$CM" ]; then
    n=0
    for i in $(seq 1 10); do
      lvl=$([ $((i % 2)) -eq 0 ] && echo PRODUCTION || echo PROTOTYPE)
      run "$CM" "alter project security level $lvl;"
      [ "$(chk "$CM")" = "contains: 0 errors" ] && n=$((n+1))
    done
    printf '  %-46s %s\n' "clean checks" "$n/10"
    [ "$n" -eq 10 ] || FAILS=$((FAILS+1))
    if [ -x "$MXBUILD" ]; then
      JE="$(command -v java || true)"
      if [ -n "$JE" ]; then
        # Resolve the java symlink without `readlink -f` (GNU-only; macOS has no -f).
        JR="$JE"; _hops=0
        while [ -L "$JR" ] && [ "$_hops" -lt 16 ]; do
          _t="$(ls -ld "$JR" | sed 's/.* -> //')"
          case "$_t" in /*) JR="$_t" ;; *) JR="$(cd "$(dirname "$JR")" && pwd)/$_t" ;; esac
          _hops=$((_hops+1))
        done
        JR="$(cd "$(dirname "$JR")" && pwd)/$(basename "$JR")"
        JH="$(dirname "$(dirname "$JR")")"
        if "$MXBUILD" --java-home="$JH" --java-exe-path="$JE" --target=deploy "$CM" 2>&1 | grep -q "BUILD SUCCEEDED"; then
          printf '  %-46s %s\n' "full deploy build afterwards" "BUILD SUCCEEDED"
        else
          printf '  %-46s %s\n' "full deploy build afterwards" "FAILED"; FAILS=$((FAILS+1))
        fi
      fi
    fi
  fi
else
  echo "── no content model given; empty-model result only (weaker — pass one as \$2) ──"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "BUG-22 DOES NOT REPRODUCE on mxcli $("$MXCLI" --version 2>/dev/null | head -1), Mendix $VER."
  echo "The rule's own detector (mx check) is clean on every execution."
else
  echo "BUG-22 REPRODUCES ($FAILS failing check(s)) — keep preflight STOP rule 2."
fi
exit $([ "$FAILS" -eq 0 ] && echo 0 || echo 1)
