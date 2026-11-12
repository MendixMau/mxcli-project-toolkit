#!/bin/bash
# seed_vi.sh <run folder> <empty frozen db> <target db (name contains _smoke)>
# Visual Inspection 3.0.0 seed, idempotent because it always rebuilds <target db> from the empty frozen copy.
# Order matters (SEEDING-LEARNINGS.md): snapshot -> smoke users -> rebase dates -> gap spec (relative dates, so AFTER the rebase).
set -euo pipefail
RUN=$1; EMPTY=$2; DB=$3
HERE=$(cd "$(dirname "$0")" && pwd); B=$HERE/../../bin
APP="$RUN/vi/app"; MPR="$APP/MFI - Visual Inspection.mpr"
P="docker exec -i mig-pg psql -U mendix -d $DB"
docker exec mig-pg dropdb -U mendix --if-exists "$DB"; docker exec mig-pg createdb -U mendix -T "$EMPTY" "$DB"
# the app creates its own deeplink rows at first start; the snapshot has them too (unique name): waive, the app owns that table
python3 "$B/seed_snapshot.py" "$APP/data-snapshot.zip" --psql "$P" --skip 'deeplink$deeplink' | tail -2
python3 "$B/smoke_users.py" "$DB" --roles Administrator,QualityManager,Inspector --sole-target --apply >/dev/null
python3 "$HERE/rebase_dates.py" --psql "$P" --anchor 'inspection$inspection.createdon' --hours-ago 6 --apply | tail -2
python3 "$HERE/gen_vi_spec.py" "$P" > "$HERE/vi-gap-seed.json"
python3 "$HERE/seed_usecase.py" --psql "$P" --mpr "$MPR" "$HERE/vi-gap-seed.json" --apply | tail -2
