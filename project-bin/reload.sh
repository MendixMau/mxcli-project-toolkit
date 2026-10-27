#!/usr/bin/env bash
# reload.sh — put the current model into THIS project's running Docker app, keeping its data.
#
#   bin/reload.sh            build the package, then hot-reload the model (no container restart)
#   bin/reload.sh --css      styling only (theme/SCSS already compiled into the deployment)
#   bin/reload.sh --restart  full build + container restart (after a Java/GenAI class change, or when
#                            a reload left the app odd — run 1 cloud A-43: ClassNotFoundException)
#
# WHY (run 2, 2026-10-26, arm C). `mxcli docker reload` reaches the M2EE admin API by running curl
# INSIDE the container (mxcli cmd/mxcli/docker/m2ee.go, v0.24 and v0.28 alike), and the
# eclipse-temurin JRE image has no curl. Every reload failed with "sh: 1: curl: not found", so the
# lead restarted the container after each change instead. `--direct` calls the same API over HTTP
# from the host, through the mapped admin port, with no curl.
#
# What it saves is the restart and the wait for the port, not mxbuild: the package build stays.
# So refresh the app when you need to LOOK or test, not after every apply.
#
# Falls back to --restart when the reload fails, and says so. Prints the path taken and seconds.
# Exit: 0 app serving the new model · 1 not proven up · 2 usage.
set -u
cd "$(dirname "$0")/.." || exit 2
MPR=$(ls ./*.mpr 2>/dev/null | head -1); [ -n "$MPR" ] || { echo "reload.sh: no .mpr here" >&2; exit 2; }
MXB=${MXTK_MXBUILD_PATH:-}
mxb() { [ -n "$MXB" ] && printf -- '--mxbuild-path\n%s\n' "$MXB"; }
mode=reload
case "${1:-}" in "") ;; --css) mode=css ;; --restart) mode=restart ;; *) sed -n 2,8p "$0"; exit 2 ;; esac

# The admin port as mapped on the host (compose maps container 8090 to it).
admin=$(cd .docker 2>/dev/null && docker compose port mendix 8090 2>/dev/null | sed 's/.*://')
app_url=$(grep -m1 -o 'http://localhost:[0-9]*' CLAUDE.md 2>/dev/null); app_url=${app_url:-http://localhost:8080}
up() { for i in $(seq 1 90); do [ "$(curl -s -o /dev/null -w '%{http_code}' "$app_url/login.html")" = 200 ] && return 0; sleep 2; done; return 1; }

t0=$(date +%s)
if [ "$mode" != restart ] && [ -n "$admin" ]; then
  args=(-p "$MPR" --direct --port "$admin"); [ "$mode" = css ] && args+=(--css) || { args+=(--skip-check); while IFS= read -r a; do args+=("$a"); done < <(mxb); }
  if out=$(./mxcli docker reload "${args[@]}" 2>&1); then
    up && { echo "reload.sh: $mode via --direct OK in $(( $(date +%s) - t0 )) s"; exit 0; }
  fi
  echo "reload.sh: $mode failed, falling back to restart: $(printf '%s' "$out" | grep -v WARNING | tail -1)"
fi
[ -z "$admin" ] && echo "reload.sh: app not running (no admin port mapped); starting it"
args=(-p "$MPR"); while IFS= read -r a; do args+=("$a"); done < <(mxb)
./mxcli docker build "${args[@]}" 2>&1 | grep -E 'rror|BUILD|CE[0-9]' | tail -3
./mxcli docker up -p "$MPR" --detach >/dev/null 2>&1 || (cd .docker && docker compose up -d >/dev/null 2>&1)
up && { echo "reload.sh: restart OK in $(( $(date +%s) - t0 )) s"; exit 0; }
echo "reload.sh: app not answering on $app_url after $(( $(date +%s) - t0 )) s"; exit 1
