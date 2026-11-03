#!/usr/bin/env bash
# Usage: bash test-app-facts-db-uri.sh [path-to-app-facts.sh]
#
# Fixture for the catalog URI in project-bin/app-facts.sh step 2.
#
# The defect: step 2 opened the catalog as "file:%s?mode=ro" % DB with the path pasted in raw.
# In a URI, '#' starts a fragment and '?' starts the query, so a model folder named "a #2" or
# "b?c" cut the path short and took mode=ro with it. SQLite then CREATED an empty database at
# the truncated path (a zero-byte "a " or "b" beside the model folder) and opened that. The
# shell's catalog check had already passed, because it reads the plain path with the sqlite3
# CLI, so the two opens disagreed. Measured on master d16f578 with this fixture: both folders
# end in a Python traceback ("no such table: modules_data", exit 2), no inventory.json, and a
# stray zero-byte file left outside the project.
#
# The fix: the URI comes from mxtk_sqlite_ro_uri in _common.sh (pathname2url, the escaping
# mxtk_model_version already used), and step 2 refuses when the catalog it opened has 0 tables.
#
# Cases, for each folder name ("a #2", "b?c", and a plain control):
#   1. app-facts exits 0 and inventory.json names the catalog's two modules
#   2. no stray file is created beside the model folder
# Plus:
#   3. mxtk_sqlite_ro_uri escapes '#', '?' and ' ' and ends in ?mode=ro
#   4. a catalog that is empty at the second open is refused with exit 2 and a FAULT line,
#      never written as facts
#   5. beside an OLDER _common.sh with no mxtk_sqlite_ro_uri, app-facts falls back to its inline
#      URI (no refusal) and a folder with a '#' still opens read-only: facts written, no stray file
#
# The catalog database is SYNTHETIC: tables and columns are exactly the ones app-facts.sh's
# step 1 guard and step 2 queries name. The mxcli is a stub that copies the prepared catalog
# into place, as in test-catalog-edge-guard.sh. No real mxcli runs.

set -uo pipefail

AF="${1:-}"
[ -z "$AF" ] && AF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-bin/app-facts.sh"
if [ ! -f "$AF" ]; then
  echo "SKIP: subject not found at $AF"; echo "SCORE: 0/0"; exit 0
fi
AF="$(cd "$(dirname "$AF")" && pwd)/$(basename "$AF")"
command -v sqlite3 >/dev/null || { echo "SKIP: sqlite3 not on PATH"; echo "SCORE: 0/0"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/af-dburi.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PREP="$WORK/prep.db"
{
  echo "CREATE TABLE catalog_meta (Key TEXT, Value TEXT); INSERT INTO catalog_meta VALUES ('build_mode','full');"
  echo "CREATE TABLE projects (ProjectName TEXT, MendixVersion TEXT); INSERT INTO projects VALUES ('Shop','11.12.2');"
  echo "CREATE TABLE modules_data (Name TEXT, Source TEXT, AppStoreVersion TEXT, AppStoreGuid TEXT);"
  echo "INSERT INTO modules_data VALUES ('Orders','','',''),('Billing','','','');"
  echo "CREATE TABLE entities_data (QualifiedName TEXT, ModuleName TEXT, EntityType TEXT, AttributeCount INTEGER);"
  echo "INSERT INTO entities_data VALUES ('Orders.Order','Orders','PERSISTENT',3);"
  echo "CREATE TABLE microflows_data (QualifiedName TEXT, ModuleName TEXT, Name TEXT, ActivityCount INTEGER, MicroflowType TEXT);"
  echo "INSERT INTO microflows_data VALUES ('Orders.ACT_Save','Orders','ACT_Save',3,'MICROFLOW'),('Billing.ACT_Send','Billing','ACT_Send',2,'MICROFLOW');"
  echo "CREATE TABLE activities_data (MicroflowQualifiedName TEXT, ModuleName TEXT, ActivityType TEXT);"
  echo "INSERT INTO activities_data VALUES ('Orders.ACT_Save','Orders','ActionActivity');"
  echo "CREATE TABLE pages_data (QualifiedName TEXT, ModuleName TEXT);"
  echo "CREATE TABLE scheduled_events_data (QualifiedName TEXT, ModuleName TEXT, Microflow TEXT, Enabled INTEGER, IntervalSeconds INTEGER, RepeatDescription TEXT);"
  echo "CREATE TABLE objects (QualifiedName TEXT, ModuleName TEXT, ObjectType TEXT);"
  echo "INSERT INTO objects VALUES ('Orders.ACT_Save','Orders','MICROFLOW'),('Billing.ACT_Send','Billing','MICROFLOW');"
  echo "CREATE TABLE refs (SourceType TEXT, SourceName TEXT, TargetName TEXT, RefKind TEXT, ModuleName TEXT);"
  echo "INSERT INTO refs VALUES ('MICROFLOW','Billing.ACT_Send','Orders.ACT_Save','call','Billing');"
  echo "CREATE TABLE graph_dead_assets (QualifiedName TEXT, ObjectType TEXT, ModuleName TEXT);"
} | sqlite3 "$PREP"

# stub mxcli: copies $1 (a prepared catalog) into .mxcli/catalog.db, writes the report file
mkstub() {
  cat > "$WORK/mxcli-stub" <<EOF
#!/usr/bin/env bash
[ "\${1:-}" = --version ] && { echo "mxcli stub"; exit 0; }
o=""; while [ \$# -gt 0 ]; do [ "\$1" = -o ] && o="\$2"; shift; done
mkdir -p .mxcli && cp "$1" .mxcli/catalog.db && echo '{}' > "\$o"
EOF
  chmod +x "$WORK/mxcli-stub"
}

run_af() { # <project dir> -> rc; output in $WORK/out
  ( cd "$1" && PROJECT_ROOT="$1" MXCLI="$WORK/mxcli-stub" bash "$AF" --skip-loops --facts-dir "$1/facts" ) > "$WORK/out" 2>&1
  echo $?
}
out() { tr '\n' ' ' < "$WORK/out" | cut -c1-400; }

mkstub "$PREP"
for name in 'a #2' 'b?c' 'plain'; do
  echo "== folder '$name'"
  PARENT="$WORK/p-$RANDOM"; P="$PARENT/$name"
  mkdir -p "$P"; : > "$P/Shop.mpr"
  rc="$(run_af "$P")"
  if [ "$rc" = 0 ] && [ -f "$P/facts/inventory.json" ] \
     && grep -q '"Orders"' "$P/facts/inventory.json" && grep -q '"Billing"' "$P/facts/inventory.json"; then
    ok "[$name] facts written from the real catalog (rc 0, Orders and Billing in inventory.json)"
  else
    bad "[$name] no real facts" "rc=$rc $(out)"
  fi
  stray="$(cd "$PARENT" && ls -A | grep -vxF -- "$name")"
  if [ -z "$stray" ]; then
    ok "[$name] nothing created beside the model folder"
  else
    bad "[$name] stray file(s) beside the model folder (a truncated URI was opened read-write)" "$stray"
  fi
done

echo "== mxtk_sqlite_ro_uri"
uri="$( . "$(dirname "$AF")/_common.sh" >/dev/null 2>&1; mxtk_sqlite_ro_uri "/x/a #2/b?c/catalog.db" )"
case "$uri" in
  'file:/x/a%20%232/b%3Fc/catalog.db?mode=ro') ok "escapes ' ', '#', '?' and keeps ?mode=ro ($uri)" ;;
  *) bad "unexpected URI" "$uri" ;;
esac

echo "== a catalog that is empty at the second open is refused"
# The state the truncated URI produced, made directly: step 1 checks a good catalog, then a
# python wrapper ($PYTHON, which _common.sh's resolve_py tries first) replaces it with an empty database just
# before step 2's program starts reading it from stdin.
P="$WORK/empty-$RANDOM/m"; mkdir -p "$P"; : > "$P/Shop.mpr"
mkdir -p "$WORK/bin"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/lib/portable.sh"
require_py; REAL_PY="$PY"
cat > "$WORK/bin/py-wrap" <<EOF
#!/usr/bin/env bash
# empties the catalog just before app-facts' step-2 program reads it from stdin
if [ "\${1:-}" = - ] && [ -f "$P/.mxcli/catalog.db" ]; then
  rm -f "$P/.mxcli/catalog.db"; "$REAL_PY" -c 'import sqlite3,sys; sqlite3.connect(sys.argv[1]).close()' "$P/.mxcli/catalog.db"
fi
exec "$REAL_PY" "\$@"
EOF
chmod +x "$WORK/bin/py-wrap"
rc="$( ( cd "$P" && PY="$WORK/bin/py-wrap" PYTHON="$WORK/bin/py-wrap" PROJECT_ROOT="$P" MXCLI="$WORK/mxcli-stub" bash "$AF" --skip-loops --facts-dir "$P/facts" ) > "$WORK/out" 2>&1; echo $? )"
if [ "$rc" = 2 ] && grep -q "opened with 0 tables" "$WORK/out" && [ ! -f "$P/facts/inventory.json" ]; then
  ok "0-table catalog at step 2: exit 2, FAULT line, no inventory.json"
else
  bad "0-table catalog not refused" "rc=$rc $(out)"
fi

echo "== older _common.sh without mxtk_sqlite_ro_uri: inline fallback"
# A consuming project whose bin/_common.sh predates the helper: app-facts.sh copied beside a
# _common.sh with that one function removed. Everything else (find_mpr, require_py, native_path)
# is still there, as in a real older copy.
OLD="$WORK/old-bin"; mkdir -p "$OLD"
cp "$AF" "$OLD/app-facts.sh"
"$REAL_PY" - "$(dirname "$AF")/_common.sh" "$OLD/_common.sh" <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
s2 = re.sub(r'(?ms)^mxtk_sqlite_ro_uri\(\) \{.*?^\}\n', '', s, count=1)
assert s2 != s, "mxtk_sqlite_ro_uri not found in _common.sh"
open(sys.argv[2], "w").write(s2)
PYEOF
if ( . "$OLD/_common.sh" >/dev/null 2>&1; type mxtk_sqlite_ro_uri >/dev/null 2>&1 ); then
  bad "test setup: stripped _common.sh still defines mxtk_sqlite_ro_uri"
else
  PARENT="$WORK/old-$RANDOM"; P="$PARENT/a #2"; mkdir -p "$P"; : > "$P/Shop.mpr"
  rc="$( ( cd "$P" && PROJECT_ROOT="$P" MXCLI="$WORK/mxcli-stub" bash "$OLD/app-facts.sh" --skip-loops --facts-dir "$P/facts" ) > "$WORK/out" 2>&1; echo $? )"
  if [ "$rc" = 0 ] && grep -q '"Orders"' "$P/facts/inventory.json" 2>/dev/null && grep -q '"Billing"' "$P/facts/inventory.json"; then
    ok "[older _common.sh, 'a #2'] no refusal; facts written from the real catalog"
  else
    bad "[older _common.sh, 'a #2'] fallback did not produce facts" "rc=$rc $(out)"
  fi
  stray="$(cd "$PARENT" && ls -A | grep -vxF -- 'a #2')"
  if [ -z "$stray" ]; then
    ok "[older _common.sh, 'a #2'] opened read-only: nothing created beside the model folder"
  else
    bad "[older _common.sh, 'a #2'] stray file(s) beside the model folder" "$stray"
  fi
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
