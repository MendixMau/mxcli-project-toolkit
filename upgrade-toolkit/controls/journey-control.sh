#!/bin/bash
# journey-control.sh <tmp dir>: control for the user journeys (steps/journeys.md), called by run-controls.sh without
# --fast. Real app start in Docker plus a Playwright run, so the whole control holds the REAL heavy lock once.
#   pass   the final E1 MDA (MFA on): the always-on journeys login-User and mfa-password-only-refused PASS
#   catch  the SAME MDA with one planted fault, CONST_OVERRIDES MFAmodule.EnabledMFA=false (the E1 defect: MFA silently
#          off): mfa-password-only-refused must FAIL and run_journeys.py must exit 1
# Journeys are generated from the E1 project (impact_map.py old old = the always-on baseline set, gen_journeys.py).
# Ports 8880/8890 only (PORT_OFF=800), database fx_ctl_journey only (a createdb -T copy of the frozen E1 baseline,
# dropped afterwards), container ctl-journey only. Test users: smoke_users.py (role User) plus the seeded MFA user s102
# (MFA type Google_Authenticator, given role User), passwords set on the copy AFTER the start. The pass case alone
# cannot tell "refused because of MFA" from "refused because the login is broken" (same message); the catch case on the
# same users proves the MFA user's password works. Evidence: $UPG_LAB/controls-last-journey.
set -u
T=$1; here=$(cd "$(dirname "$0")" && pwd); B=$here/../bin
if [ "${2:-}" != --locked ]; then
  UPG_NAME=upgrade-toolkit-controls UPG_LOCK= exec zsh $B/heavy-lock.sh "journey-control (ports 8880/8890, db fx_ctl_journey)" \
    bash "$0" "$T" --locked
fi
unset UPG_LOCK UPG_LOCK_POLL
LAB=${UPG_LAB:-$HOME/upgrade-lab}; E1=$LAB/f1/runs/e1/app; E1W=$LAB/f1/runs/e1/work
W=$T/journey; mkdir -p $W
export WORKDIR=$W UPG_TOOLS=$LAB/f1/mig/tools PORT_OFF=800 UPG_DB_PREFIX=fx_ UPG_NAME=ctl UPG_SESSION_TIMEOUT=30000
db=fx_ctl_journey; tmpl=e1_base_frozen; pw='Ctl-only-3!'
psql() { docker exec -i mig-pg psql -U mendix "$@"; }

git -C $E1 show 693f127:common-parts-app.mpr > $W/app.mpr
python3 $B/impact_map.py $W/app.mpr $W/app.mpr --out $W/impact.json > $W/impact.out 2>&1
python3 $B/gen_journeys.py $W/impact.json --out-dir $W/gen --roles-with-users User > $W/gen.out 2>&1
[ -f $W/gen/journeys/User/mfa-password-only-refused.journey.json ] || { echo "FAIL  journey-generate (no MFA journey; see $W/gen.out)"; exit 1; }
echo "ok    journey-generate (always-on set has login-User and mfa-password-only-refused)"
hash=$(python3 -c "import bcrypt,sys; print('{BCrypt}' + bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(10, prefix=b'2a')).decode())" "$pw")
printf '{"User": {"user": "smoke_user", "pass": "%s"}, "_mfa": {"user": "s102", "pass": "%s"}}\n' "$pw" "$pw" > $W/users.json

run() {  # label consts-json [run_journeys args] -> runs the journeys, leaves exit code in $W/<label>.rc
  local label=$1 consts=$2; shift 2
  psql -d postgres -qc "drop database if exists $db" > /dev/null
  psql -d postgres -qc "create database $db template $tmpl" > /dev/null || { echo 99 > $W/$label.rc; return; }
  CONST_OVERRIDES=$consts python3 $B/runapp.py start journey $E1W/new-10.24.16.mda 10.24.16 $db > $W/$label-start.out 2>&1 \
    || { echo 98 > $W/$label.rc; python3 $B/runapp.py stop journey > /dev/null 2>&1; return; }
  python3 $B/smoke_users.py $db --roles User --password "$pw" --apply > $W/$label-users.out 2>&1
  # the MFA user needs a user role too: a user without roles is refused like a wrong password, and the MFA journey
  # would then PASS for the wrong reason (seen while building this control)
  psql -d $db -v ON_ERROR_STOP=1 >> $W/$label-users.out 2>&1 <<SQL
update "system\$user" set password='$hash', active=true, blocked=false, failedlogins=0 where name='s102';
delete from "system\$userroles" where "system\$userid" = (select id from "system\$user" where name='s102');
insert into "system\$userroles" ("system\$userid", "system\$userroleid")
  select u.id, r.id from "system\$user" u, "system\$userrole" r where u.name='s102' and r.name='User';
select 'mfa user', u.name, a.mfa_type, count(x.*) from "system\$user" u join "administration\$account" a on a.id=u.id
  left join "system\$userroles" x on x."system\$userid"=u.id where u.name='s102' group by 1,2,3;
SQL
  python3 $B/run_journeys.py $W/gen --label $label --port 8880 --admin-port 8890 --admin-pass m2ee-local-only \
    --users $W/users.json --work $W/e2e --only login-User,mfa-password-only-refused "$@" > $W/$label.out 2>&1
  echo $? > $W/$label.rc
  python3 $B/runapp.py stop journey > /dev/null 2>&1
  psql -d postgres -qc "drop database if exists $db" > /dev/null
}
ok=0
run pass '{}'
if [ "$(cat $W/pass.rc)" = 0 ] && grep -Eq '^ +PASS +mfa-password-only-refused' $W/pass.out; then
  echo "ok    journey-mfa-pass (MFA on: password alone refused)"
else echo "FAIL  journey-mfa-pass (rc $(cat $W/pass.rc))"; tail -12 $W/pass.out $W/pass-start.out 2>/dev/null | sed 's/^/      | /'; ok=1; fi
run catch '{"MFAmodule.EnabledMFA": "false"}' --compare $W/e2e/pass/summary.json
if [ "$(cat $W/catch.rc)" = 1 ] && grep -Eq '^ +FAIL +mfa-password-only-refused.*\[REGRESSION\]' $W/catch.out && grep -Eq '^ +PASS +login-User' $W/catch.out; then
  echo "ok    journey-mfa-catch (planted EnabledMFA=false: MFA user got in with the password alone, journey FAIL, REGRESSION vs the pass run)"
else echo "FAIL  journey-mfa-catch (rc $(cat $W/catch.rc))"; tail -12 $W/catch.out $W/catch-start.out 2>/dev/null | sed 's/^/      | /'; ok=1; fi
# evidence outside the repo (screenshots and logs show the app): $UPG_LAB/controls-last-journey
rm -rf $LAB/controls-last-journey; mkdir -p $LAB/controls-last-journey
cp -R $W/*.out $W/e2e/pass $W/e2e/catch $W/logs $LAB/controls-last-journey/ 2>/dev/null
exit $ok
