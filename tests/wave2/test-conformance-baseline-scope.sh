#!/usr/bin/env bash
# Usage: bash test-conformance-baseline-scope.sh [path-to-conformance-check.sh]
#
# Fixture for project-bin/conformance-check.sh's baseline — which rows it guards, and which rows
# a `--module` rewrite may touch.
#
# The defects (card-disbursement requirements-driven build, 2026-09-26):
#   (a) The baseline is written once, by the first run. A module built afterwards has no baseline
#       rows, its rows were compared with "" and could never regress — silently, forever. That
#       project's committed baseline held 1 of its 4 modules (127 of 246 rows).
#   (b) `--update-baseline --module X` wrote X's rows over the WHOLE file, dropping every other
#       module's rows — a scoped measurement doing an unscoped write.
# Cases 2-3 are (a), cases 4-5 are (b), case 6 guards the unscoped rewrite.
#
# The ledgers and the mxcli stub are SYNTHETIC. That is deliberate and allowed: the field-proof
# rule's "golden input is captured" governs parsers of tool output, and nothing below exercises
# the DESCRIBE-output parser — the stub answers the two shapes it already classifies (text + rc 0
# = PRESENT, "Error: … not found" + rc 1 = ABSENT) and the assertions are about the baseline file.
# The field run that motivated it is cited in CHANGELOG.md.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-bin/conformance-check.sh"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"
[ -f "$(dirname "$SUT")/_common.sh" ] || { echo "FAIL — _common.sh not beside $SUT"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/conf-baseline.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
P="$WORK/proj"
mkdir -p "$P/architecture/modules/Orders" "$P/architecture/modules/Billing"
: > "$P/Shop.mpr"
# PRESENT lists the qualified names the stub model holds; edit it to break or restore one.
printf 'Orders.Order\nOrders.ACT_Order_Save\nBilling.Invoice\nBilling.ACT_Invoice_Send\n' > "$P/PRESENT"
cat > "$P/mxcli" <<'EOF'
#!/usr/bin/env bash
cmd=""; while [ $# -gt 0 ]; do [ "$1" = -c ] && cmd="$2"; shift; done
name="${cmd##* }"
if grep -qx "$name" "$(dirname "$0")/PRESENT"; then echo "-- $name"; echo "create $name;"; exit 0; fi
echo "Error: $name not found"; exit 1
EOF
chmod +x "$P/mxcli"
ledger() {  # ledger <Module> <entity> <microflow>
  cat > "$P/architecture/modules/$1/coverage-ledger.md" <<EOF
| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| \`/domainEntities/0\` | entity | $2 | 1.1 | exec.sh | \`DESCRIBE ENTITY $1.$2\` | built |
| \`/microflows/0\` | microflow | $3 | 1.2 | exec.sh | \`DESCRIBE MICROFLOW $1.$3\` | built |
EOF
}
run() { ( cd "$P" && PROJECT_ROOT="$P" bash "$SUT" --quiet "$@" ) > "$WORK/out" 2>&1; echo $?; }
rows() { awk -F'\t' -v m="$1" '$1==m' "$P/docs/conformance/baseline.tsv" 2>/dev/null | grep -c . ; }
out() { tr '\n' ' ' < "$WORK/out" | cut -c1-300; }

# --- 1. first run writes the baseline (unchanged behaviour) ---------------------------------
ledger Orders Order ACT_Order_Save
rc="$(run)"
[ "$rc" = 0 ] && [ "$(rows Orders)" = 2 ] && ok "first run baselines Orders (2 rows)" \
  || bad "first run did not write a 2-row Orders baseline (rc=$rc)" "$(out)"

# --- 2. a module built after the baseline is baselined on first sight, and said so -----------
ledger Billing Invoice ACT_Invoice_Send
rc="$(run)"
[ "$rc" = 0 ] && [ "$(rows Billing)" = 2 ] && ok "Billing's rows are baselined on first sight (2 rows added)" \
  || bad "Billing's rows never reached the baseline (the 2026-09-26 unguarded module)" "rc=$rc rows=$(rows Billing)"
grep -q "newly baselined *2" "$WORK/out" && ok "the run says how many rows it newly baselined" \
  || bad "no 'newly baselined 2' line" "$(out)"

# --- 3. ...so a later break in Billing IS a regression ----------------------------------------
sed -i.bak '/^Billing.Invoice$/d' "$P/PRESENT"
rc="$(run)"
[ "$rc" = 1 ] && grep -q "Billing.*was OK, now STALE" "$WORK/out" \
  && ok "Billing.Invoice going absent fails the run as a regression" \
  || bad "a module built after the baseline cannot regress" "rc=$rc $(out)"
mv "$P/PRESENT.bak" "$P/PRESENT"

# --- 4. --update-baseline --module rewrites only that module's rows ---------------------------
rc="$(run --module Billing --update-baseline)"
[ "$rc" = 0 ] && [ "$(rows Orders)" = 2 ] && [ "$(rows Billing)" = 2 ] \
  && ok "--module Billing --update-baseline keeps Orders' 2 rows" \
  || bad "a --module rewrite dropped other modules' rows (the 2026-09-26 clobber)" "rc=$rc Orders=$(rows Orders) Billing=$(rows Billing)"

# --- 5. ...so Orders is still guarded after it ------------------------------------------------
sed -i.bak '/^Orders.ACT_Order_Save$/d' "$P/PRESENT"
rc="$(run)"
[ "$rc" = 1 ] && grep -q "Orders.*was OK, now STALE" "$WORK/out" \
  && ok "Orders.ACT_Order_Save going absent still fails the run after Billing's rewrite" \
  || bad "Orders lost its regression guard" "rc=$rc $(out)"
mv "$P/PRESENT.bak" "$P/PRESENT"

# --- 6. an unscoped --update-baseline still rewrites everything --------------------------------
printf 'Orders\t`/stale`\tOK\n' >> "$P/docs/conformance/baseline.tsv"
rc="$(run --update-baseline)"
[ "$rc" = 0 ] && [ "$(wc -l < "$P/docs/conformance/baseline.tsv" | tr -d ' ')" = 4 ] \
  && ok "unscoped --update-baseline rewrites the whole file (a retired row is dropped)" \
  || bad "unscoped rewrite changed behaviour" "rc=$rc lines=$(wc -l < "$P/docs/conformance/baseline.tsv")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
