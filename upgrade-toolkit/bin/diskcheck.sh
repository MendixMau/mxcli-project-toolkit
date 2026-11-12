#!/usr/bin/env bash
# diskcheck.sh [--need-mb N] [--log FILE] PATH: say plainly when the disk, not the app, is the problem (BT-10).
# Why (batch-templates DOCGEN): the old-app build wrote app/deployment (858 MB) onto a full disk and mxbuild reported
# "An error occurred while creating the deployment package"; the stop read as an app defect and the cause was found by df.
# Exit 0 = enough room and no out-of-space line in the log. Exit 1 = DISK FULL: free MB below --need-mb (default 2000),
# or FILE holds "No space left on device" / ENOSPC. The message names the cause and the fix.
# UPG_FREE_MB replaces the df reading (controls). Called by bin/cloud/upgrade-pipeline.sh before baseline, convert and build,
# and again when a build fails (so a disk-full stop is named as such). Producer of the call: those mandatory steps.
need=2000; log=""; path=""
while [ $# -gt 0 ]; do
  case "$1" in --need-mb) need=${2:-2000}; shift 2 ;; --log) log=${2:-}; shift 2 ;; *) path=$1; shift ;; esac
done
[ -n "$path" ] || { echo "usage: diskcheck.sh [--need-mb N] [--log FILE] PATH" >&2; exit 2; }
if [ -n "${UPG_FREE_MB:-}" ]; then free=$UPG_FREE_MB
else free=$(df -Pm "$path" 2> /dev/null | awk 'NR==2{print $4}'); fi
free=${free:-0}
why=""
if [ -n "$log" ] && [ -f "$log" ] && grep -Eiq 'No space left on device|ENOSPC|not enough space on the disk' "$log"; then
  why="the log holds an out-of-space error (No space left on device)"
elif [ "$free" -lt "$need" ]; then
  why="only ${free} MB are free on the disk holding $path, this step needs about ${need} MB"
fi
if [ -n "$why" ]; then
  echo "DISK FULL: $why. This is the host, not the app: a build that fails with \"An error occurred while creating the deployment package\" on a full disk says nothing about the app."
  echo "Fix: free about $((need / 1000 + 1)) GB (finished run folders under work/run/, tools of finished runs, docker system prune, the shipped deployment/ folder of the app), or use a disk with 4 GB or more free per app, then rerun the same command (it resumes at this step)."
  exit 1
fi
echo "disk ok: ${free} MB free"
