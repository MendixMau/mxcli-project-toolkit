#!/bin/bash
# seed_cl.sh <run folder> <empty frozen db> <target db (name contains _smoke)>
# Checklist to go 1.0.0 seed (no publisher snapshot: route b, use-case spec). Idempotent: rebuilds <target db> from the empty frozen copy.
set -euo pipefail
RUN=$1; EMPTY=$2; DB=$3
HERE=$(cd "$(dirname "$0")" && pwd); B=$HERE/../../bin
P="docker exec -i mig-pg psql -U mendix -d $DB"
docker exec mig-pg dropdb -U mendix --if-exists "$DB"; docker exec mig-pg createdb -U mendix -T "$EMPTY" "$DB"
python3 "$B/smoke_users.py" "$DB" --roles Administrator,DepartmentManager,Inspector --sole-target --apply >/dev/null
python3 "$HERE/gen_checklist_spec.py" > "$HERE/checklist-seed.json"
python3 "$HERE/seed_usecase.py" --psql "$P" --mpr "$RUN/cl/app/App.mpr" "$HERE/checklist-seed.json" --apply | tail -3
