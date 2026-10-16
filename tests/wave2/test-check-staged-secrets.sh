#!/usr/bin/env bash
# test-check-staged-secrets.sh — project-bin/check-staged-secrets.sh finds a secret VALUE in staged
# blobs and in the tracked tree, names the file and the key, and never prints the value.
#
# Usage: bash tests/wave2/test-check-staged-secrets.sh
# The .env and run-local.json here are written by this test with made-up values; no field capture
# is claimed. Values are arbitrary strings, so the test proves the mechanism, not a real leak.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="$TOOLKIT/project-bin/check-staged-secrets.sh"
W="$(mktemp -d "${TMPDIR:-/tmp}/mxtk-css.XXXXXX")"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3')"; echo "$2" | sed 's/^/       /' ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (leaked '$3')" ;; *) ok "$1" ;; esac; }

P="$W/proj"; mkdir -p "$P/.mxcli" "$P/bin"; cd "$P" || exit 1
git init -q . && git config user.email t@t && git config user.name t
cp "$SUBJECT" bin/check-staged-secrets.sh
printf 'DEMO_PASSWORD=Zq7-xylophone-91\nAPP_NAME=shortname\nDB=x\n' > .env
printf '.env\n.mxcli/\n' > .gitignore
cat > .mxcli/run-local.json <<'J'
{"pid": 1, "bootConfig": {"DatabasePassword": "pgpass-Tango-55", "DatabaseName": "appdb", "Cards.HubApiPassword": "hubpass-Delta-77"}}
J
git add .gitignore && git commit -q -m init

echo "-- a clean staged file: clean"
printf 'hello\n' > hello.txt; git add hello.txt
OUT="$(bash bin/check-staged-secrets.sh 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "clean exits 0" || bad "clean exits 0 (got $RC)"
has "reports how many values it checked" "$OUT" "3 value(s) checked"

git reset -q hello.txt; rm hello.txt
echo "-- a staged file holding a .env value"
printf '<input value="Zq7-xylophone-91">\n' > login.html; git add login.html
OUT="$(bash bin/check-staged-secrets.sh 2>&1)"; RC=$?
[ "$RC" = 1 ] && ok "exits 1" || bad "exits 1 (got $RC)"
has "names the file" "$OUT" "login.html"
has "names the key" "$OUT" ".env:DEMO_PASSWORD"
hasnt "never prints the value" "$OUT" "Zq7-xylophone-91"

echo "-- a staged file holding a run-local.json bootConfig value"
git reset -q login.html; rm login.html
printf 'x=pgpass-Tango-55\n' > notes.txt; git add notes.txt
OUT="$(bash bin/check-staged-secrets.sh 2>&1)"; RC=$?
[ "$RC" = 1 ] && ok "bootConfig value found" || bad "bootConfig value found (got $RC)"
has "names the bootConfig key" "$OUT" "DatabasePassword"
hasnt "never prints the value" "$OUT" "pgpass-Tango-55"

echo "-- a short or non-secret value is not a source"
git reset -q notes.txt; printf 'shortname appdb\n' > notes.txt; git add notes.txt
OUT="$(bash bin/check-staged-secrets.sh 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "non-secret keys are not scanned for" || bad "non-secret keys are not scanned for (got $RC: $OUT)"

echo "-- --tree sees what is already committed"
printf 'hubpass-Delta-77\n' > committed.txt; git add committed.txt; git commit -q -m leak
git reset -q; OUT="$(bash bin/check-staged-secrets.sh --tree 2>&1)"; RC=$?
[ "$RC" = 1 ] && ok "--tree exits 1" || bad "--tree exits 1 (got $RC)"
has "--tree names the file" "$OUT" "committed.txt"
hasnt "--tree never prints the value" "$OUT" "hubpass-Delta-77"

echo "-- no sources: says so, exits 0"
rm -f .env .mxcli/run-local.json
OUT="$(bash bin/check-staged-secrets.sh 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "no sources exits 0" || bad "no sources exits 0 (got $RC)"
has "no sources is stated, not silent" "$OUT" "nothing checked"

echo "-- the default database password is not a secret (review: mass false positives)"
mkdir -p .mxcli; printf '{"bootConfig": {"DatabasePassword": "mendix"}}' > .mxcli/run-local.json
printf 'DB_PASSWORD=mendix\nOTHER_PASSWORD=Password\n' > .env
printf 'mendix Mendix password\n' > notes.txt; git add notes.txt
OUT="$(bash bin/check-staged-secrets.sh 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "staged 'mendix' with default bootConfig/.env password exits 0" || bad "default password exits 0 (got $RC: $OUT)"
has "says it skipped defaults" "$OUT" "nothing checked"
git reset -q notes.txt

echo "-- .docker/.env is a source; CRLF, spaces and inline comment are normalised"
rm -f .env .mxcli/run-local.json; mkdir -p .docker
printf '%s = %s  # local only\r\n%s=%s\r\n%s="%s"\r\n' M2EE_ADMIN_PASS "Kx9-admin-Quartz-31" DB_PASSWORD mendix TOKEN "Rv4-token-Magnolia-08" > .docker/.env
printf 'a Kx9-admin-Quartz-31 b\n' > one.txt; printf 'Rv4-token-Magnolia-08\n' > two.txt; git add one.txt two.txt
OUT="$(bash bin/check-staged-secrets.sh 2>&1)"; RC=$?
[ "$RC" = 1 ] && ok ".docker/.env value found" || bad ".docker/.env value found (got $RC)"
has "names the .docker/.env key" "$OUT" ".docker/.env:M2EE_ADMIN_PASS"
has "CRLF quoted value matches" "$OUT" "two.txt holds the value of .docker/.env:TOKEN"
hasnt "never prints the value" "$OUT" "Kx9-admin-Quartz-31"
hasnt "never prints a CRLF value" "$OUT" "Rv4-token-Magnolia-08"
git reset -q one.txt two.txt

echo "-- a value equal to .env.example for the same key is published, not a secret"
printf 'API_TOKEN=Published-Example-99\n' > .docker/.env.example
printf 'API_TOKEN=Published-Example-99\n' > .docker/.env
printf 'Published-Example-99\n' > pub.txt; git add pub.txt
OUT="$(bash bin/check-staged-secrets.sh 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "example-equal value ignored" || bad "example-equal value ignored (got $RC: $OUT)"
git reset -q pub.txt

echo "-- run --local writes every model default into MicroflowConstants: a default already in the model is not a source"
rm -rf .docker; rm -f .env; mkdir -p mprcontents/ab
printf 'default: your-api-key-here\n' > mprcontents/ab/unit1.mxunit; git add mprcontents; git commit -q -m model
printf '{"bootConfig": {"MicroflowConstants": {"MyModule.ApiKey": "your-api-key-here", "MyModule.AuthToken": "passed-Cedar-4821"}}}' > .mxcli/run-local.json
printf 'your-api-key-here\n' > unit2.mxunit; git add unit2.mxunit
OUT="$(bash bin/check-staged-secrets.sh 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "placeholder model default staged: exit 0" || bad "placeholder default staged (got $RC: $OUT)"
git reset -q unit2.mxunit
OUT="$(bash bin/check-staged-secrets.sh --tree 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "placeholder model default in --tree: exit 0" || bad "placeholder default --tree (got $RC: $OUT)"
printf 'x=passed-Cedar-4821\n' > leak.txt; git add leak.txt
OUT="$(bash bin/check-staged-secrets.sh 2>&1)"; RC=$?
[ "$RC" = 1 ] && ok "constant value NOT in the model is still found" || bad "constant not in model (got $RC)"
has "names the constant" "$OUT" "MicroflowConstants.MyModule.AuthToken"
hasnt "never prints the value" "$OUT" "passed-Cedar-4821"
git reset -q leak.txt; rm -f leak.txt

echo "-- MXTK_SECRET_VALUES_FILE is not filtered"
printf 'mendix\n' > "$W/extra.txt"; printf 'mendix\n' > tracked.txt; git add tracked.txt; git commit -q -m t; git reset -q
OUT="$(MXTK_SECRET_VALUES_FILE="$W/extra.txt" bash bin/check-staged-secrets.sh --tree 2>&1)"; RC=$?
[ "$RC" = 1 ] && ok "explicit extra value 'mendix' is found (rc 1)" || bad "extra value (rc $RC)"
OUT="$(bash bin/check-staged-secrets.sh --tree 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "without the extra file the default is ignored in --tree" || bad "tree default (rc $RC: $OUT)"

echo; echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
