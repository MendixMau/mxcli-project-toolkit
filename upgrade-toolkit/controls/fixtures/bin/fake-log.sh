#!/usr/bin/env bash
# fake-log.sh MPR [mxcli flags...]: stands in for "mxcli marketplace update" and replays REAL captured output
# (controls/fixtures/mxcli-0.28.0/, CAPTURE.txt). Env:
#   FAKE_REFUSE  the log printed (exit 1) when the call has no --force
#   FAKE_SAVED   a folder of real saved-edits files, copied into the --save-edits folder of a forced call
#   FAKE_FORCE   a log printed for a forced call, with exit FAKE_FORCE_RC (default 1); unset = the forced call succeeds
#   FAKE_OK      the model the successful forced call leaves behind (default: no change)
mpr=$1; shift
args=" $* "
if [[ "$args" == *" --force "* ]]; then
  if [[ "$args" == *" --save-edits "* ]]; then
    dir=$(echo "$args" | sed -E 's/.* --save-edits ([^ ]+) .*/\1/'); mkdir -p "$dir"
    [ -z "${FAKE_SAVED:-}" ] || cp "$FAKE_SAVED"/* "$dir"/
  fi
  if [ -n "${FAKE_FORCE:-}" ]; then cat "$FAKE_FORCE"; exit "${FAKE_FORCE_RC:-1}"; fi
  [ -z "${FAKE_OK:-}" ] || cp "$FAKE_OK" "$mpr"
  exit 0
fi
cat "$FAKE_REFUSE"; exit 1
