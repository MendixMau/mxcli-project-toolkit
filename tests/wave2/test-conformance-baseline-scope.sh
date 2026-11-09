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

# --- 7. bare pointers and status `planned` are read (TK-006) -----------------------------------
rm -rf "$P/docs/conformance"
cat > "$P/architecture/modules/Orders/coverage-ledger.md" <<EOF
| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| /domainEntities/0 | entity | Order | 1.1 | exec.sh | \`DESCRIBE ENTITY Orders.Order\` | built |
| /microflows/0 | microflow | ACT_Later | 1.2 | exec.sh | \`DESCRIBE MICROFLOW Orders.ACT_Later\` | planned |
EOF
rm -f "$P/architecture/modules/Billing/coverage-ledger.md"
rc="$(run)"
[ "$rc" = 0 ] && [ "$(rows Orders)" = 2 ] && ok "bare-pointer ledger is read (2 rows) and planned+absent is OK" \
  || bad "bare pointers or planned not read (rc=$rc)" "$(out)"

# --- 8. bare pointers AND bare acceptance text: rows found, none measurable, FAULT names the cause
cat > "$P/architecture/modules/Orders/coverage-ledger.md" <<EOF
| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| /domainEntities/0 | entity | Order | 1.1 | exec.sh | DESCRIBE ENTITY Orders.Order | built |
| /microflows/0 | microflow | ACT_Later | 1.2 | exec.sh | DESCRIBE MICROFLOW Orders.ACT_Later | planned |
EOF
rc="$(run)"
[ "$rc" = 2 ] && [ "$(grep -c 'acceptance text is prose' "$WORK/out")" = 1 ] && [ "$(grep -c 'glob matched nothing' "$WORK/out")" = 0 ] \
  && ok "bare acceptance text: exit 2 and the FAULT says rows were found but are prose" \
  || bad "prose-only ledger FAULT wrong (rc=$rc)" "$(out)"

# --- 9-14. a built `planned` row is not a regression; --mark-built (#671) ----------------------
# The #671 repro: a ledger row `planned`, absent at baseline (OK), then built. Master scored it
# "was OK, now UNDERSTATED" (exit 1) and refused --update-baseline as a loosening (exit 2).
# Three ledger shapes at once: per-module, per-BRD directory, flat.
rm -rf "$P/docs/conformance" "$P/architecture/modules"
mkdir -p "$P/architecture/modules/Orders" "$P/architecture/modules/Billing/coverage-ledger"
cat > "$P/architecture/modules/Orders/coverage-ledger.md" <<EOF
| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| \`/domainEntities/0\` | entity | Order | 1.1 | exec.sh | \`DESCRIBE ENTITY Orders.Order\` | built |
| \`/microflows/0\` | microflow | ACT_Later | 1.2 | exec.sh | \`DESCRIBE MICROFLOW Orders.ACT_Later\` | planned |
| \`/microflows/1\` | microflow | ACT_Prose | 1.3 | exec.sh | runs on save | planned |
EOF
cat > "$P/architecture/modules/Billing/coverage-ledger/F001.md" <<EOF
| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| /domainEntities/0 | entity | Invoice | 2.1 | exec.sh | \`DESCRIBE ENTITY Billing.Invoice\` | \`planned\` |
| /microflows/0 | microflow | ACT_Blocked | 2.2 | exec.sh | \`DESCRIBE MICROFLOW Billing.ACT_Blocked\` | blocked (needs API) |
EOF
cat > "$P/architecture/modules/Ship-coverage-ledger.md" <<EOF
| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| /domainEntities/0 | entity | Parcel | 3.1 | exec.sh | \`DESCRIBE ENTITY Ship.Parcel\` | not built |
EOF
printf 'Orders.Order\n' > "$P/PRESENT"
rc="$(run)"
[ "$rc" = 0 ] && ok "9: baseline with the planned rows absent (OK)" || bad "9: baseline run rc=$rc" "$(out)"
printf 'Orders.Order\nOrders.ACT_Later\nBilling.Invoice\nBilling.ACT_Blocked\nShip.Parcel\n' > "$P/PRESENT"
rc="$(run)"
[ "$rc" = 0 ] && ! grep -q "was OK, now UNDERSTATED" "$WORK/out" \
  && ok "10: building the planned rows is not a regression (exit 0)" \
  || bad "10: a correct build scored as a regression (the #671 symptom)" "rc=$rc $(out)"
grep -q "ledger lags: 3 row(s) built but marked planned — run --mark-built" "$WORK/out" \
  && grep -q "1 row(s) marked blocked but PRESENT" "$WORK/out" \
  && ok "10b: the lag is a note naming --mark-built (3 planned/not built); the blocked row has its own line" \
  || bad "10b: wrong ledger-lags / blocked notes" "$(out)"
rc="$(run --update-baseline </dev/null)"
[ "$rc" = 0 ] && ok "11: --update-baseline over a lagging ledger is not refused as a loosening" \
  || bad "11: --update-baseline refused (rc=$rc)" "$(out)"
cp -R "$P/architecture" "$WORK/arch.before"
rc="$(run --mark-built)"
grep -q "3 row(s) marked built in 3 ledger(s)" "$WORK/out" && [ "$rc" = 0 ] \
  && ok "12: --mark-built flips the 3 planned/not-built rows across per-module, per-BRD and flat ledgers" \
  || bad "12: --mark-built did not report 3 rows / 3 ledgers" "rc=$rc $(out)"
d="$(diff -r "$WORK/arch.before" "$P/architecture" | grep '^[<>]')"
want='< | `/microflows/0` | microflow | ACT_Later | 1.2 | exec.sh | `DESCRIBE MICROFLOW Orders.ACT_Later` | planned |
> | `/microflows/0` | microflow | ACT_Later | 1.2 | exec.sh | `DESCRIBE MICROFLOW Orders.ACT_Later` | built |
< | /domainEntities/0 | entity | Invoice | 2.1 | exec.sh | `DESCRIBE ENTITY Billing.Invoice` | `planned` |
> | /domainEntities/0 | entity | Invoice | 2.1 | exec.sh | `DESCRIBE ENTITY Billing.Invoice` | `built` |
< | /domainEntities/0 | entity | Parcel | 3.1 | exec.sh | `DESCRIBE ENTITY Ship.Parcel` | not built |
> | /domainEntities/0 | entity | Parcel | 3.1 | exec.sh | `DESCRIBE ENTITY Ship.Parcel` | built |'
[ "$(printf '%s\n' "$d" | sort)" = "$(printf '%s\n' "$want" | sort)" ] \
  && ok "13: only the status cells of PRESENT planned/not-built rows changed (prose and blocked rows kept)" \
  || bad "13: --mark-built changed more or less than the 3 status cells" "$d"
cp -R "$P/architecture" "$WORK/arch.after"
rc="$(run --mark-built)"
grep -q "0 row(s) marked built" "$WORK/out" && diff -r "$WORK/arch.after" "$P/architecture" >/dev/null \
  && ok "14: --mark-built is idempotent (second run: 0 rows, no file changed)" \
  || bad "14: second --mark-built changed something" "$(out)"
! grep -q "ledger lags" "$WORK/out" && grep -q "1 row(s) marked blocked but PRESENT" "$WORK/out" \
  && ok "14b: after --mark-built the run-mark-built note is gone; only the blocked row is still named" \
  || bad "14b: the lag note survives --mark-built (it counted the blocked row it never flips)" "$(out)"
# --- 15. ...and the guard still holds: a marked-built row that goes missing is a regression ----
sed -i.bak '/^Orders.ACT_Later$/d' "$P/PRESENT"
rc="$(run)"
[ "$rc" = 1 ] && grep -q "Orders.*was OK, now STALE" "$WORK/out" \
  && ok "15: a built row going absent still fails the run (OK -> STALE)" \
  || bad "15: the regression guard was weakened" "rc=$rc $(out)"
grep -q -- "--mark-built" "$(dirname "$SUT")/module-close.sh" 2>/dev/null \
  && ok "16: module-close.sh runs --mark-built once per module" \
  || bad "16: module-close.sh does not call conformance-check --mark-built"

# --- 17. two rows of one ledger share a pointer: only the PRESENT one flips (PR #697 review) ----
mv "$P/PRESENT.bak" "$P/PRESENT"
rm -rf "$P/docs/conformance" "$P/architecture/modules"
mkdir -p "$P/architecture/modules/Orders"
cat > "$P/architecture/modules/Orders/coverage-ledger.md" <<EOF
| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| \`/entities/0\` | entity | Order | 1.1 | exec.sh | \`DESCRIBE ENTITY Orders.Order\` | planned |
| \`/entities/0\` | entity | Draft | 1.2 | exec.sh | \`DESCRIBE ENTITY Orders.Draft\` | planned |
EOF
printf 'Orders.Order\n' > "$P/PRESENT"
rc="$(run --mark-built)"
st="$(awk -F'|' 'NR>2 {gsub(/ /, "", $4); gsub(/ /, "", $8); printf "%s=%s ", $4, $8}' "$P/architecture/modules/Orders/coverage-ledger.md")"
[ "$st" = "Order=built Draft=planned " ] && ok "17: duplicate pointer — only the PRESENT row flips" \
  || bad "17: duplicate pointer flipped the wrong rows" "$st"
rc="$(run)"
[ "$rc" = 0 ] && grep -Eq "STALE +0 " "$WORK/out" \
  && ok "17b: the next run has no STALE row (exit 0)" || bad "17b: the next run failed (rc=$rc)" "$(out)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
