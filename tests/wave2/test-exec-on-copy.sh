#!/usr/bin/env bash
# test-exec-on-copy.sh — exec.sh --on-copy / EXEC_ON_COPY=1 (#350): write a scratch copy, promote
# it only on a clean gate.
#
# Usage: bash tests/wave2/test-exec-on-copy.sh [path-to-exec.sh]
#
# WHY (#350, external review 2026-10-14). The default path writes the live model, then runs
# mxbuild, then restores on failure: for the length of the gate (22-65 s per apply in the field,
# iterative-build-loop.md) the live model holds an unverified write, and a killed exec.sh leaves
# it there. --on-copy runs exec and the gate on a copy and promotes by rename.
#
# Covers, on BOTH layouts (.mpr at the root, and under app/):
#   clean copy-exec promotes: exec and mxbuild ran on the copy, the live model gains the change
#     (.mpr, a changed unit, a new unit, a file written outside the model), one applied row, the
#     scratch copy is removed;
#   failing gate: live model byte-identical, copy kept with the change, resume hint, one row;
#   mxcli exec exit 1 (partial, on the copy): live byte-identical, exit code passed through;
#   live model modified during the exec: promotion refused, the concurrent change survives,
#     exec's change is not promoted;
#   Studio Pro opens the project during the exec: promotion refused, live byte-identical;
#   a swap that fails half-way (fixture hook) is renamed back: live byte-identical;
#   EXEC_ON_COPY=1 is the same as --on-copy; flag unset runs on the live model as before;
#   kept copies are pruned to MXTK_ON_COPY_KEEP; --on-copy --patch is refused; EXEC_ON_COPY=1
#   with --patch runs the patch as before;
#   a kill in each of 8 promotion windows: the default exec and test-scratch refuse, and
#   `exec.sh --recover-promote` run TWICE leaves the pre-exec or the promoted model, never a mix;
#   leftovers without a manifest are refused untouched; a side file with an archive mtime is promoted.
# Stub mxcli and mxbuild record the model path they were given. No real model, mxcli or mxbuild.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/execcopy.XXXXXX")" || exit 2
BG=""
cleanup() { for p in $BG; do kill -KILL "$p" 2>/dev/null; done; rm -rf "$WORK"; }
trap cleanup EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — missing '$3' in: $(printf '%s' "$2" | tail -6)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — unexpected '$3'" ;; *) ok "$1" ;; esac; }
echo "== subject: $SUBJECT"

# ── Stubs ────────────────────────────────────────────────────────────────────
mkdir -p "$WORK/jdk/bin"
printf '#!/bin/sh\nexit 0\n' > "$WORK/jdk/bin/java"; chmod +x "$WORK/jdk/bin/java"
# mxbuild: records its model path; STUB_MXB_ERR=1 reports a new error; STUB_MXB_TOUCH=<file>
# appends to that (live) file mid-gate; STUB_MXB_SP=<lockfile> makes Studio Pro "open" the model.
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
ef=""; for a in "$@"; do case "$a" in --write-errors=*) ef="${a#--write-errors=}" ;; esac; done
eval "m=\${$#}"; echo "$m" >> "$STUB_LOG/mxbuild-targets"
[ -n "${STUB_MXB_TOUCH:-}" ] && echo "edited by someone else" >> "$STUB_MXB_TOUCH"
if [ -n "${STUB_MXB_SP:-}" ]; then
  nohup sleep 60 >/dev/null 2>&1 & echo $! >> "$STUB_LOG/sp-pids"
  printf '{"ProcessId":%s}\n' "$!" > "$STUB_MXB_SP"
fi
if [ "${STUB_MXB_ERR:-0}" = 1 ]; then
  printf '{"problems":[{"severity":"Error","errorCode":"CE0117","message":"Error(s) in expression.","locations":[{"module":"M","document":"D","element":"E"}]}]}' > "$ef"
  exit 1
fi
printf '{"problems":[]}' > "$ef"; exit 0
MXB
chmod +x "$WORK/mxbuild"

mkproj() {  # $1 = project dir, $2 = "" (root layout) or "app"
  local P="$1" M="$1${2:+/$2}"
  mkdir -p "$P/bin" "$P/mdlsource" "$M/mprcontents/ab" "$M/javasource/m"
  printf 'model index v1\n' > "$M/Fixture.mpr"
  printf 'unit a\n' > "$M/mprcontents/ab/a.mxunit"
  printf 'unit b\n' > "$M/mprcontents/ab/b.mxunit"
  printf 'class Old {}\n' > "$M/javasource/m/Old.java"
  printf 'CREATE MODULE "Nope";\n' > "$P/mdlsource/test.mdl"
  printf 'print("patched")\n' > "$P/mdlsource/p.sh"
  cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$TOOLKIT/project-bin/snapshot-mpr.sh" \
     "$TOOLKIT/project-bin/test-scratch.sh" "$P/bin/"
  cp "$SUBJECT" "$P/bin/exec.sh"
  # mxcli: `exec <script> -p <mpr>` writes into the model it is given. STUB_EXEC_RC=1 writes half
  # and fails; STUB_SIDE=1 also writes a Java file beside the model.
  cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
[ "${1:-}" = exec ] || exit 0
m=""; while [ $# -gt 0 ]; do [ "$1" = -p ] && m="$2"; shift; done
echo "$m" >> "$STUB_LOG/exec-targets"
d="$(dirname "$m")"
echo "changed by exec" >> "$m"
echo "changed by exec" >> "$d/mprcontents/ab/a.mxunit"
[ "${STUB_EXEC_RC:-0}" = 1 ] && { echo "fake mxcli exec: statement 2 failed"; exit 1; }
mkdir -p "$d/mprcontents/cd"; echo "new unit" > "$d/mprcontents/cd/new.mxunit"
[ "${STUB_SIDE:-0}" = 1 ] && { echo "class New {}" > "$d/javasource/m/New.java"; echo "// edited" >> "$d/javasource/m/Old.java"; }
[ "${STUB_OTHER:-0}" = 1 ] && { mkdir -p "$d/other"; echo x > "$d/other/x.txt"; }
[ "${STUB_JOURNAL:-0}" = 1 ] && echo j > "$m-journal"
[ "${STUB_OLDMTIME:-0}" = 1 ] && { echo "class Arch {}" > "$d/javasource/m/Arch.java"; touch -t 200001010000 "$d/javasource/m/Arch.java"; }
echo "fake mxcli exec ok"; exit 0
MXCLI
  chmod +x "$P/bin/"*.sh "$P/mxcli"
  ( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\n' > .gitignore && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
}
fp() {  # $1 = model dir: every file of the live model tree (bytes and names), minus the logs exec.sh writes
  ( cd "$1" && find . \( -path ./deployment -o -path ./.git -o -path ./.mpr-snapshots -o -path ./docs -o -path ./.claude \) -prune \
      -o -type f ! -name '*.lock' -print | LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done ) | cksum
}
run() {  # $1 = project, rest = exec.sh args (env passes through)
  local P="$1"; shift
  mkdir -p "$WORK/log"; rm -f "$WORK/log/"*
  ( cd "$P" && STUB_LOG="$WORK/log" JAVA_HOME="$WORK/jdk" SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 \
      MXTK_NO_SCORE=1 SKIP_DOCTOR=1 MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh "$@" ) 2>&1
}
rows() { grep -c '^| 20' "$1/docs/BUILD-LOG.md" 2>/dev/null || echo 0; }

for LAYOUT in root app; do
  SUB=""; [ "$LAYOUT" = app ] && SUB="app"
  echo "== layout: $LAYOUT"

  echo "-- flag unset: exec runs on the live model, as before"
  P="$WORK/$LAYOUT-default"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 0 ] && ok "default run rc 0" || bad "default run rc $RC: $(printf '%s' "$OUT" | tail -4)"
  [ "$(cat "$WORK/log/exec-targets" 2>/dev/null)" = "$M/Fixture.mpr" ] && ok "default: exec got the live .mpr" || bad "default: exec target $(cat "$WORK/log/exec-targets" 2>/dev/null)"
  hasnt "default: no on-copy wording" "$OUT" "on-copy"
  [ -d "$P/.mpr-snapshots/.on-copy" ] && bad "default: an on-copy dir was created" || ok "default: no scratch copy made"

  echo "-- --on-copy, clean gate: promoted"
  P="$WORK/$LAYOUT-clean"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  OUT="$(STUB_SIDE=1 run "$P" --on-copy mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 0 ] && ok "clean on-copy rc 0" || bad "clean on-copy rc $RC: $(printf '%s' "$OUT" | tail -6)"
  case "$(cat "$WORK/log/exec-targets" 2>/dev/null)" in
    "$P/.mpr-snapshots/.on-copy/"*/model/Fixture.mpr) ok "exec ran on the copy" ;;
    *) bad "exec target: $(cat "$WORK/log/exec-targets" 2>/dev/null)" ;; esac
  case "$(cat "$WORK/log/mxbuild-targets" 2>/dev/null)" in
    "$P/.mpr-snapshots/.on-copy/"*/model/Fixture.mpr) ok "the mxbuild gate ran on the copy" ;;
    *) bad "mxbuild target: $(cat "$WORK/log/mxbuild-targets" 2>/dev/null)" ;; esac
  grep -q 'changed by exec' "$M/Fixture.mpr" && ok "live .mpr holds the change" || bad "live .mpr unchanged"
  grep -q 'changed by exec' "$M/mprcontents/ab/a.mxunit" && ok "live unit holds the change" || bad "live unit unchanged"
  [ -f "$M/mprcontents/cd/new.mxunit" ] && ok "new unit promoted" || bad "new unit missing"
  [ -f "$M/javasource/m/New.java" ] && ok "file exec wrote outside the model promoted" || bad "javasource/m/New.java not promoted"
  grep -q '// edited' "$M/javasource/m/Old.java" && ok "edited file beside the model promoted" || bad "Old.java edit not promoted"
  [ -z "$(ls -d "$M"/.mxtk-promote.* 2>/dev/null)" ] && ok "no promotion leftovers" || bad "leftovers: $(ls -d "$M"/.mxtk-promote.*)"
  [ -z "$(ls -A "$P/.mpr-snapshots/.on-copy" 2>/dev/null)" ] && ok "scratch copy removed after promotion" || bad "scratch copy left: $(ls "$P/.mpr-snapshots/.on-copy")"
  [ "$(rows "$P")" = 1 ] && ok "exactly one BUILD-LOG row" || bad "BUILD-LOG rows: $(rows "$P")"
  has "row says applied + promoted" "$(cat "$P/docs/BUILD-LOG.md")" "on-copy: promoted"
  has "row is an applied row" "$(cat "$P/docs/BUILD-LOG.md")" "✅ applied"
  ls -d "$P/.mpr-snapshots/"[0-9]*/ >/dev/null 2>&1 && ok "pre-exec snapshot still taken" || bad "no snapshot"

  echo "-- --on-copy, failing gate: live model untouched, copy kept"
  P="$WORK/$LAYOUT-fail"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  B="$(fp "$M")"
  OUT="$(STUB_MXB_ERR=1 run "$P" --on-copy mdlsource/test.mdl)"; RC=$?
  [ "$RC" -ne 0 ] && ok "failing gate rc $RC" || bad "failing gate rc 0"
  [ "$(fp "$M")" = "$B" ] && ok "live model byte-identical" || bad "live model changed after a failed on-copy exec"
  K="$(ls -d "$P/.mpr-snapshots/.on-copy/"*/ 2>/dev/null | head -1)"
  [ -n "$K" ] && grep -q 'changed by exec' "$K/model/Fixture.mpr" && ok "copy kept, holding the change" || bad "copy not kept"
  has "prints the kept copy" "$OUT" "The copy is kept:"
  has "prints a resume hint" "$OUT" "Resume: fix the script"
  has "names statement-level resume as not built" "$OUT" "not built"
  has "says the live model was never written" "$OUT" "never written"
  [ "$(rows "$P")" = 1 ] && ok "exactly one BUILD-LOG row" || bad "BUILD-LOG rows: $(rows "$P")"
  has "row says gate failed, on-copy" "$(cat "$P/docs/BUILD-LOG.md")" "live model not written"

  echo "-- --on-copy, mxcli exec exit 1: partial on the copy only"
  P="$WORK/$LAYOUT-partial"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  B="$(fp "$M")"
  OUT="$(STUB_EXEC_RC=1 run "$P" --on-copy mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 1 ] && ok "exit code passed through (1)" || bad "rc $RC"
  [ "$(fp "$M")" = "$B" ] && ok "live model byte-identical" || bad "live model changed after a partial on-copy exec"
  has "says COPY, not the live model" "$OUT" "COPY (not the live model)"
  [ "$(rows "$P")" = 1 ] && ok "exactly one BUILD-LOG row" || bad "BUILD-LOG rows: $(rows "$P")"
  has "row says not promoted" "$(cat "$P/docs/BUILD-LOG.md")" "not promoted"

  echo "-- live model modified during the exec: promotion refused"
  P="$WORK/$LAYOUT-raced"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  OUT="$(STUB_MXB_TOUCH="$M/mprcontents/ab/b.mxunit" run "$P" --on-copy mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 1 ] && ok "refused rc 1" || bad "rc $RC: $(printf '%s' "$OUT" | tail -4)"
  has "names why" "$OUT" "changed since the copy was taken"
  grep -q 'edited by someone else' "$M/mprcontents/ab/b.mxunit" && ok "the concurrent change survives" || bad "concurrent change lost"
  grep -q 'changed by exec' "$M/Fixture.mpr" && bad "exec's change was promoted over it" || ok "exec's change not promoted"
  [ ! -f "$M/mprcontents/cd/new.mxunit" ] && ok "no new unit in live" || bad "new unit leaked into live"
  [ -z "$(ls -d "$M"/.mxtk-promote.* 2>/dev/null)" ] && ok "staging cleaned up" || bad "staging left: $(ls -d "$M"/.mxtk-promote.*)"
  K="$(ls -d "$P/.mpr-snapshots/.on-copy/"*/ 2>/dev/null | head -1)"
  [ -n "$K" ] && [ -f "$K/model/Fixture.mpr" ] && [ -f "$K/model/mprcontents/cd/new.mxunit" ] && ok "copy kept whole (staged files put back)" || bad "copy incomplete after refusal"
  has "row says not promoted" "$(cat "$P/docs/BUILD-LOG.md")" "🚫 not promoted"

  echo "-- Studio Pro opens the project during the exec: promotion refused"
  P="$WORK/$LAYOUT-sp"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  B="$(fp "$M")"
  OUT="$(STUB_MXB_SP="$M/Fixture.mpr.lock" run "$P" --on-copy mdlsource/test.mdl)"; RC=$?
  for p in $(cat "$WORK/log/sp-pids" 2>/dev/null); do BG="$BG $p"; done
  [ "$RC" -eq 1 ] && ok "refused rc 1" || bad "rc $RC: $(printf '%s' "$OUT" | tail -4)"
  has "names Studio Pro" "$OUT" "Studio Pro holds Fixture"
  [ "$(fp "$M")" = "$B" ] && ok "live model byte-identical" || bad "live model changed while SP held it"

  echo "-- swap fails half-way: renamed back"
  P="$WORK/$LAYOUT-swapfail"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  B="$(fp "$M")"
  OUT="$(_MXTK_TEST_SWAP_FAIL=mpr run "$P" --on-copy mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 1 ] && ok "rc 1" || bad "rc $RC"
  has "says renamed back" "$OUT" "renamed back"
  [ "$(fp "$M")" = "$B" ] && ok "live model byte-identical after the failed swap" || bad "live model differs after a failed swap"
  [ -z "$(ls -d "$M"/.mxtk-promote.* 2>/dev/null)" ] && ok "no leftovers" || bad "leftovers: $(ls -d "$M"/.mxtk-promote.*)"
  has "row says promotion failed" "$(cat "$P/docs/BUILD-LOG.md")" "promotion failed"
  K="$(ls -d "$P/.mpr-snapshots/.on-copy/"*/ 2>/dev/null | head -1)"
  [ -n "$K" ] && grep -q 'changed by exec' "$K/model/Fixture.mpr" && [ -f "$K/model/mprcontents/cd/new.mxunit" ] \
    && ok "L1: the kept copy is whole after the rollback" || bad "L1: kept copy incomplete after rollback"
  hasnt "L1: no 'incomplete' note when the copy is whole" "$OUT" "is incomplete"

  echo "-- kill windows: recovery run TWICE is the pre-exec model (not committed) or the promoted one (committed), never a mix"
  T="$WORK/$LAYOUT-twin"; mkproj "$T" "$SUB"
  STUB_SIDE=1 run "$T" --on-copy mdlsource/test.mdl >/dev/null
  PROMOTED="$(fp "$T${SUB:+/$SUB}")"
  B0="$(mkproj "$WORK/$LAYOUT-pristine" "$SUB"; fp "$WORK/$LAYOUT-pristine${SUB:+/$SUB}")"
  [ -n "$PROMOTED" ] && [ "$PROMOTED" != "$B0" ] && ok "[setup] promoted and pre-exec models differ" || bad "[setup] promoted == pre-exec: the window checks prove nothing"
  for W in manifest staged mprcontents mpr side-ln side committed cleanup; do
    P="$WORK/$LAYOUT-kill-$W"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
    B="$(fp "$M")"
    STUB_SIDE=1 _MXTK_TEST_SWAP_KILL="$W" run "$P" --on-copy mdlsource/test.mdl >/dev/null 2>&1
    [ -n "$(ls -d "$M"/.mxtk-promote.* 2>/dev/null)" ] && ok "[$W] the kill left leftovers" || bad "[$W] [setup] no leftovers — the kill missed its window"
    if [ "$W" = mprcontents ]; then
      [ ! -d "$M/mprcontents" ] && ok "[$W] [setup] live model has no mprcontents/" || bad "[$W] [setup] mprcontents/ present"
      OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
      [ "$RC" -eq 1 ] && ok "[$W] M1: the DEFAULT exec refuses" || bad "[$W] M1: default exec rc $RC"
      [ ! -f "$WORK/log/exec-targets" ] && ok "[$W] M1: nothing executed" || bad "[$W] M1: exec ran over a half-swapped model"
      has "[$W] M2: the refusal names the recovery command" "$OUT" "./bin/exec.sh --recover-promote"
      hasnt "[$W] M2: no shell commands printed" "$OUT" "mv '"
      OUT2="$(cd "$P" && STUB_LOG="$WORK/log" bash ./bin/test-scratch.sh -- x 2>&1)"; RC=$?
      [ "$RC" -eq 3 ] && ok "[$W] M1: test-scratch refuses the copy" || bad "[$W] M1: test-scratch rc $RC: $(printf '%s' "$OUT2" | tail -2)"
      has "[$W] M1: test-scratch names the recovery command" "$OUT2" "--recover-promote"
    fi
    OUT="$(run "$P" --recover-promote)"; RC1=$?
    OUT2="$(run "$P" --recover-promote)"; RC2=$?
    [ "$RC1" -eq 0 ] && [ "$RC2" -eq 0 ] && ok "[$W] recovery rc 0, twice" || bad "[$W] recovery rc $RC1 then $RC2: $(printf '%s' "$OUT" | tail -2)"
    has "[$W] the second run is a no-op" "$OUT2" "Nothing to recover"
    F="$(fp "$M")"
    case "$W" in committed|cleanup) EXP="$PROMOTED"; WHAT="promoted" ;; *) EXP="$B"; WHAT="pre-exec" ;; esac
    [ "$F" = "$EXP" ] && ok "[$W] live model byte-identical to the $WHAT model" \
      || bad "[$W] live model is $([ "$F" = "$B" ] && echo 'the pre-exec model' || { [ "$F" = "$PROMOTED" ] && echo 'the promoted model' || echo 'A MIX'; }), expected $WHAT"
    [ -z "$(find "$M" -name '*mxtk-promote*' 2>/dev/null)" ] && ok "[$W] no leftovers anywhere" || bad "[$W] leftovers: $(find "$M" -name '*mxtk-promote*')"
  done
  OUT="$(run "$WORK/$LAYOUT-kill-mprcontents" mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 0 ] && ok "default exec runs again after the recovery" || bad "rc $RC after recovery: $(printf '%s' "$OUT" | tail -3)"
  K="$(ls -d "$WORK/$LAYOUT-kill-mpr/.mpr-snapshots/.on-copy/"*/ 2>/dev/null | head -1)"
  [ -n "$K" ] && grep -q 'changed by exec' "$K/model/Fixture.mpr" && [ -f "$K/model/mprcontents/cd/new.mxunit" ] \
    && ok "the kept copy is whole after a rollback by --recover-promote" || bad "kept copy incomplete after the recovery"

  echo "-- leftovers without a manifest: ambiguous, nothing touched"
  P="$WORK/$LAYOUT-nomanifest"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  mkdir "$M/.mxtk-promote.999.mprcontents"; printf 'x\n' > "$M/.mxtk-promote.999.mpr"
  OUT="$(run "$P" --recover-promote)"; RC=$?
  [ "$RC" -eq 2 ] && ok "recovery refuses (rc 2)" || bad "rc $RC"
  has "and says why" "$OUT" "cannot tell what it is"
  [ -d "$M/.mxtk-promote.999.mprcontents" ] && [ -f "$M/.mxtk-promote.999.mpr" ] && ok "nothing touched" || bad "ambiguous leftovers were touched"

  echo "-- a lone .committed (kill between the cleanup's last two rms) is recovered, then exec runs"
  P="$WORK/$LAYOUT-lonecommit"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  : > "$M/.mxtk-promote.998.committed"
  OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 1 ] && ok "exec refuses over it first" || bad "rc $RC"
  OUT="$(run "$P" --recover-promote)"; RC=$?
  [ "$RC" -eq 0 ] && [ ! -e "$M/.mxtk-promote.998.committed" ] && ok "recovery removes it (rc 0)" || bad "rc $RC: $(printf '%s' "$OUT" | tail -2)"
  OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 0 ] && ok "the next exec runs" || bad "next exec rc $RC: $(printf '%s' "$OUT" | tail -2)"

  echo "-- --recover-promote refuses while Studio Pro holds the model, FORCE_EXEC or not"
  P="$WORK/$LAYOUT-recsp"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  : > "$M/.mxtk-promote.997.committed"
  sleep 60 & SPP=$!; BG="$BG $SPP"; printf '{"ProcessId":%s}\n' "$SPP" > "$M/Fixture.mpr.lock"
  OUT="$(FORCE_EXEC=1 run "$P" --recover-promote)"; RC=$?
  [ "$RC" -eq 1 ] && ok "refused (rc 1)" || bad "rc $RC"
  has "says FORCE_EXEC does not override" "$OUT" "FORCE_EXEC does not override"
  [ -e "$M/.mxtk-promote.997.committed" ] && ok "nothing touched" || bad "recovery ran while SP held the model"
  kill "$SPP" 2>/dev/null; rm -f "$M/Fixture.mpr.lock"

  echo "-- a side file written with an archive mtime is still promoted (by checksum)"
  P="$WORK/$LAYOUT-archmtime"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  OUT="$(STUB_OLDMTIME=1 run "$P" --on-copy mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 0 ] && grep -q 'class Arch' "$M/javasource/m/Arch.java" 2>/dev/null && ok "Arch.java (mtime 2000) promoted" || bad "archive-mtime file not promoted (rc $RC)"

  echo "-- M3: a side file changed live during the exec"
  P="$WORK/$LAYOUT-sidechg"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  OUT="$(STUB_SIDE=1 STUB_MXB_TOUCH="$M/javasource/m/Old.java" run "$P" --on-copy mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 1 ] && ok "M3: refused (rc 1)" || bad "M3: rc $RC: $(printf '%s' "$OUT" | tail -3)"
  has "M3: names the file" "$OUT" "changed live since the copy was taken: javasource/m/Old.java"
  grep -q 'changed by exec' "$M/Fixture.mpr" && bad "M3: model promoted anyway" || ok "M3: model not promoted"
  grep -q 'edited by someone else' "$M/javasource/m/Old.java" && ok "M3: the live edit survives" || bad "M3: live edit lost"

  echo "-- a write outside the model and the side dirs refuses; -journal is never a side file"
  P="$WORK/$LAYOUT-other"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  OUT="$(STUB_OTHER=1 STUB_JOURNAL=1 run "$P" --on-copy mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 1 ] && ok "refused (rc 1)" || bad "rc $RC"
  has "names the stray write" "$OUT" "other/x.txt"
  hasnt "-journal not listed as a write" "$OUT" "Fixture.mpr-journal"
  P="$WORK/$LAYOUT-journal"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  OUT="$(STUB_JOURNAL=1 run "$P" --on-copy mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 0 ] && [ ! -f "$M/Fixture.mpr-journal" ] && ok "L2: -journal never promoted" || bad "L2: rc $RC, journal promoted?"

  echo "-- nit: FORCE_EXEC with Studio Pro open refuses --on-copy up front"
  P="$WORK/$LAYOUT-force"; mkproj "$P" "$SUB"; M="$P${SUB:+/$SUB}"
  sleep 60 & SPP=$!; BG="$BG $SPP"; printf '{"ProcessId":%s}\n' "$SPP" > "$M/Fixture.mpr.lock"
  OUT="$(FORCE_EXEC=1 run "$P" --on-copy mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 1 ] && ok "refused (rc 1)" || bad "rc $RC"
  has "says FORCE_EXEC does not override" "$OUT" "FORCE_EXEC does not override"
  [ ! -f "$WORK/log/exec-targets" ] && ok "nothing executed" || bad "exec ran"
  kill "$SPP" 2>/dev/null
done

echo "== L4: single-tree copy is the allow-list"
P="$WORK/allow"; mkproj "$P" ""
mkdir -p "$P/analysis" "$P/sources"; echo big > "$P/analysis/a.txt"; echo src > "$P/sources/s.txt"
STUB_MXB_ERR=1 run "$P" --on-copy mdlsource/test.mdl >/dev/null
K="$(ls -d "$P/.mpr-snapshots/.on-copy/"*/ 2>/dev/null | head -1)"
[ -n "$K" ] && [ -f "$K/model/Fixture.mpr" ] && [ -d "$K/model/mprcontents" ] && [ -d "$K/model/javasource" ] && ok "model + app dirs copied" || bad "copy lacks the model"
[ -n "$K" ] && [ ! -e "$K/model/analysis" ] && [ ! -e "$K/model/sources" ] && [ ! -e "$K/model/mxcli" ] && [ ! -e "$K/model/mdlsource" ] \
  && ok "analysis/, sources/, mdlsource/ and the mxcli binary not copied" || bad "copy holds non-app paths: $(ls "$K/model")"

echo "== env and options"
echo "-- EXEC_ON_COPY=1 is the same as --on-copy"
P="$WORK/env"; mkproj "$P" ""
OUT="$(EXEC_ON_COPY=1 run "$P" mdlsource/test.mdl)"; RC=$?
case "$(cat "$WORK/log/exec-targets" 2>/dev/null)" in */.on-copy/*) ok "EXEC_ON_COPY=1 ran on a copy" ;; *) bad "EXEC_ON_COPY=1 target: $(cat "$WORK/log/exec-targets")" ;; esac
[ "$RC" -eq 0 ] && grep -q 'changed by exec' "$P/Fixture.mpr" && ok "and promoted" || bad "not promoted (rc $RC)"

echo "-- kept copies pruned to MXTK_ON_COPY_KEEP"
P="$WORK/keep"; mkproj "$P" ""
for i in 1 2 3 4; do STUB_MXB_ERR=1 run "$P" --on-copy mdlsource/test.mdl >/dev/null; sleep 1; done
N="$(ls -d "$P/.mpr-snapshots/.on-copy/"*/ 2>/dev/null | wc -l | tr -d ' ')"
[ "$N" = 3 ] && ok "4 failures keep the newest 3" || bad "kept $N copies"
MXTK_ON_COPY_KEEP=1 STUB_MXB_ERR=1 run "$P" --on-copy mdlsource/test.mdl >/dev/null
N="$(ls -d "$P/.mpr-snapshots/.on-copy/"*/ 2>/dev/null | wc -l | tr -d ' ')"
[ "$N" = 1 ] && ok "MXTK_ON_COPY_KEEP=1 keeps 1" || bad "kept $N copies"
N="$(ls -d "$P/.mpr-snapshots/"[0-9]*/ 2>/dev/null | wc -l | tr -d ' ')"
[ "$N" -le 5 ] && ok "snapshot rotation unaffected by .on-copy ($N kept)" || bad "$N snapshots"

echo "-- --on-copy --patch refused; EXEC_ON_COPY=1 --patch runs as before"
P="$WORK/patch"; mkproj "$P" ""
OUT="$(run "$P" --on-copy --patch mdlsource/p.sh)"; RC=$?
[ "$RC" -eq 2 ] && ok "--on-copy --patch refused rc 2" || bad "rc $RC"
has "and says so" "$OUT" "does not take --patch"
printf '#!/bin/sh\necho patched >> "$1"\n' > "$P/mdlsource/p.sh"
OUT="$(EXEC_ON_COPY=1 run "$P" --patch mdlsource/p.sh)"; RC=$?
has "EXEC_ON_COPY with --patch: note" "$OUT" "does not apply to --patch"
grep -q patched "$P/Fixture.mpr" && ok "patch ran on the live model" || bad "patch did not run (rc $RC): $(printf '%s' "$OUT" | tail -4)"

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
