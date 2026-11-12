#!/bin/zsh
[ -n "${BASH_VERSION:-}" ] && exec zsh "$0" "$@"  # a zsh script: `bash script.sh` re-runs it under zsh (E6-1)
# mxrun.sh [docker args... --] <image> <command...>: run a Linux Mendix tool in an amd64 container with the run folder and the toolsets
# mounted at THEIR OWN host paths (so absolute paths in arguments work unchanged) and the run folder also at /w (cwd).
# Env: UPG_ROOT   run folder (default: current folder). Project, work files and outputs must be under it.
#      UPG_TOOLS  folder with mxbuild-<ver>/, runtime-<ver>/, mxcli-linux (default: $UPG_ROOT/tools). Mounted read-only.
#      UPG_NAME   container name prefix (default upg); the container is --rm and named <prefix>-<pid>.
#      UPG_EXTRA  extra docker arguments (word-split), for example "-v /path:/path:ro". A value with spaces cannot go
#                 through it (JAVA_TOOL_OPTIONS: T2-9, T5-13): put it in UPG_ENV_FILE.
#      UPG_ENV_FILE  a docker --env-file (KEY=value per line; the value may hold spaces).
#      UPG_DRYRUN print the docker command instead of running it (controls).
#      UPG_RETRY_CRASH  N: a tool crash is retried up to N times before its result counts (NR2-15, NR2-17). A crash is rc 139
#                 (segfault, mxbuild 11.12.x under emulation: about 1 call in 3 on notification-service 10.24.8 to 11.12.6)
#                 or a non-zero rc whose output names "signal: aborted", AccessViolationException or "Segmentation fault".
#                 With N > 0 the output of the final attempt is shown when it ends (not live): mx10.sh and mx9.sh set 2
#                 (mx check, mxbuild, convert: all run to completion), mxcli-container.sh sets 2 for `fix` and `check`
#                 only. UPG_RETRY_CRASH=0 streams live, with no retry. UPG_RETRY_CRASH_SLEEP: seconds between tries (3).
#                 Loader flake (FM-2): a retry that follows a crash and dies in the model loader ("Object reference not set",
#                 "Collection was of a fixed size", rc not 0) on a model that is fine is the same emulation flake, not
#                 corruption: it is retried once more beyond N (said as "amd64 emulation flake, rerun").
# Egress proxy (batch 1: T1-12, T3-7, T4-2, T6-6, T8-11: a containerised mxcli without the proxy failed every Marketplace
# call with "x509: certificate signed by unknown authority", and stepupdate recorded every module as KEPT):
#      HTTPS_PROXY / https_proxy set: passed on as HTTPS_PROXY and https_proxy, with NO_PROXY / no_proxy. A proxy on
#                 127.0.0.1 or localhost is reachable only with --network host, which is then added (unless the docker
#                 args or UPG_EXTRA already name a network).
#      UPG_CA     a CA bundle the container must trust: mounted read-only at /etc/upg/ca.crt, named by SSL_CERT_FILE.
#                 Without UPG_CA, and only when a proxy is set: the first existing of $SSL_CERT_FILE and
#                 /root/.ccr/ca-bundle.crt (the cloud container's agent-proxy bundle).
pre=()
if [[ $1 == -* ]]; then while [[ $# -gt 0 && $1 != -- ]]; do pre+=("$1"); shift; done; shift; fi
img=${1:?usage: mxrun.sh [docker args... --] <image> <command...>}; shift
given=${UPG_ROOT:-$PWD}; root=${given:A}
tools=${UPG_TOOLS:-$root/tools}; tools=${tools:A}
args=(--rm --platform linux/amd64 --name ${UPG_NAME:-upg}-$$ -e DOTNET_EnableWriteXorExecute=0 -v "$root":/w -v "$root":"$root" -w /w)
[[ $given != $root && $given == /* ]] && args+=(-v "$root":"${given%/}")  # /var -> /private/var: both spellings work
case $tools/ in $root/*) ;; *) [[ -d $tools ]] && args+=(-v "$tools":"$tools":ro) ;; esac
px=${HTTPS_PROXY:-${https_proxy:-}}
if [[ -n $px ]]; then
  args+=(-e HTTPS_PROXY=$px -e https_proxy=$px)
  np=${NO_PROXY:-${no_proxy:-}}; [[ -n $np ]] && args+=(-e NO_PROXY=$np -e no_proxy=$np)
  ph=${px#*://}; ph=${ph##*@}; ph=${ph%%/*}; ph=${ph%:*}
  [[ $ph == (127.0.0.1|localhost) && " $pre ${UPG_EXTRA:-} " != *" --net"* ]] && args+=(--network host)
fi
ca=${UPG_CA:-}
[[ -n $ca && ! -f $ca ]] && { echo "mxrun.sh: UPG_CA=$ca is not a file" >&2; exit 2; }
if [[ -z $ca && -n $px ]]; then for c in ${SSL_CERT_FILE:-} /root/.ccr/ca-bundle.crt; do [[ -f $c ]] && { ca=$c; break; }; done; fi
[[ -n $ca ]] && args+=(-v "${ca:A}":/etc/upg/ca.crt:ro -e SSL_CERT_FILE=/etc/upg/ca.crt)
if [[ -n ${UPG_ENV_FILE:-} ]]; then
  [[ -f $UPG_ENV_FILE ]] || { echo "mxrun.sh: UPG_ENV_FILE=$UPG_ENV_FILE is not a file" >&2; exit 2; }
  args+=(--env-file "${UPG_ENV_FILE:A}")
fi
[[ -n $UPG_DRYRUN ]] && { print -r -- docker run $args $pre ${=UPG_EXTRA} $img "$@"; exit 0; }
if [[ ${UPG_RETRY_CRASH:-0} -gt 0 ]]; then
  o=$(mktemp) e=$(mktemp); tries=$UPG_RETRY_CRASH; prevcrash=0; flaked=0
  for ((i = 0; i <= tries; i++)); do
    docker run $args $pre ${=UPG_EXTRA} $img "$@" > $o 2> $e; rc=$?
    crashed=0; [[ $rc == 139 ]] && crashed=1
    [[ $rc != 0 ]] && grep -Eq 'signal: aborted|AccessViolationException|Segmentation fault' $o $e && crashed=1
    flake=0
    if [[ $crashed == 0 && $rc != 0 && $prevcrash == 1 && $flaked == 0 ]] && grep -Eq 'Object reference not set|Collection was of a fixed size' $o $e; then
      flake=1; flaked=1; tries=$((tries + 1))   # FM-2: one extra try for a loader flake after a crash retry
    fi
    prevcrash=$crashed
    [[ ( $crashed == 1 || $flake == 1 ) && $i -lt $tries ]] || break
    if [[ $flake == 1 ]]; then print -u2 "mxrun.sh: model loader exception after a crash retry (rc $rc): amd64 emulation flake, rerun $((i + 1)) of $tries"
    else print -u2 "mxrun.sh: tool crash (rc $rc), retry $((i + 1)) of $tries"; fi
    sleep ${UPG_RETRY_CRASH_SLEEP:-3}
  done
  cat $o; cat $e >&2; rm -f $o $e; exit $rc
fi
exec docker run $args $pre ${=UPG_EXTRA} $img "$@"
