#!/usr/bin/env bash
# ============================================================================
# run-hub.sh — expose a locally-running Mendix app at a public URL, with the
#              settings its outbound calls actually need.
# ----------------------------------------------------------------------------
# Usage:  MXCLI_HUB_KEY=<key> bin/run-hub.sh [<project-root>] [-- <extra mxcli args>]
#
# Reasoning, symptoms and the isolation that found them:
#   skills/preview-over-hub-tunnel.md
#
# WHY THIS WRAPPER EXISTS AT ALL. `mxcli run --hub` is one command and this is
# three flags on top of it. Those three flags are the difference between a demo
# that works and one where the AI silently cannot answer, and none of them is
# guessable from the failure:
#
#   --db-name            the default is the .mpr NAME, not your database. Wrong
#                        default -> "The database to be used does not exist",
#                        which reads as a broken environment.
#
#   --runtime-setting    the Mendix runtime's REST client is configured from
#   http.proxyHost/Port  RUNTIME SETTINGS, not JVM system properties. A sandbox
#                        that advertises its proxy in JAVA_TOOL_OPTIONS therefore
#                        does NOT cover a `Call REST`: the call goes out
#                        unproxied and Mendix Cloud GenAI answers
#                        "403 - Host not in allowlist ... add this host to your
#                        network egress settings" -- which sends you to the
#                        allowlist, where nothing is wrong. Check with curl: a
#                        401 means the host was reachable all along.
#
# THE HUB KEY IS A SECRET. It is read from the environment and must never be
# written into this file, a wrapper, or a commit. Get one from https://<hub>/cli.
# ============================================================================
set -euo pipefail

HUB_URL="${MXCLI_HUB_URL:-https://hub.mxcli.org}"
ROOT="${1:-$(pwd)}"
[ "${1:-}" = "--" ] && ROOT="$(pwd)"
[ -d "$ROOT" ] || { echo "run-hub: no such directory: $ROOT" >&2; exit 2; }
cd "$ROOT"

: "${MXCLI_HUB_KEY:?run-hub: set MXCLI_HUB_KEY in the environment (never commit it)}"

# The .mpr, wherever this project keeps it: repo root, or under app/ in a
# two-tree checkout. Refuse to guess between two -- picking the wrong model is
# worse than stopping.
# Dedupe by RESOLVED path. A project may keep a root-level symlink to the real
# model under app/ so that root-relative tooling works; find reports both, and
# refusing to choose between two names for one file is a false alarm that stops
# the launcher for no reason. Ambiguity means two DIFFERENT models.
# Portable resolve (macOS system bash is 3.2: no mapfile; readlink -f is GNU-only).
# Bounded symlink walk, same pattern as tests/retests/retest-bug22-settings-writes.sh.
_resolve() {
  local t="$1" hops=0
  while [ -L "$t" ] && [ "$hops" -lt 16 ]; do
    local dest; dest="$(ls -ld "$t" | sed 's/.* -> //')"
    case "$dest" in /*) t="$dest" ;; *) t="$(cd "$(dirname "$t")" && pwd)/$dest" ;; esac
    hops=$((hops+1))
  done
  printf '%s/%s\n' "$(cd "$(dirname "$t")" && pwd)" "$(basename "$t")"
}
MPRS=()
while IFS= read -r f; do MPRS+=("$f"); done < <(
  find . -maxdepth 3 -name '*.mpr' -not -path '*/.mpr-snapshots/*' \
       -not -path '*/.docker/*' -not -path '*/node_modules/*' 2>/dev/null \
  | while read -r f; do printf '%s\t%s\n' "$(_resolve "$f")" "$f"; done \
  | sort -u -k1,1 | cut -f2- | sort)
case "${#MPRS[@]}" in
  0) echo "run-hub: no .mpr found under $ROOT" >&2; exit 2 ;;
  1) MPR="${MPRS[0]}" ;;
  *) if [ -n "${MPR_FILE:-}" ]; then MPR="$MPR_FILE"; else
       echo "run-hub: ${#MPRS[@]} .mpr files found — set MPR_FILE to choose:" >&2
       printf '  %s\n' "${MPRS[@]}" >&2; exit 2
     fi ;;
esac

# Database: the mxcli default is derived from the .mpr name and is usually not
# the database a project actually populated.
# Credentials come from the environment or the project's own generated .docker/.env —
# never from a literal here (the leak guard refuses a hard-coded password, rightly).
if [ -z "${DB_PASSWORD:-}" ] && [ -f "$ROOT/.docker/.env" ]; then
  DB_PASSWORD="$(sed -n 's/^RUNTIME_PARAMS_DATABASEPASSWORD=//p' "$ROOT/.docker/.env" | head -1)"
fi
DB_NAME="${DB_NAME:-mendix}"
DB_USER="${DB_USER:-mendix}"
: "${DB_PASSWORD:?run-hub: set DB_PASSWORD (or let .docker/.env provide RUNTIME_PARAMS_DATABASEPASSWORD — mxcli docker init writes it)}"

ARGS=(run --hub "$HUB_URL" -p "$MPR"
      --db-name "$DB_NAME" --db-user "$DB_USER" --db-password "$DB_PASSWORD")
[ -n "${MXCLI_HUB_PROJECT:-}" ] && ARGS+=(--hub-project "$MXCLI_HUB_PROJECT")

_p="${HTTPS_PROXY:-${https_proxy:-}}"
if [ -n "$_p" ]; then
  _hp="${_p#*://}"; _hp="${_hp%/}"
  ARGS+=(--runtime-setting "http.proxyHost=${_hp%%:*}"
         --runtime-setting "http.proxyPort=${_hp##*:}")
  echo "run-hub: runtime REST via ${_hp%%:*}:${_hp##*:} (JVM proxy properties do NOT cover Call REST)"
fi

# Anything after `--` goes straight to mxcli (--watch, --hub-prefix, …).
while [ $# -gt 0 ]; do [ "$1" = "--" ] && { shift; ARGS+=("$@"); break; }; shift; done

MXCLI="./mxcli"; command -v mxcli >/dev/null 2>&1 && [ ! -x "$MXCLI" ] && MXCLI="mxcli"

echo "run-hub: $MPR -> $HUB_URL (db $DB_NAME)"
echo "run-hub: after it prints the URL, EXERCISE ONE OUTBOUND CALL before sharing it."
echo "run-hub: a 200 from the app root proves the web tier, not that integrations can reach anything."
exec "$MXCLI" "${ARGS[@]}"
