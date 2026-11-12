#!/bin/zsh
[ -n "${BASH_VERSION:-}" ] && exec zsh "$0" "$@"  # a zsh script: `bash script.sh` re-runs it under zsh (E6-1)
# toolcheck.sh <toolset dir> [mx|mxbuild]: refuse an incomplete mxbuild toolset before a tool runs.
# Why (E4-20, E5b-1): shared toolsets had lost modeler/runtemplates/deployment and modeler/tools/node/node_modules
# (about 24k files; mxbuild.dll itself identical). mxbuild then fails late with a message that does not name the cause:
#   9.24 / 10.12  DirectoryNotFoundException .../deployment/dojo-web ("Prepare deployment" / "Clean up")
#   10.24         NoSuchFileException in copyDeploymentArtifacts
# Ten failed builds in E5b and three in E4 before the toolset was found to be incomplete.
# Complete = modeler/<tool> executable, modeler/runtemplates/deployment and modeler/tools/node/node_modules present.
# Exit: 0 complete; 2 incomplete for mxbuild (refused); mx (check, convert) does not need the deployment templates:
# a warning on stderr and exit 0. Fix: extract the CDN tarball (mxbuild-<full ver>.tar.gz) again into a fresh folder.
#
# toolcheck.sh --host: the host tools the scripts need, before a run starts (batch 1: T1-6, T1-19, T4-4, T6-7, T6-21).
#   python3 modules bson (pip package pymongo: idcheck, localedits, every MPR reader) and bcrypt (smoke_users): REFUSED,
#   exit 2, with the exact `python3 -m pip install X` (pip on PATH may belong to another Python, T1-6).
#   rsync: WARNING only, exit 0 (design_props_guard.sh falls back to cp -a; without rsync it used to say "applied" and
#   change nothing). Chromium missing (no /opt/pw-browsers, no playwright cache): WARNING with the install line, exit 0 (S3).
#   UPG_PYTHON replaces python3, UPG_PW_OPT replaces /opt/pw-browsers (controls).
if [[ ${1:-} == --host ]]; then
  py=${UPG_PYTHON:-python3}; bad=()
  for m in bson:pymongo bcrypt:bcrypt; do
    $py -c "import ${m%%:*}" > /dev/null 2>&1 || bad+=(${m#*:})
  done
  command -v rsync > /dev/null || echo "toolcheck: WARNING, no rsync: design_props_guard.sh copies back with cp -a (install rsync to use it)" >&2
  # C6: GNU timeout (or gtimeout) bounds a hung gate rung; gate.sh falls back to a bash watchdog, so WARNING only.
  if ! command -v timeout > /dev/null && ! command -v gtimeout > /dev/null; then
    echo "toolcheck: WARNING, no GNU timeout or gtimeout (macOS: brew install coreutils): gate.sh limits rungs with a bash watchdog instead" >&2
  fi
  # GNU sed expected: BSD sed (macOS) differs on -i, \+ and \n in replacements.
  if ! sed --version 2>/dev/null | grep -q GNU && ! command -v gsed > /dev/null; then
    echo "toolcheck: WARNING, sed is not GNU sed and no gsed (macOS: brew install gnu-sed): BSD sed differs on -i, \\+ and \\n" >&2
  fi
  # S3: Chromium for smokewalk.js / the journeys: /opt/pw-browsers in the cloud image, else playwright's own cache. Warning only.
  pwb=(${UPG_PW_OPT:-/opt/pw-browsers}(N/) ~/.cache/ms-playwright/chromium-*(N/) ~/Library/Caches/ms-playwright/chromium-*(N/))
  [[ -d ${PLAYWRIGHT_BROWSERS_PATH:-/nonexistent} ]] && pwb+=($PLAYWRIGHT_BROWSERS_PATH)
  (( ${#pwb} )) || echo "toolcheck: WARNING, no Chromium for Playwright (smokewalk and the journeys need it): cd ~/mendix-playwright && npx --yes playwright@1.56.1 install chromium" >&2
  if (( ${#bad} )); then
    echo "toolcheck: REFUSED, python modules missing for $($py -c 'import sys; print(sys.executable)' 2>/dev/null || echo $py): ${(j:, :)bad}. Install with: $py -m pip install ${(j: :)bad}" >&2
    exit 2
  fi
  echo "toolcheck: host OK ($py has pymongo/bson and bcrypt$(command -v rsync > /dev/null && echo ', rsync present'))"
  exit 0
fi
# toolcheck.sh --image [image]: report whether the image holds the three libs mx10.sh preloads for 11.x on Apple Silicon
#   (M1: libuuid.so.1, libfreetype.so.6, libfontconfig.so.1 against the rc 139 segfaults of mxbuild 11.12.x under emulation).
#   Information only, exit 0 (a missing lib is skipped by mx10.sh); exit 2 when the image cannot be run. Default image UPG_IMAGE10 / mig-mx10.
if [[ ${1:-} == --image ]]; then
  img=${2:-${UPG_IMAGE10:-mig-mx10}}
  out=$(docker run --rm --platform linux/amd64 $img sh -c 'for l in libuuid.so.1 libfreetype.so.6 libfontconfig.so.1; do if [ -e /usr/lib/x86_64-linux-gnu/$l ]; then echo "have $l"; else echo "missing $l"; fi; done' 2>&1) || { echo "toolcheck: cannot run image $img: $out" >&2; exit 2; }
  have=(${(f)"$(print -r -- $out | sed -n 's/^have //p')"}); miss=(${(f)"$(print -r -- $out | sed -n 's/^missing //p')"})
  echo "toolcheck: image $img preload libs (11.x on arm64): present ${#have}/3${have:+ ($have)}${miss:+, missing: $miss (mx10.sh skips them)}"
  exit 0
fi
tb=${1:?usage: toolcheck.sh <toolset dir> [mx|mxbuild] | toolcheck.sh --host | toolcheck.sh --image [image]}; tool=${2:-mxbuild}
if [[ ! -x $tb/modeler/$tool && -f $tb/modeler/$tool.exe ]]; then  # BT-1: Mono-era Mendix 9 (before 9.20)
  echo "toolcheck: $tb is a Mono-era toolset (before 9.20): modeler/$tool.exe and no native launcher. Run: bash ${0:A:h}/mono-shim.sh $tb (bin/mx9.sh does it itself) and use the image e5-mx9-mono (bin/docker/Dockerfile.mx9-mono)" >&2; exit 2
fi
[[ -x $tb/modeler/$tool ]] || { echo "toolcheck: no $tb/modeler/$tool" >&2; exit 2; }
miss=()
[[ -d $tb/modeler/runtemplates/deployment ]] || miss+=(modeler/runtemplates/deployment)
[[ -d $tb/modeler/tools/node/node_modules ]] || miss+=(modeler/tools/node/node_modules)
(( ${#miss} )) || exit 0
msg="incomplete toolset ${tb}: missing ${(j:, :)miss}. mxbuild would fail late with dojo-web DirectoryNotFoundException (9.x, 10.12) or copyDeploymentArtifacts NoSuchFileException (10.24). Extract mxbuild-<full ver>.tar.gz again into a fresh folder."
v=${${tb:A:t}#mxbuild-}; [[ $v == [0-9]*.[0-9]*.[0-9]*.[0-9]* ]] || v='<full ver>'
msg="$msg Fetch (E6-2): curl -fLO https://cdn.mendix.com/runtime/mxbuild-$v.tar.gz && mkdir <fresh dir> && tar -xzf mxbuild-$v.tar.gz -C <fresh dir> (python3 \$B/mxversion.py <old dir> prints the full version)"
if [[ $tool == mxbuild ]]; then echo "toolcheck: REFUSED, $msg" >&2; exit 2; fi
echo "toolcheck: WARNING, $msg (mx can still run)" >&2; exit 0
