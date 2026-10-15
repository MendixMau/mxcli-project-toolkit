#!/usr/bin/env bash
# test-rehost-list-modules.sh — fixture for the own-module parse of the Rehost extractor
# (pipelines/mendix-mpr/lib/own-modules.awk) and the refusals rehost-extract.sh makes before it
# touches anything.
#
#   T1  mxcli v0.26.0 capture (WARNING + "Connected to:" lead lines): own = Billing, Orders
#   T2  mxcli v0.25.0 capture: same result
#   T3  field-service template capture (table starts on line 1, 59 modules): 42 own, none of
#       them System or a Marketplace module. The table starts on line 1 here, so a parse that
#       skips a fixed number of lines would drop a data row (the old `NR>3` did).
#   T4  rehost-extract.sh refuses source == target (same file through a symlink), exit 2,
#       before creating the out-dir
#   T5  rehost-extract.sh with a capture holding no own module: exit 2 with a message, not an
#       unbound-variable crash (bash 3.2 `set -u` on an empty array)
#   T6  the sibling export-module-mpk.py refuses an unknown `--` option (a typo such as
#       `--scrub-constants`) with exit 2 and writes nothing; the three known flags pass that check
#       (the run then stops at the missing source, exit 3)
#
# Golden input: tests/wave2/fixtures/rehost-list-modules/ (verbatim; see CAPTURE.txt there).
# Usage: bash tests/wave2/test-rehost-list-modules.sh [path to the pipeline's rehost extractor]
#   (default: pipelines/mendix-mpr/ in this toolkit — run-all.sh resolves subjects under bin/,
#   project-bin/ and skills/ only, so this fixture finds its own when given none)
# Keep bash-3.2 compatible.

set -uo pipefail
SUBJ="${1:-$(cd "$(dirname "$0")/../.." && pwd)/pipelines/mendix-mpr/rehost-extract.sh}"
LIB="$(cd "$(dirname "$SUBJ")" && pwd)/lib/own-modules.awk"
FX="$(cd "$(dirname "$0")" && pwd)/fixtures/rehost-list-modules"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
own()  { awk -F'|' -f "$LIB" "$1" | tr '\n' ' ' | sed 's/ $//'; }

r=$(own "$FX/list-modules-v0.26.0.txt"); [ "$r" = "Billing Orders" ] && ok "T1 v0.26.0: $r" || bad "T1 v0.26.0: got '$r'"
r=$(own "$FX/list-modules-v0.25.0.txt"); [ "$r" = "Billing Orders" ] && ok "T2 v0.25.0: $r" || bad "T2 v0.25.0: got '$r'"

n=$(awk -F'|' -f "$LIB" "$FX/field-service-template-9.24.2.txt" | wc -l | tr -d ' ')
leak=$(awk -F'|' -f "$LIB" "$FX/field-service-template-9.24.2.txt" | while read -r m; do
  grep -E "^\| $m +\| Marketplace" "$FX/field-service-template-9.24.2.txt" >/dev/null && echo "$m"
  [ "$m" = System ] && echo System; done)
if [ "$n" = 42 ] && [ -z "$leak" ]; then ok "T3 field-service template: 42 own, no Marketplace/System"
else bad "T3 field-service template: $n own, leaked: $leak"; fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rehost-lm.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$TMP/mxcli"; chmod +x "$TMP/mxcli"
: > "$TMP/app.mpr"; ln -s app.mpr "$TMP/link.mpr"
MXCLI="$TMP/mxcli" bash "$SUBJ" "$TMP/app.mpr" "$TMP/link.mpr" "$TMP/out4" >"$TMP/t4.log" 2>&1; rc=$?
if [ "$rc" = 2 ] && [ ! -d "$TMP/out4" ] && grep -q 'same file' "$TMP/t4.log"; then ok "T4 source == target refused, exit 2, nothing written"
else bad "T4 rc=$rc out-dir=$([ -d "$TMP/out4" ] && echo created || echo absent): $(head -2 "$TMP/t4.log")"; fi

# a stub mxcli whose `list modules` lists only Marketplace + System (the v0.26.0 capture minus own rows)
grep -v -E '^\| (Billing|Orders) ' "$FX/list-modules-v0.26.0.txt" > "$TMP/none.txt"
printf '#!/bin/sh\ncase "$*" in *"list modules"*) cat "%s";; *) echo "[]";; esac\n' "$TMP/none.txt" > "$TMP/mxcli"
: > "$TMP/tgt.mpr"
MXCLI="$TMP/mxcli" bash "$SUBJ" "$TMP/app.mpr" "$TMP/tgt.mpr" "$TMP/out5" >"$TMP/t5.log" 2>&1; rc=$?
if [ "$rc" = 2 ] && grep -q 'no own modules' "$TMP/t5.log" && ! grep -q 'unbound' "$TMP/t5.log"; then ok "T5 no own modules: exit 2 with a message"
else bad "T5 rc=$rc: $(tail -2 "$TMP/t5.log")"; fi

EXP="$(cd "$(dirname "$SUBJ")" && pwd)/export-module-mpk.py"
. "$(cd "$(dirname "$0")/../.." && pwd)/bin/lib/portable.sh"
require_py
"$PY" -I "$EXP" "$TMP/none.mpr" M "$TMP/t6.mpk" --scrub-constants >"$TMP/t6.log" 2>&1; rc=$?
"$PY" -I "$EXP" "$TMP/none.mpr" M "$TMP/t6b.mpk" --no-widgets --scrub-constant-defaults --json >"$TMP/t6b.log" 2>&1; rc2=$?
if [ "$rc" = 2 ] && grep -q 'unknown option(s): --scrub-constants' "$TMP/t6.log" && [ ! -e "$TMP/t6.mpk" ] && [ "$rc2" = 3 ]; then
  ok "T6 exporter: unknown flag refused (exit 2, nothing written); known flags accepted"
else bad "T6 rc=$rc rc2=$rc2: $(head -1 "$TMP/t6.log") / $(head -1 "$TMP/t6b.log")"; fi

echo "test-rehost-list-modules.sh: $PASS ok, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
