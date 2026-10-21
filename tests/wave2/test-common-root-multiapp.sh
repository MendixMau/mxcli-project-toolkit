#!/usr/bin/env bash
# test-common-root-multiapp.sh — _common.sh's root search stays inside the project (#420).
#
#   usage: bash tests/wave2/test-common-root-multiapp.sh project-bin/_common.sh
#
# The defect: tier 2 and tier 3 of the root search accepted a model only at <root>/ or
# <root>/app/. A multi-app project (apps/<X>/X.mpr) matched neither, so tier 3 kept walking up
# from $PWD and the first ancestor holding ANY .mpr became PROJECT_ROOT; with none above, it fell
# back to the toolkit. look-ledger `seen` rows then landed in that other folder's ledger.
# The fix probes apps/*/ as a third layout and stops the walk at the first project folder (an
# installed bin/_common.sh, or .claude/ beside PROJECT.md — not in $HOME).
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
#   R8  PWD inside one app's folder: the project when it is marked (#489), else the app folder
#   R9  find_mpr: one app under apps/ found; two refused with both listed; MPR_FILE picks one
#       (as an absolute path); from inside one app's folder, that app; outside any, refused
#   R10 bin/check-requirements.sh (same walk): multi-app root named; a model-less project exits 2
#   R11 a bare .claude/ (no PROJECT.md) is not a project folder: a stray /tmp/.claude above an
#       unmarked project must not capture the walk; the old self-parent fallback still applies
#   The consumers that probe for the model themselves, in the apps/<X>/ layout:
#   R12 model-stamp.sh check, one app: a staged model reaches the stamp check (not "no .mpr
#       resolves"); nothing staged still passes `check --staged`
#   R13 model-stamp.sh check, two apps: nothing staged passes (a multi-app folder must not block
#       every commit); staged under one app is checked against that app; across two refuses
#       with "one app at a time"; MPR_FILE=apps/A with A and B staged refuses naming apps/B (the
#       stamp covers A only); MPR_FILE=apps/A with only A staged and A stamped passes
#   R14 lint-gate.sh: one app gets past model discovery; two apps refuse naming MPR=apps/<X>
#   R15 doctor.sh <project>: reports the app's model, and names MPR_FILE when there are two
#   R16 a model-less git worktree under <project>/.claude/worktrees/<w> (it carries its own
#       bin/_common.sh) resolves to the worktree, no longer to the main project above it
#   R17 PWD in app/, app/javasource, apps/A, apps/A/javasource of a marked project: the
#       installed and toolkit copies both answer the project (#489); unmarked, the app folder;
#       an app folder that is a project of its own keeps its root (g, h); any letter case (i, j)
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
# wire <dir> — the .claude/ + PROJECT.md pair init-project.sh writes
wire() { mkdir -p "$1/.claude"; : > "$1/PROJECT.md"; }
# install <project> — an installed copy, as init-project.sh lays it out
install() { mkdir -p "$1/bin"; wire "$1"; cp "$COMMON" "$1/bin/_common.sh"; cp "$T/tk/project-bin/probe.sh" "$1/bin/probe.sh"; }
# root <pwd> <probe script> [HOME] — the PROJECT_ROOT that script resolves from that directory
root() { (cd "$1" && env -i PATH="$PATH" HOME="${3:-$T/nohome}" bash "$2"); }
TKP="$T/tk/project-bin/probe.sh"

echo "== R1 multi-app under a stray .mpr =="
S="$T/r1/stray"; P="$S/proj"; mkdir -p "$P/apps/A" "$P/docs"; : > "$S/stray.mpr"; : > "$P/apps/A/A.mpr"; install "$P"
eq "R1a installed copy, PWD=project"     "$(root "$P" "$P/bin/probe.sh")" "$P"
eq "R1b toolkit copy, PWD=project"       "$(root "$P" "$TKP")" "$P"
eq "R1c toolkit copy, PWD=project/docs"  "$(root "$P/docs" "$TKP")" "$P"

echo "== R2 multi-app, nothing above =="
P="$T/r2/proj"; mkdir -p "$P/apps/A" "$P/docs"; : > "$P/apps/A/A.mpr"; wire "$P"
eq "R2 toolkit copy, PWD=project/docs: the project, not the toolkit" "$(root "$P/docs" "$TKP")" "$P"

echo "== R3 single tree / R4 two-tree, unchanged =="
S="$T/r3/stray"; P="$S/proj"; mkdir -p "$P/mdlsource"; : > "$S/stray.mpr"; : > "$P/App.mpr"; install "$P"
eq "R3a single tree, installed copy"        "$(root "$P" "$P/bin/probe.sh")" "$P"
eq "R3b single tree, toolkit copy from mdlsource/" "$(root "$P/mdlsource" "$TKP")" "$P"
S="$T/r4/stray"; P="$S/proj"; mkdir -p "$P/app" "$P/docs"; : > "$S/stray.mpr"; : > "$P/app/App.mpr"; install "$P"
eq "R4a two-tree, installed copy"           "$(root "$P" "$P/bin/probe.sh")" "$P"
eq "R4b two-tree, toolkit copy from docs/"  "$(root "$P/docs" "$TKP")" "$P"
rm -rf "$P/bin" "$P/.claude" "$P/PROJECT.md"
eq "R4c two-tree, unwired (no markers): found by the app/ probe" "$(root "$P/docs" "$TKP")" "$P"

echo "== R5 nested multi-app folders =="
O="$T/r5/outer"; I="$O/work/inner"
mkdir -p "$O/apps/X" "$I/apps/A" "$I/docs" "$O/work/notes"; : > "$O/apps/X/X.mpr"; : > "$I/apps/A/A.mpr"
wire "$O"; wire "$I"
eq "R5a from inside the inner project"      "$(root "$I/docs" "$TKP")" "$I"
eq "R5b from between the two: the outer one" "$(root "$O/work/notes" "$TKP")" "$O"

echo "== R6 project folder, no model yet =="
S="$T/r6/stray"; P="$S/proj"; mkdir -p "$P/docs"; : > "$S/stray.mpr"; install "$P"
eq "R6a walk stops at the project folder"   "$(root "$P/docs" "$TKP")" "$P"
out="$(cd "$P" && env -i PATH="$PATH" HOME="$T/nohome" bash -c ". '$T/tk/project-bin/_common.sh'; find_mpr" 2>&1)"; rc=$?
case "$rc:$out" in 1:*"no .mpr found in $P"*) ok "R6b find_mpr fails naming the project, not the stray" ;; *) fail "R6b find_mpr rc=$rc: $out" ;; esac

echo "== R7 \$HOME's .claude/ is not a project folder =="
H="$T/r7/home"; mkdir -p "$H/scratch/sub"; wire "$H"; : > "$T/r7/Above.mpr"
eq "R7 walk passes \$HOME and finds the model above it" "$(root "$H/scratch/sub" "$TKP" "$H")" "$T/r7"

echo "== R8 PWD inside one app's folder =="
P="$T/r8/proj"; mkdir -p "$P/apps/A/javasource"; wire "$P"; : > "$P/apps/A/A.mpr"
eq "R8a apps/A/javasource, project marked -> the project (#489)" "$(root "$P/apps/A/javasource" "$TKP")" "$P"
rm -rf "$P/.claude" "$P/PROJECT.md"
eq "R8b apps/A/javasource, no marker -> apps/A (the model's own folder, as before)" "$(root "$P/apps/A/javasource" "$TKP")" "$P/apps/A"

echo "== R9 find_mpr in a multi-app folder =="
P="$T/r9/proj"; mkdir -p "$P/apps/A"; wire "$P"; : > "$P/apps/A/A.mpr"
fm() { (cd "$P" && env -i PATH="$PATH" HOME="$T/nohome" ${1:+MPR_FILE="$1"} bash -c ". '$T/tk/project-bin/_common.sh'; find_mpr; d=\$(find_model_dir) && echo \"dir=\$d\"" 2>&1); }
eq "R9a one app: found, model dir is apps/A" "$(fm)" "$P/apps/A/A.mpr
dir=$P/apps/A"
mkdir -p "$P/apps/B"; : > "$P/apps/B/B.mpr"
out="$(fm)"
case "$out" in *"2 .mpr files"*"apps/A/A.mpr"*"apps/B/B.mpr"*"MPR_FILE=apps/"*) ok "R9b two apps: refused, both listed, MPR_FILE named" ;; *) fail "R9b: $out" ;; esac
eq "R9c MPR_FILE=apps/B/B.mpr picks B, as an absolute path (#489 review)" "$(fm apps/B/B.mpr | head -1)" "$P/apps/B/B.mpr"
# R9d: two apps, MPR_FILE unset, the session inside one app's folder: that app (#489 review)
fmin() { (cd "$1" && env -i PATH="$PATH" HOME="$T/nohome" bash -c ". '$T/tk/project-bin/_common.sh'; find_mpr" 2>&1); }
mkdir -p "$P/apps/A/javasource" "$P/docs"
eq "R9d two apps, PWD=apps/A/javasource: apps/A's model" "$(fmin "$P/apps/A/javasource")" "$P/apps/A/A.mpr"
case "$(fmin "$P/docs")" in *"2 .mpr files"*"MPR_FILE=apps/"*) ok "R9e two apps, PWD=docs/ (in no app): still refused" ;; *) fail "R9e: $(fmin "$P/docs")" ;; esac
# R9f: a cwd-relative MPR_FILE still names the model after the caller cd's to the root (exec.sh)
out="$(cd "$P/apps" && env -i PATH="$PATH" HOME="$T/nohome" MPR_FILE=A/A.mpr bash -c ". '$T/tk/project-bin/_common.sh'; m=\$(find_mpr) && cd \"\$PROJECT_ROOT\" && [ -f \"\$m\" ] && echo \"\$m\"" 2>&1)"
eq "R9f MPR_FILE=A/A.mpr from apps/: absolute, survives cd to the root" "$out" "$P/apps/A/A.mpr"

echo "== R10 bin/check-requirements.sh uses the same walk =="
CR="$TK_SRC/bin/check-requirements.sh"
S="$T/r10/stray"; P="$S/proj"; mkdir -p "$P/apps/A"; : > "$S/stray.mpr"; : > "$P/apps/A/A.mpr"; wire "$P"
out="$(cd "$P" && env -i PATH="$PATH" HOME="$T/nohome" bash "$CR" 2>&1)"
line="$(printf '%s\n' "$out" | grep 'project root' | sed 's/.*project root *//; s/ *$//')"
eq "R10a multi-app root reported, not the stray" "$line" "$P"
rm -f "$P/apps/A/A.mpr"
out="$(cd "$P" && env -i PATH="$PATH" HOME="$T/nohome" bash "$CR" 2>&1)"; rc=$?
case "$rc:$out" in 2:*"stopped at the project folder $P"*) ok "R10b model-less project: exit 2, names where the walk stopped" ;; *) fail "R10b rc=$rc: $out" ;; esac

echo "== R11 a bare .claude/ is not a project folder =="
B="$T/r11/tmpish"; P="$B/work/proj"; mkdir -p "$B/.claude" "$P/project-bin"
cp "$COMMON" "$P/project-bin/_common.sh"; cp "$TKP" "$P/project-bin/probe.sh"
eq "R11a unmarked project under a bare .claude/: self-parent fallback, as before" "$(root "$P" "$P/project-bin/probe.sh")" "$P"
: > "$T/r11/Up.mpr"
eq "R11b ... and a model above the bare .claude/ is still found, as before" "$(root "$P" "$P/project-bin/probe.sh")" "$T/r11"

echo "== R12/R13 model-stamp.sh check in a multi-app folder =="
TKB="$TK_SRC/project-bin"
mkms() {  # mkms <dir> <app>... — a git project with an installed model-stamp.sh and the apps
  local d="$1" a; shift; mkdir -p "$d/bin"; wire "$d"
  cp "$COMMON" "$d/bin/_common.sh"; cp "$TKB/model-stamp.sh" "$d/bin/"
  for a in "$@"; do mkdir -p "$d/apps/$a/mprcontents"; echo m > "$d/apps/$a/$a.mpr"; echo u > "$d/apps/$a/mprcontents/u.mxunit"; done
  ( cd "$d" && git init -q . && git -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init )
}
ms() { (cd "$1" && shift && env -i PATH="$PATH" HOME="$T/nohome" bash bin/model-stamp.sh "$@" 2>&1); }
P="$T/r12/proj"; mkms "$P" A
out="$(ms "$P" check --staged)"; rc=$?
case "$rc:$out" in 0:*"no model files staged"*) ok "R12a one app, nothing staged: check --staged passes" ;; *) fail "R12a rc=$rc: $out" ;; esac
(cd "$P" && git add apps)
out="$(ms "$P" check --staged)"; rc=$?
case "$out" in *"no .mpr resolves"*) fail "R12b staged model still reads as no model: $out" ;;
  *UNVERIFIED*) ok "R12b one app, model staged: reaches the stamp check (UNVERIFIED, rc $rc)" ;; *) fail "R12b rc=$rc: $out" ;; esac
P="$T/r13/proj"; mkms "$P" A B
out="$(ms "$P" check --staged)"; rc=$?
case "$rc:$out" in 0:*) ok "R13a two apps, nothing staged: check --staged passes" ;; *) fail "R13a rc=$rc: $out" ;; esac
out="$(ms "$P" check)"; rc=$?
case "$rc:$out" in 0:*"several apps"*) ok "R13b two apps, nothing staged: plain check passes and says why" ;; *) fail "R13b rc=$rc: $out" ;; esac
(cd "$P" && git add apps/A)
out="$(ms "$P" check --staged)"; rc=$?
case "$out" in *UNVERIFIED*) ok "R13c staged under apps/A only: checked against apps/A (UNVERIFIED, rc $rc)" ;; *) fail "R13c rc=$rc: $out" ;; esac
(cd "$P" && git add apps/B)
out="$(ms "$P" check --staged)"; rc=$?
case "$rc:$out" in 1:*"one app at a time"*"git reset apps/"*) ok "R13d staged across two apps: refused, one app at a time" ;; *) fail "R13d rc=$rc: $out" ;; esac
msA() { (cd "$P" && env -i PATH="$PATH" HOME="$T/nohome" MPR_FILE=apps/A/A.mpr bash bin/model-stamp.sh "$@" 2>&1); }
msA write pass fixture >/dev/null
out="$(msA check --staged)"; rc=$?
case "$rc:$out" in 1:*"covers apps/A/ only"*"apps/B/"*) ok "R13e MPR_FILE=apps/A, A and B staged: refused, apps/B paths named" ;; *) fail "R13e rc=$rc: $out" ;; esac
(cd "$P" && git reset -q apps/B)
out="$(msA check --staged)"; rc=$?
case "$rc" in 0) ok "R13f MPR_FILE=apps/A, only A staged (and stamped): passes" ;; *) fail "R13f rc=$rc: $out" ;; esac

echo "== R14 lint-gate.sh model discovery in a multi-app folder =="
P="$T/r14/proj"; mkdir -p "$P/bin" "$P/apps/A"; wire "$P"; : > "$P/apps/A/A.mpr"
cp "$COMMON" "$P/bin/_common.sh"; cp "$TKB/lint-gate.sh" "$P/bin/"
out="$(cd "$P" && env -i PATH="$PATH" HOME="$T/nohome" bash bin/lint-gate.sh 2>&1)"
case "$out" in *"no .mpr found"*) fail "R14a one app: lint-gate found no model: $out" ;; *) ok "R14a one app: lint-gate gets past model discovery" ;; esac
mkdir -p "$P/apps/B"; : > "$P/apps/B/B.mpr"
out="$(cd "$P" && env -i PATH="$PATH" HOME="$T/nohome" bash bin/lint-gate.sh 2>&1)"; rc=$?
case "$rc:$out" in 2:*"MPR=apps/"*"apps/A/A.mpr"*"apps/B/B.mpr"*) ok "R14b two apps: refused (rc 2), both listed" ;; *) fail "R14b rc=$rc: $out" ;; esac

echo "== R15 doctor.sh <project> in a multi-app folder =="
P="$T/r15/proj"; mkdir -p "$P/apps/A" "$P/apps/B"; : > "$P/apps/A/A.mpr"
out="$(env -i PATH="$PATH" HOME="$T/nohome" bash "$TK_SRC/bin/doctor.sh" "$P" 2>&1)"
case "$out" in *"model: apps/A/A.mpr"*) ok "R15a one app: model reported" ;; *) fail "R15a: $(printf '%s' "$out" | grep -i 'mpr' | head -3)" ;; esac
: > "$P/apps/B/B.mpr"
out="$(env -i PATH="$PATH" HOME="$T/nohome" bash "$TK_SRC/bin/doctor.sh" "$P" 2>&1)"
case "$out" in *"multi-app folder: apps/A/A.mpr, apps/B/B.mpr"*MPR_FILE*) ok "R15b two apps: both named, MPR_FILE pointed at" ;; *) fail "R15b: $(printf '%s' "$out" | grep -i 'mpr' | head -3)" ;; esac
out="$(env -i PATH="$PATH" HOME="$T/nohome" bash "$TK_SRC/bin/doctor.sh" --property-sets "$P" 2>&1)"
case "$out" in *"checking apps/A/A.mpr only"*"MPR_FILE="*) ok "R15c --property-sets, two apps: says which app it checked" ;; *) fail "R15c: $(printf '%s' "$out" | head -5)" ;; esac

echo "== R16 a model-less worktree under .claude/worktrees/ =="
P="$T/r16/proj"; W="$P/.claude/worktrees/w"; install "$P"; : > "$P/App.mpr"; install "$W"; mkdir -p "$W/docs"
eq "R16 toolkit copy from the worktree's docs/: the worktree" "$(root "$W/docs" "$TKP")" "$W"

echo "== R17 PWD inside an app folder: installed and toolkit copies agree (#489) =="
# Before #489 the toolkit copy stopped at the folder holding the model, the installed copy
# (tier 2) answered the project, and the two wrote their ledgers to different roots.
both() {  # both <label> <project> <pwd>
  eq "$1, installed copy" "$(root "$3" "$2/bin/probe.sh")" "$2"
  eq "$1, toolkit copy"   "$(root "$3" "$TKP")" "$2"
}
S="$T/r17/stray"; P="$S/two"; mkdir -p "$P/app/javasource"; : > "$S/stray.mpr"; : > "$P/app/App.mpr"; install "$P"
both "R17a two-tree, PWD=app/"            "$P" "$P/app"
both "R17b two-tree, PWD=app/javasource"  "$P" "$P/app/javasource"
P="$S/multi"; mkdir -p "$P/apps/A/javasource" "$P/apps/B"; : > "$P/apps/A/A.mpr"; : > "$P/apps/B/B.mpr"; install "$P"
both "R17c multi-app, PWD=apps/A"            "$P" "$P/apps/A"
both "R17d multi-app, PWD=apps/A/javasource" "$P" "$P/apps/A/javasource"
P="$S/single"; mkdir -p "$P/javasource"; : > "$P/App.mpr"; install "$P"
both "R17e single tree, PWD=javasource (unchanged)" "$P" "$P/javasource"
# R17g: a project nested at apps/X (its own install, .claude/, PROJECT.md, model) inside a
# marked project keeps its own root
P="$S/outer"; X="$P/apps/X"; install "$P"; mkdir -p "$X/javasource"; : > "$X/X.mpr"; install "$X"
both "R17g nested project at apps/X, PWD=apps/X/javasource" "$X" "$X/javasource"
# R17h: app/ is a wired project of its own (PROJECT.md + .claude/ + its install), parent marked
P="$S/wiredapp"; install "$P"; mkdir -p "$P/app/javasource"; : > "$P/app/App.mpr"; install "$P/app"
both "R17h app/ wired as its own project, PWD=app/javasource" "$P/app" "$P/app/javasource"
rm -rf "$P/app/bin"
eq "R17h2 ... marked by .claude/ + PROJECT.md only: toolkit copy keeps app/" "$(root "$P/app/javasource" "$TKP")" "$P/app"
# R17i: the app folder's letter case does not matter (App/ on a case-insensitive disk)
P="$S/case"; mkdir -p "$P/App/javasource" "$P/Apps/A/javasource"; : > "$P/App/App.mpr"; install "$P"
eq "R17i App/javasource (capital A): the project" "$(root "$P/App/javasource" "$TKP")" "$P"
rm -rf "$P/App"; : > "$P/Apps/A/A.mpr"
eq "R17j Apps/A/javasource (capital A): the project" "$(root "$P/Apps/A/javasource" "$TKP")" "$P"
P="$T/r17/bare"; mkdir -p "$P/app/javasource"; : > "$P/app/App.mpr"
eq "R17f two-tree, no marker, PWD=app/javasource: app/ (the model's folder, as before)" "$(root "$P/app/javasource" "$TKP")" "$P/app"

echo
echo "root-multiapp: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
