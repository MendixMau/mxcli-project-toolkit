#!/usr/bin/env bash
# test-app-facts-incremental.sh — the incremental loop sweep in project-bin/app-facts.sh and the
# "app map" freshness line in bin/status.sh (#297).
#
# Usage: bash tests/wave2/test-app-facts-incremental.sh [path-to-app-facts.sh]
#        (bin/status.sh and mx-metadata-note.py are taken from the same toolkit as the subject)
#
# The defect: every app-facts run re-described every loop-containing microflow. A field run on a
# 17,500-unit app took 2 h 45 at 6 workers for 1,917 describes, while ~80 units had changed
# since the previous map. The fix keys each mdl/ output on its unit's ContentsHash (the .mpr Unit
# table) and module/folder path, and re-describes only what changed.
#
# Model, catalog and mxcli are built by fixtures/app-facts-incremental/: the module and one
# microflow are REAL captured units (fixtures/mx-metadata-note, Mendix 11.15.0) and the rest is
# synthetic BSON; the stub mxcli counts describes in a log. See mkmodel.py for what is captured.
#
# Cases, each on BOTH layouts (single-tree, and two-tree with the .mpr under app/):
#   T1  first run describes all candidates (full: no index yet); snapshot + index in manifest
#   T2  second run, nothing changed: 0 describes, every output kept
#   T3  one unit changed: exactly 1 describe, its mdl/ file rewritten
#   T3b a stale Unit-table ContentsHash (file changed, row not) still triggers that 1 describe
#   T4  one unit removed: 0 describes, its mdl/ file and loops.json entry gone
#   T5  a unit moved to a folder (hash unchanged, path changed): 1 describe
#   T6  a describe that fails is not indexed, so the next run retries it
#   T7  incremental outputs are byte-identical to a --full run and to a fresh full run
#   T8  --full re-describes everything; a changed mxcli version forces a full sweep
#   T9  a model whose Unit table cannot be read: full sweep, a reason, never a false incremental
#   T10 --freshness: "fresh", then "N units changed since <date>"; silent with no map
#   T11 bin/status.sh shows the app map line (full screen and --brief); no line without a map
#   T12 the real captured units map to MyFirstModule.MyFirstLogic through mx-metadata-note.py units
#   T13 --freshness and status.sh on 2,101 units (past the 128 KB single-env-var cap)
#   T14 a renamed module: old outputs deleted, every candidate re-described under the new name
#   T15 a --skip-loops run keeps the last loop sweep's snapshot, so freshness is not "fresh"

set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AF="${1:-$TK/project-bin/app-facts.sh}"
case "$AF" in /*) ;; *) AF="$PWD/$AF" ;; esac
SRC="$(cd "$(dirname "$AF")/.." && pwd)"
STATUS="$SRC/bin/status.sh"
FX="$TK/tests/wave2/fixtures/app-facts-incremental"
CAP="$TK/tests/wave2/fixtures/mx-metadata-note"
command -v sqlite3 >/dev/null || { echo "SKIP: sqlite3 not on PATH"; echo "PASS=0 FAIL=0"; exit 0; }
. "$TK/bin/lib/portable.sh"; require_py

W="$(mktemp -d "${TMPDIR:-/tmp}/af-incr.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
jq_() { "$PY" -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("/"):
    d = d.get(k, "MISSING") if isinstance(d, dict) else "MISSING"
print(json.dumps(d) if isinstance(d,(dict,list)) else d)' "$1" "$2"; }

export STUB_VERSION="mxcli stub 1.0"
M=MyFirstModule
SPEC_BASE="MyFirstLogic	1	-	1
SUB_A	1	-	1
SUB_B	1	-	1
SUB_C	1	-	1
SUB_D	1	-	1
ACT_NoLoop	1	-	0"

# model <spec text> : (re)build the model under $MD and the prepared catalog $PREP_DB
model() { printf '%s\n' "$1" > "$W/spec.tsv"; "$PY" "$FX/mkmodel.py" "$MD" "$PREP_DB" "$W/spec.tsv" "$CAP" || bad "mkmodel failed"; }
# run [args] : one app-facts run; describes counted from the stub's log
run() {
  : > "$DESCRIBE_LOG"
  ( cd "$P" && PROJECT_ROOT="$P" MXCLI="$FX/mxcli-stub.sh" PREP_DB="$PREP_DB" DESCRIBE_LOG="$DESCRIBE_LOG" \
      bash "$AF" --workers 3 --facts-dir "$FACTS" "$@" ) > "$W/out" 2>&1
  RC=$?
  NDESC=$(grep -c . "$DESCRIBE_LOG")
}
mdls() { ls "$FACTS/mdl" 2>/dev/null | tr '\n' ' '; }

for layout in single two; do
  echo "== $layout-tree layout"
  P="$W/$layout"; mkdir -p "$P"
  if [ "$layout" = two ]; then MD="$P/app"; else MD="$P"; fi
  PREP_DB="$W/$layout-prep.db"; DESCRIBE_LOG="$W/$layout-describe.log"; FACTS="$P/analysis/app-facts"
  export PREP_DB DESCRIBE_LOG

  # --- T1 first run --------------------------------------------------------------------------
  model "$SPEC_BASE"
  run
  check "[$layout] T1 first run exits 0" "$RC" "0"
  [ "$RC" = 0 ] || { tail -5 "$W/out"; continue; }
  check "[$layout] T1 first run describes all 5 loop microflows" "$NDESC" "5"
  check "[$layout] T1 sweep mode full (no index yet)" "$(jq_ "$FACTS/manifest.json" sections/loops/sweep/mode)" "full"
  check "[$layout] T1 snapshot holds every unit (module + 6 microflows)" "$(jq_ "$FACTS/manifest.json" units/count)" "7"
  check "[$layout] T1 index holds the 5 described outputs" \
    "$("$PY" -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["mdl_index"]))' "$FACTS/manifest.json")" "5"
  check "[$layout] T1 the real captured microflow is indexed by its real UnitID" \
    "$(jq_ "$FACTS/manifest.json" "mdl_index/$M.MyFirstLogic/unit")" "4a8475b3-14cb-4100-8963-58f2fd3a0be8"
  for t in .units.tsv .sweep-plan.json .describe-todo.txt; do
    [ -e "$FACTS/$t" ] && bad "[$layout] T1 temp file $t left behind"
  done

  # --- T2 nothing changed ----------------------------------------------------------------------
  B_MTIME="$(ls -l "$FACTS/mdl/$M.SUB_B.mdl")"
  run
  check "[$layout] T2 unchanged model: 0 describes" "$NDESC" "0"
  check "[$layout] T2 sweep mode incremental" "$(jq_ "$FACTS/manifest.json" sections/loops/sweep/mode)" "incremental"
  check "[$layout] T2 all 5 outputs reused" "$(jq_ "$FACTS/manifest.json" sections/loops/sweep/reused)" "5"
  check "[$layout] T2 loops section still counts 5 described files" "$(jq_ "$FACTS/manifest.json" sections/loops/described)" "5"
  check "[$layout] T2 0 units changed since the previous map" "$(jq_ "$FACTS/manifest.json" units/changed_since_previous_map/changed)" "0"

  # --- T3 one unit changed ----------------------------------------------------------------------
  model "$(printf '%s\n' "$SPEC_BASE" | sed 's/^SUB_B	1/SUB_B	2/')"
  run
  check "[$layout] T3 one changed unit: exactly 1 describe" "$NDESC" "1"
  check "[$layout] T3 the describe was the changed unit" "$(cat "$DESCRIBE_LOG")" "$M.SUB_B"
  grep -q "'v2'" "$FACTS/mdl/$M.SUB_B.mdl" && ok "[$layout] T3 its mdl/ file holds the new version" \
    || bad "[$layout] T3 mdl/ file for the changed unit is stale"
  check "[$layout] T3 manifest counts 1 changed unit" "$(jq_ "$FACTS/manifest.json" units/changed_since_previous_map/changed)" "1"

  # --- T3b a stale Unit-table ContentsHash does not hide a changed unit ------------------------
  # Nothing guarantees a row is rewritten together with its file. Here SUB_B's file changes while
  # its row keeps the hash the last map recorded.
  model "$(printf '%s\n' "$SPEC_BASE" | sed 's/^SUB_B	1/SUB_B	3/')"
  "$PY" - "$MD/App.mpr" "$FACTS/manifest.json" "$M.SUB_B" <<'PY'
import json, sqlite3, sys
man = json.load(open(sys.argv[2])); u = man["mdl_index"][sys.argv[3]]["unit"]
b = bytes.fromhex(u.replace("-", "")); b = b[3::-1] + b[5:3:-1] + b[7:5:-1] + b[8:]
db = sqlite3.connect(sys.argv[1]); db.execute("update Unit set ContentsHash=? where UnitID=?", (man["units"]["snapshot"][u], b)); db.commit()
PY
  run
  check "[$layout] T3b stale table hash, changed file: still 1 describe" "$(cat "$DESCRIBE_LOG")" "$M.SUB_B"
  case "$(jq_ "$FACTS/manifest.json" units/reason)" in *"1 unit(s) whose Unit-table ContentsHash disagrees"*)
    ok "[$layout] T3b the stale row is counted in the manifest" ;;
    *) bad "[$layout] T3b stale row not reported" "$(jq_ "$FACTS/manifest.json" units/reason)" ;; esac
  model "$(printf '%s\n' "$SPEC_BASE" | sed 's/^SUB_B	1/SUB_B	2/')"; run
  check "[$layout] T3b back to v2: 1 describe" "$NDESC" "1"

  # --- T4 one unit removed ----------------------------------------------------------------------
  SPEC_NOW="$(printf '%s\n' "$SPEC_BASE" | sed 's/^SUB_B	1/SUB_B	2/' | grep -v '^SUB_C	')"
  model "$SPEC_NOW"
  run
  check "[$layout] T4 removed unit: 0 describes" "$NDESC" "0"
  [ ! -e "$FACTS/mdl/$M.SUB_C.mdl" ] && ok "[$layout] T4 the removed unit's mdl/ file is deleted" \
    || bad "[$layout] T4 stale mdl/ file kept for a removed unit" "$(mdls)"
  check "[$layout] T4 loops.json no longer lists it" "$(jq_ "$FACTS/loops.json" "microflows/$M.SUB_C")" "MISSING"
  check "[$layout] T4 removed_outputs = 1" "$(jq_ "$FACTS/manifest.json" sections/loops/sweep/removed_outputs)" "1"
  check "[$layout] T4 manifest counts 1 removed unit" "$(jq_ "$FACTS/manifest.json" units/changed_since_previous_map/removed)" "1"

  # --- T5 moved to a folder: same bytes, new path ---------------------------------------------
  SPEC_NOW="$(printf '%s\n' "$SPEC_NOW" | sed 's/^SUB_A	1	-/SUB_A	1	Batch/')"
  model "$SPEC_NOW"
  run
  check "[$layout] T5 moved unit (hash unchanged, folder changed): 1 describe" "$(cat "$DESCRIBE_LOG")" "$M.SUB_A"
  check "[$layout] T5 index records the folder path" "$(jq_ "$FACTS/manifest.json" "mdl_index/$M.SUB_A/path")" "$M/Batch/SUB_A"

  # --- T6 a failed describe is retried ---------------------------------------------------------
  SPEC_NOW="$(printf '%s\n' "$SPEC_NOW" | sed 's/^SUB_D	1/SUB_D	2/')"
  model "$SPEC_NOW"
  STUB_FAIL="$M.SUB_D" run
  check "[$layout] T6 failing describe: loops status partial" "$(jq_ "$FACTS/manifest.json" sections/loops/status)" "partial"
  check "[$layout] T6 the failed unit is not indexed" "$(jq_ "$FACTS/manifest.json" "mdl_index/$M.SUB_D")" "MISSING"
  [ ! -e "$FACTS/mdl/$M.SUB_D.mdl" ] && ok "[$layout] T6 no stale mdl/ file for the failed unit" \
    || bad "[$layout] T6 the old SUB_D output survived a failed re-describe"
  run
  check "[$layout] T6 next run retries exactly the failed unit" "$(cat "$DESCRIBE_LOG")" "$M.SUB_D"
  check "[$layout] T6 loops status back to pass" "$(jq_ "$FACTS/manifest.json" sections/loops/status)" "pass"

  # --- T7 incremental == full -------------------------------------------------------------------
  INC="$W/$layout-inc"; rm -rf "$INC"; cp -R "$FACTS" "$INC"
  FACTS_SAVE="$FACTS"; FACTS="$W/$layout-fresh"; rm -rf "$FACTS"
  run
  check "[$layout] T7 fresh full run describes the 4 current candidates" "$NDESC" "4"
  same=1
  for f in loops.json inventory.json dependencies.json loops-expected.json loops-candidates.tsv loops-scheduled.json; do
    cmp -s "$INC/$f" "$FACTS/$f" || { same=0; bad "[$layout] T7 $f differs between incremental and full"; }
  done
  diff -r "$INC/mdl" "$FACTS/mdl" > "$W/mdl.diff" 2>&1 || { same=0; bad "[$layout] T7 mdl/ differs" "$(head -5 "$W/mdl.diff")"; }
  [ "$same" = 1 ] && ok "[$layout] T7 incremental outputs byte-identical to a fresh full run (mdl/ + 6 fact files)"
  FACTS="$FACTS_SAVE"

  # --- T8 --full and an mxcli upgrade ----------------------------------------------------------
  run --full
  check "[$layout] T8 --full re-describes all 4" "$NDESC" "4"
  check "[$layout] T8 --full recorded as the reason" "$(jq_ "$FACTS/manifest.json" sections/loops/sweep/reason)" "--full"
  diff -r "$INC/mdl" "$FACTS/mdl" >/dev/null 2>&1 && cmp -s "$INC/loops.json" "$FACTS/loops.json" \
    && ok "[$layout] T8 --full in place gives the same outputs as the incremental run" \
    || bad "[$layout] T8 --full in place differs from the incremental outputs"
  STUB_VERSION="mxcli stub 2.0" run
  check "[$layout] T8 mxcli version change: full sweep of all 4" "$NDESC" "4"
  case "$(jq_ "$FACTS/manifest.json" sections/loops/sweep/reason)" in
    "mxcli changed"*) ok "[$layout] T8 reason names the mxcli change" ;;
    *) bad "[$layout] T8 reason does not name the mxcli change" "$(jq_ "$FACTS/manifest.json" sections/loops/sweep/reason)" ;;
  esac

  # --- T10 freshness (before T9 breaks the model) ----------------------------------------------
  fresh() { ( cd "$P" && PROJECT_ROOT="$P" bash "$AF" --freshness --facts-dir "$FACTS" ) 2>&1; }
  case "$(fresh)" in "app map: fresh (built "*) ok "[$layout] T10 freshness says fresh right after a map" ;;
    *) bad "[$layout] T10 freshness after a map" "$(fresh)" ;; esac
  model "$(printf '%s\n' "$SPEC_NOW" | sed 's/^SUB_A	1/SUB_A	3/; s/^MyFirstLogic	1/MyFirstLogic	1/')
NEW_One	1	-	1"
  case "$(fresh)" in "app map: 2 units changed since "2[0-9][0-9][0-9]-*) ok "[$layout] T10 one changed + one added unit: '2 units changed since <date>'" ;;
    *) bad "[$layout] T10 changed-unit count" "$(fresh)" ;; esac
  check "[$layout] T10 no map: silent" "$( (cd "$P" && PROJECT_ROOT="$P" bash "$AF" --freshness --facts-dir "$W/nowhere") 2>&1)" ""

  # --- T11 status.sh -----------------------------------------------------------------------------
  printf '# PROJECT\n\n## Current stage\n**Stage 1 in progress.**\n' > "$P/PROJECT.md"
  if [ "$layout" = single ]; then
    S_FULL="$(bash "$STATUS" "$P" 2>/dev/null)"; S_BRIEF="$(bash "$STATUS" "$P" --brief 2>/dev/null)"
    printf '%s\n' "$S_FULL" | grep -q "app map: 2 units changed since " && ok "[$layout] T11 status.sh full screen shows the app map line" \
      || bad "[$layout] T11 status.sh full screen lacks the app map line" "$(printf '%s\n' "$S_FULL" | head -8)"
    printf '%s\n' "$S_BRIEF" | grep '^STATE' | grep -q "app map: 2 units changed since " && ok "[$layout] T11 status.sh --brief STATE carries it" \
      || bad "[$layout] T11 status.sh --brief lacks the app map" "$S_BRIEF"
    mv "$FACTS/manifest.json" "$W/man.bak"
    bash "$STATUS" "$P" 2>/dev/null | grep -q "app map" && bad "[$layout] T11 status.sh printed an app map line with no map" \
      || ok "[$layout] T11 no map, no app map line"
    mv "$W/man.bak" "$FACTS/manifest.json"
  fi

  # --- T15 --skip-loops keeps the last loop sweep's snapshot -----------------------------------
  # The model has 2 changed units since the map; a --skip-loops run leaves mdl/ stale, so the
  # freshness line must not turn "fresh" (#297 review).
  run --skip-loops
  case "$(fresh)" in "app map: 2 units changed since "*) ok "[$layout] T15 after --skip-loops the line still counts 2 changed units" ;;
    *) bad "[$layout] T15 --skip-loops made a stale loop map read fresh" "$(fresh)" ;; esac
  run
  case "$(fresh)" in "app map: fresh (built "*) ok "[$layout] T15 a loop sweep then makes it fresh" ;;
    *) bad "[$layout] T15 freshness after the loop sweep" "$(fresh)" ;; esac

  # --- T14 module renamed: same UnitIDs and microflow bytes, new qualified names ---------------
  SPEC_REN="$(printf '%s\n' "$SPEC_NOW" | sed 's/^SUB_A	1/SUB_A	3/')
NEW_One	1	-	1"
  MKMODEL_MODULE=Renamed model "$SPEC_REN"
  run
  check "[$layout] T14 renamed module: every loop microflow re-described (5)" "$NDESC" "5"
  check "[$layout] T14 no output left under the old module name" "$(ls "$FACTS/mdl" | grep -c "^$M\.")" "0"
  check "[$layout] T14 5 outputs under the new name" "$(ls "$FACTS/mdl" | grep -c '^Renamed\.')" "5"
  check "[$layout] T14 loops.json lists the new names only" \
    "$("$PY" -c 'import json,sys;print(sorted({k.split(".")[0] for k in json.load(open(sys.argv[1]))["microflows"]}))' "$FACTS/loops.json")" "['Renamed']"

  # --- T9 unreadable Unit table ----------------------------------------------------------------
  P9="$W/$layout-v1"; mkdir -p "$P9"; if [ "$layout" = two ]; then MD9="$P9/app"; else MD9="$P9"; fi
  MD_SAVE="$MD"; P_SAVE="$P"; FACTS_SAVE="$FACTS"
  MD="$MD9"; P="$P9"; FACTS="$P9/analysis/app-facts"
  model "$SPEC_BASE"; : > "$MD/App.mpr"          # an .mpr with no Unit table
  run; run
  check "[$layout] T9 no Unit table: second run is still a full sweep (5 describes)" "$NDESC" "5"
  check "[$layout] T9 units section is a fault, not absent" "$(jq_ "$FACTS/manifest.json" units/status)" "fault"
  case "$(jq_ "$FACTS/manifest.json" sections/loops/sweep/reason)" in "no unit snapshot"*) ok "[$layout] T9 reason: no unit snapshot" ;;
    *) bad "[$layout] T9 reason" "$(jq_ "$FACTS/manifest.json" sections/loops/sweep/reason)" ;; esac
  MD="$MD_SAVE"; P="$P_SAVE"; FACTS="$FACTS_SAVE"
done

# --- T12 the real captured units, through the shared mapping ---------------------------------
echo "== T12 mx-metadata-note.py units on captured units"
MD="$W/t12"; PREP_DB="$W/t12.db"; model "MyFirstLogic	1	-	1"
L="$("$PY" "$SRC/project-bin/mx-metadata-note.py" units "$MD/App.mpr" | grep '^4a8475b3')"
check "T12 real microflow unit -> type, qualified name, path" "$(printf '%s\n' "$L" | cut -f3-5)" \
  "Microflows\$Microflow	MyFirstModule.MyFirstLogic	MyFirstModule/MyFirstLogic"
check "T12 hash is the Unit table's ContentsHash = base64(sha256(.mxunit))" "$(printf '%s\n' "$L" | cut -f2)" \
  "$("$PY" -c 'import base64,hashlib,sys;print(base64.b64encode(hashlib.sha256(open(sys.argv[1],"rb").read()).digest()).decode())' "$CAP/4a8475b3-14cb-4100-8963-58f2fd3a0be8.mxunit")"
check "T12 the module unit itself has no qualified name" \
  "$("$PY" "$SRC/project-bin/mx-metadata-note.py" units "$MD/App.mpr" | grep '^16747dc6' | cut -f3,4)" "Projects\$ModuleImpl	"

# --- T13 --freshness on a model of more than 2,000 units ---------------------------------------
# The unit list once went to Python through one env var, capped at 128 KB on Linux (~1,600 units):
# "Argument list too long", and status.sh, which hides stderr, silently dropped the line.
echo "== T13 --freshness on 2,100 units"
P="$W/big"; MD="$P"; PREP_DB="$W/big.db"; DESCRIBE_LOG="$W/big.log"; FACTS="$P/analysis/app-facts"; mkdir -p "$P"
BIG="$(awk 'BEGIN { for (i = 1; i <= 2100; i++) printf "ACT_%05d\t1\t-\t0\n", i }')"
model "$BIG"; run
check "T13 map of 2,100 units built" "$(jq_ "$FACTS/manifest.json" units/count)" "2101"
F13="$( (cd "$P" && PROJECT_ROOT="$P" bash "$AF" --freshness --facts-dir "$FACTS") 2>&1)"
case "$F13" in "app map: fresh (built "*) ok "T13 2,101 units: freshness says fresh" ;; *) bad "T13 freshness on 2,101 units" "$F13" ;; esac
model "$(printf '%s\n' "$BIG" | sed 's/^ACT_00007	1/ACT_00007	2/')"
F13="$( (cd "$P" && PROJECT_ROOT="$P" bash "$AF" --freshness --facts-dir "$FACTS") 2>&1)"
case "$F13" in "app map: 1 units changed since "*) ok "T13 2,101 units, one changed: counted" ;; *) bad "T13 changed count on 2,101 units" "$F13" ;; esac
printf '# PROJECT\n\n## Current stage\n**Stage 1 in progress.**\n' > "$P/PROJECT.md"
bash "$STATUS" "$P" --brief 2>/dev/null | grep -q "app map: 1 units changed since " && ok "T13 status.sh --brief carries the line on 2,101 units" \
  || bad "T13 status.sh lost the app map line on a large model"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
