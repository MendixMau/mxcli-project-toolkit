#!/bin/zsh
[ -n "${BASH_VERSION:-}" ] && exec zsh "$0" "$@"  # a zsh script: `bash script.sh` re-runs it under zsh (E6-1)
# mxcli-container.sh <mxcli args...>: the Linux mxcli in an amd64 container (Mendix 9.x/10.x mxbuild has no macOS build).
# Every toolset $UPG_TOOLS/mxbuild-* is mounted at /root/.mxcli/mxbuild/<FULL version> (read from its manifest by
# mxversion.py: mxcli refuses a near match), the PAT file read-only (both under <HOME>/.mxcli when HOME is set, below). Paths: as in mxrun.sh (own host path, and /w = cwd).
# Env: UPG_ROOT (default: current folder; old name MXC_ROOT), UPG_TOOLS (default $UPG_ROOT/tools),
#      UPG_MXCLI Linux mxcli binary (default $UPG_TOOLS/mxcli-linux; old name MXC_MXCLI),
#      UPG_IMAGE (default: e5-mx9 when the -p project is 9.x, else mig-mx10; old name MXC_IMAGE).
# Before running it checks that a toolset of the project's exact version is mounted (E5 F7: a 10.24.8 project with only
# 10.24.9 mounted fails late with a misleading error).
# Proxy, CA and UPG_ENV_FILE: see mxrun.sh (T1-12, T8-11).
# HOME in the container (T7-13): a HOME set through UPG_EXTRA ("-e HOME=/tmp") or UPG_ENV_FILE moved mxcli's config
# away from /root/.mxcli, so every call failed with "auth: no credential for profile default" and stepupdate kept every
# module. The credential and the toolsets are now mounted under <that HOME>/.mxcli instead.
# -p: absolute, /w/..., or relative to the CURRENT folder (T6R-11); the project must be under UPG_ROOT.
# Example: UPG_ROOT=~/runs/acme mxcli-container.sh marketplace diff 23513 --module Administration -p ~/runs/acme/app/App.mpr
here=${0:A:h}
ch=/root   # HOME inside the container: the last -e/--env HOME=... of UPG_EXTRA, else of UPG_ENV_FILE, else /root
[[ -n ${UPG_ENV_FILE:-} && -f $UPG_ENV_FILE ]] && { h=$(sed -n 's/^HOME=//p' $UPG_ENV_FILE | tail -1); [[ -n $h ]] && ch=$h; }
ex=(${=UPG_EXTRA:-})
for (( i = 1; i <= $#ex; i++ )); do
  case $ex[i] in
    -e|--env) [[ ${ex[i+1]:-} == HOME=?* ]] && ch=${ex[i+1]#HOME=};;
    -eHOME=?*|--env=HOME=?*) ch=${ex[i]#*HOME=};;
  esac
done
[[ $ch == /* ]] || { echo "mxcli-container.sh: HOME=$ch in UPG_EXTRA/UPG_ENV_FILE is not an absolute path" >&2; exit 2; }
mx=${ch%/}/.mxcli
export UPG_ROOT=${UPG_ROOT:-${MXC_ROOT:-$PWD}}; root=${UPG_ROOT:A}
export UPG_TOOLS=${UPG_TOOLS:-$root/tools}; tools=${UPG_TOOLS:A}
mxcli=${UPG_MXCLI:-${MXC_MXCLI:-$tools/mxcli-linux}}
if [[ ! -f $mxcli ]]; then
  [[ -L $mxcli ]] && { echo "mxcli-container.sh: $mxcli is a dangling symlink (to $(readlink $mxcli)); point it at the shared Linux mxcli" >&2; exit 2; }
  echo "mxcli-container.sh: no Linux mxcli at $mxcli" >&2; exit 2
fi
# The binary is mounted by its RESOLVED path: tools/ made of symlinks into a shared folder showed the container a
# dangling link and a misleading "no such file" (E4-2).
extra=(-v "${mxcli:A}":/opt/upg/mxcli:ro)
typeset -A have
for d in $tools/mxbuild-*(N-/); do
  v=$(python3 $here/mxversion.py $d 2>/dev/null) || continue
  extra+=(-v "${d:A}":$mx/mxbuild/${v}:ro); have[$v]=1
done
[[ -n $MXC_MXBUILD && -n $MXC_VERSION ]] && { extra+=(-v "$MXC_MXBUILD":$mx/mxbuild/${MXC_VERSION}:ro); have[$MXC_VERSION]=1; }
# T6R-11: a relative -p was resolved inside the container against /w (= UPG_ROOT), not against the caller's folder, so
# `cd $UPG_ROOT/app && mxcli-container.sh -p App.mpr` failed with "mpr file not found: App.mpr". A relative -p is now made
# absolute against the HOST cwd (the run folder is mounted at its own host path); a project outside UPG_ROOT is not mounted
# at all and is refused with the rule instead of the container's misleading "not found".
proj=""; prev=""; args=()
for a in "$@"; do
  if [[ $prev == -p ]]; then
    [[ $a != /* ]] && { a=$PWD/$a; a=${a:A}; }
    if [[ $a != /w/* && ${a:A} != $root/* && $a != ${UPG_ROOT%/}/* ]]; then
      echo "mxcli-container.sh: project $a is not under UPG_ROOT=$root; only UPG_ROOT is mounted in the container (at its own path and at /w). Set UPG_ROOT to a folder that holds the project." >&2; exit 2
    fi
    proj=$a
  fi
  args+=("$a"); prev=$a
done
set -- "${args[@]}"
img=${UPG_IMAGE:-$MXC_IMAGE}
if [[ -n $proj ]]; then
  hp=$proj; [[ $hp == /w/* ]] && hp=$root/${hp#/w/}
  [[ -f $hp ]] || { echo "mxcli-container.sh: project $proj not found on the host (a relative -p is resolved against the current folder $PWD)" >&2; exit 2; }
  if [[ -f $hp ]]; then
    pv=$(python3 $here/mxversion.py $hp 2>/dev/null)
    if [[ -n $pv && -z ${have[$pv]} && $* != *convert* && $* != *version* ]]; then
      echo "mxcli-container.sh: project $proj is $pv, mounted toolsets: ${(k)have:-none}. Unpack the $pv toolset as mxbuild-${pv%.*} into $tools first." >&2; exit 2
    fi
    [[ -z $img && $pv == 9.* ]] && img=e5-mx9
  fi
fi
[[ -f $HOME/.mxcli/auth.json ]] && extra+=(-v "$HOME/.mxcli/auth.json":$mx/auth.json:ro)
# R38 (Purchase Request 10.24): a credential held only in MENDIX_PAT (mxcli auth status: "Source: env") never reached the
# container, so every update stopped "no credential for profile default". Forward it by NAME: docker reads the value from
# this environment, so the token never appears on a command line.
[[ -n ${MENDIX_PAT:-} ]] && extra+=(-e MENDIX_PAT)
case ${1:-} in fix|check) export UPG_RETRY_CRASH=${UPG_RETRY_CRASH:-2};; esac  # NR2-15/17: a crashed fixer is retried, see mxrun.sh
exec $here/mxrun.sh $extra -- ${img:-mig-mx10} /opt/upg/mxcli "$@"
