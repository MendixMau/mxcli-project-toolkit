#!/usr/bin/env bash
# mono-shim.sh <mxbuild toolset dir>...: give a Mono-era Mendix 9 toolset (before 9.20) the launchers the wrappers expect (BT-1).
# The CDN mxbuild for 9.0 to 9.19 holds modeler/mxbuild.exe and modeler/mx.exe and no native launcher, so bin/mx9.sh stopped with
# "no .../modeler/mxbuild". This writes modeler/mxbuild and modeler/mx as two-line shims (`exec mono "$(dirname "$0")/<tool>.exe" "$@"`).
# bin/mx9.sh recognises the shim (its marker line) and runs it in the e5-mx9-mono image (bin/docker/Dockerfile.mx9-mono).
# Idempotent. A toolset that has a native modeler/mxbuild is left alone; a folder with neither is an error (exit 2).
# Producer of the call: bin/setup-container.sh step 6 and bin/cloud/setup.sh step toolsets (after the unpack), and bin/mx9.sh itself.
# Writes only inside the toolset folder; nothing is downloaded. Exit: 0 shimmed or nothing to do, 2 not a toolset.
rc=0
for tb in "$@"; do
  m="$tb/modeler"
  if [ ! -d "$m" ]; then echo "mono-shim: $tb has no modeler/ folder: not an mxbuild toolset" >&2; rc=2; continue; fi
  if [ -e "$m/mxbuild" ] && ! grep -qs 'mono-shim' "$m/mxbuild"; then echo "mono-shim: $tb has a native modeler/mxbuild launcher: nothing to do"; continue; fi
  if [ ! -f "$m/mxbuild.exe" ]; then echo "mono-shim: $tb has neither modeler/mxbuild nor modeler/mxbuild.exe: not an mxbuild toolset" >&2; rc=2; continue; fi
  for t in mxbuild mx; do
    [ -f "$m/$t.exe" ] || continue
    printf '#!/bin/sh\n# mono-shim: written by bin/mono-shim.sh (BT-1), a Mono-era toolset runs through mono\nexec mono "$(dirname "$0")/%s.exe" "$@"\n' "$t" > "$m/$t"
    chmod +x "$m/$t"
  done
  echo "mono-shim: $tb: modeler/mxbuild and modeler/mx run through mono (image e5-mx9-mono)"
done
exit $rc
