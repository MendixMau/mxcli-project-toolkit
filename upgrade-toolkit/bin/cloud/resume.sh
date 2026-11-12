#!/usr/bin/env bash
# resume.sh: after a cloud container restart (dockerd and the pipeline are killed), bring docker back and re-launch the
# pipelines that had not finished.
#
# Usage: resume.sh RUN_DIR [RUN_DIR ...]      RUN_DIR = a folder made by setup.sh, holding run-pipeline.sh and work/
#
# 1. docker: if `docker info` fails, start dockerd (same recipe as setup-container.sh step 3, log <first run>/dockerd.log)
#    and wait up to 60 s for it. Docker never came up: exit 3, nothing launched.
# 2. per run folder, "not finished" = no work/state/gate.done AND the log's last line is not "exit N".
#    Not finished: run-pipeline.sh is started detached (nohup, own session) and appends to the log.
#    The same command resumes: finished steps are skipped by their done markers. Never --from: that clears markers
#    and would redo (and archive) finished journeys.
# Log: <run>/pipeline.log, else the newest <run>/run*.log, else a new pipeline.log.
# Skipped, one line each: finished (gate.done / exit line), already running, no run-pipeline.sh.
# Env: UPG_RESUME_DOCKER_WAIT=SECONDS (default 60); UPG_RESUME_NO_DOCKER=1 skips step 1 (controls, hosts without docker); UPG_RESUME_FOREGROUND=1 waits for each
# launched pipeline instead of detaching (controls).
# Exit: 0 done, 2 usage, 3 docker did not start.
set -u
[ $# -ge 1 ] || { sed -n 2,5p "$0" >&2; exit 2; }
log() { echo "[resume $(date -u +%H:%M:%S)] $*"; }
first=$(cd "$1" 2>/dev/null && pwd) || { echo "resume.sh: not a folder: $1" >&2; exit 2; }

if [ -z "${UPG_RESUME_NO_DOCKER:-}" ]; then
  if ! docker info >/dev/null 2>&1; then
    log "docker is down, starting dockerd"
    (nohup dockerd > "$first/dockerd.log" 2>&1 &)
    for _ in $(seq 1 "${UPG_RESUME_DOCKER_WAIT:-60}"); do docker info >/dev/null 2>&1 && break; sleep 1; done
  fi
  docker info >/dev/null 2>&1 || { echo "resume.sh: docker did not start, see $first/dockerd.log" >&2; exit 3; }
  log "docker up"
fi

for d in "$@"; do
  R=$(cd "$d" 2>/dev/null && pwd) || { log "SKIP $d: not a folder"; continue; }
  if [ ! -f "$R/run-pipeline.sh" ]; then log "SKIP $R: no run-pipeline.sh"; continue; fi
  L=$R/pipeline.log
  [ -f "$L" ] || { n=$(ls -t "$R"/run*.log 2>/dev/null | head -1); [ -z "$n" ] || L=$n; }
  if [ -f "$R/work/state/gate.done" ]; then log "SKIP $R: finished (gate.done)"; continue; fi
  if [ -f "$L" ] && tail -n 1 "$L" | grep -Eq '^exit [0-9]+[[:space:]]*$'; then
    log "SKIP $R: stopped on its own ($(tail -n 1 "$L")), a person owns the next step (see work/NEEDS-JUDGMENT.md)"; continue
  fi
  if command -v pgrep >/dev/null 2>&1 && { pgrep -f "$R/run-pipeline.sh" >/dev/null 2>&1 || pgrep -f "upgrade-pipeline.sh .*--work $R/work" >/dev/null 2>&1; }; then
    # run-pipeline.sh execs upgrade-pipeline.sh, so a live run is found by its --work folder, not the launcher name
    log "SKIP $R: already running"; continue
  fi
  log "RESUME $R (log $L)"
  # no --from: the done markers decide what is skipped
  if [ -n "${UPG_RESUME_FOREGROUND:-}" ]; then
    { bash "$R/run-pipeline.sh"; echo "exit $?"; } >> "$L" 2>&1
  else
    nohup setsid bash -c 'bash "$1"; echo "exit $?"' _ "$R/run-pipeline.sh" >> "$L" 2>&1 < /dev/null &
  fi
done
exit 0
