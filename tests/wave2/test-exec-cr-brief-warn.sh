#!/usr/bin/env bash
# Fixture for exec.sh's CR brief advisory (2026-10-16).
#
# usage: bash tests/wave2/test-exec-cr-brief-warn.sh [/path/to/exec.sh]
#
# WHY. `exec.sh --cr CR-NN` tagged the BUILD-LOG but never asked whether the module's brief knew
# about the change, so a CR could be built while the brief (the mdl-agent's per-module input)
# stayed stale. exec.sh now WARNs, never blocks, when the brief of a module the script writes to
# does not mention the CR id. Both brief forms count: architecture/modules/<M>/module-brief.md and
# a "## Module brief - <M>" section of architecture/build-plan.md.
#
# Cases: folder brief lacking the id (warn), folder brief with the id (no warn), merged brief
# lacking / holding the id (warn / no warn), a different module's section holding the id (warn),
# CR-1 vs CR-12 (no prefix match), no --cr (no warn), no brief at all (only the old advisory).
set -uo pipefail

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
EXEC_SH="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$EXEC_SH" in /*) ;; *) EXEC_SH="$PWD/$EXEC_SH" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/exec-crw.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
echo "== subject: $EXEC_SH"

mkproj() {  # $1 = dir
  local P="$1"; mkdir -p "$P/bin" "$P/mprcontents/84/77" "$P/architecture" "$WORK/jdk/bin"
  printf 'not a real model\n' > "$P/Fixture.mpr"
  printf 'bson\n' > "$P/mprcontents/84/77/84776610-13b2-48cb-a265-d5e984d63129.mxunit"
  cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
  cp "$EXEC_SH" "$P/bin/exec.sh"
  cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
mkdir -p "$D"; cp Fixture.mpr "$D/Fixture.mpr"; cp -r mprcontents "$D/mprcontents"
echo "Snapshot saved: $D"
SNAP
  chmod +x "$P/bin/"*.sh
  printf '#!/usr/bin/env bash\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli"
  printf 'CREATE ENTITY Orders.Thing (Name: String(50));\n' > "$P/script.mdl"
  printf '# Build plan\n\n### Phase 1\n| # | Kind | Step |\n|---|---|---|\n| 1 | BRIEF | Orders |\n' > "$P/architecture/build-plan.md"
}
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --write-errors=*) printf '{"problems":[]}' > "${a#--write-errors=}" ;; esac; done
exit 0
MXB
mkdir -p "$WORK/jdk/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/jdk/bin/java"; chmod +x "$WORK/mxbuild" "$WORK/jdk/bin/java"

run() {  # $1 = project dir, rest = exec.sh args; output in $WORK/out
  local P="$1"; shift
  ( cd "$P" && git init -q . 2>/dev/null; git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm fx >/dev/null 2>&1
    mkdir -p "$WORK/tmp"
    TMPDIR="$WORK/tmp" SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXBUILD_PATH="$WORK/mxbuild" \
      JAVA_HOME="$WORK/jdk" ./bin/exec.sh "$@" ) > "$WORK/out" 2>&1
  return $?
}
warned() { grep -q "WARN: the brief of $1 does not mention $2" "$WORK/out"; }
# The exec.sh under test must reach the brief advisory at all, or every "no warn" case is vacuous.
reached() { grep -q "Change request: \|No module brief for" "$WORK/out"; }

folder() {  # $1=proj  $2=text
  mkdir -p "$1/architecture/modules/Orders"
  printf '# Module brief: Orders\n\n### Build steps\n| Step | What |\n|---|---|\n%s\n' "$2" > "$1/architecture/modules/Orders/module-brief.md"
}

echo "== folder brief lacking the id: warns"
P="$WORK/a"; mkproj "$P"; folder "$P" "| 1 | base |"
run "$P" --cr CR-07 script.mdl; RC=$?
warned Orders CR-07 && ok "warn names module and CR" || bad "no warn" "$(head -30 "$WORK/out")"
grep -q "Add a CR-07 tagged Build steps row" "$WORK/out" && ok "warn tells what to add" || bad "advice missing"
[ "$RC" -eq 0 ] && ok "non-fatal (exit 0)" || bad "rc=$RC" "$(tail -15 "$WORK/out")"

echo "== folder brief holding the id: silent"
P="$WORK/b"; mkproj "$P"; folder "$P" "| CR-07-1 | VAT field |"
run "$P" --cr CR-07 script.mdl; RC=$?
reached && ok "advisory block reached" || bad "advisory not reached" "$(head -20 "$WORK/out")"
warned Orders CR-07 && bad "warned although the brief has CR-07" || ok "no warn"
[ "$RC" -eq 0 ] && ok "exit 0" || bad "rc=$RC"

echo "== CR-1 does not match CR-12 in the brief"
P="$WORK/c"; mkproj "$P"; folder "$P" "| CR-12-1 | other |"
run "$P" --cr CR-1 script.mdl
warned Orders CR-1 && ok "CR-1 warned, CR-12 is another change" || bad "prefix matched" "$(head -20 "$WORK/out")"

echo "== no --cr: silent"
P="$WORK/d"; mkproj "$P"; folder "$P" "| 1 | base |"
run "$P" script.mdl; RC=$?
grep -q "does not mention" "$WORK/out" && bad "warned without --cr" || ok "no warn without --cr"
[ "$RC" -eq 0 ] && ok "exit 0" || bad "rc=$RC"

echo "== merged brief in build-plan.md"
P="$WORK/e"; mkproj "$P"
printf '\n## Module brief - Orders\n\n### Build steps\n| Step | What |\n|---|---|\n| 1 | base |\n\n## Module brief - Billing\n\n| CR-07-1 | elsewhere |\n' >> "$P/architecture/build-plan.md"
run "$P" --cr CR-07 script.mdl
warned Orders CR-07 && ok "merged: warns, the id sits in another module's section" || bad "merged: no warn" "$(head -20 "$WORK/out")"
P="$WORK/f"; mkproj "$P"
printf '\n## Module brief - Orders\n\n### Build steps\n| Step | What |\n|---|---|\n| CR-07-1 | VAT |\n' >> "$P/architecture/build-plan.md"
run "$P" --cr CR-07 script.mdl
warned Orders CR-07 && bad "merged: warned although present" || ok "merged: silent when present"

echo "== merged brief: em dash heading, UTF-8 locale (macOS awk towc failure)"
P="$WORK/h"; mkproj "$P"
printf '\n## Module brief \xe2\x80\x94 Orders\n\n### Build steps\n| Step | What |\n|---|---|\n| CR-07-1 | VAT |\n' >> "$P/architecture/build-plan.md"
LC_ALL=en_US.UTF-8 run "$P" --cr CR-07 script.mdl
warned Orders CR-07 && bad "em dash: false warn although present" "$(head -20 "$WORK/out")" || ok "em dash: silent when present"
grep -q "multibyte\|awk:" "$WORK/out" && bad "awk error leaked" "$(grep -n 'awk' "$WORK/out")" || ok "em dash: no awk error"
run "$P" --cr CR-09 script.mdl
warned Orders CR-09 && ok "em dash: still warns for an absent id" || bad "em dash: no warn for CR-09" "$(head -20 "$WORK/out")"

echo "== merged brief: CR-12-1 then CR-1-1 on one line, --cr CR-1 and CR-2"
P="$WORK/i"; mkproj "$P"
printf '\n## Module brief - Orders\n\n| CR-12-1 | x | CR-1-1 |\n' >> "$P/architecture/build-plan.md"
run "$P" --cr CR-1 script.mdl
warned Orders CR-1 && bad "boundary: false warn, CR-1-1 is on the line" "$(head -20 "$WORK/out")" || ok "boundary: later occurrence on the line counts"
P="$WORK/j"; mkproj "$P"
printf '\n## Module brief - Orders\n\n| CR-12-1 | x | CR-13-1 |\n' >> "$P/architecture/build-plan.md"
run "$P" --cr CR-1 script.mdl
warned Orders CR-1 && ok "boundary: CR-12/CR-13 only, still warns for CR-1" || bad "boundary: no warn" "$(head -20 "$WORK/out")"

echo "== no brief at all: no crash, only the existing advisory"
P="$WORK/g"; mkproj "$P"
run "$P" --cr CR-07 script.mdl; RC=$?
grep -q "No module brief for: Orders" "$WORK/out" && ok "old no-brief advisory still prints" || bad "old advisory gone" "$(head -20 "$WORK/out")"
grep -q "does not mention" "$WORK/out" && bad "CR warn without a brief" || ok "no CR warn without a brief"
[ "$RC" -eq 0 ] && ok "exit 0" || bad "rc=$RC" "$(tail -15 "$WORK/out")"

echo "== $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
