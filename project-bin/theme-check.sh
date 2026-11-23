#!/usr/bin/env bash
# theme-check.sh — does the app's theme (SCSS) compile? Seconds, no build.
#
#   ./bin/theme-check.sh            # exit 0 compiles · 1 does not (file:line:col, sass's message) · 2 not run
#
# `mx check` never compiles the theme and a deploy build reports a broken one without a place, so a
# row could close green on an app that `mxcli run` then refuses to start ([CE6093] The theme could not
# be compiled ... main.scss 254:58, field regression run 2026-11-17, #837). This runs the dart-sass that
# ships beside mxbuild (<mxbuild dir>/tools/sass/*/sass) over the entry file mxbuild generated
# (deployment/sass/main.scss): ~0.4 s on a fresh Atlas app (measured, Mendix 11.8.0, Linux).
# Callers that need it without asking: exec.sh's gate (every exec), bin/verify-model.sh (a failing
# theme is an error there, no stamp), bin/module-close.sh. The logic is _common.sh mxtk_theme_check.
# "not run" (exit 2) is never green: no sass beside mxbuild, or no full build has written the entry file yet.
# Producer of its inputs: mxbuild's own build (exec.sh's full gate, bin/verify-model.sh), which writes
# deployment/sass/main.scss; theme/ and themesource/ are the project's own SCSS.
set -e
. "$(dirname "$0")/_common.sh"
MD="$(find_model_dir)" || { echo "theme-check: no .mpr found" >&2; exit 2; }
rc=0; mxtk_theme_check "$MD" || rc=$?
mxtk_theme_say
exit "$rc"
