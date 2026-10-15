#!/usr/bin/env bash
# Usage: bash test-catalog-edge-guard.sh [path-to-graph-sweep.sh]
#
# Fixture for the catalog guard in project-bin/graph-sweep.sh and project-bin/app-facts.sh
# (app-facts.sh is taken from beside the subject).
#
# The defect (issue #259, field report 2026-10-11, mxcli v0.24.0, Mendix 11.14.0): both scripts
# refused any catalog whose catalog_meta.build_mode was not the literal 'full'. mxcli v0.24.0
# writes 'source' even after `REFRESH CATALOG FULL`, on a catalog holding 5,368 typed refs rows,
# so every sweep on that mxcli ended in (verbatim from the report — the golden input):
#   FAULT: catalog build_mode is 'source'; reference edges require 'full'.
# The fix tests what the scripts read instead of the label: a non-empty refs table whose rows
# carry a RefKind. It FAULTs only on an empty or kind-less refs table.
#
# The first cut of the fix required a 'call' edge, which refused a model with no
# microflow-to-microflow calls at all (an early module reached only from pages and buttons) —
# a regression against master, caught in review. Case 2 guards it.
#
# Cases, each on BOTH layouts (single-tree, and two-tree with the .mpr and catalog under app/):
#   1. build_mode 'source' + call edges   -> sweep runs, orphan finding still correct
#   2. build_mode 'full'   + action edges only, zero calls -> sweep runs (as on master)
#   3. build_mode 'full'   + kind-less refs -> FAULT naming the mode and the per-kind counts
#   4. build_mode 'fast'   + empty refs    -> FAULT, as before
#   4b. refs typed, but none of the orphan-read kinds -> sweeps, with the orphan-list WARNING
#   5. app-facts: 'source' + calls and action-only both pass the guard; kind-less FAULTs
#
# The catalog databases are SYNTHETIC: no real catalog.db is captured in this repo, and the
# report quotes only the FAULT line and the counts. Tables and columns are exactly the ones the
# two scripts query (catalog_meta key/value, refs SourceName/TargetName/RefKind, objects,
# microflows_data, and app-facts' nine required tables); RefKind values 'call' and 'action' are
# the ones the scripts' own queries name. The mxcli used by app-facts is a stub that copies a
# prepared catalog into place — no real mxcli runs.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-bin/graph-sweep.sh"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"
AF="$(dirname "$SUT")/app-facts.sh"
command -v sqlite3 >/dev/null || { echo "SKIP: sqlite3 not on PATH"; echo "SCORE: 0/0"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/catalog-calls.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# mkdb <db> <build_mode> <refs shape: calls|actions|kindless|otherkind|empty>
mkdb() {
  local db="$1" mode="$2" shape="$3"
  mkdir -p "$(dirname "$db")"; rm -f "$db"
  {
    echo "CREATE TABLE catalog_meta (key TEXT, value TEXT);"
    echo "INSERT INTO catalog_meta VALUES ('mpr_mod_time','2026-10-10T12:00:00.000');"
    echo "INSERT INTO catalog_meta VALUES ('build_mode','$mode');"
    echo "CREATE TABLE refs (SourceType TEXT, SourceName TEXT, TargetName TEXT, RefKind TEXT, ModuleName TEXT);"
    echo "CREATE TABLE objects (QualifiedName TEXT, ModuleName TEXT, ObjectType TEXT);"
    echo "CREATE TABLE microflows_data (QualifiedName TEXT, ModuleName TEXT, Name TEXT, ActivityCount INTEGER, MicroflowType TEXT);"
    echo "CREATE TABLE modules_data (Name TEXT, Source TEXT, AppStoreVersion TEXT, AppStoreGuid TEXT);"
    echo "CREATE TABLE entities_data (QualifiedName TEXT, ModuleName TEXT, EntityType TEXT);"
    echo "CREATE TABLE activities_data (MicroflowQualifiedName TEXT, ModuleName TEXT, ActivityType TEXT);"
    echo "CREATE TABLE pages_data (QualifiedName TEXT, ModuleName TEXT);"
    echo "CREATE TABLE scheduled_events_data (QualifiedName TEXT, ModuleName TEXT);"
    echo "CREATE TABLE projects (Name TEXT);"
    echo "INSERT INTO modules_data VALUES ('Orders','', '', ''),('Billing','', '', '');"
    echo "INSERT INTO activities_data VALUES ('Orders.SUB_Total','Orders','ActionActivity');"
    for m in Orders.ACT_Save Orders.SUB_Total Orders.SUB_Unused Billing.ACT_Send; do
      echo "INSERT INTO objects VALUES ('$m','${m%%.*}','MICROFLOW');"
      echo "INSERT INTO microflows_data VALUES ('$m','${m%%.*}','${m#*.}',3,'MICROFLOW');"
    done
    case "$shape" in
      calls|actions)
        echo "INSERT INTO refs VALUES ('PAGE','Orders.Order_Edit','Orders.ACT_Save','action','Orders');"
        echo "INSERT INTO refs VALUES ('MICROFLOW','Billing.ACT_Send','Orders.ACT_Save','action','Billing');"
        [ "$shape" = calls ] && echo "INSERT INTO refs VALUES ('MICROFLOW','Orders.ACT_Save','Orders.SUB_Total','call','Orders');" ;;
      otherkind)
        echo "INSERT INTO refs VALUES ('MICROFLOW','Orders.ACT_Save','Orders.Order','retrieve','Orders');" ;;
      kindless)
        echo "INSERT INTO refs VALUES ('PAGE','Orders.Order_Edit','Orders.ACT_Save','','Orders');"
        echo "INSERT INTO refs VALUES ('MICROFLOW','Orders.ACT_Save','Orders.SUB_Total',NULL,'Orders');" ;;
    esac
  } | sqlite3 "$db"
}

# proj <layout:single|two> -> prints project dir; .mpr mtime pinned to match catalog_meta
proj() {
  local p="$WORK/$1-$RANDOM" mdir
  mkdir -p "$p"
  if [ "$1" = two ]; then mdir="$p/app"; else mdir="$p"; fi
  mkdir -p "$mdir"
  : > "$mdir/Shop.mpr"
  touch -t 202610101200.00 "$mdir/Shop.mpr"
  printf '%s\n' "$p"
}
mdir() { if [ -d "$1/app" ]; then printf '%s/app\n' "$1"; else printf '%s\n' "$1"; fi; }
sweep() { ( cd "$1" && PROJECT_ROOT="$1" bash "$SUT" --min-elements 1 ) > "$WORK/out" 2>&1; echo $?; }
out() { tr '\n' ' ' < "$WORK/out" | cut -c1-400; }

for layout in single two; do
  echo "== graph-sweep · $layout-tree layout"

  # --- 1. 'source' with call edges: the field case --------------------------------------------
  P="$(proj $layout)"; mkdb "$(mdir "$P")/.mxcli/catalog.db" source calls
  rc="$(sweep "$P")"
  if grep -q "FAULT: catalog build_mode is 'source'; reference edges require 'full'." "$WORK/out"; then
    bad "[$layout] build_mode 'source' refused by label (issue #259 golden FAULT line)" "rc=$rc $(out)"
  elif [ "$rc" = 0 ] && grep -q "graph-sweep ·" "$WORK/out"; then
    ok "[$layout] build_mode 'source' with call edges is swept (rc 0)"
  else
    bad "[$layout] 'source' catalog with call edges did not sweep" "rc=$rc $(out)"
  fi
  if grep -q "Orders.SUB_Unused" "$WORK/out" && ! grep -q "Orders.SUB_Total " "$WORK/out"; then
    ok "[$layout] orphan finding still reads call edges (SUB_Unused listed, called SUB_Total not)"
  else
    bad "[$layout] orphan finding wrong on a 'source' catalog" "$(out)"
  fi

  # --- 2. no microflow-to-microflow calls at all: still sweeps (the review-caught regression) ----
  P="$(proj $layout)"; mkdb "$(mdir "$P")/.mxcli/catalog.db" full actions
  rc="$(sweep "$P")"
  if [ "$rc" = 0 ] && grep -q "graph-sweep ·.*action=2" "$WORK/out" && grep -q "Orders.SUB_Total" "$WORK/out"; then
    ok "[$layout] action-only catalog (zero calls) is swept, as on master"
  else
    bad "[$layout] a model with no calls was refused" "rc=$rc $(out)"
  fi

  # --- 3. refs present but kind-less: the label is not evidence ---------------------------------
  P="$(proj $layout)"; mkdb "$(mdir "$P")/.mxcli/catalog.db" full kindless
  rc="$(sweep "$P")"
  if [ "$rc" = 2 ] && grep -q "carry no RefKind" "$WORK/out" && grep -q "build_mode 'full'" "$WORK/out" \
     && grep -q "(none)=2" "$WORK/out"; then
    ok "[$layout] kind-less refs FAULT, naming the mode and per-kind counts ((none)=2)"
  else
    bad "[$layout] a catalog with untyped edges was not refused by what it holds" "rc=$rc $(out)"
  fi

  # --- 4. empty refs still FAULTs ---------------------------------------------------------------
  P="$(proj $layout)"; mkdb "$(mdir "$P")/.mxcli/catalog.db" fast empty
  rc="$(sweep "$P")"
  if [ "$rc" = 2 ] && grep -q "^FAULT:" "$WORK/out"; then
    ok "[$layout] empty refs still FAULTs (never a clean sweep)"
  else
    bad "[$layout] empty refs not refused" "rc=$rc $(out)"
  fi

  # --- 4b. typed refs, but none the orphan query reads: sweep, and say the orphan list is moot ----
  P="$(proj $layout)"; mkdb "$(mdir "$P")/.mxcli/catalog.db" full otherkind
  rc="$(sweep "$P")"
  if [ "$rc" = 0 ] && grep -q "WARNING: the catalog has no call/action/menu_item/show_page/datasource edges" "$WORK/out" \
     && grep -q "retrieve=1" "$WORK/out"; then
    ok "[$layout] no orphan-read kinds: sweeps with the orphan-list WARNING (retrieve=1 shown)"
  else
    bad "[$layout] missing orphan-read kinds not warned about" "rc=$rc $(out)"
  fi
  P="$(proj $layout)"; mkdb "$(mdir "$P")/.mxcli/catalog.db" full actions
  sweep "$P" >/dev/null
  ! grep -q "WARNING: the catalog has no call" "$WORK/out" \
    && ok "[$layout] no orphan-list WARNING when an orphan-read kind is present" \
    || bad "[$layout] orphan-list WARNING printed on an action-bearing catalog" "$(out)"

  # --- 5. app-facts: same guard, through a stub mxcli that drops a prepared catalog -------------
  if [ -f "$AF" ]; then
    for variant in source-calls full-actions full-kindless py-crlf; do
      P="$(proj $layout)"
      case "$variant" in
        source-calls|py-crlf)  mkdb "$WORK/prep.db" source calls ;;
        full-actions)  mkdb "$WORK/prep.db" full actions ;;
        full-kindless) mkdb "$WORK/prep.db" full kindless ;;
      esac
      cat > "$WORK/mxcli-stub" <<EOF
#!/usr/bin/env bash
[ "\${1:-}" = --version ] && { echo "mxcli stub"; exit 0; }
o=""; while [ \$# -gt 0 ]; do [ "\$1" = -o ] && o="\$2"; shift; done
mkdir -p .mxcli && cp "$WORK/prep.db" .mxcli/catalog.db && echo '{}' > "\$o"
EOF
      chmod +x "$WORK/mxcli-stub"
      if [ "$variant" = py-crlf ]; then
        # The sqlite3-CLI-less path with a Python that ends every line in CRLF, as native Windows
        # Python does under Git Bash (which ships no sqlite3). The real interpreter does the work.
        _real_py="$(command -v python3 || command -v python)"  # portability-ok: fixture picks the real interpreter to wrap
        printf '#!/usr/bin/env bash\nset -o pipefail\n"%s" "$@" | awk '"'"'{printf "%%s\\r\\n", $0}'"'"'\n' "$_real_py" > "$WORK/py-crlf"
        chmod +x "$WORK/py-crlf"
        ( cd "$P" && PROJECT_ROOT="$P" MXCLI="$WORK/mxcli-stub" APPFACTS_NO_SQLITE3_CLI=1 PYTHON="$WORK/py-crlf" \
            bash "$AF" --skip-loops --facts-dir "$P/facts" ) > "$WORK/out" 2>&1
      else
        ( cd "$P" && PROJECT_ROOT="$P" MXCLI="$WORK/mxcli-stub" bash "$AF" --skip-loops --facts-dir "$P/facts" ) > "$WORK/out" 2>&1
      fi
      rc=$?
      case "$variant" in
        source-calls)
          if grep -q "catalog ok: build_mode=source" "$WORK/out" && ! grep -q "build_mode is 'source'" "$WORK/out"; then
            ok "[$layout] app-facts accepts a 'source' catalog with call edges"
          else
            bad "[$layout] app-facts refused a 'source' catalog with call edges" "rc=$rc $(out)"
          fi ;;
        full-actions)
          if grep -q "catalog ok: build_mode=full" "$WORK/out"; then
            ok "[$layout] app-facts accepts an action-only catalog (zero calls)"
          else
            bad "[$layout] app-facts refused a model with no calls" "rc=$rc $(out)"
          fi ;;
        py-crlf)
          # The guard is what is under test (as for the variants above); step 2 needs columns this
          # synthetic catalog does not carry.
          if grep -q "catalog ok: build_mode=source modules=2 refs=3" "$WORK/out" && ! grep -q "schema is missing" "$WORK/out"; then
            ok "[$layout] app-facts without the sqlite3 CLI, CRLF Python: the guard reads the catalog clean"
          else
            bad "[$layout] app-facts failed on the sqlite3-less CRLF path" "rc=$rc $(out)"
          fi ;;
        full-kindless)
          if [ "$rc" = 2 ] && grep -q "carry no RefKind" "$WORK/out" && grep -q "build_mode 'full'" "$WORK/out" \
             && grep -q "(none)=2" "$WORK/out"; then
            ok "[$layout] app-facts FAULTs on kind-less refs, naming the mode and counts"
          else
            bad "[$layout] app-facts wrote facts from untyped refs" "rc=$rc $(out)"
          fi ;;
      esac
    done
  else
    bad "app-facts.sh not beside $SUT"
  fi
done

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
