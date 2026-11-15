#!/usr/bin/env bash
# test-runtime-complete.sh — project-bin/_common.sh: mxtk_runtime_gaps / _problems / _sp_runtime / _report (#692).
#
# Usage: bash tests/wave2/test-runtime-complete.sh [path-to-_common.sh]
#
# WHY (#692, field run 2026-11): mxcli accepts a cached runtime when runtime/launcher/runtimelauncher.jar exists;
# a cache without bundles/org.osgi*.jar then dies at startup (NoClassDefFoundError org/osgi/service/event/
# EventHandler) with no test verdict. The toolkit now names such a cache, what it lacks, and the repair, and
# never blocks. GOLDEN INPUT: fixtures/runtime-layout-11.13.0.txt is `find runtime -maxdepth 3` of a REAL cached
# runtime (a mxcli-downloaded 11.13.0; it holds bundles/org.osgi.osgi.cmpn.jar). Directories are rebuilt from it
# here (empty files). The incomplete layouts are that listing with the file removed — the issue's own symptom.
# macOS Studio Pro path (Contents/runtime) is exercised through a stubbed mxtk_sp_list: NOT RUN on a real Mac.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/_common.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
LIST="$TOOLKIT/tests/wave2/fixtures/runtime-layout-11.13.0.txt"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/rtcomplete.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — missing '$3' in: $(printf '%s' "$2" | tail -3)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — found '$3'" ;; *) ok "$1" ;; esac; }
echo "== subject: $SUBJECT"
export PROJECT_ROOT="$WORK/none"; mkdir -p "$PROJECT_ROOT"
# shellcheck disable=SC1090
. "$SUBJECT"

build() {  # $1 = target dir that becomes <v>/ ; lays out the captured listing under it
  local p; mkdir -p "$1"
  while IFS= read -r p; do case "$p" in *.jar|*.txt|*.properties|*.json|*.xml) mkdir -p "$1/$(dirname "$p")"; : > "$1/$p" ;; *) mkdir -p "$1/$p" ;; esac; done < "$LIST"
}
# the OLD acceptance rule (mxcli's own, per the issue): the launcher jar exists
old_accepts() { [ -f "$1/launcher/runtimelauncher.jar" ]; }

export MXTK_MXCLI_HOME="$WORK/home"
build "$MXTK_MXCLI_HOME/runtime/11.13.0"
R="$MXTK_MXCLI_HOME/runtime/11.13.0/runtime"
[ -f "$R/bundles/org.osgi.osgi.cmpn.jar" ] && ok "[setup] golden layout carries org.osgi.osgi.cmpn.jar" || bad "[setup] golden layout has no org.osgi jar"

echo "-- complete runtime: old and new agree, no output"
old_accepts "$R" && ok "old: accepted" || bad "old rejected"
OUT="$(mxtk_runtime_gaps "$R")"; RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "new: complete, silent" || bad "new flagged a complete runtime: $OUT"
OUT="$(mxtk_runtime_report 11.13.0 '!')"; RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "report: silent, rc 0" || bad "report printed for a complete runtime"
OUT="$(mxtk_runtime_problems)"; [ -z "$OUT" ] && ok "problems (no version): silent" || bad "$OUT"
N=0; S=$(date +%s); while [ "$N" -lt 200 ]; do mxtk_runtime_problems 11.13.0 >/dev/null; N=$((N+1)); done; E=$(date +%s)
echo "  info — 200 complete-runtime checks: $((E-S)) s"

echo "-- incomplete: no org.osgi jar (the issue's case)"
rm -f "$R"/bundles/org.osgi*.jar
old_accepts "$R" && ok "old: still ACCEPTED (the defect)" || bad "old rejected?"
OUT="$(mxtk_runtime_gaps "$R")"; RC=$?
[ "$RC" -eq 1 ] && [ "$OUT" = "bundles/org.osgi*.jar" ] && ok "new: refused, names bundles/org.osgi*.jar" || bad "rc=$RC out=$OUT"
OUT="$(mxtk_runtime_report 11.13.0 '!')"; RC=$?
[ "$RC" -eq 1 ] && ok "report rc 1" || bad "report rc $RC"
has "report names the dir" "$OUT" "incomplete Mendix runtime: $R"
has "report names what is missing" "$OUT" "missing: bundles/org.osgi*.jar"
has "report names the repair command" "$OUT" "mxcli setup mxruntime -p"
hasnt_() { case "$1" in *"$2"*) bad "unexpected: $2" ;; *) ok "no: $2" ;; esac; }
hasnt_ "$OUT" "UNVERIFIED"
[ "$(printf '%s\n' "$OUT" | grep -vc '^!')" = 0 ] && ok "every line carries the prefix" || bad "unprefixed line in report"
mxtk_runtime_problems 11.9.0 >/dev/null && ok "another version's cache is not looked at" || bad "checked the wrong version"

echo "-- incomplete: no bundles dir, launcher only (the issue's 'a cache containing only a launcher')"
rm -rf "$R/bundles"
OUT="$(mxtk_runtime_gaps "$R")"; has "bundles/ named" "$OUT" "bundles/"
rm -rf "$R/launcher"
OUT="$(mxtk_runtime_gaps "$R" | tr '\n' ' ')"; has "launcher named too" "$OUT" "launcher/runtimelauncher.jar"

echo "-- the mxbuild runtime link is checked too"
build "$WORK/home2/runtime/11.13.0"; mkdir -p "$WORK/home2/mxbuild/11.13.0"
cp -R "$WORK/home2/runtime/11.13.0/runtime" "$WORK/home2/mxbuild/11.13.0/runtime"
rm -f "$WORK/home2/mxbuild/11.13.0/runtime"/bundles/org.osgi*.jar
OUT="$(MXTK_MXCLI_HOME="$WORK/home2" mxtk_runtime_problems 11.13.0)"; RC=$?
[ "$RC" -eq 1 ] && has "stale mxbuild/<v>/runtime named" "$OUT" "mxbuild/11.13.0/runtime|bundles/org.osgi*.jar" || bad "not detected (rc $RC)"
hasnt "the complete runtime/<v> is not named" "$OUT" "home2/runtime"
OUT="$(MXTK_MXCLI_HOME="$WORK/home2" mxtk_runtime_report 11.13.0 '!')"
has "mxbuild-dir repair names setup mxbuild" "$OUT" "mxcli setup mxbuild -p"
hasnt_ "$OUT" "setup mxruntime"

echo "-- Studio Pro runtime (macOS path, stubbed mxtk_sp_list; NOT RUN on a real Mac)"
SPA="$WORK/Mendix Studio Pro 11.13.0.app"; build "$SPA/Contents"
mxtk_sp_list() { printf '%s\n' "$SPA"; }
OUT="$(MXTK_PLATFORM=macos mxtk_sp_runtime 11.13.0)"; RC=$?
[ "$RC" -eq 0 ] && [ "$OUT" = "$SPA/Contents/runtime" ] && ok "complete matching SP runtime found" || bad "rc=$RC $OUT"
MXTK_PLATFORM=macos mxtk_sp_runtime 11.12.2 >/dev/null && bad "wrong-version SP runtime offered" || ok "other version not offered"
MXTK_PLATFORM=linux mxtk_sp_runtime 11.13.0 >/dev/null && bad "linux invented an SP path" || ok "linux: nothing (no location named)"
MXTK_PLATFORM=windows mxtk_sp_runtime 11.13.0 >/dev/null && bad "windows invented an SP path" || ok "windows: nothing (no location named)"
OUT="$(MXTK_PLATFORM=macos mxtk_runtime_report 11.13.0 '!')"
has "report points at the SP runtime" "$OUT" "matching complete Studio Pro runtime: $SPA/Contents/runtime"
has "report still names the incomplete cache" "$OUT" "incomplete Mendix runtime"
rm -f "$SPA"/Contents/runtime/bundles/org.osgi*.jar
MXTK_PLATFORM=macos mxtk_sp_runtime 11.13.0 >/dev/null && bad "incomplete SP runtime offered" || ok "an incomplete SP runtime is not offered"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
