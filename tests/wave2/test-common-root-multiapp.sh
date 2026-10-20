#!/usr/bin/env bash
# test-common-root-multiapp.sh — _common.sh's root search stays inside the project (#420).
#
#   usage: bash tests/wave2/test-common-root-multiapp.sh project-bin/_common.sh
#
# The defect: tier 2 and tier 3 of the root search accepted a model only at <root>/ or
# <root>/app/. A multi-app project (apps/<X>/X.mpr) matched neither, so tier 3 kept walking up
# from $PWD and the first ancestor holding ANY .mpr became PROJECT_ROOT; with none above, it fell
# back to the toolkit. look-ledger `seen` rows then landed in that other folder's ledger.
# The fix probes apps/*/ as a third layout and stops the walk at the first project folder (one
# holding .claude/ — not $HOME's — or an installed bin/_common.sh).
#
# Every case runs in its own `env -i` shell with PROJECT_ROOT unset, from a chosen $PWD, through
# a probe script that sources _common.sh the way the instruments do — either an installed copy
# (<project>/bin/) or the shared toolkit copy (<toolkit>/project-bin/). A stray .mpr sits in an
# ancestor of every project, so a walk that climbs past the project is caught, not lucky.
#
#   R1  multi-app under a stray .mpr: installed copy, toolkit copy from the root and from docs/
#   R2  multi-app, nothing above: the project, not the toolkit fallback
#   R3  single tree and R4 two-tree (app/): unchanged — the root, from a subfolder too
#   R5  nested multi-app folders: the inner project from inside it, the outer one from between
#   R6  a project folder with no model yet: the walk stops there; find_mpr fails naming it
#   R7  $HOME's .claude/ is not a project folder: the walk goes on past it (old behaviour)
#   R8  PWD inside one app's folder: that app's folder (state follows the model, as before)
#   R9  find_mpr: one app under apps/ found; two refused with both listed; MPR_FILE picks one
#   R10 bin/check-requirements.sh (same walk): multi-app root named; a model-less project exits 2
set -u

COMMON="${1:?usage: $0 project-bin/_common.sh}"
COMMON="$(cd "$(dirname "$COMMON")" && pwd)/$(basename "$COMMON")"
TK_SRC="$(cd "$(dirname "$COMMON")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/mxtk-root-multiapp.XXXXXX")"
T="$(cd "$T" && pwd)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (want ${3#$T/}, got ${2#$T/})"; fi; }

PROBE='. "$(dirname "$0")/_common.sh"; printf "%s\n" "$PROJECT_ROOT"'
# The shared toolkit copy, in a folder of its own beside the projects.
mkdir -p "$T/tk/project-bin"; cp "$COMMON" "$T/tk/project-bin/_common.sh"
printf '#!/usr/bin/env bash\n%s\n' "$PROBE" > "$T/tk/project-bin/probe.sh"
# install <project> — an installed copy, as init-project.sh lays it out
install() { mkdir -p "$1/bin" "$1/.claude"; cp "$COMMON" "$1/bin/_common.sh"; cp "$T/tk/project-bin/probe.sh" "$1/bin/probe.sh"; }
# root <pwd> <probe script> [HOME] — the PROJECT_ROOT that script resolves from that directory
root() { (cd "$1" && env -i PATH="$PATH" HOME="${3:-$T/nohome}" bash "$2"); }
TKP="$T/tk/project-bin/probe.sh"

echo "== R1 multi-app under a stray .mpr =="
S="$T/r1/stray"; P="$S/proj"; mkdir -p "$P/apps/A" "$P/docs"; : > "$S/stray.mpr"; : > "$P/apps/A/A.mpr"; install "$P"
eq "R1a installed copy, PWD=project"     "$(root "$P" "$P/bin/probe.sh")" "$P"
eq "R1b toolkit copy, PWD=project"       "$(root "$P" "$TKP")" "$P"
eq "R1c toolkit copy, PWD=project/docs"  "$(root "$P/docs" "$TKP")" "$P"

echo "== R2 multi-app, nothing above =="
P="$T/r2/proj"; mkdir -p "$P/apps/A" "$P/docs"; : > "$P/apps/A/A.mpr"; mkdir -p "$P/.claude"
eq "R2 toolkit copy, PWD=project/docs: the project, not the toolkit" "$(root "$P/docs" "$TKP")" "$P"

echo "== R3 single tree / R4 two-tree, unchanged =="
S="$T/r3/stray"; P="$S/proj"; mkdir -p "$P/mdlsource"; : > "$S/stray.mpr"; : > "$P/App.mpr"; install "$P"
eq "R3a single tree, installed copy"        "$(root "$P" "$P/bin/probe.sh")" "$P"
eq "R3b single tree, toolkit copy from mdlsource/" "$(root "$P/mdlsource" "$TKP")" "$P"
S="$T/r4/stray"; P="$S/proj"; mkdir -p "$P/app" "$P/docs"; : > "$S/stray.mpr"; : > "$P/app/App.mpr"; install "$P"
eq "R4a two-tree, installed copy"           "$(root "$P" "$P/bin/probe.sh")" "$P"
eq "R4b two-tree, toolkit copy from docs/"  "$(root "$P/docs" "$TKP")" "$P"
rm -rf "$P/bin" "$P/.claude"
eq "R4c two-tree, unwired (no markers): found by the app/ probe" "$(root "$P/docs" "$TKP")" "$P"

echo "== R5 nested multi-app folders =="
O="$T/r5/outer"; I="$O/work/inner"
mkdir -p "$O/apps/X" "$I/apps/A" "$I/docs" "$O/work/notes"; : > "$O/apps/X/X.mpr"; : > "$I/apps/A/A.mpr"
mkdir -p "$O/.claude" "$I/.claude"
eq "R5a from inside the inner project"      "$(root "$I/docs" "$TKP")" "$I"
eq "R5b from between the two: the outer one" "$(root "$O/work/notes" "$TKP")" "$O"

echo "== R6 project folder, no model yet =="
S="$T/r6/stray"; P="$S/proj"; mkdir -p "$P/docs"; : > "$S/stray.mpr"; install "$P"
eq "R6a walk stops at the project folder"   "$(root "$P/docs" "$TKP")" "$P"
out="$(cd "$P" && env -i PATH="$PATH" HOME="$T/nohome" bash -c ". '$T/tk/project-bin/_common.sh'; find_mpr" 2>&1)"; rc=$?
case "$rc:$out" in 1:*"no .mpr found in $P"*) ok "R6b find_mpr fails naming the project, not the stray" ;; *) fail "R6b find_mpr rc=$rc: $out" ;; esac

echo "== R7 \$HOME's .claude/ is not a project folder =="
H="$T/r7/home"; mkdir -p "$H/.claude" "$H/scratch/sub"; : > "$T/r7/Above.mpr"
eq "R7 walk passes \$HOME and finds the model above it" "$(root "$H/scratch/sub" "$TKP" "$H")" "$T/r7"

echo "== R8 PWD inside one app's folder =="
P="$T/r8/proj"; mkdir -p "$P/apps/A/javasource" "$P/.claude"; : > "$P/apps/A/A.mpr"
eq "R8 apps/A/javasource -> apps/A (the model's own folder)" "$(root "$P/apps/A/javasource" "$TKP")" "$P/apps/A"

echo "== R9 find_mpr in a multi-app folder =="
P="$T/r9/proj"; mkdir -p "$P/apps/A" "$P/.claude"; : > "$P/apps/A/A.mpr"
fm() { (cd "$P" && env -i PATH="$PATH" HOME="$T/nohome" ${1:+MPR_FILE="$1"} bash -c ". '$T/tk/project-bin/_common.sh'; find_mpr; d=\$(find_model_dir) && echo \"dir=\$d\"" 2>&1); }
eq "R9a one app: found, model dir is apps/A" "$(fm)" "$P/apps/A/A.mpr
dir=$P/apps/A"
mkdir -p "$P/apps/B"; : > "$P/apps/B/B.mpr"
out="$(fm)"
case "$out" in *"2 .mpr files"*"apps/A/A.mpr"*"apps/B/B.mpr"*"MPR_FILE=apps/"*) ok "R9b two apps: refused, both listed, MPR_FILE named" ;; *) fail "R9b: $out" ;; esac
eq "R9c MPR_FILE=apps/B/B.mpr picks B (echoed as given, as before)" "$(fm apps/B/B.mpr | head -1)" "apps/B/B.mpr"

echo "== R10 bin/check-requirements.sh uses the same walk =="
CR="$TK_SRC/bin/check-requirements.sh"
S="$T/r10/stray"; P="$S/proj"; mkdir -p "$P/apps/A"; : > "$S/stray.mpr"; : > "$P/apps/A/A.mpr"; mkdir -p "$P/.claude"
out="$(cd "$P" && env -i PATH="$PATH" HOME="$T/nohome" bash "$CR" 2>&1)"
line="$(printf '%s\n' "$out" | grep 'project root' | sed 's/.*project root *//; s/ *$//')"
eq "R10a multi-app root reported, not the stray" "$line" "$P"
rm -f "$P/apps/A/A.mpr"
out="$(cd "$P" && env -i PATH="$PATH" HOME="$T/nohome" bash "$CR" 2>&1)"; rc=$?
case "$rc:$out" in 2:*"stopped at the project folder $P"*) ok "R10b model-less project: exit 2, names where the walk stopped" ;; *) fail "R10b rc=$rc: $out" ;; esac

echo
echo "root-multiapp: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
