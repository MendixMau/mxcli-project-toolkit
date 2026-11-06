#!/usr/bin/env bash
# Usage: bash test-ledger-resolver.sh [path-to-_common.sh]
#
# Fixture for the one coverage-ledger lookup (mxtk_resolve_ledger in project-bin/_common.sh)
# and the toolkit-root lookup of the module rungs. The scripts under test are the siblings of
# the given _common.sh: review-module.sh, verify-module.sh, coverage-preflight.sh.
#
# The defects (field run, 2026-11-05):
#   #673  review-module.sh knew two of the four ledger forms (per-BRD dir, <M>/coverage-ledger.md)
#         and verify-module.sh three; a project with only architecture/coverage-ledger.md (the
#         sanctioned single-BRD form) or the flat <M>-coverage-ledger.md got a conformance FAULT
#         and a coverage FAULT from review-module while the dedicated checks measured it.
#   #672  coverage-preflight.sh never consulted find_toolkit_root, so an installed project wired
#         only through the "Toolkit root" row of CLAUDE.local.md (MXTK_ROOT unset) got
#         "FAULT: bin/coverage-check.sh not found".
#
# Every case runs on BOTH layouts (single-tree, and two-tree with the .mpr under app/). The
# files are SYNTHETIC and hand-written: nothing below parses tool output, it lays out files and
# asserts which ledger / engine the scripts find. mxcli is a stub that answers SHOW MODULES.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-bin/_common.sh"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
PB="$(cd "$(dirname "$SUT")" && pwd)"
REPO="$(cd "$PB/.." && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ledger-resolver.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
unset MXTK_ROOT COVERAGE_ENGINE COVERAGE_CHECK LEDGER_FILE

fn() { awk -v n="$2" '$0 ~ "^"n"\\(\\) \\{" {on=1} on{print} on && /^\}/{exit}' "$1"; }
HELPER="$(fn "$PB/_common.sh" mxtk_resolve_ledger)"
TKFN="$(fn "$PB/_common.sh" find_toolkit_root)"
HINT="$(fn "$PB/verify-module.sh" resolve_ledger_hint)"
VTOOL="$(fn "$PB/verify-module.sh" _tool)"

setup() {  # setup <single|two> -> P
  P="$WORK/$1"; rm -rf "$P"
  mkdir -p "$P/architecture/modules" "$P/docs/conformance" "$P/bin"
  if [ "$1" = two ]; then mkdir -p "$P/app"; : > "$P/app/Shop.mpr"; else : > "$P/Shop.mpr"; fi
  cat > "$P/mxcli" <<'EOF'
#!/usr/bin/env bash
case "$*" in *"SHOW MODULES"*) echo "| Orders |"; exit 0 ;; esac
echo "Error: not available in this fixture"; exit 1
EOF
  chmod +x "$P/mxcli"
  if command -v sqlite3 >/dev/null 2>&1; then
    mkdir -p "$P/.mxcli"
    printf "CREATE TABLE objects (QualifiedName TEXT, ModuleName TEXT);\nINSERT INTO objects VALUES ('Orders.X','Orders');\n" \
      | sqlite3 "$P/.mxcli/catalog.db"
  fi
  # A conformance stub in the project's bin/ (which _tool prefers): one OK row for Orders.
  cat > "$P/bin/conformance-check.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p docs/conformance
printf 'module\tpointer\tstored\tobserved\tverdict\tcommand\nOrders\tF001:`/x`\tbuilt\tPRESENT\tOK\tDESCRIBE MICROFLOW Orders.X\n' \
  > "docs/conformance/report-$(date +%Y-%m-%d).tsv"
echo "conformance-check stub"; exit 0
EOF
  chmod +x "$P/bin/conformance-check.sh"
}
review() { ( cd "$P" && PROJECT_ROOT="$P" bash "$PB/review-module.sh" Orders --json-only --out "$P/out/report.json" ) \
             > "$WORK/out" 2>&1; }
NOLEDGER='no (architecture/modules/Orders/coverage-ledger\.md or|coverage-ledger\.md or coverage-ledger/|coverage ledger for Orders)'
out() { sed $'s/\033\[[0-9;]*m//g' "$WORK/out" | grep -iE 'ledger|FAULT' | tr '\n' ' ' | cut -c1-300; }

for layout in single two; do
  echo "== $layout-tree layout"
  setup "$layout"; A="$P/architecture"; M="$A/modules"

  # --- 1. the helper: four forms, in the documented order ------------------------------------
  res() { ( cd "$P" && eval "$HELPER" && mxtk_resolve_ledger "$@" ); }
  if [ -z "$HELPER" ]; then
    bad "[$layout] no mxtk_resolve_ledger() in _common.sh"
  else
    : > "$A/coverage-ledger.md"
    [ "$(res "$P" Orders)" = "$A/coverage-ledger.md" ] && ok "[$layout] helper: project file is the last resort" || bad "[$layout] helper: project form" "$(res "$P" Orders)"
    : > "$M/Orders-coverage-ledger.md"
    [ "$(res "$P" Orders)" = "$M/Orders-coverage-ledger.md" ] && ok "[$layout] helper: flat form beats the project file" || bad "[$layout] helper: flat form" "$(res "$P" Orders)"
    mkdir -p "$M/Orders/coverage-ledger"; : > "$M/Orders/coverage-ledger.md"
    [ "$(res "$P" Orders)" = "$M/Orders/coverage-ledger.md" ] && ok "[$layout] helper: <M>/coverage-ledger.md beats flat; an empty dir is no ledger" || bad "[$layout] helper: canonical form" "$(res "$P" Orders)"
    : > "$M/Orders/coverage-ledger/F001.md"
    [ "$(res "" Orders)" = "architecture/modules/Orders/coverage-ledger" ] && ok "[$layout] helper: per-BRD dir wins; empty root gives a relative path" || bad "[$layout] helper: dir form" "$(res "" Orders)"
    rm -rf "$M"/* "$A/coverage-ledger.md"
    res "$P" Orders >/dev/null && bad "[$layout] helper: found a ledger in an empty tree" || ok "[$layout] helper: no ledger returns 1"
  fi

  # --- 2. review-module on the single-BRD project ledger (#673) ------------------------------
  printf '# Coverage ledger\n' > "$A/coverage-ledger.md"
  review
  if grep -qE "$NOLEDGER" "$WORK/out"; then
    bad "[$layout] review-module: single-BRD architecture/coverage-ledger.md reported as no ledger (#673)" "$(out)"
  elif grep -q "conformance-check stub" "$WORK/out" || grep -q "conformance" "$P/.claude/loop/review/Orders/summary.tsv" 2>/dev/null; then
    ok "[$layout] review-module: single-BRD ledger found; conformance ran"
  else
    bad "[$layout] review-module: conformance rung did not run" "$(out)"
  fi

  # --- 3. review-module on the flat <M>-coverage-ledger.md (#673) ----------------------------
  rm -f "$A/coverage-ledger.md"; printf '# Coverage ledger — Orders\n' > "$M/Orders-coverage-ledger.md"
  review
  grep -qE "$NOLEDGER" "$WORK/out" \
    && bad "[$layout] review-module: flat Orders-coverage-ledger.md reported as no ledger (#673)" "$(out)" \
    || ok "[$layout] review-module: flat ledger found"

  # --- 4. verify-module's hint knows the flat form too (#673) --------------------------------
  v="$( ROOT="$P"; MODULE=Orders; eval "$HELPER"; eval "$HINT"; resolve_ledger_hint )"
  [ "$v" = "$M/Orders-coverage-ledger.md" ] && ok "[$layout] verify-module hint: flat ledger, not the absent project file" \
    || bad "[$layout] verify-module hint missed the flat form (#673)" "$v"
  rm -f "$M/Orders-coverage-ledger.md"

  # --- 5. coverage-preflight installed, wired only by the Toolkit root row (#672) ------------
  command -v jq >/dev/null 2>&1 || { echo "  skip — jq not installed (the engine needs it)"; continue; }
  TK="$WORK/tk-$layout"; mkdir -p "$TK/bin" "$TK/project-bin"
  cp "$REPO/bin/coverage-check.sh" "$TK/bin/"; chmod +x "$TK/bin/coverage-check.sh"
  [ -d "$REPO/bin/lib" ] && cp -R "$REPO/bin/lib" "$TK/bin/lib"
  for f in coverage-preflight.sh _common.sh _claims.sh; do cp "$PB/$f" "$P/bin/"; done
  printf '| Item | Value | Why |\n|---|---|---|\n| Toolkit root | `%s` | The process authority |\n' "$TK" > "$P/CLAUDE.local.md"
  mkdir -p "$P/analysis/src/knowledge-base/brd"
  printf '{"id":"FA01","title":"Alpha","useCases":[{"id":"UC1","name":"Place order"}]}\n' \
    > "$P/analysis/src/knowledge-base/brd/FA01-alpha.brd.json"
  { echo "## BUILDABLE"; echo ""
    echo "| pointer | type | title | slice | writeMode | acceptance | status |"; echo "|---|---|---|---|---|---|---|"
    echo "| \`/useCases/0/*\` (2) | usecase | UC1 | 1.1 | test | e2e | not-built |"
    echo ""; echo "## NON-BUILDABLE"; echo ""; echo "| pointer | category | reason |"; echo "|---|---|---|"
    echo "| \`/id\` | provenance | metadata |"; echo "| \`/title\` | provenance | metadata |"
  } > "$A/coverage-ledger.md"
  ( cd "$P" && PROJECT_ROOT="$P" bash "$P/bin/coverage-preflight.sh" --summary --module Orders ) > "$WORK/out" 2>&1; rc=$?
  if grep -q "coverage-check.sh not found" "$WORK/out"; then
    bad "[$layout] coverage-preflight: engine not found with only the Toolkit root row (#672)" "rc=$rc $(out)"
  elif [ "$rc" -eq 0 ]; then
    ok "[$layout] coverage-preflight: engine found through the Toolkit root row; single-BRD ledger measured (rc 0)"
  else
    bad "[$layout] coverage-preflight: engine found but the run did not come out clean" "rc=$rc $(out)"
  fi

  # --- 6. verify/review _tool reach the toolkit through the row (#672) -----------------------
  t="$( ROOT="$P"; BIN="$P/nowhere"; PROJECT_ROOT="$P"; eval "$TKFN"; eval "$VTOOL"; _tool coverage-check.sh )"
  [ "$t" = "$TK/bin/coverage-check.sh" ] && ok "[$layout] _tool: coverage-check.sh found via find_toolkit_root" \
    || bad "[$layout] _tool does not consult find_toolkit_root (#672)" "$t"
done

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
