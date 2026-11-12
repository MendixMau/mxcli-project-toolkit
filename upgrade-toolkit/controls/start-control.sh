#!/bin/bash
# start-control.sh <tmp dir>: control for the mandatory quick start of the new app (E1 18, E5 F6), called by
# run-controls.sh without --fast. Real app start in Docker, so it holds the REAL heavy lock (/tmp/heavy-docker.lock)
# and waits while another session holds it.
#   pass   the final E1 MDA (10.24.16) on runtime 10.24.16 starts: runapp.py quick exits 0, "QUICK START PASS"
#   catch  the old E1 MDA (10.12.9) on runtime 10.24.16 cannot start: exit 1, "QUICK START FAIL"
# Ports 8880/8890 only (PORT_OFF=800), database fx_ctl_quick only (UPG_DB_PREFIX=fx_, dropped afterwards), container
# ctl-quick* only. mig-pg is used as it is, never recreated.
set -u
T=$1; here=$(cd "$(dirname "$0")" && pwd); B=$here/../bin
LAB=${UPG_LAB:-$HOME/upgrade-lab}; E1W=$LAB/f1/runs/e1/work
W=$T/start; mkdir -p $W
export WORKDIR=$W UPG_TOOLS=$LAB/f1/mig/tools PORT_OFF=800 UPG_DB_PREFIX=fx_ UPG_NAME=ctl
unset UPG_LOCK UPG_LOCK_POLL   # the real lock: other sessions start apps too
db=fx_ctl_quick
run() {  # name mda -> output in $W/<name>.out
  UPG_NAME=upgrade-toolkit-controls zsh $B/heavy-lock.sh "start-control $1 (ports 8880/8890, db $db)" \
    python3 $B/runapp.py quick $1 $2 10.24.16 $db > $W/$1.out 2>&1
}
ok=0
run quick-new $E1W/new-10.24.16.mda; rc=$?
if [ $rc = 0 ] && grep -q 'QUICK START PASS' $W/quick-new.out; then echo "ok    start-quick-pass (E1 10.24.16 MDA starts)"
else echo "FAIL  start-quick-pass (exit $rc)"; tail -15 $W/quick-new.out | sed 's/^/      | /'; ok=1; fi
docker exec mig-pg dropdb -U mendix --if-exists $db > /dev/null 2>&1
run quick-old $E1W/old-10.12.9-fallback.mda; rc=$?
if [ $rc = 1 ] && grep -q 'QUICK START FAIL' $W/quick-old.out; then echo "ok    start-quick-catch (10.12.9 MDA on runtime 10.24.16 refused)"
else echo "FAIL  start-quick-catch (exit $rc)"; tail -15 $W/quick-old.out | sed 's/^/      | /'; ok=1; fi
docker exec mig-pg dropdb -U mendix --if-exists $db > /dev/null 2>&1
# keep the evidence outside the repo (runtime logs name the app): $UPG_LAB/controls-last-start
mkdir -p $LAB/controls-last-start && cp $W/*.out $W/logs/runtime-quick-*.log $LAB/controls-last-start/ 2>/dev/null
exit $ok
