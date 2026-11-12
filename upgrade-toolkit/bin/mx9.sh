#!/bin/zsh
[ -n "${BASH_VERSION:-}" ] && exec zsh "$0" "$@"  # a zsh script: `bash script.sh` re-runs it under zsh (E6-1)
# mx9.sh <ver> <mx|mxbuild> args...: Linux mxbuild 9.x tool in an amd64 container with JDK 11 (what a 9.24 app needs).
#   <ver> names $UPG_TOOLS/mxbuild-<ver> (for example 9.24.32). Image: UPG_IMAGE9 (default e5-mx9, bin/docker/Dockerfile.mx9;
#   e5-mx9-mono, Dockerfile.mx9-mono, for a Mono-era toolset before 9.20: bin/mono-shim.sh writes its launchers, BT-1).
#   Paths, toolset check and mxbuild defaults as in mx10.sh / mxrun.sh.
v=${1:?usage: mx9.sh <ver> <mx|mxbuild> args...}; tool=${2:?}; shift 2
root=${UPG_ROOT:-$PWD}; tools=${UPG_TOOLS:-${root:A}/tools}
# BT-1: a Mono-era toolset (9.0 to 9.19: modeler/<tool>.exe, no native launcher) gets its mono shim and runs in e5-mx9-mono
if [[ -f $tools/mxbuild-$v/modeler/$tool.exe && ! -e $tools/mxbuild-$v/modeler/$tool ]]; then
  bash ${0:A:h}/mono-shim.sh $tools/mxbuild-$v >&2 || exit 2
fi
[[ -x $tools/mxbuild-$v/modeler/$tool ]] || { echo "mx9.sh: no $tools/mxbuild-$v/modeler/$tool" >&2; exit 2; }
img=${UPG_IMAGE9:-e5-mx9}
if grep -qs mono-shim $tools/mxbuild-$v/modeler/$tool; then
  img=${UPG_IMAGE9:-e5-mx9-mono}
  if [[ -z $UPG_DRYRUN ]] && ! docker image inspect $img > /dev/null 2>&1; then
    echo "mx9.sh: $tools/mxbuild-$v is a Mono-era toolset (before 9.20) and needs the image $img: docker build --network host -t $img -f ${0:A:h}/docker/Dockerfile.mx9-mono ${0:A:h}/docker" >&2; exit 3
  fi
fi
tb=$tools/mxbuild-$v; tb=${tb:A}  # toolset may be a symlink to a shared folder: mount its real path
${0:A:h}/toolcheck.sh "$tb" "$tool" || exit 2   # E4-20 / E5b-1: refuse an incomplete toolset before mxbuild runs
if [[ $tool == mxbuild ]]; then  # E4-4: the container JDK and a writable HOME, unless the caller set them
  [[ " $* " == *" --java-home="* ]] || set -- --java-home=/opt/java/openjdk --java-exe-path=/opt/java/openjdk/bin/java "$@"
  [[ " ${UPG_EXTRA:-} " == *"HOME="* ]] || export UPG_EXTRA="${UPG_EXTRA:-} -e HOME=/tmp"
fi
export UPG_RETRY_CRASH=${UPG_RETRY_CRASH:-2}  # NR2-15: rc 139 retry, see mxrun.sh
exec ${0:A:h}/mxrun.sh -v "$tb":"$tb":ro -- $img $tb/modeler/$tool "$@"
