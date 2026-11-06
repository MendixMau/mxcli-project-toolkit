#!/usr/bin/env bash
# test-batch5-rules.sh -- unit tests for the toolkit-owned lint-rules/conv007_xpath_on_all_access.star
# (CONV007, WRITE-only replacement) and lint-rules/mxtk_sec015_flow_execute_rights.star (MXTK-SEC015,
# flow execute rights vs a declared role matrix), run
# under the real Go Starlark interpreter with the mxcli builtins mocked from JSON
# (tests/lint-rules/starrun). get_option() is mocked the way mxcli 0.26.0 converts
# lint-config.yaml options: bool / int / float / text pass, a list becomes None. permissions()
# serves every fixture row with element_type / element_name.
#
# IMPORTANT: every fixture in tests/lint-rules/fixtures/conv007-*.json and sec015-*.json is a
# HAND-WRITTEN unit fixture. The access_type / element_type spellings (READ, WRITE, EXECUTE,
# ENTITY, MICROFLOW, NANOFLOW) and the qualified role names were taken from the catalog
# `permissions` table of a real 20-module model (2026-11-06), but the rows themselves are invented. These tests prove the rule logic and
# the self-checks; they do NOT prove the vocabulary matches YOUR model.
#
# Needs `go` on PATH. A missing toolchain is a FAILURE (exit 1), never a quiet skip.
# Keep bash-3.2 compatible.
# Usage: tests/lint-rules/test-batch5-rules.sh      Exit 0 only if every assertion holds.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TK="$(cd "$HERE/../.." && pwd)"
FX="$HERE/fixtures"
R1="$TK/lint-rules/conv007_xpath_on_all_access.star"
R2="$TK/lint-rules/mxtk_sec015_flow_execute_rights.star"
for r in "$R1" "$R2"; do
  [ -f "$r" ] || { echo "FAIL rule file missing: ${r#"$TK"/}"; exit 1; }
done

if ! command -v go >/dev/null 2>&1; then
  echo "FAIL go toolchain not found; these tests cannot run (NOT a pass)."
  echo "     Install Go (https://go.dev/dl/, or: brew install go / apt install golang) and re-run."
  exit 1
fi
# shellcheck source=../../bin/lib/portable.sh
. "$TK/bin/lib/portable.sh"
require_py   # sets $PY or exits 2 with an actionable message

W=$(mktemp -d "${TMPDIR:-/tmp}/b5rules.XXXXXX")
trap 'rm -rf "$W"' EXIT
PASS=0; FAILED=0
ok(){ printf '  PASS %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n' "$1"; FAILED=$((FAILED+1)); }

cd "$TK" || exit 1
OUT="$W/out.json"; ERR="$W/err.txt"; RC=0

BIN="$W/starrun"
if ! (cd "$HERE/starrun" && GOFLAGS=-mod=mod go build -o "$BIN" . 2>"$ERR"); then
  echo "FAIL could not build tests/lint-rules/starrun: $(head -c 400 "$ERR")"; exit 1
fi

# run RULE FIXTURE [STRIP]  -> OUT holds stdout, RC the exit code
run(){
  local rule="$1" fix="$2" strip="${3:-}"
  if [ -n "$strip" ]; then
    "$BIN" -rule "$rule" -fixture "$FX/$fix.json" -strip-fields "$strip" >"$OUT" 2>"$ERR"
  else
    "$BIN" -rule "$rule" -fixture "$FX/$fix.json" >"$OUT" 2>"$ERR"
  fi
  RC=$?
}

# check LABEL PY-EXPR : v is the parsed violation list; the expression must be truthy.
check(){
  local label="$1" expr="$2"
  if [ "$RC" -ne 0 ]; then no "$label (harness exit $RC: $(head -c 300 "$ERR"))"; return; fi
  if "$PY" - "$OUT" "$expr" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
  then ok "$label"; else no "$label (got: $(head -c 400 "$OUT"))"; fi
}

echo "== CONV007 =="
run "$R1" conv007-a-default
check "a defaults -> only non-admin unscoped WRITE: Shop.Clerk on Order, Vend.Agent on Cache (Admin / Administrator of any module, READ, CREATE, scoped, non-persistent, external all skipped)" 'sorted((x["document_name"], x["message"].split("for role ")[1]) for x in v)==[("Shop.Order","'"'"'Shop.Clerk'"'"' - all rows are accessible"),("Vend.Cache","'"'"'Vend.Agent'"'"' - all rows are accessible")] and all("unconstrained WRITE" in x["message"] for x in v)'
run "$R1" conv007-b-check-read
check "b check_read: true -> the two unscoped READ rows join (4)" 'len(v)==4 and sum("unconstrained READ" in x["message"] for x in v)==2'
run "$R1" conv007-c-skip-modules
check "c skip_modules: \"Vend, Other\" -> the vendor module row is gone (1)" 'len(v)==1 and v[0]["document_name"]=="Shop.Order"'
run "$R1" conv007-d-skip-roles-replaces-default
check "d skip_roles: Clerk replaces the default: admins are flagged again, Clerk is not (4)" 'len(v)==4 and not any("Shop.Clerk" in x["message"] for x in v) and any("Shop.Admin" in x["message"] for x in v)'
run "$R1" conv007-e-bug-a-employee-unscoped
check "e BUG (a): Employee WRITE loses its XPath -> exactly one more finding, for Shop.Employee" 'len(v)==3 and sum("Shop.Employee" in x["message"] for x in v)==1'
run "$R1" conv007-f-check-read-text
check "f check_read: \"yes\" -> 1 _rule finding, no silent default" 'len(v)==1 and v[0]["module"]=="_rule" and "check_read" in v[0]["message"]'
run "$R1" conv007-g-skip-roles-list
check "g skip_roles as a YAML list (None on mxcli 0.26) -> 1 _rule finding, admins not silently unskipped" 'len(v)==1 and v[0]["module"]=="_rule" and "skip_roles" in v[0]["message"]'
run "$R1" conv007-h-skip-modules-number
check "h skip_modules: 5 -> 1 _rule finding" 'len(v)==1 and v[0]["module"]=="_rule" and "skip_modules" in v[0]["message"]'
run "$R1" conv007-i-empty
check "i empty model -> 0" 'len(v)==0'
run "$R1" conv007-j-admin-mapped-ok
check "j Shop.Admin mapped only to user role Admin, Inv.Administrator likewise -> still skipped (2: Clerk, Agent)" 'len(v)==2 and not any("Admin" in x["message"].split("for role ")[1] for x in v)'
run "$R1" conv007-k-admin-role-held-by-employee
check "k module role named Admin mapped to the Employee user role -> no longer skipped (3), Inv.Administrator still skipped" 'len(v)==3 and any("Shop.Admin" in x["message"] for x in v) and not any("Inv.Administrator" in x["message"] for x in v)'
run "$R1" conv007-l-admin-role-anonymous
check "l module role named Admin mapped to an anonymous user role -> not skipped, Inv.Administrator (admin-like, not anonymous) still is" 'any("Shop.Admin" in x["message"] for x in v) and not any("Inv.Administrator" in x["message"] for x in v)'

echo "== MXTK-SEC015 =="
run "$R2" sec015-a-no-config
check "a Employee can execute ACT_Vendor_Approve but nothing is configured -> 0 (silent by design)" 'len(v)==0'
run "$R2" sec015-b-matrix-clean
check "b matrix declared, only Admin and ProcurementOfficer execute -> 0" 'len(v)==0'
run "$R2" sec015-c-matrix-bug-b
check "c BUG (b): Employee added to execute -> 1 finding naming role, flow and the allowed roles" 'len(v)==1 and v[0]["document_name"]=="Procurement.ACT_Vendor_Approve" and "Role '"'"'Employee'"'"'" in v[0]["message"] and "allows only: Admin, ProcurementOfficer" in v[0]["message"] and v[0]["document_type"]=="Microflow"'
run "$R2" sec015-d-glob
check "d trailing glob + comment and blank lines -> Employee flagged on both Vendor_Approve and Vendor_Reject (2)" 'sorted(x["document_name"] for x in v)==["Procurement.ACT_Vendor_Approve","Procurement.ACT_Vendor_Reject"]'
run "$R2" sec015-e-unknown-role
check "e a misspelt matrix role -> 1 _rule finding naming it (not a flood of excess-role findings)" 'len(v)==1 and v[0]["module"]=="_rule" and "ProcurementOfficr" in v[0]["message"]'
run "$R2" sec015-f-stale-pattern
check "f a matrix pattern matching no flow -> 1 _rule finding naming the pattern" 'len(v)==1 and v[0]["module"]=="_rule" and "ACT_Vendor_Archive" in v[0]["message"] and "matches no flow" in v[0]["message"]'
run "$R2" sec015-g-no-equals
check "g a matrix line without '=' -> 1 _rule finding" 'len(v)==1 and v[0]["module"]=="_rule" and "no '"'"'='"'"'" in v[0]["message"]'
run "$R2" sec015-h-matrix-list-none
check "h matrix as a YAML list (None) -> 1 _rule finding, not silence" 'len(v)==1 and v[0]["module"]=="_rule" and "multi-line text" in v[0]["message"]'
run "$R2" sec015-i-unqualified
check "i matrix pattern without a module -> 1 _rule finding" 'len(v)==1 and v[0]["module"]=="_rule" and "qualified" in v[0]["message"]'
run "$R2" sec015-j-heuristic-only
check "j heuristic on, no matrix -> Employee on ACT_Vendor_Approve only (delete-only flow, System.User, writers and SUB_ flows are quiet)" 'len(v)==1 and v[0]["document_name"]=="Procurement.ACT_Vendor_Approve" and "no WRITE right on Procurement.Vendor" in v[0]["message"] and "Role '"'"'Employee'"'"'" in v[0]["message"]'
run "$R2" sec015-k-matrix-and-heuristic
check "k matrix + heuristic: the matrix-covered flow is reported once, by the matrix" 'len(v)==1 and "role matrix allows only" in v[0]["message"]'
run "$R2" sec015-l-two-lines-both-apply
check "l two matching lines: a role must pass every one -> FinanceApprover flagged by the narrower line" 'len(v)==1 and "Role '"'"'FinanceApprover'"'"'" in v[0]["message"] and "allows only: Admin, ProcurementOfficer" in v[0]["message"]'
run "$R2" sec015-q-matrix-no-execute-rows
check "q matrix declared but permissions() has no EXECUTE row -> 1 _rule self-check finding, not a clean pass" 'len(v)==1 and v[0]["module"]=="_rule" and "no EXECUTE row" in v[0]["message"]'
run "$R2" sec015-m-nanoflow
check "m a nanoflow execute right is checked, and named a Nanoflow" 'len(v)==1 and v[0]["document_name"]=="Procurement.NF_Vendor_Preview" and v[0]["document_type"]=="Nanoflow"'
run "$R2" sec015-n-heuristic-text
check "n heuristic: \"yes\" -> 1 _rule finding" 'len(v)==1 and v[0]["module"]=="_rule" and "heuristic" in v[0]["message"]'
run "$R2" sec015-o-no-mappings
check "o matrix declared but no user roles / mappings visible -> 1 _rule finding, not a clean pass" 'len(v)==1 and v[0]["module"]=="_rule" and "inspected NOTHING" in v[0]["message"]'
run "$R2" sec015-p-heuristic-prefix
check "p action_prefix is read: with SUB_ the SUB_ flow is the entry point (1)" 'len(v)==1 and v[0]["document_name"]=="Procurement.SUB_Vendor_Touch"'
run "$R2" sec015-q-empty-matrix-comments-only
check "q a matrix of comments only and no heuristic -> 0 (not configured)" 'len(v)==0'

echo
echo "passed: $PASS  failed: $FAILED"
[ "$FAILED" -eq 0 ]
