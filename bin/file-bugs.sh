#!/usr/bin/env bash
# file-bugs.sh — a per-project bug log (docs/bugs.jsonl) and a safe way to file it publicly.
#
#   bin/file-bugs.sh [--project DIR]                  # dry run: redacted title + body, duplicates
#   bin/file-bugs.sh --file PBUG-02 [--file ...]       # file that bug, after a y/N per bug
#   bin/file-bugs.sh --all                            # every open bug, still a y/N per bug
#   bin/file-bugs.sh --file PBUG-02 --to mxcli         # file it to the other repo as well (row keeps its target)
#   bin/file-bugs.sh --auto                           # opted-in project only: post every clean open bug, no y/N
#   bin/file-bugs.sh --links                          # prefilled github new-issue URL per open bug
#   bin/file-bugs.sh --json                           # redacted bugs + URLs as JSON (for the report)
#   bin/file-bugs.sh --bundle [PATH]                  # no GitHub: every clean open bug in ONE file to mail
#   bin/file-bugs.sh --import BUNDLE [--dry-run]      # maintainer: file a mailed bundle with your own gh
#   bin/file-bugs.sh --add --target mxcli|toolkit --title T --repro R --expected E --actual A \
#                    [--workaround W] [--mxcli V] [--mendix V] \
#                    [--log FILE [--log-lines N]]  # append a row, next free PBUG-NN; last N (40) log lines, redacted
#
# WHY. Both target repos are public (target mxcli = mendixlabs/mxcli, toolkit =
# MendixMau/mxcli-project-toolkit; nothing else is ever addressed). A bug found in a client
# project must leave it without the client in it. Every title and body is Unicode-normalised
# (NFKC, zero-width and lookalike letters folded), then redacted: home paths, user and host
# names, emails, IPs, tokens and key=value / --flag secrets, any dotted hostname, URLs other than
# the two repos, project names (.mpr, module, entity, attribute, page, microflow from
# PROJECT.md and mdlsource/, matched inside identifiers and across a line break), server names
# from the project's config files, and the deny list ($LEAKGUARD_DENY as a regex like
# check-no-client-data.sh, plus <project>/.leakguard-deny, plus the toolkit clone's .leakguard-deny or
# $MXTK_LEAKGUARD_DENYFILE where init-project.sh registers every project's name; that last one redacts
# but is not the required deny list). Code is not a host: obj.method( keeps its name, a Java package
# keeps its shape with the organisation label redacted (org.<org>.x.y). The versions line is built from
# version-shaped strings only; a row without a toolkit version gets PROJECT.md's Toolkit commit, else
# git describe of the toolkit clone. The same matcher then scans the result. A bug that still looks
# unsafe is shown by the dry run only: no duplicate search, no URL, no --links/--json text, no post.
# A deny list is required: without <project>/.leakguard-deny or $LEAKGUARD_DENY the dry run shows the
# text with a note, and posting, --links and --json are refused. An invalid regex is split on | and its
# valid alternatives kept (the rest warned about). Only the repo prefix of an allowed repo URL (plus
# /issues/N or /pull/N) survives; Authorization/cookie style header values are redacted.
# Posting needs --file/--all AND y/N read from /dev/tty (never stdin). NO SCRIPT CAN TELL A HUMAN FROM
# AN AGENT DRIVING A PTY (a `script` wrapper answers y), so the shipped Claude Code permissions deny
# `file-bugs.sh --file` and `--all` (bin/install-claude-permissions.sh): a human runs posting with
# `!bin/file-bugs.sh --file PBUG-NN`. An agent uses the dry run, --links or --json and hands over --
# UNLESS the person opted the project in with a PROJECT.md line `Bug filing: auto` (exactly that,
# bold/backtick/bullet variants OK, not inside an HTML comment or code fence, and present in the
# committed HEAD too -- the run prints the commit that set it; no git repo = not opted in). Then `--auto` posts every open row
# whose redacted title and body pass the scan, with the person's own `gh` login (gh, else gh.exe,
# else $MXTK_GH; `gh auth status` must pass), no tty and no y/N: duplicate search first (a row whose
# exact title is already an issue gets that URL recorded instead of a second issue), label
# `auto-filed` when the repo has it or the user may create it (else none), status=filed + issue_url
# written back. The deny list stays mandatory; a row that fails the scan is reported, never posted.
# --auto never takes --to and never re-posts a filed row. gh unusable: --links or --bundle (below), exit 0. Without the opt-in line, --auto is a
# dry run. The shipped permissions deny --file/--all but not --auto (the opt-in line is the gate).
# --log FILE on --add stores the last --log-lines (40) lines, redacted; a log that still fails the
# scan is not stored, and a stored log that fails at posting time is left out of the issue. The id is project-local
# (PBUG-NN, not a toolkit BUG-n); the public number is the issue. Success writes status=filed
# and issue_url back, keeping the file mode.
# WHICH PATH. --auto and the dry run name, in one line, why gh can or cannot post: "GitHub CLI
# not installed", "not signed in: run `gh auth login --web`", or "signed in, but this GitHub account has no
# access to <repo>" (gh api repos/<repo> answered HTTP 403/404), or "cannot reach GitHub (network/proxy): <first
# stderr line>" (any other failure). gh unusable: --auto falls back to --links when the person has a GitHub
# account (--github-account or MXTK_GITHUB_ACCOUNT=1), else to --bundle. A Mendix account is not a GitHub one.
# --bundle [PATH] writes ONE markdown file (default <project>/toolkit-bugs-<date>.md, never overwritten,
# /toolkit-bugs-*.md added to .gitignore in a git repo) holding every clean open row, title and body exactly
# as --json gives them; a row the scan holds back is left out, as for posting. It needs the deny list like
# --json. Header: format mxtk-bug-bundle/1, toolkit version, count, ids (the bugs.jsonl row ids), reporter
# (blank; the sender may add a name). Top line: "Mail this file to <$MXTK_BUG_EMAIL, else MXTK_BUG_EMAIL= or
# `Bug email:` in <project>/.claude/toolkit.env or ~/.mxcli-toolkit.env, else a `Bug email:` line in the README.md
# of the company brain wired in CLAUDE.local.md>", else "send this file to whoever gave you the toolkit". Bundled
# rows get status=bundled + bundled=<date>: the dry run and --auto skip them, --file/--all/--links/--json still
# reach them, --bundle --all bundles them again; gate-check and harvest-learnings count them as "bundled, not yet
# filed". --import BUNDLE (the maintainer; denied to agents, --dry-run included) refuses a file without that header,
# whose ids/count do not match its bugs, or with more than --max (20) bugs; re-redacts and re-scans every bug with
# the maintainer's deny list (one is required); always files to the toolkit repo (a target=mxcli row gets a line
# saying the reporter marked it as an mxcli bug, never an upstream post); runs the duplicate search (an exact title
# is skipped, its URL listed); asks y/N per bug when stdin is a terminal; puts a zero-width joiner after every @
# and every # before a digit, after GH- and before the number of a github.com issue/PR URL in the reporter's text
# (no @mention, team ping or #N / owner/repo#N / GH-N / URL cross-reference); files
# with gh and the labels auto-filed / via-email only where the repo already has them (never created), footer
# "Reported by: <reporter or 'toolkit user'> via email bundle". --dry-run files nothing.
# Row fields: id date target title repro expected actual versions{mxcli,mendix,toolkit}
# workaround status(open|filed|bundled|fixed) issue_url [log] [duplicate] [bundled]. Dry run, --links, --json
# and --bundle post nothing.
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/portable.sh"
require_py
exec "$PY" -I "$SCRIPT_DIR/lib/file-bugs.py" "$@"
