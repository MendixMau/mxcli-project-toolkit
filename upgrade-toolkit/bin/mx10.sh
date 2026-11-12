#!/bin/zsh
[ -n "${BASH_VERSION:-}" ] && exec zsh "$0" "$@"  # a zsh script: `bash script.sh` re-runs it under zsh (E6-1)
# mx10.sh <ver> <mx|mxbuild> args...: Linux mxbuild 10.x/11.x tool (mx check, mx convert, mxbuild) in an amd64 container.
#   <ver> names $UPG_TOOLS/mxbuild-<ver> (for example 10.24.16). Image: UPG_IMAGE10 (default mig-mx10, bin/docker/Dockerfile.mx10).
#   mxbuild: refused on an incomplete toolset (toolcheck.sh); --java-home/--java-exe-path and HOME=/tmp are added.
#   11.x on an arm64 host (Docker emulating amd64): the tool is started through a small sh that sets LD_PRELOAD to those of
#   libuuid.so.1, libfreetype.so.6, libfontconfig.so.1 (in /usr/lib/x86_64-linux-gnu) that EXIST in the image (M1: mxbuild
#   11.12.x segfaulted, rc 139, intermittently in mx check / rename-design-properties; with the preload every later call
#   passed). Not applied on amd64 hosts, with UPG_PRELOAD=0, or when UPG_EXTRA already sets LD_PRELOAD; UPG_PRELOAD=1 forces
#   it. UPG_HOST_ARCH replaces `uname -m` (controls). toolcheck.sh --image reports which libs the image has.
#   rc 139 (or "signal: aborted") is retried twice before it counts (NR2-15; UPG_RETRY_CRASH=0 turns it off, output then shows when the
#   call ends). Paths: any absolute path under UPG_ROOT (default: current folder) works as on the host. See mxrun.sh.
#   Example: UPG_ROOT=~/runs/acme mx10.sh 10.24.16 mx check ~/runs/acme/app/App.mpr
#   A bare subcommand is accepted (FM-11): `mx10.sh 11.12.6 check app.mpr` runs `mx check app.mpr` (a first word that is no
#   binary of the toolset, while mx is, gets mx put in front; it is said on stderr).
v=${1:?usage: mx10.sh <ver> <mx|mxbuild> args...}; tool=${2:?}; shift 2
root=${UPG_ROOT:-$PWD}; tools=${UPG_TOOLS:-${root:A}/tools}
if [[ $tool != (mx|mxbuild) && ! -e $tools/mxbuild-$v/modeler/$tool && -x $tools/mxbuild-$v/modeler/mx ]]; then
  echo "mx10.sh: '$tool' is no tool of mxbuild-$v, running: mx $tool ..." >&2; set -- $tool "$@"; tool=mx
fi
[[ -x $tools/mxbuild-$v/modeler/$tool ]] || { echo "mx10.sh: no $tools/mxbuild-$v/modeler/$tool" >&2; exit 2; }
tb=$tools/mxbuild-$v; tb=${tb:A}  # toolset may be a symlink to a shared folder: mount its real path
${0:A:h}/toolcheck.sh "$tb" "$tool" || exit 2   # E4-20 / E5b-1: refuse an incomplete toolset before mxbuild runs
if [[ $tool == mxbuild ]]; then  # E4-4: the container JDK and a writable HOME, unless the caller set them
  [[ " $* " == *" --java-home="* ]] || set -- --java-home=/opt/java/openjdk --java-exe-path=/opt/java/openjdk/bin/java "$@"
  [[ " ${UPG_EXTRA:-} " == *"HOME="* ]] || export UPG_EXTRA="${UPG_EXTRA:-} -e HOME=/tmp"
fi
run=($tb/modeler/$tool)
arch=${UPG_HOST_ARCH:-$(uname -m)}
if [[ $v == 11.* && ${UPG_PRELOAD:-} != 0 && " ${UPG_EXTRA:-} " != *"LD_PRELOAD="* && ( $arch == (arm64|aarch64) || ${UPG_PRELOAD:-} == 1 ) ]]; then
  run=(sh -c 'p=; for l in libuuid.so.1 libfreetype.so.6 libfontconfig.so.1; do [ -e /usr/lib/x86_64-linux-gnu/$l ] && p="$p:/usr/lib/x86_64-linux-gnu/$l"; done; [ -n "$p" ] && export LD_PRELOAD=${p#:}; exec "$@"' sh $run)  # M1
fi
export UPG_RETRY_CRASH=${UPG_RETRY_CRASH:-2}
exec ${0:A:h}/mxrun.sh -v "$tb":"$tb":ro -- ${UPG_IMAGE10:-mig-mx10} $run "$@"
