#!/usr/bin/env bash
# file-bugs.sh — a per-project bug log (docs/bugs.jsonl) and a safe way to file it publicly.
#
#   bin/file-bugs.sh [--project DIR]                  # dry run: redacted title + body, duplicates
#   bin/file-bugs.sh --file BUG-02 [--file ...]       # file that bug, after a y/N per bug
#   bin/file-bugs.sh --all                            # every open bug, still a y/N per bug
#   bin/file-bugs.sh --links                          # prefilled github new-issue URL per open bug
#   bin/file-bugs.sh --json                           # redacted bugs + URLs as JSON (for the report)
#   bin/file-bugs.sh --add --target mxcli|toolkit --title T --repro R --expected E --actual A \
#                    [--workaround W] [--mxcli V] [--mendix V]     # append a row, next free BUG-NN
#
# WHY. Both target repos are public (target mxcli = mendixlabs/mxcli, toolkit =
# MendixMau/mxcli-project-toolkit; nothing else is ever addressed). A bug found in a client
# project must leave it without the client in it. Every title and body is redacted first
# (home paths, user and host names, emails, IPs, tokens, URLs other than the two repos, the
# project's .mpr / module / entity names from PROJECT.md and mdlsource/, and the deny list in
# $LEAKGUARD_DENY or <project>/.leakguard-deny), then scanned again. A bug that still looks
# unsafe is shown with a warning and never posted, never given a URL.
# Posting needs --file/--all AND an interactive y/N; stdin must be a terminal
# (MXTK_FILE_BUGS_STDIN=1 lets tests feed answers). A successful post writes status=filed and
# issue_url back. The id is project-local; the public number is the issue.
# Row fields: id date target title repro expected actual versions{mxcli,mendix,toolkit}
# workaround status(open|filed|fixed) issue_url. Dry run, --links and --json post nothing.
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/portable.sh"
require_py
exec "$PY" -I "$SCRIPT_DIR/lib/file-bugs.py" "$@"
