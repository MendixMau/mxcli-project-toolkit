#!/usr/bin/env bash
# setup.sh: make a Claude Code cloud container (Ubuntu 24.04 amd64) ready for upgrade-toolkit runs.
# Merged from the worker setups T1-T8 (T8 as base). Re-runnable: every step checks before it acts.
#
# Usage: MENDIX_PAT=... bash setup.sh --run-dir DIR --source FULLVER --target FULLVER [--target2 FULLVER]
#        [--only step[,step]] [--skip step[,step]] [--check]
# Full versions only: 10.24.26.123458 (4 parts). Exception: 11.x without build number (T7 used 11.15.0).
# --check only reports which steps are done: exit 0 if all done, 3 otherwise. Bad args: exit 2.
# Steps, in order: symlink zsh pydeps pkgs docker images build cacert mxcli toolsets mxlinks
#                  playwright journeys auth envsh
# MXCLI_REF (env, default the commit 78bdfa5; v0.28.0 is blocked, see SETUP.md): the mxcli tag, branch or commit the build step checks out and builds; the binary is stamped
# with it, `mxcli --version` is logged and must agree. One run uses one mxcli version (bin/mxcli_pin.sh, SETUP.md).
# Never run 'pkill -f setup.sh' from a shell whose own command line contains that string (T8).
set -euo pipefail

STEPS=(symlink zsh pydeps pkgs docker images build cacert mxcli toolsets mxlinks playwright journeys auth envsh)
CA_BUNDLE=/root/.ccr/ca-bundle.crt
RUN=""; SOURCE_FULL=""; TARGET_FULL=""; TARGET2_FULL=""
ONLY=""; SKIP=""; CHECK=0

# apt with a time box: 'dpkg --configure --pending' can hang after the package is unpacked; the binary works (T1)
apt_in() { timeout 180 apt-get install -y -q "$@" >/dev/null 2>&1 || true; }
apt_up() { timeout 120 apt-get update -q >/dev/null 2>&1 || true; }
log() { echo "[setup $(date -u +%H:%M:%S)] $*"; }
die() { echo "setup.sh: $*" >&2; exit 2; }

# Retry a network command: first try plus 3 retries after 2s, 4s, 8s (transient TLS timeouts: T5, T6, T7, T8).
retry() {
  local d
  for d in 2 4 8; do
    "$@" && return 0
    log "retry in ${d}s: $1 $2"
    sleep "$d"
  done
  "$@"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --run-dir) RUN=${2:-}; shift 2 ;;
    --source) SOURCE_FULL=${2:-}; shift 2 ;;
    --target) TARGET_FULL=${2:-}; shift 2 ;;
    --target2) TARGET2_FULL=${2:-}; shift 2 ;;
    --only) ONLY="$ONLY,${2:-}"; shift 2 ;;
    --skip) SKIP="$SKIP,${2:-}"; shift 2 ;;
    --check) CHECK=1; shift ;;
    -h|--help) sed -n 2,12p "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$RUN" ] || die "--run-dir is required"
[ -n "$SOURCE_FULL" ] || die "--source is required"
[ -n "$TARGET_FULL" ] || die "--target is required"

check_full() {  # $1 flag name, $2 version
  if [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then return 0; fi
  # T7: Mendix 11 toolsets on the CDN carry no build number (mendix-11.15.0.tar.gz)
  if [[ "$2" =~ ^1[1-9]\.[0-9]+\.[0-9]+$ ]]; then return 0; fi
  die "$1 '$2' is not a full version (need 4 parts, e.g. 10.24.26.123458); short versions do not match the CDN tarball names"
}
check_full --source "$SOURCE_FULL"
check_full --target "$TARGET_FULL"
[ -z "$TARGET2_FULL" ] || check_full --target2 "$TARGET2_FULL"

valid_step() { local s; for s in "${STEPS[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }
for s in $(echo "$ONLY,$SKIP" | tr ',' ' '); do valid_step "$s" || die "unknown step '$s' (steps: ${STEPS[*]})"; done
selected() {
  local s=$1
  if [ -n "${ONLY//,/}" ]; then case ",$ONLY," in *",$s,"*) ;; *) return 1 ;; esac; fi
  case ",$SKIP," in *",$s,"*) return 1 ;; esac
  return 0
}

mkdir -p "$RUN" ~/Mendix
RUN=$(cd "$RUN" && pwd)
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
TK=$HOME/Mendix/mxcli-project-toolkit/upgrade-toolkit
MXCLI=$RUN/tools/mxcli-linux
MXCLI_SRC=${MXCLI_SRC:-/opt/mendixlabs/mxcli}
# default: 78bdfa5, the build the pipeline ran on. v0.28.0 is blocked (SETUP.md, "Known problem of v0.28.0")
MXCLI_REF=${MXCLI_REF:-78bdfa51a2e0a84b971093ebd7b6b82e7596c950}
MXCLI_VER=$MXCLI_REF; [[ $MXCLI_REF =~ ^[0-9a-f]{40}$ ]] && MXCLI_VER=${MXCLI_REF:0:7}   # a full commit id reports as its 7-digit form
ANTLR_JAR=$HOME/.m2/repository/org/antlr/antlr4/4.13.2/antlr4-4.13.2-complete.jar
VERSIONS=("$SOURCE_FULL" "$TARGET_FULL")
[ -z "$TARGET2_FULL" ] || VERSIONS+=("$TARGET2_FULL")
SRC_MAJOR=${SOURCE_FULL%%.*}
mkdir -p "$RUN"/tools "$RUN"/work "$RUN"/dl

tgz_name() {  # $1 kind, $2 version
  if [ "$1" = mxbuild ]; then echo "mxbuild-$2.tar.gz"; else echo "mendix-$2.tar.gz"; fi
}
dir_full() { [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]; }

# Which images this path needs. e5-mx9 only for 9.x sources (T7 skipped it: no 9.x on a 10.6 path).
need_mx9() { [ "$SRC_MAJOR" = 9 ]; }
# BT-1: the Mendix 9 mxbuild before 9.20 is Mono-era (modeler/mxbuild.exe): it needs the e5-mx9-mono image (Dockerfile.mx9-mono)
# and bin/mono-shim.sh on its toolset (step toolsets).
need_mono() { [ "$SRC_MAJOR" = 9 ] && [ "$(echo "$SOURCE_FULL" | cut -d. -f2)" -lt 20 ]; }
# Java 17 variant: no worker built one (T7 used mig-mx10 / JDK 21 for 10.6 sources), so nothing to add.
# If a 10.x source below 10.24 ever needs it, add it here: [ "$SRC_MAJOR" = 10 ] && [ "$SRC_MINOR" -lt 24 ].
base_images() {
  echo "eclipse-temurin:21-jdk postgres:16"
  if need_mx9; then echo "eclipse-temurin:11-jdk"; fi
}

# ---- each step has chk_<name> (0 = done) and step_<name> ----

chk_symlink() { [ -e ~/Mendix/mxcli-project-toolkit ]; }
step_symlink() {  # the toolkit hard-codes ~/Mendix/mxcli-project-toolkit
  ln -sfn "$REPO" ~/Mendix/mxcli-project-toolkit
}

chk_zsh() { command -v zsh >/dev/null; }
step_zsh() {  # every bin/*.sh is a zsh script
  apt_up
  apt_in zsh
  command -v zsh >/dev/null
}

# T1/T3/T4/T5/T7/T8: python3 -m pip, NOT pip3 (a different interpreter in this image)
chk_pydeps() { python3 -c 'import bson, bcrypt' 2>/dev/null && command -v antlr4 >/dev/null 2>&1; }
step_pydeps() {
  python3 -c 'import bson' 2>/dev/null || retry python3 -m pip install -q pymongo   # T3: bson readers
  python3 -c 'import bcrypt' 2>/dev/null || retry python3 -m pip install -q bcrypt  # T2, T8: test users
  command -v antlr4 >/dev/null 2>&1 || retry python3 -m pip install -q 'antlr4-tools==0.2.2'
}

# T4/T6: psql client for seed/snapshot; T2: design_props_guard.sh needs rsync; the controls need sqlite3;
# T6/T7: host Maven for vendorlib_mvn.sh (mx sync-java-dependencies fails behind the proxy)
chk_pkgs() { command -v psql >/dev/null && command -v rsync >/dev/null && command -v sqlite3 >/dev/null && command -v mvn >/dev/null; }
step_pkgs() {
  apt_up
  command -v psql >/dev/null || apt_in postgresql-client
  command -v rsync >/dev/null || apt_in rsync
  command -v sqlite3 >/dev/null || apt_in sqlite3
  command -v mvn >/dev/null || apt_in maven
  chk_pkgs
}

chk_docker() { docker info >/dev/null 2>&1; }
step_docker() {  # installed in the image but not running; works with overlayfs
  log "starting dockerd"
  # T3: nohup + subshell so it survives the calling shell
  (nohup dockerd > "$RUN/dockerd.log" 2>&1 &)
  for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
  docker info --format 'docker {{.ServerVersion}} {{.Driver}}'
}

pull_one() {  # $1 image; Docker Hub answers 429 from the shared egress IP (T1): mirrors, then retag
  local img=$1 m
  for m in mirror.gcr.io/library public.ecr.aws/docker/library; do
    if retry docker pull -q "$m/$img" >/dev/null 2>&1; then docker tag "$m/$img" "$img"; return 0; fi
  done
  return 1
}
chk_images() {
  local img
  docker info >/dev/null 2>&1 || return 1
  for img in $(base_images); do docker image inspect "$img" >/dev/null 2>&1 || return 1; done
}
step_images() {
  local img
  for img in $(base_images); do
    docker image inspect "$img" >/dev/null 2>&1 || pull_one "$img" || { log "cannot pull $img"; return 1; }
  done
}

chk_build() {
  docker info >/dev/null 2>&1 || return 1
  docker image inspect mig-mx10 >/dev/null 2>&1 || return 1
  if need_mx9; then docker image inspect e5-mx9 >/dev/null 2>&1 || return 1; fi
  if need_mono; then docker image inspect e5-mx9-mono >/dev/null 2>&1 || return 1; fi
}
step_build() {
  # apt inside the build: plain http through the agent proxy is 405, direct port 80 works with --network host (T1)
  docker image inspect mig-mx10 >/dev/null 2>&1 ||
    retry docker build -q --network host -t mig-mx10 -f "$TK/bin/docker/Dockerfile.mx10" "$TK/bin/docker"
  if need_mx9; then
    docker image inspect e5-mx9 >/dev/null 2>&1 ||
      retry docker build -q --network host -t e5-mx9 -f "$TK/bin/docker/Dockerfile.mx9" "$TK/bin/docker"
  fi
  if need_mono; then
    docker image inspect e5-mx9-mono >/dev/null 2>&1 ||
      retry docker build -q --network host -t e5-mx9-mono -f "$TK/bin/docker/Dockerfile.mx9-mono" "$TK/bin/docker"
  fi
}

# T6/T8: the container mxcli fails with x509 unknown authority at the Marketplace (agent proxy CA).
# Fix written to env.sh: UPG_EXTRA mounts the bundle and points the container at it (T3, T6),
# and UPG_UPDATE_CMD (T8) runs the marketplace update with the host mxcli instead.
chk_cacert() { [ -s "$CA_BUNDLE" ]; }
step_cacert() { log "no CA bundle at $CA_BUNDLE: container Marketplace calls will fail with x509 errors"; return 1; }

# The built binary must be the pinned ref: a binary built from HEAD earlier (or from another MXCLI_REF) is rebuilt.
mxcli_is_ref() { "$1" --version 2>/dev/null | head -1 | grep -qE "(^| )${MXCLI_VER//./\\.}( |\$)"; }
mxcli_checkout() {  # the ref (tag, branch or commit) at depth 1 into $MXCLI_SRC
  mkdir -p "$MXCLI_SRC"; [ -d "$MXCLI_SRC/.git" ] || git -C "$MXCLI_SRC" init -q
  git -C "$MXCLI_SRC" remote get-url origin >/dev/null 2>&1 || git -C "$MXCLI_SRC" remote add origin https://github.com/mendixlabs/mxcli
  GIT_LFS_SKIP_SMUDGE=1 git -C "$MXCLI_SRC" fetch -q --depth 1 origin "$MXCLI_REF" &&
    git -C "$MXCLI_SRC" checkout -q -f --detach FETCH_HEAD
}
chk_mxcli() { [ -x "$RUN/tools/mxcli-bin/mxcli" ] && [ -L "$MXCLI" ] && [ -e "$MXCLI" ] && [ -L ~/.local/bin/mxcli ] && mxcli_is_ref "$RUN/tools/mxcli-bin/mxcli"; }
step_mxcli() {
  if [ -x "$RUN/tools/mxcli-bin/mxcli" ] && ! mxcli_is_ref "$RUN/tools/mxcli-bin/mxcli"; then
    log "mxcli in $RUN/tools/mxcli-bin is not $MXCLI_VER ($("$RUN/tools/mxcli-bin/mxcli" --version 2>/dev/null | head -1)): rebuilding"
    rm -f "$RUN/tools/mxcli-bin/mxcli"
  fi
  if [ ! -x "$RUN/tools/mxcli-bin/mxcli" ]; then
    # GitHub release downloads are 403 at the egress proxy (T1): build from source, at the pinned ref (not HEAD)
    retry mxcli_checkout
    command -v antlr4 >/dev/null 2>&1 || retry python3 -m pip install -q 'antlr4-tools==0.2.2'
    # T2/T8: repo1.maven.org answers 429; antlr4-tools looks in ~/.m2 first, so pre-place the jar from the GCS mirror
    if [ ! -s "$ANTLR_JAR" ]; then
      mkdir -p "$(dirname "$ANTLR_JAR")"
      retry curl -sS -f -o "$ANTLR_JAR.part" https://maven-central.storage-download.googleapis.com/maven2/org/antlr/antlr4/4.13.2/antlr4-4.13.2-complete.jar ||
        retry curl -sS -f -o "$ANTLR_JAR.part" https://repo.maven.apache.org/maven2/org/antlr/antlr4/4.13.2/antlr4-4.13.2-complete.jar
      mv "$ANTLR_JAR.part" "$ANTLR_JAR"
    fi
    # `make build` runs the generate steps itself (its prerequisites: grammar = make -C mdl/grammar generate, sync-all,
    # completions; the checkout ships no generated parser). VERSION= stamps the binary with the ref: a depth-1 checkout has no
    # tag to `git describe`, and sync-all leaves the tree "dirty".
    (cd "$MXCLI_SRC" && ANTLR4_TOOLS_ANTLR_VERSION=4.13.2 GOTOOLCHAIN=auto make build VERSION="$MXCLI_VER" BUILD_DIR="$RUN/tools/mxcli-bin")
  fi
  ln -sfn "$RUN/tools/mxcli-bin/mxcli" "$MXCLI"
  mkdir -p ~/.local/bin && ln -sfn "$RUN/tools/mxcli-bin/mxcli" ~/.local/bin/mxcli
  log "mxcli: $("$MXCLI" --version 2>/dev/null | head -1) (MXCLI_REF=$MXCLI_REF)"
  mxcli_is_ref "$MXCLI" || { log "mxcli --version does not report $MXCLI_VER"; return 1; }
}

chk_toolsets() {
  local v kind
  for v in "${VERSIONS[@]}"; do
    for kind in mxbuild runtime; do dir_full "$RUN/tools/$kind-$v" || return 1; done
  done
}
step_toolsets() {
  local v kind tgz
  cd "$RUN/tools"
  for v in "${VERSIONS[@]}"; do
    for kind in mxbuild runtime; do
      dir_full "$kind-$v" && continue
      tgz=$(tgz_name "$kind" "$v")
      # T6: download to .part and extract into .tmp, so an interrupted run never leaves a half toolset
      [ -f "$tgz" ] || { retry curl -sS -f -o "$tgz.part" "https://cdn.mendix.com/runtime/$tgz" && mv "$tgz.part" "$tgz"; }
      rm -rf "$kind-$v.tmp" && mkdir -p "$kind-$v.tmp"
      tar -xzf "$tgz" -C "$kind-$v.tmp"
      rm -rf "$kind-$v" && mv "$kind-$v.tmp" "$kind-$v"
      rm -f "$tgz"   # T2/T7: disk allowance is ~30 GB, drop tarballs
    done
    # BT-1: a Mono-era mxbuild (9.0 to 9.19) gets its mono shim
    [ ! -f "mxbuild-$v/modeler/mxbuild.exe" ] || [ -e "mxbuild-$v/modeler/mxbuild" ] || bash "$TK/bin/mono-shim.sh" "$RUN/tools/mxbuild-$v"
  done
}

# T8: host mxcli finds toolsets in ~/.mxcli/mxbuild/<full version>
chk_mxlinks() {
  local v
  for v in "${VERSIONS[@]}"; do [ -L ~/.mxcli/mxbuild/"$v" ] || return 1; done
}
step_mxlinks() {
  local v
  mkdir -p ~/.mxcli/mxbuild
  for v in "${VERSIONS[@]}"; do ln -sfn "$RUN/tools/mxbuild-$v" ~/.mxcli/mxbuild/"$v"; done
}

chk_playwright() { [ -d ~/mendix-playwright/node_modules/playwright ]; }
step_playwright() {  # preinstalled Chromium is used; skip the browser download
  mkdir -p ~/mendix-playwright
  (cd ~/mendix-playwright && { [ -f package.json ] || npm init -y >/dev/null; } &&
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 retry npm install -q playwright@1.56 >/dev/null 2>&1)
}

chk_journeys() { [ -d ~/Mendix/mxcli-project-toolkit/project-tests/e2e ]; }
step_journeys() {  # T8: journey engine (public repo), read-only clone
  rm -rf ~/Mendix/mxcli-project-toolkit
  retry git clone -q --depth 1 https://github.com/MendixMau/mxcli-project-toolkit ~/Mendix/mxcli-project-toolkit
}

chk_auth() { [ -x "$MXCLI" ] && "$MXCLI" auth status >/dev/null 2>&1; }
step_auth() {  # T3/T4/T8: non-interactive login with the PAT
  if [ -z "${MENDIX_PAT:-}" ]; then log "MENDIX_PAT not set: skipping mxcli auth login"; return 0; fi
  retry "$MXCLI" auth login --token "$MENDIX_PAT" >/dev/null 2>&1
}

chk_envsh() { [ -s "$RUN/env.sh" ] && grep -q "SOURCE_FULL=\"$SOURCE_FULL\"" "$RUN/env.sh" &&
  grep -q "TARGET_FULL=\"$TARGET_FULL\"" "$RUN/env.sh" && grep -q "TARGET2_FULL=\"$TARGET2_FULL\"" "$RUN/env.sh"; }
step_envsh() {
  cat > "$RUN/env.sh" <<ENVEOF
# Generated by setup.sh. Source it before running the toolkit: . $RUN/env.sh
# Toolkit root (the toolkit hard-codes ~/Mendix/mxcli-project-toolkit)
export TK="$TK"
# Run folder: tools/, work/, app copies
export RUN="$RUN"
export UPG_ROOT="$RUN"
export UPG_TOOLS="$RUN/tools"
# Full versions of the path
export SOURCE_FULL="$SOURCE_FULL"
export TARGET_FULL="$TARGET_FULL"
export TARGET2_FULL="$TARGET2_FULL"
# Linux mxcli built from source
export MXCLI="$MXCLI"
export UPG_MXCLI="$MXCLI"
case ":\$PATH:" in *":\$HOME/.local/bin:"*) ;; *) export PATH="\$HOME/.local/bin:\$PATH" ;; esac
# T6/T8: the container mxcli fails the Marketplace TLS handshake behind the agent proxy (x509 unknown authority).
# Extra docker args for mxrun.sh: proxy env plus the proxy CA bundle mounted and trusted.
# Verified by T3 and T6 (T4 used the mount and SSL_CERT_FILE only).
export UPG_EXTRA="--network host -e HTTPS_PROXY=\${HTTPS_PROXY:-} -e https_proxy=\${HTTPS_PROXY:-} -e NO_PROXY=localhost,127.0.0.1 -v $CA_BUNDLE:/etc/ssl/certs/ccr-ca.crt:ro -e SSL_CERT_FILE=/etc/ssl/certs/ccr-ca.crt"
# T8: run the Marketplace update with the host mxcli (toolsets via ~/.mxcli/mxbuild/<full>), not in the container.
# stepupdate.sh requires the command to end with the mxcli call.
# Not exported by default: the toolkit default (container mxcli) works once UPG_EXTRA carries the CA. Uncomment to use T8's route.
# export UPG_UPDATE_CMD="$MXCLI marketplace update {cid} --to {version} --module {module} -p {mpr}"
# T7: nothing to split; mx10.sh/mx9.sh add -e HOME=/tmp to UPG_EXTRA themselves unless HOME= is already in it.
ENVEOF
}

# ---- run ----
if [ "$CHECK" = 1 ]; then
  pending=0
  for s in "${STEPS[@]}"; do
    selected "$s" || continue
    if "chk_$s" 2>/dev/null; then log "check $s: done"; else log "check $s: NOT done"; pending=1; fi
  done
  [ "$pending" = 0 ] && exit 0
  exit 3
fi

failed=()
for s in "${STEPS[@]}"; do
  selected "$s" || { log "skip $s"; continue; }
  if "chk_$s" 2>/dev/null; then log "ok $s (already done)"; continue; fi
  log "run $s"
  set +e; ( set -e; "step_$s" ); rc=$?; set -e
  if [ "$rc" != 0 ]; then log "FAILED $s (exit $rc)"; failed+=("$s"); fi
done

if [ ${#failed[@]} -gt 0 ]; then log "failed steps: ${failed[*]}"; exit 1; fi
log "done"
