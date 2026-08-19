#!/usr/bin/env bash
# test-lint-delivery.sh — fixture tests for bin/lib/install-lint-rules.sh.
#
# Same rule as tests/run-tests.sh: a guard is not fixed until a fixture proves it FAILS on the
# case it exists to catch. The cases that matter most here are the destructive ones — 5, 7, 8,
# 9 and 12 all assert that local work SURVIVES. A copy path that installs correctly but eats a
# project's tuned rule is a worse outcome than no copy path at all, because it does it to
# every project at once and only shows up the next time someone reads the rule.
#
# Case 3 is the reason this file exists: `mxcli init` silently reverts a rule to stock, and a
# stock ARCH002/ARCH003 reports a clean pass while inspecting nothing.
#
# Fixtures are generated at runtime, never committed. A forged STOCK-HASHES.txt is used so the
# stock-detection branch is exercised honestly rather than mocked away.
#
# Keep bash-3.2 compatible: stock macOS `env bash` is 3.2.57.
#
# Usage: tests/test-lint-delivery.sh          Exit 0 only if every assertion holds.

set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$TK/bin/lib/portable.sh"

W=$(mktemp -d "${TMPDIR:-/tmp}/lintdeliv.XXXXXX")
trap 'rm -rf "$W"' EXIT
FAILED=0
ok(){ printf '  PASS %s\n' "$1"; }
no(){ printf '  FAIL %s\n' "$1"; FAILED=1; }

# A throwaway toolkit copy, so the forged stock hash below cannot touch the real one.
mkdir -p "$W/tk/bin/lib" "$W/tk/lint-rules"
cp "$TK"/bin/lib/install-manifest.sh "$TK"/bin/lib/install-lint-rules.sh \
   "$TK"/bin/lib/portable.sh "$W/tk/bin/lib/"
cp "$TK"/lint-rules/*.star "$TK"/lint-rules/README.md "$W/tk/lint-rules/"
# Forge "stock" ARCH002 = the real rule with the known-broken casing restored.
sed 's/!= "Persistent"/!= "PERSISTENT"/' "$TK/lint-rules/data_change_microflows.star" \
  > "$W/stock-arch002.star"
printf 'data_change_microflows.star  %s  vFIXTURE\n' "$(portable_md5 "$W/stock-arch002.star")" \
  > "$W/tk/lint-rules/STOCK-HASHES.txt"

P="$W/proj"; mkdir -p "$P/.claude"; echo "# PROJECT" > "$P/PROJECT.md"
. "$W/tk/bin/lib/install-manifest.sh" >/dev/null 2>&1
. "$W/tk/bin/lib/install-lint-rules.sh"
R="$P/.claude/lint-rules"
A="$R/data_change_microflows.star"; C="$R/conv020_action_user_feedback.star"
RECEIPT="$P/.claude/.mxtk-lint-receipt"

echo "== 1 fresh install =="
mxtk_install_lint_rules "$W/tk" "$P" 0 "" >/dev/null
{ [ -f "$A" ] && [ -f "$C" ] && [ -f "$RECEIPT" ]; } && ok "rules + receipt written" || no "install"
[ "$(ls "$R" | wc -l | tr -d ' ')" = 4 ] && ok "NOINSTALL list respected (4 files)" || no "leaked: $(ls "$R")"

echo "== 2 re-run is silent and rewrites nothing =="
before=$(portable_md5 "$A"); out=$(mxtk_install_lint_rules "$W/tk" "$P" 0 "")
[ -z "$out" ] && ok "silent" || no "noisy on a no-op"
[ "$(portable_md5 "$A")" = "$before" ] && ok "unchanged" || no "rewrote an identical file"

echo "== 3 mxcli init reverted a rule to stock =="
cp "$W/stock-arch002.star" "$A"
out=$(mxtk_install_lint_rules "$W/tk" "$P" 0 "")
echo "$out" | grep -q "REVERTED TO STOCK" && ok "named the revert" || no "did not identify revert"
cmp -s "$TK/lint-rules/data_change_microflows.star" "$A" && ok "restored" || no "not restored"

echo "== 4 toolkit ships a newer rule; local copy unedited =="
printf '\n# toolkit change\n' >> "$W/tk/lint-rules/entity_business_key.star"
out=$(mxtk_install_lint_rules "$W/tk" "$P" 0 "")
echo "$out" | grep -q "refreshed" && ok "refreshed" || no "a toolkit fix did not propagate"
cmp -s "$W/tk/lint-rules/entity_business_key.star" "$R/entity_business_key.star" \
  && ok "content matches new template" || no "content wrong"

echo "== 5 project hand-edited a managed rule =="
printf '\n# LOCAL TUNING - must survive\n' >> "$A"
out=$(mxtk_install_lint_rules "$W/tk" "$P" 0 "" 2>&1)
grep -q "LOCAL TUNING" "$A" && ok "local edit survived" || no "DESTROYED local work"
echo "$out" | grep -q "LOCALLY MODIFIED" && ok "reported the drift" || no "silent about drift"

echo "== 6 --dry-run writes nothing =="
b1=$(portable_md5 "$A"); b2=$(portable_md5 "$RECEIPT")
mxtk_install_lint_rules "$W/tk" "$P" 1 "all" >/dev/null 2>&1
{ [ "$(portable_md5 "$A")" = "$b1" ] && [ "$(portable_md5 "$RECEIPT")" = "$b2" ]; } \
  && ok "nothing written" || no "dry-run WROTE"
ls "$R" | grep -q "local-" && no "dry-run left a backup" || ok "no stray backup"

echo "== 7 --upgrade-lint-rules backs up, then replaces =="
mxtk_install_lint_rules "$W/tk" "$P" 0 "data_change_microflows.star" >/dev/null
cmp -s "$TK/lint-rules/data_change_microflows.star" "$A" && ok "upgraded" || no "not upgraded"
ls "$R"/*.local-* >/dev/null 2>&1 && grep -q "LOCAL TUNING" "$R"/*.local-* \
  && ok "backup holds the local work" || no "backup missing or empty"
rm -f "$R"/*.local-*

echo "== 8 configured conv020 is left alone, silently =="
sed 's/^PROJECT_MODULES = ()/PROJECT_MODULES = ("MyModule",)/' "$C" > "$C.t" && mv "$C.t" "$C"
out=$(mxtk_install_lint_rules "$W/tk" "$P" 0 "" 2>&1)
[ -z "$out" ] && ok "silent" || no "noisy about the expected state"
grep -q 'PROJECT_MODULES = ("MyModule",)' "$C" && ok "config survived" || no "CONFIG WIPED"

echo "== 9 conv020 template moves while the project is configured =="
printf '\n# template moved\n' >> "$W/tk/lint-rules/conv020_action_user_feedback.star"
out=$(mxtk_install_lint_rules "$W/tk" "$P" 0 "" 2>&1)
echo "$out" | grep -q "template has since changed" && ok "flagged the move" || no "silent on move"
grep -q 'PROJECT_MODULES = ("MyModule",)' "$C" && ok "config STILL survived" || no "CONFIG WIPED"

echo "== 10 caller forgot the manifest: the lib sources it itself =="
P4="$W/proj4"; mkdir -p "$P4/.claude"; echo x > "$P4/PROJECT.md"
bash -c "set -u; . '$W/tk/bin/lib/install-lint-rules.sh'; \
         mxtk_install_lint_rules '$W/tk' '$P4' 0 ''" >/dev/null 2>&1
[ "$(ls "$P4/.claude/lint-rules" 2>/dev/null | wc -l | tr -d ' ')" = 4 ] \
  && ok "rules landed anyway" || no "silent no-op"

echo "== 11 manifest genuinely unavailable: warn, never pretend success =="
W2=$(mktemp -d "${TMPDIR:-/tmp}/nomani.XXXXXX")
mkdir -p "$W2/bin/lib" "$W2/lint-rules"
cp "$W/tk/bin/lib/install-lint-rules.sh" "$W/tk/bin/lib/portable.sh" "$W2/bin/lib/"
cp "$W/tk"/lint-rules/*.star "$W2/lint-rules/"
P5="$W/proj5"; mkdir -p "$P5/.claude"; echo x > "$P5/PROJECT.md"
out=$(bash -c "set -u; . '$W2/bin/lib/install-lint-rules.sh'; \
               mxtk_install_lint_rules '$W2' '$P5' 0 ''" 2>&1)
echo "$out" | grep -q "no lint rules were installed" && ok "warned loudly" || no "silent"
rm -rf "$W2"

echo "== 12 early adopter: our rule applied by hand, no provenance header =="
P2="$W/proj2"; mkdir -p "$P2/.claude/lint-rules"; echo x > "$P2/PROJECT.md"
for f in data_change_microflows entity_business_key; do
  sed '1,/^# --- end mxtk-lint-rule header ---$/d' "$TK/lint-rules/$f.star" \
    > "$P2/.claude/lint-rules/$f.star"
done
out=$(mxtk_install_lint_rules "$TK" "$P2" 0 "" 2>&1)
echo "$out" | grep -q "LOCALLY MODIFIED" && no "false drift warning on an identical rule" \
  || ok "no false drift warning"
cmp -s "$TK/lint-rules/entity_business_key.star" "$P2/.claude/lint-rules/entity_business_key.star" \
  && ok "headered in place" || no "not refreshed"

echo "== 13 headerless AND body-edited is NOT silently refreshed =="
P3="$W/proj3"; mkdir -p "$P3/.claude/lint-rules"; echo x > "$P3/PROJECT.md"
sed '1,/^# --- end mxtk-lint-rule header ---$/d' "$TK/lint-rules/entity_business_key.star" \
  > "$P3/.claude/lint-rules/entity_business_key.star"
printf '\n# REAL LOCAL EDIT\n' >> "$P3/.claude/lint-rules/entity_business_key.star"
out=$(mxtk_install_lint_rules "$TK" "$P3" 0 "" 2>&1)
grep -q "REAL LOCAL EDIT" "$P3/.claude/lint-rules/entity_business_key.star" \
  && ok "body edit survived" || no "DESTROYED a body edit"
echo "$out" | grep -q "LOCALLY MODIFIED" && ok "reported it" || no "silent"

echo "== 14 the rules are wired to a caller at all =="
# The tripwire in install-manifest.sh. Two lines in init/sync are all that connect these rules
# to a project, and a concurrent rewrite of either file drops them without a trace.
bash -c ". '$TK/bin/lib/install-manifest.sh'" 2>&1 | grep -q "NOT WIRED" \
  && no "install-lint-rules.sh is not called by init-project.sh / sync-project.sh" \
  || ok "wired into both callers"

echo
[ "$FAILED" = 0 ] && { echo "ALL GREEN"; exit 0; } || { echo "FAILURES ABOVE"; exit 1; }
