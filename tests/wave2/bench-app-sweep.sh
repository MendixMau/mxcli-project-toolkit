#!/usr/bin/env bash
# bench-app-sweep.sh — describes per refresh of the app-facts loop sweep, full vs incremental (#297).
#
# Usage: bash tests/wave2/bench-app-sweep.sh [path-to-app-facts.sh] [units] [percent-changed]
#        defaults: project-bin/app-facts.sh, 2000 units, 1 % changed
#
# Builds a synthetic model of N microflow units, every one loop-containing (the worst case: one
# describe per unit), through fixtures/app-facts-incremental/ (a stub mxcli that counts describes),
# then runs: a first map (full), a refresh with nothing changed, a refresh with P % of the units
# changed, and a --full refresh; and --freshness after the map, after the change and after the
# refresh (fresh / N changed / fresh) on a model past the 128 KB single-env-var size. The count of describes is the number that matters: on a real
# model each one costs seconds to tens of seconds (~31 s each measured on a 17,500-unit app), and
# the stub's wall time here says nothing about that. Exit 1 when the incremental refresh describes
# anything other than exactly the changed units.

set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AF="${1:-$TK/project-bin/app-facts.sh}"
case "$AF" in /*) ;; *) AF="$PWD/$AF" ;; esac
N="${2:-2000}"; PCT="${3:-1}"
FX="$TK/tests/wave2/fixtures/app-facts-incremental"
command -v sqlite3 >/dev/null || { echo "SKIP: sqlite3 not on PATH"; exit 0; }
. "$TK/bin/lib/portable.sh"; require_py

W="$(mktemp -d "${TMPDIR:-/tmp}/af-bench.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT
P="$W/proj"; mkdir -p "$P"
export PREP_DB="$W/prep.db" DESCRIBE_LOG="$W/describe.log" STUB_VERSION="mxcli stub 1.0"
CHANGED=$(( N * PCT / 100 ))

spec() {  # spec <version-for-changed-units>
  awk -v n="$N" -v c="$CHANGED" -v v="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "SUB_%05d\t%s\t-\t1\n", i, (i <= c ? v : 1) }'
}
build() { spec "$1" > "$W/spec.tsv"; "$PY" "$FX/mkmodel.py" "$P" "$PREP_DB" "$W/spec.tsv" || exit 2; }
run() {
  : > "$DESCRIBE_LOG"
  local t0; t0=$(date +%s)
  ( cd "$P" && PROJECT_ROOT="$P" MXCLI="$FX/mxcli-stub.sh" bash "$AF" --workers 8 --facts-dir "$P/facts" "$@" ) > "$W/out" 2>&1 \
    || { echo "app-facts failed:"; tail -5 "$W/out"; exit 2; }
  DESC=$(grep -c . "$DESCRIBE_LOG"); SECS=$(( $(date +%s) - t0 ))
}

fresh() { ( cd "$P" && PROJECT_ROOT="$P" bash "$AF" --freshness --facts-dir "$P/facts" ) 2>&1; }

echo "bench-app-sweep: $N units, all loop-containing; $CHANGED changed ($PCT %)"
printf '%-34s %10s %8s\n' "refresh" "describes" "wall s"
build 1; run;        printf '%-34s %10s %8s\n' "first map (full)" "$DESC" "$SECS"; D_FIRST=$DESC
run;                 printf '%-34s %10s %8s\n' "refresh, nothing changed" "$DESC" "$SECS"; D_NONE=$DESC
FR_FIRST="$(fresh)"
build 2; FR_STALE="$(fresh)"
run;                 printf '%-34s %10s %8s\n' "refresh, $PCT % changed (incremental)" "$DESC" "$SECS"; D_INC=$DESC
FR_AFTER="$(fresh)"
run --full;          printf '%-34s %10s %8s\n' "refresh, $PCT % changed (--full)" "$DESC" "$SECS"; D_FULL=$DESC
echo "(wall time is the stub's; on a real model multiply describes by the per-describe cost)"
echo "freshness: after first map '$FR_FIRST' · after $PCT % changed '$FR_STALE' · after refresh '$FR_AFTER'"
case "$FR_FIRST|$FR_STALE|$FR_AFTER" in
  "app map: fresh "*"|app map: $CHANGED units changed since "*"|app map: fresh "*) : ;;
  *) echo "FAIL: --freshness did not report fresh / $CHANGED changed / fresh"; exit 1 ;;
esac
if [ "$D_FIRST" -eq "$N" ] && [ "$D_NONE" -eq 0 ] && [ "$D_INC" -eq "$CHANGED" ] && [ "$D_FULL" -eq "$N" ]; then
  echo "OK: incremental describes $D_INC of $N ($PCT %), full describes $D_FULL"
  exit 0
fi
echo "FAIL: expected $N / 0 / $CHANGED / $N describes, got $D_FIRST / $D_NONE / $D_INC / $D_FULL"
exit 1
