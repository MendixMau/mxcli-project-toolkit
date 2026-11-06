#!/usr/bin/env bash
# test-contract-check.sh — pin bin/contract-check.sh against captured mxcli output.
#
# Runs with no mxcli: fixtures/contract-check/mxcli-replay.sh answers each call with the real
# mxcli v0.28.0 stdout captured for it (CAPTURE.txt). Two apps: "cars" publishes OData, REST and a
# business event service; "shop" consumes cars over REST and as an OData external entity.
# What is pinned:
#   1. PARSED COUNTS from the captures: cars 1 OData service / 1 entity set / 2 members (one KEY),
#      1 REST operation, 1 business event message; shop 1 consumed REST op, 1 external entity
#      with 2 attributes; the shop base URL held in a constant resolves to its default value.
#   2. DETERMINISTIC: two snapshots are byte-identical.
#   3. base -> 2/2 EDGE, exit 0.  rename (resource renamed, version unchanged) -> BREAKING +
#      VIOLATION + BROKEN shop consumer, exit 1.  drop (exposed attribute dropped from the entity,
#      the case mxcli impact misses) -> BREAKING + DANGLING + BROKEN, exit 1.  bump (same rename,
#      major version bumped) -> 0 VIOLATION but the consumer still BROKEN, exit 1.
#   4. THE BASELINE IS THE COMMITTED COPY: a re-snapshot left uncommitted does not hide a change.
#   5. --impact names the consumer app of an exposed attribute, and NOT-EXPOSED otherwise.
#   6. BOTH LAYOUTS: cars registered as a single-tree root, shop as a two-tree root (app/*.mpr),
#      and a direct .mpr path.
#   7. NO GUESSING: without url columns two publishers of one path read AMBIGUOUS; an app with no
#      publisher in the registry reads EXTERNAL; neither is a violation.
#   8. EXIT 2: no registry, bad role, no baseline (NOT RUN), mxcli failing.
#
# Usage: bash tests/wave2/test-contract-check.sh [path-to-contract-check.sh]
set -u
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
CC="${1:-$TOOLKIT/bin/contract-check.sh}"
FIX="$TOOLKIT/tests/wave2/fixtures/contract-check"
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "no '$2' in output:"; sed 's/^/       /' "$3"; fi; }
hasnt(){ if grep -qF -- "$2" "$3"; then bad "$1" "unexpected '$2'"; else ok "$1"; fi; }
cnt()  { grep -c -- "$1" "$2" | tr -d ' '; }
jq_()  { "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("/"):
    d = d[int(k)] if isinstance(d, list) else d[k]
print(json.dumps(d) if isinstance(d,(dict,list)) else d)' "$1" "$2"; }

export MXTK_CONTRACT_MXCLI="$FIX/mxcli-replay.sh" CC_CAPTURES="$TMP/cap"
unset CC_RECORD MXCLI MXTK_SYSTEM_REGISTRY
cp -R "$FIX/captures" "$TMP/cap"
mkdir -p "$TMP/cars" "$TMP/shop/app" "$TMP/sys"
: > "$TMP/cars/TestApp.mpr"; : > "$TMP/shop/app/TestApp.mpr"
REG="$TMP/sys/system.tsv"
printf '# system\ncars\t../cars\tpublisher\thttp://localhost:8085\nshop\t../shop\tconsumer\thttp://localhost:8086\n' > "$REG"
O="$TMP/out"

echo "== 1-2. snapshot: parsed counts, determinism, both layouts"
bash "$CC" snapshot --registry "$REG" > "$O"; check "snapshot exit 0" "$?" "0"
C="$TMP/sys/contracts/cars.json"; S="$TMP/sys/contracts/shop.json"
check "cars OData services"         "$(jq_ "$C" published/odata | "$PY" -c 'import json,sys;print(len(json.load(sys.stdin)))')" "1"
check "cars entity set name"        "$(jq_ "$C" published/odata/0/entity_sets/0/name)" "VCars"
check "cars exposed members"        "$(jq_ "$C" published/odata/0/entity_sets/0/members | "$PY" -c 'import json,sys;print(len(json.load(sys.stdin)))')" "2"
check "ModelID is KEY"              "$(jq_ "$C" published/odata/0/entity_sets/0/members/1/key)" "True"
check "Brand resolved, String"      "$(jq_ "$C" published/odata/0/entity_sets/0/members/0/type)" "String"
check "cars REST op path"           "$(jq_ "$C" published/rest/0/operations/0/path)" "/rest/cars/v1/cars"
check "cars REST version"           "$(jq_ "$C" published/rest/0/version)" "1.0.0"
check "cars BE message"             "$(jq_ "$C" published/business_events/0/messages/0/name)" "CarSold"
check "shop consumed REST op"       "$(jq_ "$S" consumed/rest/0/operations/0/path)" "/rest/cars/v1/cars"
check "shop external entity set"    "$(jq_ "$S" consumed/odata/0/external_entities/0/entity_set)" "VCars"
check "shop external attributes"    "$(jq_ "$S" consumed/odata/0/external_entities/0/attributes | "$PY" -c 'import json,sys;print(len(json.load(sys.stdin)))')" "2"
has   "counts line printed"         "1 OData service(s) / 1 entity set(s) / 2 member(s), 1 REST service(s) / 1 operation(s), 1 business event service(s) / 1 message(s)" "$O"
cp "$C" "$TMP/c1"; bash "$CC" snapshot --registry "$REG" >/dev/null
if cmp -s "$C" "$TMP/c1"; then ok "second snapshot byte-identical"; else bad "second snapshot byte-identical"; fi

echo "== 3. check per state (baseline = file, not in git)"
bash "$CC" check --registry "$REG" > "$O"; check "base exit 0" "$?" "0"
has "base: REST edge"      "EDGE       shop:MyFirstModule.CarsClient.GetCars -> cars:MyFirstModule.CarsApi GET /rest/cars/v1/cars" "$O"
has "base: OData edge"     "EDGE       shop:MyFirstModule.ECar -> cars:MyFirstModule.CarOdataApi 'VCars'" "$O"
has "base: denominator"    "denominator: 2/2 consumed" "$O"
has "base: baseline named" "BASELINE   cars: file (not in git)" "$O"

CC_STATE_cars=rename bash "$CC" check --registry "$REG" > "$O"; check "rename exit 1" "$?" "1"
has "rename: BREAKING with rename hint" "operation GET /rest/cars/v1/cars removed (renamed to GET /rest/cars/v1/vehicles? same microflow)" "$O"
has "rename: VIOLATION"                 "VIOLATION  cars:MyFirstModule.CarsApi 1 breaking change(s) with major version unchanged (1.0.0 -> 1.0.0)" "$O"
has "rename: consumer BROKEN"           "BROKEN     shop:MyFirstModule.CarsClient.GetCars -> cars:MyFirstModule.CarsApi" "$O"
has "rename: 1/2"                       "denominator: 1/2 consumed" "$O"

CC_STATE_cars=drop bash "$CC" check --registry "$REG" > "$O"; check "drop exit 1" "$?" "1"
has "drop: BREAKING dropped attribute" "'VCars'.Brand still exposed but MyFirstModule.VCar.Brand no longer exists" "$O"
has "drop: VIOLATION"                  "VIOLATION  cars:MyFirstModule.CarOdataApi" "$O"
check "drop: 1 DANGLING row"           "$(cnt '^DANGLING' "$O")" "1"
has "drop: external entity BROKEN"     "BROKEN     shop:MyFirstModule.ECar -> cars:MyFirstModule.CarOdataApi 'VCars'  (Brand exposed but dangling" "$O"
has "drop: REST still fine"            "EDGE       shop:MyFirstModule.CarsClient.GetCars" "$O"

CC_STATE_cars=bump bash "$CC" check --registry "$REG" > "$O"; check "bump exit 1 (consumer still broken)" "$?" "1"
check "bump: 0 VIOLATION" "$(cnt '^VIOLATION' "$O")" "0"
has "bump: VERSION row"   "VERSION    cars:MyFirstModule.CarsApi version 1.0.0 -> 2.0.0" "$O"
has "bump: BROKEN"        "BROKEN     shop:MyFirstModule.CarsClient.GetCars" "$O"

echo "== 4. baseline is the committed copy"
if command -v git >/dev/null 2>&1; then
  ( cd "$TMP/sys" && git init -q . && git add contracts && git -c user.email=t@example.com -c user.name=t commit -qm base ) >/dev/null 2>&1
  CC_STATE_cars=rename bash "$CC" snapshot --registry "$REG" --app cars >/dev/null
  CC_STATE_cars=rename bash "$CC" check --registry "$REG" > "$O"; check "uncommitted re-snapshot: still exit 1" "$?" "1"
  has "baseline from git HEAD" "BASELINE   cars: git HEAD" "$O"
  has "violation still seen"   "VIOLATION  cars:MyFirstModule.CarsApi" "$O"
  CC_STATE_cars=rename bash "$CC" check --registry "$REG" --baseline file > "$O"
  check "--baseline file: re-snapshot hides the diff" "$(cnt '^VIOLATION' "$O")" "0"
  ( cd "$TMP/sys" && git checkout -q -- contracts )
else
  bad "git present" "git not on PATH; section 4 NOT RUN"
fi

echo "== 5. --impact"
bash "$CC" --impact cars:MyFirstModule.VCar.Brand --registry "$REG" > "$O"; check "impact exit 0" "$?" "0"
has "impact: exposed via"  "EXPOSED    cars:MyFirstModule.VCar.Brand via MyFirstModule.CarOdataApi VCars.Brand" "$O"
has "impact: consumer"     "CONSUMER   shop:MyFirstModule.ECar (EDGE)" "$O"
has "impact: denominator"  "1 consumer app(s) in a registry of 2: shop" "$O"
bash "$CC" --impact cars:MyFirstModule.REST_GetCars --registry "$REG" > "$O"
has "impact microflow -> REST consumer" "CONSUMER   shop:MyFirstModule.CarsClient.GetCars (EDGE)" "$O"
bash "$CC" --impact cars:MyFirstModule.Car --registry "$REG" > "$O"
has "impact: not exposed"  "NOT-EXPOSED cars:MyFirstModule.Car" "$O"

echo "== 6-7. layouts, AMBIGUOUS, EXTERNAL"
for f in "$TMP"/cap/base/cars.*; do cp "$f" "$TMP/cap/base/cars2.${f##*/cars.}"; done
mkdir -p "$TMP/cars2"; : > "$TMP/cars2/TestApp.mpr"
R2="$TMP/sys2/system.tsv"; mkdir -p "$TMP/sys2"
printf 'cars\t%s\tpublisher\nshop\t../shop/app/TestApp.mpr\tconsumer\ncars2\t../cars2\tboth\n' "$TMP/cars/TestApp.mpr" > "$R2"
bash "$CC" snapshot --registry "$R2" >/dev/null; check "absolute .mpr + direct two-tree .mpr resolve" "$?" "0"
bash "$CC" check --registry "$R2" > "$O"; check "ambiguous is not a violation" "$?" "0"
check "two AMBIGUOUS rows" "$(cnt '^AMBIGUOUS' "$O")" "2"
has "ambiguous names both apps" "cars,cars2" "$O"
R3="$TMP/sys3/system.tsv"; mkdir -p "$TMP/sys3"; printf 'shop\t../shop\tconsumer\n' > "$R3"
bash "$CC" snapshot --registry "$R3" >/dev/null; bash "$CC" check --registry "$R3" > "$O"; check "external-only exit 0" "$?" "0"
check "two EXTERNAL rows" "$(cnt '^EXTERNAL' "$O")" "2"
has "external denominator" "denominator: 0/2 consumed" "$O"

echo "== 8. exit 2"
bash "$CC" check --registry "$TMP/nope.tsv" >/dev/null 2>&1; check "no registry -> 2" "$?" "2"
R4="$TMP/sys4/system.tsv"; mkdir -p "$TMP/sys4"; printf 'cars\t../cars\tserver\n' > "$R4"
bash "$CC" check --registry "$R4" >/dev/null 2>&1; check "bad role -> 2" "$?" "2"
printf 'cars\t../cars\tpublisher\n' > "$R4"
bash "$CC" check --registry "$R4" > "$O" 2>&1; check "no baseline -> 2" "$?" "2"
has "NOT RUN named" "NOT RUN    no committed baseline for: cars" "$O"
CC_STATE_cars=nosuchstate bash "$CC" snapshot --registry "$R4" >/dev/null 2>&1; check "mxcli failing -> 2" "$?" "2"
printf 'ghost\t../ghost\tpublisher\n' > "$R4"
bash "$CC" snapshot --registry "$R4" >/dev/null 2>&1; check "no .mpr -> 2" "$?" "2"

echo
echo "contract-check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
