#!/usr/bin/env bash
# setup-container.sh: make a fresh Linux container (Claude Code cloud, Ubuntu 24.04 amd64) or laptop ready for an
# upgrade run. Re-runnable: every step checks before it acts.
#
#   MENDIX_PAT=... bash setup-container.sh <run folder> <mendix version> [<mendix version> ...]
#   e.g. bash setup-container.sh ~/run1 9.24.3.8044 10.24.26.123458 11.15.0
#
# Versions are the full CDN names (Mendix 9/10 carry a build number; see https://cdn.mendix.com/?prefix=runtime/mxbuild-).
# Then: `source <run folder>/upg-env.sh` and follow ../SKILL.md.
# The controls (`make fast`) also want a 10.24 toolset: add a 10.24.x version to the list (B4N1-3).
# Exit: 0 = ready; non-zero = NOT ready, the failing step says what is missing (B4T2-1, B4N1-3: python modules and rsync
#   used to be "installed" with `|| true` and the REFUSED toolcheck ran BEFORE the pip step, exit 0 either way).
# Env: UPG_PYTHON (default python3); UPG_MAVEN_MIRROR = an extra Maven repository base URL tried first for the ANTLR jar
#   (credentials never in the URL: they would show in ps and logs; put them in ~/.netrc, curl --netrc-optional reads it);
#   MXCLI_REF = the mxcli tag, branch or commit step 5 builds (default the commit 78bdfa5, never HEAD); the binary is stamped with it and
#   the pipeline pins the version it finds at triage (bin/mxcli_pin.sh).
#   UPG_SETUP_STEPS = comma list of steps to run (link,zsh,docker,images,antlr,mxcli,toolsets,host,playwright,auth,env,
#   check; default all; the controls run single steps).
#
# Why this file (SETUP-1): every batch-1 to batch-3 worker copied T1's runs/t1-purchase-request/setup.sh by hand and
# re-learned its traps. Each step below was needed in a real run (T1, T2, N1 JOURNAL.md):
#  1 ~/Mendix/mxcli-project-toolkit symlink (SKILL.md paths)       6 mxbuild + runtime per version from cdn.mendix.com
#  2 zsh (the bin/*.sh wrappers are zsh scripts)                7 python modules (pymongo for bson, bcrypt), rsync
#  3 dockerd (installed but not running in the cloud image)    8 Playwright module (Chromium is preinstalled there)
#  4 base images via mirror.gcr.io (Docker Hub 429), toolkit   9 mxcli marketplace auth from $MENDIX_PAT
#    images built with --network host                         10 upg-env.sh: proxy + CA for mxcli in its container
#  5 mxcli built from source (GitHub release downloads 403); the ANTLR jar pre-placed in ~/.m2 first: Maven Central
#    answers 429 from a shared egress IP and `make build` then fails (B4T2-1); mirror fallback
#  11 check: toolcheck.sh --host AFTER step 7; REFUSED or no rsync = exit 1 (B4T2-1, B4N1-3)
# The journey engine is vendored (../vendor/e2e): no other repo is cloned except mendixlabs/mxcli (public).
set -euo pipefail
[ $# -ge 2 ] || { sed -n 2,8p "$0" >&2; exit 2; }
R=$(mkdir -p "$1" && cd "$1" && pwd); shift
TK=$(cd "$(dirname "$0")/.." && pwd); REPO=$(cd "$TK/.." && pwd)
mkdir -p "$R"/{tools,work,dl} ~/Mendix
log(){ echo "[setup $(date -u +%H:%M:%S)] $*"; }
want(){ [ -z "${UPG_SETUP_STEPS:-}" ] || [[ ",$UPG_SETUP_STEPS," == *",$1,"* ]]; }
PY=${UPG_PYTHON:-python3}
ANTLR_VER=4.13.2
ANTLR_JAR=$HOME/.m2/repository/org/antlr/antlr4/$ANTLR_VER/antlr4-$ANTLR_VER-complete.jar   # where antlr4-tools 0.2.2 looks first
antlr_jar() {  # B4T2-1: pre-place the jar; repo1.maven.org answers 429, so try mirrors; a non-zip answer (proxy page) is no jar
  local rel=org/antlr/antlr4/$ANTLR_VER/antlr4-$ANTLR_VER-complete.jar base bases=() tried=()
  if [ -s "$ANTLR_JAR" ] && [ "$(head -c 2 "$ANTLR_JAR")" = PK ]; then log "antlr jar present: $ANTLR_JAR"; return 0; fi
  if [ -n "${UPG_MAVEN_MIRROR:-}" ]; then
    case $UPG_MAVEN_MIRROR in
      *://*@*) echo "setup: REFUSED, UPG_MAVEN_MIRROR carries credentials in the URL (they would show in ps and logs); put them in ~/.netrc (machine <host> login <user> password <pw>) and give the plain URL" >&2; exit 2;;
    esac
    bases+=("${UPG_MAVEN_MIRROR%/}")
  fi
  bases+=(https://repo1.maven.org/maven2 https://maven-central.storage-download.googleapis.com/maven2 https://repo.maven.apache.org/maven2)
  mkdir -p "$(dirname "$ANTLR_JAR")"
  for base in "${bases[@]}"; do
    rm -f "$ANTLR_JAR.part"
    if curl -sS -f -L --retry 2 --netrc-optional -o "$ANTLR_JAR.part" "$base/$rel" && [ "$(head -c 2 "$ANTLR_JAR.part" 2>/dev/null)" = PK ]; then
      mv "$ANTLR_JAR.part" "$ANTLR_JAR"; log "antlr jar placed from $base"; return 0
    fi
    tried+=("$base"); log "antlr jar: $base failed (429, unreachable or not a jar), next"
  done
  rm -f "$ANTLR_JAR.part"
  echo "setup: REFUSED, antlr4-$ANTLR_VER-complete.jar could not be fetched from ${tried[*]}; put it at $ANTLR_JAR by hand (or set UPG_MAVEN_MIRROR) and rerun" >&2
  exit 1
}

# 1 toolkit path
if want link; then
  [ -e ~/Mendix/mxcli-project-toolkit ] || ln -sfn "$REPO" ~/Mendix/mxcli-project-toolkit
  log "toolkit at $(readlink -f ~/Mendix/mxcli-project-toolkit)"
fi

# 2 zsh
if want zsh && ! command -v zsh >/dev/null; then
  apt-get update -q >/dev/null 2>&1 || true
  apt-get install -y -q zsh >/dev/null 2>&1 || true   # dpkg postinst may report an error; the binary still works
fi
command -v zsh >/dev/null || { echo "setup: zsh missing and apt-get could not install it" >&2; exit 1; }

# 3 docker daemon
if want docker; then
  if ! docker info >/dev/null 2>&1; then
    log "starting dockerd"
    (nohup dockerd > "$R/dockerd.log" 2>&1 &)
    for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
  fi
  docker info --format 'docker {{.ServerVersion}} {{.Driver}}'
fi

# 4 images: Docker Hub answers 429 from a shared egress IP, so pull from a mirror and retag
want images && for img in eclipse-temurin:11-jdk eclipse-temurin:21-jdk postgres:16; do
  docker image inspect $img >/dev/null 2>&1 && continue
  docker pull --platform linux/amd64 -q $img >/dev/null 2>&1 && continue   # S2: mxrun.sh runs linux/amd64; an arm64 pull (Apple Silicon) would not match
  for m in mirror.gcr.io/library public.ecr.aws/docker/library; do
    docker pull --platform linux/amd64 -q $m/$img >/dev/null 2>&1 && docker tag $m/$img $img && break
  done
  docker image inspect $img >/dev/null 2>&1 || { echo "setup: could not pull $img" >&2; exit 1; }
done
# apt inside the build: plain http through the agent proxy is 405, direct port 80 works with --network host
want images && { docker image inspect mig-mx10 >/dev/null 2>&1 || docker build --platform linux/amd64 -q --network host -t mig-mx10 -f "$TK/bin/docker/Dockerfile.mx10" "$TK/bin/docker"
docker image inspect e5-mx9  >/dev/null 2>&1 || docker build --platform linux/amd64 -q --network host -t e5-mx9  -f "$TK/bin/docker/Dockerfile.mx9"  "$TK/bin/docker"
# BT-1: Mendix 9 before 9.20 has a Mono-era mxbuild: the same image plus Mono
for v in "$@"; do [ "${v%%.*}" = 9 ] && [ "$(echo "$v" | cut -d. -f2)" -lt 20 ] && { docker image inspect e5-mx9-mono >/dev/null 2>&1 || docker build --platform linux/amd64 -q --network host -t e5-mx9-mono -f "$TK/bin/docker/Dockerfile.mx9-mono" "$TK/bin/docker"; break; }; done; }

# 5 mxcli from source (public repo mendixlabs/mxcli; a release binary works too: put it at tools/mxcli-linux), at MXCLI_REF
# default: 78bdfa5, the build the pipeline ran on. v0.28.0 is blocked (SETUP.md, "Known problem of v0.28.0")
MXCLI_REF=${MXCLI_REF:-78bdfa51a2e0a84b971093ebd7b6b82e7596c950}
MXCLI_VER=$MXCLI_REF; [[ $MXCLI_REF =~ ^[0-9a-f]{40}$ ]] && MXCLI_VER=${MXCLI_REF:0:7}   # a full commit id reports as its 7-digit form
# ref_state BIN: 0 = BIN reports MXCLI_REF, 1 = another version, 2 = cannot tell (does not run here, e.g. a Linux binary on a Mac)
ref_state() {
  local v; v=$("$1" --version 2>/dev/null | head -1) || v=""
  [ -n "$v" ] || return 2
  case " $v " in *" $MXCLI_VER "*) return 0;; *) return 1;; esac
}
mxcli_checkout() {  # $1 = source dir: MXCLI_REF (tag, branch or commit) at depth 1, no HEAD
  mkdir -p "$1"; [ -d "$1/.git" ] || git -C "$1" init -q
  git -C "$1" remote get-url origin >/dev/null 2>&1 || git -C "$1" remote add origin https://github.com/mendixlabs/mxcli
  GIT_LFS_SKIP_SMUDGE=1 git -C "$1" fetch -q --depth 1 origin "$MXCLI_REF" && git -C "$1" checkout -q -f --detach FETCH_HEAD
}
if want antlr && [ ! -x "$R/tools/mxcli-linux" ]; then antlr_jar; fi
if want mxcli; then
  # our own earlier build of another ref is rebuilt; a binary somebody put at tools/mxcli-linux is theirs: warned, not replaced
  if [ -x "$R/tools/mxcli-linux" ] && [ "$(readlink -f "$R/tools/mxcli-linux")" = "$(readlink -f "$R/tools/mxcli-bin/mxcli" 2>/dev/null || echo -)" ]; then
    ref_state "$R/tools/mxcli-linux" || [ $? = 2 ] || { log "tools/mxcli-linux is not $MXCLI_VER ($("$R/tools/mxcli-linux" --version 2>/dev/null | head -1)): rebuilding"; rm -f "$R/tools/mxcli-linux" "$R/tools/mxcli-bin/mxcli"; }
  fi
  if [ ! -x "$R/tools/mxcli-linux" ]; then
    src=${MXCLI_SRC:-$HOME/mendixlabs/mxcli}
    mxcli_checkout "$src" || { echo "setup: could not fetch mxcli $MXCLI_REF from github.com/mendixlabs/mxcli" >&2; exit 1; }
    "$PY" -m pip install -q 'antlr4-tools==0.2.2'
    # S1: tools/mxcli-linux runs in the linux/amd64 container (mxcli-container.sh), so cross-build it even on a Mac.
    # `make build` runs the generate steps itself (prerequisites grammar = make -C mdl/grammar generate, sync-all, completions;
    # the checkout ships no generated parser). VERSION= stamps the binary: a depth-1 checkout has no tag to describe.
    (cd "$src" && GOOS=linux GOARCH=amd64 ANTLR4_TOOLS_ANTLR_VERSION=$ANTLR_VER GOTOOLCHAIN=auto make build VERSION="$MXCLI_VER" BUILD_DIR="$R/tools/mxcli-bin")
    ln -sfn "$R/tools/mxcli-bin/mxcli" "$R/tools/mxcli-linux"
  fi
  rs=0; ref_state "$R/tools/mxcli-linux" || rs=$?
  case $rs in
    0) log "mxcli: $("$R/tools/mxcli-linux" --version 2>/dev/null | head -1) (MXCLI_REF=$MXCLI_REF)";;
    1) log "WARNING: tools/mxcli-linux reports '$("$R/tools/mxcli-linux" --version 2>/dev/null | head -1)', MXCLI_REF is $MXCLI_REF: the pipeline pins whatever it finds at triage (bin/mxcli_pin.sh)";;
    *) log "mxcli: tools/mxcli-linux does not run on this host ($(uname -s)); its version is checked inside the container";;
  esac
  # S1: the host mxcli is the user's own; only a Linux host with none gets this (Linux) binary, never a Mac or a host that has one
  if [ "$(uname -s)" = Linux ] && ! command -v mxcli >/dev/null && { [ ! -e ~/.local/bin/mxcli ] || [ -L ~/.local/bin/mxcli ]; }; then
    mkdir -p ~/.local/bin && ln -sfn "$(readlink -f "$R/tools/mxcli-linux")" ~/.local/bin/mxcli
  else
    log "host mxcli left alone ($(command -v mxcli || echo "none on PATH; $(uname -s) host")); the container uses $R/tools/mxcli-linux"
  fi
fi

# 6 toolsets per version
want toolsets && for v in "$@"; do
  for kind in mxbuild runtime; do
    tgz=$([ $kind = mxbuild ] && echo "mxbuild-$v.tar.gz" || echo "mendix-$v.tar.gz")
    if [ -z "$(ls -A "$R/tools/$kind-$v" 2>/dev/null)" ]; then
      [ -f "$R/dl/$tgz" ] || curl -sS -f -o "$R/dl/$tgz" "https://cdn.mendix.com/runtime/$tgz" \
        || { echo "setup: $tgz not on the CDN; check the full version name" >&2; exit 1; }
      mkdir -p "$R/tools/$kind-$v" && tar -xzf "$R/dl/$tgz" -C "$R/tools/$kind-$v"
    fi
  done
  # BT-1: a Mono-era mxbuild (9.0 to 9.19) gets its mono shim
  [ ! -f "$R/tools/mxbuild-$v/modeler/mxbuild.exe" ] || [ -e "$R/tools/mxbuild-$v/modeler/mxbuild" ] || bash "$TK/bin/mono-shim.sh" "$R/tools/mxbuild-$v"
done

# 7 python modules ($PY -m pip: plain pip may install into another python), rsync (design_props_guard). A failure here is
#   not hidden: step 11 runs toolcheck.sh --host afterwards and exits non-zero (B4T2-1, B4N1-3)
if want host; then
  for m in bson:pymongo bcrypt:bcrypt PIL:pillow; do
    "$PY" -c "import ${m%%:*}" >/dev/null 2>&1 || "$PY" -m pip install -q "${m#*:}" || log "pip install ${m#*:} failed"
  done
  if ! command -v rsync >/dev/null; then
    { apt-get update -q && apt-get install -y -q rsync; } >/dev/null 2>&1 || log "apt-get install rsync failed"
  fi
fi

# 8 Playwright module for smokewalk.js and the journeys (browsers: /opt/pw-browsers in the cloud image)
if want playwright && [ ! -d ~/mendix-playwright/node_modules/playwright ]; then
  mkdir -p ~/mendix-playwright && (cd ~/mendix-playwright && npm init -y >/dev/null && \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=${PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD:-1} npm install -q playwright@1.56.1 >/dev/null 2>&1)
fi
# S3: no /opt/pw-browsers (not the cloud image) = no Chromium: fetch it, unless the caller set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD
if want playwright && [ ! -d "${UPG_PW_OPT:-/opt/pw-browsers}" ]; then
  if [ -n "${PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD:-}" ]; then
    log "NEXT-STEP: Chromium not installed (PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD is set): cd ~/mendix-playwright && npx --yes playwright@1.56.1 install chromium"
  else
    log "no /opt/pw-browsers: installing Chromium"
    (cd ~/mendix-playwright && npx --yes playwright@1.56.1 install chromium)
  fi
fi

# 9 marketplace auth (host and container both read ~/.mxcli/auth.json); the token never lands in a file here, nor on a
#   command line (ps shows argv to every user): `mxcli auth login` without --token reads it from stdin (B4T2-1)
if want auth && [ -n "${MENDIX_PAT:-}" ] && [ ! -f ~/.mxcli/auth.json ] && ! command -v mxcli >/dev/null; then
  log "NEXT-STEP: no host mxcli on PATH: install one, then: printf %s \"\$MENDIX_PAT\" | mxcli auth login"
elif want auth && [ -n "${MENDIX_PAT:-}" ] && [ ! -f ~/.mxcli/auth.json ]; then
  printf '%s\n' "$MENDIX_PAT" | mxcli auth login >/dev/null
fi
want auth && [ ! -f ~/.mxcli/auth.json ] && log "WARNING: no MENDIX_PAT and no ~/.mxcli/auth.json: Marketplace downloads and module updates will fail"

# 10 environment for the container wrappers (cloud: the agent proxy and its CA; harmless where they are absent)
ca=/root/.ccr/ca-bundle.crt
want env && {
  echo "export UPG_ROOT=$R UPG_TOOLS=$R/tools WORKDIR=$R/work"
  if [ -f $ca ]; then
    echo "export UPG_EXTRA=\"--network host -e HTTPS_PROXY=\${HTTPS_PROXY:-} -e SSL_CERT_FILE=/etc/upg-ca.crt -v $ca:/etc/upg-ca.crt:ro\""
  fi
  echo "export UPG_SESSION_TIMEOUT=30000"
} > "$R/upg-env.sh"

# 11 check, AFTER step 7 (B4T2-1: it ran before the pip step and printed REFUSED for modules installed a step later;
#   B4N1-3: REFUSED and no rsync were only printed, exit 0)
if want check; then
  UPG_PYTHON=$PY bash "$TK/bin/toolcheck.sh" --host || { echo "setup: NOT READY: toolcheck.sh --host refused (above); install what it names and rerun" >&2; exit 1; }
  command -v rsync >/dev/null || { echo "setup: NOT READY: rsync missing (apt-get install rsync failed); design_props_guard.sh needs it" >&2; exit 1; }
  ls -d "$R"/tools/mxbuild-10.24.* >/dev/null 2>&1 || log "NOTE: no 10.24 toolset in $R/tools: the controls (make fast) want one; rerun with a 10.24.x version added"
fi
log "done: source $R/upg-env.sh, then follow $TK/SKILL.md"
