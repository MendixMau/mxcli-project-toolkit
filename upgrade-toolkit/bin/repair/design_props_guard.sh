#!/bin/zsh
[ -n "${BASH_VERSION:-}" ] && exec zsh "$0" "$@"  # a zsh script: `bash script.sh` re-runs it under zsh (E6-1)
# design_props_guard.sh <app dir> <ver> [--fixed CE6087[,CE...]] -- <fixer command...>
# Never trust `mxcli fix design-properties` / `mx rename-design-properties` blind (E5 F16: 142 CE6085 after an Atlas 3.13
# update; E1: the renamed Spacing values were all invalid). This runs the fixer on a COPY of the app, runs mx check on the
# original and on the copy (under the heavy lock), and copies the result back only when checkdiff.py says it is not worse.
#   <ver>      mxbuild toolset (mx9.sh / mx10.sh <ver>); 9.* selects mx9.sh
#   fixer      runs with its cwd in the copy; the literal word APP in it is replaced by the copy's .mpr path. A fixer
#              without APP, or one that names the app itself (its folder or .mpr), is REFUSED before anything runs, exit 2
#              (B4T2-7: the .mpr passed instead of APP; the fixer edited the original, the unchanged copy was copied back
#              over it, and the guard said "applied (fixer rc 0; rsync)": the fix was silently undone)
# Example: design_props_guard.sh ~/runs/acme/app 10.24.16 -- ~/tk/bin/mx10.sh 10.24.16 mx rename-design-properties APP
#   --fixed    the error codes the fixer is FOR, passed to checkdiff.py: when they are all gone and only classes they
#              hid appear, the verdict is CASCADE and the copy is applied (E7-4: the rename removed CE6087 and revealed
#              6 CE2729; without --fixed that is WORSE and the copy had to be applied by hand)
#   The fixer runs under the heavy lock too (E7-20). It may call mx10.sh through heavy-lock.sh itself: the lock is
#   re-entrant for the process tree that holds it. bin/repair/pds_oldnames.sh is a ready fixer for CE6085 floods.
# Env: UPG_GUARD_MX replaces mx10.sh/mx9.sh (same arguments: <ver> mx check <mpr>); used by the controls.
# Copy back (batch 1: T1-19, T2-8, T3-16, T4-4, T5-11, T6-7, T8-15: with rsync missing the guard printed "applied",
#   exit 0, and the app was unchanged): rsync -a --delete when rsync is there, else cp -a plus a delete pass (said in the
#   "applied" line). Either way the exit code is tested and the app is compared with the copy (diff -rq, .git left out):
#   any failure or difference is "APPLY FAILED", exit 1, never "applied". UPG_GUARD_NO_RSYNC=1 forces the cp route.
# NO-OP (B4T2-7): the fixer exited 0 but the copy is identical to the app (diff -rq, .git left out): nothing to apply,
#   exit 1, never "applied".
# Loader flake (FM-2): a check whose output is a model loader exception ("Object reference not set", "Collection was of a
#   fixed size") and no "The app contains" line is the emulation flake, not a verdict: it is rerun up to twice (before and after).
# CRASHED (M2): mx check or the fixer exited 139 (segfault): exit 1 with a message naming the crash, retry; never "not an mx check output".
# Exit: 0 = applied, 1 = refused (worse; the original is untouched, logs kept in <app>/../repair-guard/), NO-OP or APPLY
#       FAILED (the app may be half copied: restore it with git checkout -- . && git clean -fd), 2 = usage error or a
#       fixer without APP / naming the app itself (nothing ran).
here=${0:A:h:h}
copyback() {  # the copy over the app as rsync -a --delete --exclude .git would; sets how
  if [[ -z ${UPG_GUARD_NO_RSYNC:-} ]] && command -v rsync > /dev/null; then
    how=rsync; rsync -a --delete --exclude .git $g/copy/ $app/; return
  fi
  how="cp fallback, rsync not found"; local f rel e
  find $app -mindepth 1 -path $app/.git -prune -o -print | while IFS= read -r f; do   # delete pass
    rel=${f#$app/}
    [[ -e $f || -L $f ]] || continue                          # inside a folder removed just before
    [[ -e $g/copy/$rel || -L $g/copy/$rel ]] || rm -rf -- $f || return 1
  done || return 1
  for e in $g/copy/*(DN); do [[ ${e:t} == .git ]] && continue; cp -a $e $app/ || return 1; done
}
usage="usage: design_props_guard.sh <app dir> <ver> [--fixed CODES] -- <fixer...>"
app=${1:?$usage}; ver=${2:?$usage}; shift 2; fixed=()
if [[ ${1:-} == --fixed ]]; then [[ -n ${2:-} && $2 != -- ]] || { echo "$usage" >&2; exit 2; }; fixed=(--fixed $2); shift 2; fi
[[ ${1:-} == -- ]] || { echo "$usage" >&2; exit 2; }; shift
app=${app:A}; mpr=($app/*.mpr(N)); [[ ${#mpr} == 1 ]] || { echo "design_props_guard: $app: expected one .mpr" >&2; exit 2; }
(( $# )) || { echo "$usage" >&2; exit 2; }
fx="${(j: :)@}"
[[ $fx == *APP* ]] || { echo "design_props_guard: REFUSED, the fixer command has no literal APP (the copy's .mpr): it would run on something else, the copy stays unchanged and nothing is fixed (B4T2-7). Example: -- \$B/mx10.sh <ver> mx rename-design-properties APP" >&2; exit 2; }
for a in "$@"; do
  [[ $a == *APP* ]] && continue
  [[ ${a:A} == ${mpr[1]} || ${a:A} == $app || $a == *${mpr[1]}* ]] || continue
  echo "design_props_guard: REFUSED, the fixer names the app itself ($a): it would edit the original, and copying the unchanged copy back would undo that (B4T2-7). Name the copy with the literal APP." >&2; exit 2
done
mx=$here/mx10.sh; [[ $ver == 9.* ]] && mx=$here/mx9.sh
mx=${UPG_GUARD_MX:-$mx}   # controls: a fake toolset that prints canned mx check output
g=${app:h}/repair-guard; rm -rf $g; mkdir -p $g
cp -R $app $g/copy || { echo "design_props_guard: cannot copy $app to $g/copy" >&2; exit 2; }
cmpr=$g/copy/${mpr[1]:t}
export UPG_ROOT=${UPG_ROOT:-${app:h}}
chk() {  # chk <label> <mpr> <log>: mx check under the lock; a loader exception without a verdict is rerun twice (FM-2)
  local n=0; while :; do
    $here/heavy-lock.sh $1 $mx $ver mx check $2 > $3 2>&1; chkrc=$?
    [[ $chkrc != 139 && $n -lt 2 ]] && ! grep -q 'The app contains' $3 && grep -Eq 'Object reference not set|Collection was of a fixed size' $3 || break
    n=$((n + 1)); echo "design_props_guard: $1 hit a model loader exception (amd64 emulation flake), rerun $n of 2" >&2
  done
}
chk guard-before ${mpr[1]} $g/check-before.log; brc=$chkrc
( cd $g/copy && $here/heavy-lock.sh guard-fixer "${@/APP/$cmpr}" ) > $g/fixer.log 2>&1; frc=$?
chk guard-after $cmpr $g/check-after.log; arc=$chkrc
# M2: a segfault (rc 139) is the tool crashing, not an output checkdiff can read: say so, do not call it "not an mx check output"
if [[ $brc == 139 || $arc == 139 || $frc == 139 ]]; then
  echo "CRASHED: the tool died with rc 139 (segfault), not a verdict on the fix: $([[ $brc == 139 ]] && echo 'mx check before; ')$([[ $frc == 139 ]] && echo 'the fixer; ')$([[ $arc == 139 ]] && echo 'mx check after; ')original untouched, logs in $g. Known flake of amd64 mxbuild 11.12.x under Docker emulation on Apple Silicon (M1): retry, and for 11.x set LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libuuid.so.1:/usr/lib/x86_64-linux-gnu/libfreetype.so.6:/usr/lib/x86_64-linux-gnu/libfontconfig.so.1 (mx10.sh does this on an arm64 host)."
  exit 1
fi
python3 $here/checkdiff.py $g/check-before.log $g/check-after.log $fixed | tee $g/checkdiff.txt; rc=${pipestatus[1]}
if [[ $rc == 0 && $frc == 0 ]] && command -v diff > /dev/null && diff -rq -x .git $g/copy $app > /dev/null 2>&1; then
  echo "NO-OP: the fixer exited 0 but the copy is identical to the app; nothing applied (fixer log: $g/fixer.log)"; exit 1
fi
if [[ $rc == 0 && $frc == 0 ]]; then
  how=""; copyback; crc=$?
  if [[ $crc == 0 ]] && command -v diff > /dev/null; then
    diff -rq -x .git $g/copy $app > $g/apply-diff.txt 2>&1; crc=$?
  fi
  if [[ $crc != 0 ]]; then
    echo "APPLY FAILED: copying the fixed copy back ($how) failed or left differences (rc $crc; $g/apply-diff.txt)."
    echo "  The app may be half copied: restore it (git checkout -- . && git clean -fd) and rerun; the fixed copy is in $g/copy"
    exit 1
  fi
  echo "applied (fixer rc $frc; $how)"; exit 0
fi
echo "REFUSED: fixer rc $frc, checkdiff rc $rc; original untouched, see $g (fixer log: $g/fixer.log)"; exit 1
