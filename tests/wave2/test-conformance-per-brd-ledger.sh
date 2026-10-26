#!/usr/bin/env bash
# Usage: bash test-conformance-per-brd-ledger.sh [path-to-conformance-check.sh]
#
# Fixture for project-bin/conformance-check.sh on a per-BRD coverage-ledger layout:
#   architecture/modules/<Module>/coverage-ledger.md        an INDEX (no ledger table)
#   architecture/modules/<Module>/coverage-ledger/<BRD>.md  the rows, one file per BRD
#
# The defect (issue #260, field report 2026-10-11, mxcli v0.24.0, four modules): the script read
# only the index and ended every such run in (verbatim from the report — the golden input):
#   FAULT: 0 measurable rows extracted from 1 ledger(s).
# while LEDGER_FILE=<one per-BRD file> measured 128 rows. The fix measures every per-BRD file,
# writes one report per BRD, documents LEDGER_FILE, and names an index as an index.
#
# Cases, each on BOTH layouts (single-tree, and two-tree with the .mpr under app/):
#   1. --module Orders: both per-BRD files measured, one report each, the index not read
#   2. two BRDs reuse the same JSON pointer; the baseline keeps both rows (BRD-keyed)
#   3. a per-BRD row going absent is a regression naming its BRD
#   4. no --module: same rows, the index is not measured as a third ledger
#   5. LEDGER_FILE=<the index> says "index" and names the directory, not "0 measurable rows"
#   6. a module whose index links to another module's per-BRD file: the link is named
#   7. LEDGER_FILE that does not exist FAULTs instead of falling back
#   8. --help documents LEDGER_FILE
#   9. a BRD file name with a space stays one BRD (one report, not two)
#
# The ledgers and the mxcli stub are SYNTHETIC, as in test-conformance-baseline-scope.sh: the
# field-proof rule's captured-golden-input clause governs parsers of tool output, and nothing
# here exercises the DESCRIBE-output parser — the stub answers the two shapes the script already
# classifies (text + rc 0 = PRESENT, "Error: … not found" + rc 1 = ABSENT). The ledger table
# shape is the 7-column one coverage-ledger.md specifies and the existing fixture uses.

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/conf-perbrd.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
GOLDEN='FAULT: 0 measurable rows extracted from 1 ledger(s).'

ledger_rows() {  # ledger_rows <file> <Module> <entity> <microflow>
  cat > "$1" <<EOF
# Coverage ledger — $(basename "$1" .md)

| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| \`/domainEntities/0\` | entity | $3 | 1.1 | exec.sh | \`DESCRIBE ENTITY $2.$3\` | built |
| \`/microflows/0\` | microflow | $4 | 1.2 | exec.sh | \`DESCRIBE MICROFLOW $2.$4\` | built |
EOF
}

setup() {  # setup <single|two> -> sets P
  P="$WORK/$1"
  rm -rf "$P"
  local O="$P/architecture/modules/Orders" B="$P/architecture/modules/Billing"
  mkdir -p "$O/coverage-ledger" "$B"
  if [ "$1" = two ]; then mkdir -p "$P/app"; : > "$P/app/Shop.mpr"; else : > "$P/Shop.mpr"; fi
  printf 'Orders.Order\nOrders.ACT_Order_Save\nOrders.Invoice\nOrders.ACT_Invoice_Send\n' > "$P/PRESENT"
  cat > "$P/mxcli" <<'EOF'
#!/usr/bin/env bash
cmd=""; while [ $# -gt 0 ]; do [ "$1" = -c ] && cmd="$2"; shift; done
name="${cmd##* }"
d="$(dirname "$0")"
if grep -qx "$name" "$d/PRESENT"; then echo "-- $name"; echo "create $name;"; exit 0; fi
echo "Error: $name not found"; exit 1
EOF
  chmod +x "$P/mxcli"
  mkdir -p "$P/architecture/modules/Shipping/coverage-ledger"
  ledger_rows "$P/architecture/modules/Shipping/coverage-ledger/F003 shipping.md" Shipping Parcel ACT_Parcel_Send
  printf 'Shipping.Parcel\nShipping.ACT_Parcel_Send\n' >> "$P/PRESENT"
  ledger_rows "$O/coverage-ledger/F001-orders.md" Orders Order ACT_Order_Save
  ledger_rows "$O/coverage-ledger/F002-invoicing.md" Orders Invoice ACT_Invoice_Send
  cat > "$O/coverage-ledger.md" <<'EOF'
# Orders — coverage ledger index

Rows live one file per BRD:
- [F001](coverage-ledger/F001-orders.md)
- [F002](coverage-ledger/F002-invoicing.md)
EOF
  cat > "$B/coverage-ledger.md" <<'EOF'
# Billing — coverage ledger index

Billing has no ledger of its own; its rows are in [F002](../Orders/coverage-ledger/F002-invoicing.md).
EOF
}
run() { ( cd "$P" && PROJECT_ROOT="$P" bash "$SUT" --quiet "$@" ) > "$WORK/out" 2>&1; echo $?; }
out() { tr '\n' ' ' < "$WORK/out" | cut -c1-400; }
base_rows() { grep -c . "$P/docs/conformance/baseline.tsv" 2>/dev/null || echo 0; }

for layout in single two; do
  echo "== $layout-tree layout"
  setup "$layout"

  # --- 1. --module measures every per-BRD file ------------------------------------------------
  rc="$(run --module Orders)"
  if grep -qF "$GOLDEN" "$WORK/out"; then
    bad "[$layout] per-BRD layout read as the index (issue #260 golden FAULT line)" "rc=$rc $(out)"
  elif [ "$rc" = 0 ] && grep -q "measured 4 " "$WORK/out"; then
    ok "[$layout] --module Orders measures both per-BRD ledgers (4 rows)"
  else
    bad "[$layout] per-BRD rows not measured" "rc=$rc $(out)"
  fi
  n=$(ls "$P"/docs/conformance/report-*-F001-orders.tsv "$P"/docs/conformance/report-*-F002-invoicing.tsv 2>/dev/null | grep -c .)
  [ "$n" = 2 ] && ok "[$layout] one report per BRD (report-<date>-F001-orders.tsv, -F002-invoicing.tsv)" \
    || bad "[$layout] expected 2 per-BRD reports" "$(ls "$P/docs/conformance" 2>/dev/null | tr '\n' ' ')"

  # --- 2. same pointer in two BRDs: two baseline rows, not one ----------------------------------
  [ "$(base_rows)" = 4 ] && grep -q 'F001-orders:`/microflows/0`' "$P/docs/conformance/baseline.tsv" \
    && grep -q 'F002-invoicing:`/microflows/0`' "$P/docs/conformance/baseline.tsv" \
    && ok "[$layout] baseline keys rows by BRD (4 rows, /microflows/0 twice)" \
    || bad "[$layout] baseline collapsed per-BRD rows" "$(cat "$P/docs/conformance/baseline.tsv" 2>/dev/null | tr '\n' ' ')"

  # --- 3. a per-BRD row going absent is a regression --------------------------------------------
  sed -i.bak '/^Orders.ACT_Invoice_Send$/d' "$P/PRESENT"
  rc="$(run --module Orders)"
  [ "$rc" = 1 ] && grep -q 'F002-invoicing:`/microflows/0`.*was OK, now STALE' "$WORK/out" \
    && ok "[$layout] F002's microflow going absent fails the run, naming the BRD" \
    || bad "[$layout] per-BRD regression not reported" "rc=$rc $(out)"
  mv "$P/PRESENT.bak" "$P/PRESENT"

  # --- 4. unscoped run: the index is not a third ledger -----------------------------------------
  rc="$(run)"
  if [ "$rc" = 0 ] && grep -q "measured 6 " "$WORK/out" && ! grep -q "Orders/coverage-ledger.md" "$WORK/out"; then
    ok "[$layout] unscoped run measures the 6 per-BRD rows (3 BRDs); Orders' index is not read"
  else
    bad "[$layout] unscoped run wrong on per-BRD layout" "rc=$rc $(out)"
  fi

  # --- 5. LEDGER_FILE pointed at the index says so ---------------------------------------------
  rc="$( ( cd "$P" && PROJECT_ROOT="$P" LEDGER_FILE=architecture/modules/Orders/coverage-ledger.md \
           bash "$SUT" --quiet --module Orders ) > "$WORK/out" 2>&1; echo $? )"
  [ "$rc" = 2 ] && grep -q "is an index" "$WORK/out" && grep -q "architecture/modules/Orders/coverage-ledger/" "$WORK/out" \
    && ! grep -qF "$GOLDEN" "$WORK/out" \
    && ok "[$layout] LEDGER_FILE=<index> is named an index and points at its directory" \
    || bad "[$layout] index reported as '0 measurable rows'" "rc=$rc $(out)"

  # --- 6. an index that links to another module's per-BRD file names the link ------------------
  rc="$(run --module Billing)"
  [ "$rc" = 2 ] && grep -q "is an index" "$WORK/out" && grep -q "Orders/coverage-ledger/F002-invoicing.md" "$WORK/out" \
    && ok "[$layout] Billing's index names the ledger its rows are in" \
    || bad "[$layout] cross-module index not explained" "rc=$rc $(out)"

  # --- 9. a BRD id with a space is one BRD --------------------------------------------------------
  rm -f "$P"/docs/conformance/report-*.tsv
  rc="$(run --module Shipping)"
  n=$(ls "$P"/docs/conformance/ | grep -c '^report-')
  [ "$rc" = 0 ] && [ "$n" = 1 ] && ls "$P"/docs/conformance/report-*-"F003 shipping.tsv" >/dev/null 2>&1 \
    && ok "[$layout] 'F003 shipping.md' writes one report, report-<date>-F003 shipping.tsv" \
    || bad "[$layout] a BRD id with a space was split" "rc=$rc $(ls "$P/docs/conformance" | tr '\n' '|')"

  # --- 7. a LEDGER_FILE that does not exist FAULTs ----------------------------------------------
  rc="$( ( cd "$P" && PROJECT_ROOT="$P" LEDGER_FILE=architecture/nope.md bash "$SUT" --quiet --module Orders ) \
           > "$WORK/out" 2>&1; echo $? )"
  [ "$rc" = 2 ] && grep -q "LEDGER_FILE=architecture/nope.md" "$WORK/out" \
    && ok "[$layout] missing LEDGER_FILE FAULTs instead of falling back" \
    || bad "[$layout] missing LEDGER_FILE silently fell back" "rc=$rc $(out)"
done

# --- 10. a single-file multi-BRD ledger as brd-to-build-plan.md writes it (#515) --------------
# BRD-prefixed pointers, statuses `not built` and `blocked (<reason>)`. Before: "an index, not a
# ledger" (rc 2), and the two statuses would read UNKNOWN-STATUS.
mkdir -p "$P/architecture/modules/Catalog"
cat > "$P/architecture/modules/Catalog/coverage-ledger.md" <<'EOF'
# Coverage ledger — Catalog

| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| `F002/domainEntities/0` | entity | Item | 1.1 | exec.sh | `DESCRIBE ENTITY Catalog.Item` | built |
| `F002/microflows/0` | microflow | ACT_Item_Price | 1.2 | exec.sh | `DESCRIBE MICROFLOW Catalog.ACT_Item_Price` | not built |
| `F004/microflows/1` | microflow | ACT_Item_Sync | 1.3 | exec.sh | `DESCRIBE MICROFLOW Catalog.ACT_Item_Sync` | blocked (PD-04) |
EOF
printf 'Catalog.Item\n' >> "$P/PRESENT"
rc="$(run --module Catalog)"
[ "$rc" = 0 ] && grep -q "measured 3 " "$WORK/out" && ! grep -q "is an index" "$WORK/out" && ! grep -q "UNKNOWN-STATUS" "$WORK/out" \
  && ok "prefixed pointers + 'not built' / 'blocked (..)' statuses measured (3 rows, rc 0)" \
  || bad "brd-to-build-plan ledger format not measured" "rc=$rc $(out)"

# --- 8. LEDGER_FILE is in the usage text --------------------------------------------------------
( cd "$P" && PROJECT_ROOT="$P" bash "$SUT" --help ) 2>/dev/null | grep -q "LEDGER_FILE" && ok "--help documents LEDGER_FILE" \
  || bad "--help does not mention LEDGER_FILE"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
