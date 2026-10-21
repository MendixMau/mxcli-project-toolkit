#!/usr/bin/env bash
# test-sed-tab-bracket.sh — `[ \t]` in a sed/grep bracket is not a tab off GNU sed (#468).
#
# Usage: bash tests/wave2/test-sed-tab-bracket.sh bin/lib/entry-mode.sh
#
# BSD/macOS sed reads `[ \t]` as "space, backslash or t" (only GNU sed expands \t there), so
# every trim built on it also ate a leading or trailing letter t and left real tabs alone.
# context-pack.sh's own case is pinned in test-context-pack.sh (its captured golden brief has
# Sales.Product and Sales.ACT_ApprovalStep_Reject); this fixture covers the two libraries
# that carried the same trim, and the lint that keeps it out.
#
# On GNU sed the BSD reading is reproduced through a `sed --posix` shim on PATH (verified to
# turn "Product" into "Produc" with the old pattern before anything is asserted); on a machine
# whose sed is already BSD the shim is not needed and the functions run as they are.
#
#   T1  closeout.sh _co_trim keeps a trailing/leading t ("bulk import", "**test harness**")
#       and still trims a real tab; _co_stage_of reads "Stage<TAB>3" as 3
#   T2  entry-mode.sh entry_mode_token reads a tab-separated answer ("answered:<TAB>migration",
#       "<TAB>greenfield"), which the old trim left untouched and the first-word cut then emptied
#   T3  bin/check-portability.sh (same toolkit) flags `sed 's/[ \t]*$//'` and
#       `grep -c '^##[ \t]'`, passes [[:blank:]], an awk regex and a $'...' real tab
#   T4  ... and flags \t OUTSIDE a bracket in a sed pattern or replacement (#488: the
#       bug-lookup.sh index line and test-routing-tier.sh's demotion), passes ${TAB}, $'...',
#       an escaped \\t in an echo, and awk

set -uo pipefail
SUT="${1:?usage: test-sed-tab-bracket.sh /path/to/bin/lib/entry-mode.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
LIB="$(cd "$(dirname "$SUT")" && pwd)"
TK="$(cd "$LIB/../.." && pwd)"
W="$(mktemp -d "${TMPDIR:-/tmp}/sedtab.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi; }
TAB="$(printf '\t')"

SHIMPATH="$PATH"
if sed --posix -n p </dev/null >/dev/null 2>&1; then
  mkdir -p "$W/bin"
  printf '#!/usr/bin/env bash\nexec "%s" --posix "$@"\n' "$(command -v sed)" > "$W/bin/sed"; chmod +x "$W/bin/sed"
  SHIMPATH="$W/bin:$PATH"
  echo "== GNU sed: running under a sed --posix shim (BSD bracket reading) =="
else
  echo "== sed is not GNU sed: running as-is =="
fi
probe="$(printf 'Product\n' | PATH="$SHIMPATH" sed 's/[ \t]*$//')"   # portability-ok: the #468 defect, run on purpose
if [ "$probe" != "Produc" ]; then
  echo "  SKIP T1-T2: this sed expands \\t in a bracket, the old defect cannot show here"
else
  run() { PATH="$SHIMPATH" bash -c ". '$LIB/closeout.sh'; . '$SUT'; $1"; }
  echo "== T1 closeout.sh =="
  check "T1a trailing t kept"        "$(run "_co_trim '  Decision about bulk import  '")" "Decision about bulk import"
  check "T1b leading t kept"         "$(run "_co_trim '**test harness**'")"              "test harness"
  check "T1c real tab trimmed"       "$(run "_co_trim '${TAB}CONFIRMED${TAB}'")"          "CONFIRMED"
  check "T1d Stage<TAB>3 is stage 3" "$(run "_co_stage_of 'Stage${TAB}3'")"               "3"
  echo "== T2 entry-mode.sh =="
  check "T2a answered:<TAB>migration" "$(run "entry_mode_token 'answered:${TAB}migration'" 2>/dev/null)" "migration"
  check "T2b <TAB>greenfield"         "$(run "entry_mode_token '${TAB}greenfield'" 2>/dev/null)"         "greenfield"
  check "T2c bold value unchanged"    "$(run "entry_mode_token '**requirements-driven**'" 2>/dev/null)"  "requirements-driven"
fi

echo "== T3 check-portability.sh rule =="
mkdir -p "$W/lint/bad" "$W/lint/good"
# Written with @ for the backslash, so this file does not carry the pattern it plants.
tr '@' '\\' > "$W/lint/bad/a.sh" <<'X'
#!/usr/bin/env bash
x="$(printf '%s' "$1" | sed 's/^[ @t]*//; s/[ @t]*$//')"
total=$(grep -c '^##[ @t]' "$2")
X
cat > "$W/lint/good/b.sh" <<'X'
#!/usr/bin/env bash
x="$(printf '%s' "$1" | sed 's/^[[:blank:]]*//')"
y="$(awk '{gsub(/^[ \t]+/, ""); print}' "$2")"
sed -i.bak $'1s/rules=[^\t]*/rules=x/' "$2"
X
out="$(bash "$TK/bin/check-portability.sh" "$W/lint/bad" 2>&1)"; rc=$?
n="$(grep -c 'inside a sed/grep bracket' <<<"$out")"
if [ "$rc" -eq 1 ] && [ "$n" -eq 2 ]; then ok "T3a sed trim and grep -c: 2 of 2 flagged"; else bad "T3a want rc 1 and 2 hits, got rc $rc and $n" "$out"; fi
out="$(bash "$TK/bin/check-portability.sh" "$W/lint/good" 2>&1)"; rc=$?
check "T3b [[:blank:]], awk regex, \$'...' tab: clean" "$rc" "0"

echo "== T4 check-portability.sh: \\t outside a bracket (#488) =="
mkdir -p "$W/lint4/bad" "$W/lint4/good"
# The two shipped sites, verbatim but for @ = backslash; the first also holds ":##", which the
# comment filter used to read as a comment and skip.
tr '@' '\\' > "$W/lint4/bad/c.sh" <<'X'
#!/usr/bin/env bash
grep -n '^## ' "$1" | sed -E 's/^([0-9]+):## /@1@t/' | awk -F'@t' '{ print $2 }'
sed -i.bak 's/^demo@tskills@/demo-tier@.md@t@(.*@)@tbaseline@treference$/demo@tskills@/demo-tier.md@t@1@tondemand@treference/' "$1"
X
tr '@' '\\' > "$W/lint4/good/d.sh" <<'X'
#!/usr/bin/env bash
TAB=$'@t'
sed -i.bak "s/^demo${TAB}skills/x${TAB}y/" "$1"
sed -E $'s/^([0-9]+):## /@@1@t/' "$1"
echo "  SKIP: this sed --posix expands @@t in a bracket"
grep -n '^## ' "$1" | awk '{ t=$0; sub(/^[0-9]+:## /, "", t); sub(/@t.*/, "", t); print t }'
X
out="$(bash "$TK/bin/check-portability.sh" "$W/lint4/bad" 2>&1)"; rc=$?
n="$(grep -c 'in a sed pattern or replacement' <<<"$out")"
if [ "$rc" -eq 1 ] && [ "$n" -eq 2 ]; then ok "T4a replacement \\1\\t and BRE \\t: 2 of 2 flagged"; else bad "T4a want rc 1 and 2 hits, got rc $rc and $n" "$out"; fi
out="$(bash "$TK/bin/check-portability.sh" "$W/lint4/good" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "T4b \${TAB}, \$'...', an escaped \\\\t, awk: clean"; else bad "T4b want rc 0, got rc $rc" "$out"; fi

echo "-- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
