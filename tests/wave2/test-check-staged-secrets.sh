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

echo "-- nothing staged: clean"
OUT="$(bash bin/check-staged-secrets.sh 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "clean exits 0" || bad "clean exits 0 (got $RC)"
has "reports how many values it checked" "$OUT" "3 value(s) checked"

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

echo; echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
