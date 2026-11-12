#!/bin/bash
# run_variant.sh <run folder> <app: vi|cl> <label> <frozen db> <full version> <port_off> [<data-snapshot.zip>] [-- extra run_journeys args]
# env JOURNEYS=<dir> runs another journey set (e.g. without the data-wiping 'Reset all demodata' journey).
# One journeys run of the OLD app on its own copy of a frozen database (steps/baseline.md items 5-7, steps/journeys.md):
# copy db -> start (+ snapshot files) -> smoke_users (one user per role, sole-target) -> run_journeys. Writes <app>/work/e2e-<label>/ and
# <app>/work/journeys-<label>.out. Needs <app>/work/{old.mda,users.json,journeys/,actions.json} (see SEEDING-LEARNINGS.md "commands").
set -uo pipefail
RUN=$1; APP=$2; LABEL=$3; FROZEN=$4; VER=$5; OFF=$6; SNAP=${7:-}
shift 6; [ $# -gt 0 ] && shift; [ "${1:-}" = "--" ] && shift
EXTRA=("$@")
HERE=$(cd "$(dirname "$0")" && pwd); B=$HERE/../../bin
W=$RUN/$APP/work; DB=${FROZEN%_frozen}_${LABEL}_smoke
export UPG_NAME=mig-$LABEL PORT_OFF=$OFF
docker exec mig-pg dropdb -U mendix --if-exists "$DB"; docker exec mig-pg createdb -U mendix -T "$FROZEN" "$DB" || exit 2
export WORKDIR=$W
NAME=j$LABEL
WORKDIR=$W "$HERE/start_with_files.sh" "$RUN" "$NAME" old.mda "$VER" "$DB" $SNAP > "$W/start-$LABEL.log" 2>&1 || { echo "start failed, see $W/start-$LABEL.log"; exit 3; }
ROLES=$(python3 -I -c 'import json,sys;print(",".join(json.load(open(sys.argv[1]))))' "$W/users.json")
python3 "$B/smoke_users.py" "$DB" --roles "$ROLES" --sole-target --apply ${SMOKE_ENTITY:+--entity $SMOKE_ENTITY} >> "$W/start-$LABEL.log" 2>&1 || { echo "smoke_users failed"; tail -5 "$W/start-$LABEL.log"; exit 4; }
python3 "$B/run_journeys.py" "${JOURNEYS:-$W/journeys}" --label "$LABEL" --port $((8080+OFF)) --psql "docker exec -i mig-pg psql -U mendix -d $DB" \
  --admin-port $((8090+OFF)) --admin-pass m2ee-local-only --users "$W/users.json" --work "$W/e2e-$LABEL" --pause 50 --actions "$W/actions.json" "${EXTRA[@]}" > "$W/journeys-$LABEL.out" 2>&1
echo "run_journeys rc=$?" >> "$W/journeys-$LABEL.out"
python3 "$B/runapp.py" stop "$NAME" > /dev/null 2>&1
