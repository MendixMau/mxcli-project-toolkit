#!/usr/bin/env bash
# rollback-scan.sh: which side effects survive @cleanup rollback in the flows a unit test calls.
#
#   ./bin/rollback-scan.sh [--json] [--refresh] <tests/x.test.mdl | Module.Flow>...
#
# Advisory: exit 0 always (usage errors 2). A missing or stale catalog is a message, not a failure.
#
# WHY. @cleanup rollback undoes ONE transaction. Measured on a probe app (Mendix 11.15, mxcli
# nightly-20261105, hsqldb, `mxcli test` @cleanup rollback; probe-app run): a rolled-back test still
# left an outbound REST call, file bytes on disk, a consumed autonumber, a separate-transaction
# commit, a queued microflow's commit and the log line. Nothing told the author. Rollback stays
# the default; this prints what it will not undo, before the run.
#
# HOW. Roots = every `call microflow X.Y`, `@setup X.Y` and `@teardown X.Y` in the given test files,
# plus any Module.Flow named. Walks REFS call edges (and entity event handlers of every entity a
# reached flow creates, commits or deletes) in .mxcli/catalog.db, and classifies each reached flow
# with rollback-effects.tsv (data, not code: add a row to teach it a new Java action). Output, one
# line per effect:  class  effect  flow  [detail]  via root > ... > flow
#   A survives and is visible (REST, file, separate commit, queue, mail, workflow)
#   B survives, usually ignorable (autonumber counter, log line)
#   U a Java action nothing classifies (listed once, capped at 10)
# Blind spots, stated: a microflow name passed as a STRING (queue, background) is not an edge, so
# the target's effects are not followed; a custom Java action not in the tsv is only listed as U;
# an effect behind a constant or a decision is reported as reachable. The catalog is read, never
# rebuilt, unless --refresh (a stale catalog is warned about).
#
# Needs Python 3 and a catalog (mxcli -p App.mpr -c "refresh catalog full"). Bash 3.2 compatible.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
. "$SCRIPT_DIR/_common.sh"

JSON=""; REFRESH=0; ITEMS=""
usage() { sed -n '2,5p' "$0" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON="--json"; shift ;;
    --refresh) REFRESH=1; shift ;;
    -h|--help) usage ;;
    --*) echo "rollback-scan: unknown option $1" >&2; usage ;;
    *) ITEMS="$ITEMS
$1"; shift ;;
  esac
done
[ -n "$ITEMS" ] || { echo "rollback-scan: name a .test.mdl file or Module.Flow" >&2; usage; }
require_py

MPR="$(find_mpr 2>/dev/null || true)"
CATALOG=""
[ -n "$MPR" ] && CATALOG="$(dirname "$MPR")/.mxcli/catalog.db"
[ -n "${ROLLBACK_SCAN_CATALOG:-}" ] && CATALOG="$ROLLBACK_SCAN_CATALOG"

if [ "$REFRESH" = 1 ]; then
  MX="${MXCLI:-$(find_project_mxcli 2>/dev/null || command -v mxcli 2>/dev/null || true)}"
  if [ -n "$MX" ] && [ -n "$MPR" ]; then
    "$MX" -p "$MPR" -c "refresh catalog full" >&2 || echo "rollback-scan: refresh catalog failed; scanning what exists" >&2
  else
    echo "rollback-scan: --refresh needs mxcli and an .mpr; scanning what exists" >&2
  fi
fi

EFFECTS="${ROLLBACK_SCAN_EFFECTS:-$SCRIPT_DIR/rollback-effects.tsv}"
[ -f "$EFFECTS" ] || { echo "rollback-scan: rollback-effects.tsv not found beside the script (re-run sync-project.sh)"; exit 0; }

ARGS=()
while IFS= read -r it; do [ -n "$it" ] && ARGS+=("$it"); done <<EOF
$ITEMS
EOF
"$PY" "$SCRIPT_DIR/rollback-scan.py" ${JSON:+"$JSON"} --catalog "$CATALOG" ${MPR:+--mpr "$MPR"} --effects "$EFFECTS" "${ARGS[@]}"
exit 0
