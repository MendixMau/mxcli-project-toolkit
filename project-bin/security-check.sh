#!/usr/bin/env bash
# security-check.sh — who can see and do what: security lint findings plus an access snapshot,
# each compared with something a PERSON accepted, so a changed permission cannot pass in silence.
#
# WHY THIS EXISTS (planted-defect experiment on a fictional test app, 2026-11-13). Eight access-
# control mistakes were planted one at a time into a finished app. The build gate (mxbuild)
# caught three; `gate-check.sh` and `verify-module.sh` said nothing about any of them. Three
# serious ones passed everything: a role reading EVERY OTHER USER's rows (the row restriction on
# Attempt removed), a role WRITING an attribute it must only read (Learner on Question.CorrectIndex),
# and anonymous read access to the question bank (guest access on, anonymous mapped to a real role).
# Two cheap checks caught 6 and 7 of the 8 in about two seconds: (a) the security findings of
# `mxcli lint` compared with an accepted starting point, (b) the model's who-can-see-what dump
# compared with an approved copy. The app also already carried two security findings nobody had
# been told about (SEC003 demo users at Production, SEC005 strict mode off), because exec.sh's lint
# ratchet is silent until a baseline exists. This script is that pair of checks, and nothing more.
#
# AN AGENT RUNS THE CHECK; A PERSON APPROVES. `--approve`, `--accept` and `--accept-file` record a
# decision that a role may see or do something. This is a GUARD RAIL, not a lock: the permission
# rules bin/install-claude-permissions.sh writes into .claude/settings.json stop an agent from
# running those commands and from editing the approved/accepted files directly (the same pattern
# as `bin/file-bugs.sh --file`); a checksum per decision in docs/security/approvals.tsv makes a
# hand-copied approval or a hand-appended acceptance fail the next check; and the approved files
# are committed, so a person reviews every change in git. A person with a shell can still edit
# files and the checksum log together - the review in git is what catches that.
#
# WHAT "CLEAN" COVERS (R5): this check covers new security lint findings and changes to the
# recorded access facts (roles, pages, microflows, entity and attribute rights, row restrictions,
# project security settings); it does not cover published REST/OData services and their roles,
# nanoflow or workflow access, or which roles a user role may assign.
#
# WHAT IT READS (read-only: no exec, no write to the .mpr; `mxcli lint` and `show ...`/`describe ...`
# only):
#   1. `mxcli lint`, text form, kept to the SECURITY SET below. Identity of a finding is its rule id
#      plus its message (which names the entity/page and the role), never a line number or its
#      position in the report. The text form is parsed, not --format json, because the planted-
#      mistake captures this was proven on are text; the parse is guarded: the number of findings
#      parsed must equal the report's own "N issues" total, or the run is "could not run" - a
#      format change must not become "no findings".
#   2. The access snapshot, from `show project security`, `show user roles` + `describe user role`,
#      `show module roles`, `show demo users`, `show security matrix` (page and microflow access),
#      `show entities` + `show access on <entity>` (rights, row restriction text, attribute rights).
#      It is normalised to sorted one-fact-per-line records, so an unchanged model gives a byte-
#      identical file on every run. Entities of module System are not in the snapshot.
#
# FILES (under the project root; with MXTK_SECURITY_OUT=<dir> all four live in <dir> instead):
#   docs/security/access-snapshot.txt   the current snapshot (rewritten on every run)
#   docs/security/access-approved.txt   the snapshot a person approved (written by --approve only)
#   docs/security/approvals.tsv         date, kind, who, reason, checksum - one row per --approve /
#                                       --accept / --accept-file; the checksum is of the file that
#                                       decision wrote, and the next check verifies it
#   docs/security/accept-template.tsv   written on a first run: every NEW finding with an EMPTY
#                                       reason column, to edit and hand to --accept-file
#   .claude/loop/security-accepted.tsv  accepted findings: rule id, message key, reason, date
#   .claude/loop/security-check.last    verdict/counts/date/model fingerprint of the last check, so
#                                       bin/gate-check.sh can print one advisory line without running
#                                       mxcli (a result for an older model is reported as stale)
#
# Usage:
#   bin/security-check.sh                          # check; exit 0 only if nothing is new and nothing changed
#   bin/security-check.sh --json                   # same verdict as ONE JSON object on stdout
#   bin/security-check.sh --approve --reason "<who approved, and why>"
#   bin/security-check.sh --accept <rule-id> <element> --reason "<why>"
#       <element> is the finding's message, or any part of it that matches exactly one current
#       finding of that rule (the check prints the full command for every new finding).
#       There is no "accept all": each finding is a separate, reasoned decision.
#   bin/security-check.sh --accept-file <path>
#       <path> is tab-separated, one line per finding: rule id, element, reason. Every line needs a
#       non-empty reason and must match exactly one current finding; if any line does not, nothing
#       is accepted and the bad lines are named. A first run writes the template.
#
# Exit codes: 0 clean (no NEW security finding, snapshot equals the approved copy)
#             1 a NEW security finding, or the snapshot differs from the approved copy
#             2 usage error (unknown flag, --approve/--accept without --reason, ...)
#             3 nothing approved yet (first run): lists every current finding and the snapshot
#               summary and names the command that records the approval. NEVER 0: silence before a
#               baseline exists is the defect this script answers.
#             1 also: the approved copy or the accepted list does not match the checksum its
#               --approve / --accept recorded (verdict approval-mismatch)
#             4 the instrument could not run (no mxcli, no/unreadable model, a failing command, an
#               unrecognised report or dump format, the project's security lint rules not
#               installed). NEVER 0.
#
# Output contract: one line `MXTK-RESULT security verdict=<clean|new-findings|access-changed|
#   not-approved|could-not-run> new=<N> access_changes=<N> exit=<code>` is printed BEFORE the
#   closing human lines (never last). With --json the object is the only thing on stdout, so the
#   RESULT line goes to stderr. --approve and --accept print no RESULT line.
#
# --approve and the PROJECT.md decision register: writing the register from a project-bin script is
# not the convention (gate-check.sh owns register writes), so --approve prints the exact register
# row for the lead to add and appends the same facts to docs/security/approvals.tsv.
#
# Producer/consumer: this script PRODUCES .claude/loop/security-check.last, which bin/gate-check.sh
# (full run and --closeout) reads for one advisory `note:` line. No mandatory step produces it by
# itself; the note names this command, and skills/poc-build.md puts it in the hand-over.
#
# Field run: a fictional English-practice test app (Mendix 11.13, mxcli v0.28), 2026-11-13; see
# the commit that shipped this script for the measured output and timings.
#
# Requires: bash 3.2+, awk, sed, sort, comm, mktemp, cksum, tr. No python.

set -u

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
. "$SELF_DIR/_common.sh" 2>/dev/null || { echo "security-check: cannot source _common.sh" >&2; exit 2; }

# THE SECURITY SET: a lint finding counts only if its rule id matches this extended regex.
# SEC* are the security rules; MPR007 (navigation/home page not openable by a role), CONV006
# (create/delete granted in an access rule) and CONV007 (unconstrained read/write) are the
# convention rules that name access mistakes. One place; change it here, nowhere else.
SECURITY_RULES_RE='^(SEC[0-9]+|MPR007|CONV006|CONV007)$'
# REQUIRED RULES: SEC004-SEC009, SEC014, CONV006 and CONV007 are Starlark rules that exist only when the
# project has .claude/lint-rules/ ; without it `mxcli lint` reports far fewer findings and a
# "clean" result would be false. The check refuses (exit 4) unless `mxcli lint --list-rules` names
# every id below. One place; change it here, nowhere else.
SECURITY_REQUIRED_RULES="SEC001 SEC003 SEC004 SEC005 SEC007 SEC010 MPR007 CONV006 CONV007"
# A few plain words after each rule id, checked against `mxcli lint --list-rules` (mxcli v0.28).
# An id that is not here prints with no description rather than a wrong one.
rule_desc() {
  case "$1" in
    SEC001) echo "data with no access rules" ;;
    SEC002) echo "password policy too weak" ;;
    SEC003) echo "demo users on at production level" ;;
    SEC004) echo "guest (anonymous) access is on" ;;
    SEC005) echo "strict security mode is off" ;;
    SEC006) echo "personal-data attributes without access rules" ;;
    SEC007) echo "readable without signing in" ;;
    SEC008) echo "personal data readable in every row" ;;
    SEC009) echo "large entity with no attribute-level read limits" ;;
    SEC010) echo "a role can open a page but not read its data" ;;
    SEC014) echo "an external role can write controlled members" ;;
    MPR007) echo "a navigation page no role may open, or a role that cannot open its home page" ;;
    CONV006) echo "create or delete rights in an access rule" ;;
    CONV007) echo "a role can read or change every row" ;;
    *) echo "" ;;
  esac
}
rule_label() {  # rule_label <id> -> "ID" or "ID (description)"
  local d; d=$(rule_desc "$1")
  if [ -n "$d" ]; then printf '%s (%s)' "$1" "$d"; else printf '%s' "$1"; fi
}

JSON=0; MODE=check; REASON=""; HAVE_REASON=0; ACC_RULE=""; ACC_ELEM=""; ACC_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --approve) [ "$MODE" = check ] || { echo "security-check: --approve and --accept cannot be combined" >&2; exit 2; }; MODE=approve ;;
    --accept)
      [ "$MODE" = check ] || { echo "security-check: --approve and --accept cannot be combined" >&2; exit 2; }
      [ $# -ge 3 ] || { echo "security-check: --accept needs <rule-id> <element>" >&2; exit 2; }
      MODE=accept; ACC_RULE="$2"; ACC_ELEM="$3"; shift 2 ;;
    --accept-file)
      [ "$MODE" = check ] || { echo "security-check: --approve, --accept and --accept-file cannot be combined" >&2; exit 2; }
      [ $# -ge 2 ] || { echo "security-check: --accept-file needs a <path>" >&2; exit 2; }
      MODE=acceptfile; ACC_FILE="$2"; shift ;;
    --reason) [ $# -ge 2 ] || { echo "security-check: --reason needs a value" >&2; exit 2; }; REASON="$2"; HAVE_REASON=1; shift ;;
    -h|--help) sed -n '2,/^set -u/p' "${BASH_SOURCE[0]}" | sed '$d'; exit 0 ;;
    *) echo "security-check: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done
REASON=$(printf '%s' "$REASON" | tr '\t\r\n' '   ' | sed 's/^ *//; s/ *$//')
case "$MODE" in
  approve|accept)
    [ -n "$REASON" ] || { echo "security-check: --$MODE needs --reason \"<who decided, and why>\" - a decision with no reason is not recorded." >&2; exit 2; } ;;
  acceptfile) [ "$HAVE_REASON" = 0 ] || { echo "security-check: --accept-file takes the reason from each line of the file; --reason is not used with it" >&2; exit 2; }
              [ -f "$ACC_FILE" ] || { echo "security-check: --accept-file: no such file: $ACC_FILE" >&2; exit 2; } ;;
  check) [ "$HAVE_REASON" = 0 ] || { echo "security-check: --reason only goes with --approve or --accept" >&2; exit 2; } ;;
esac
if [ "$MODE" = accept ]; then
  printf '%s' "$ACC_RULE" | grep -Eq "$SECURITY_RULES_RE" \
    || { echo "security-check: '$ACC_RULE' is not in the security set ($SECURITY_RULES_RE)" >&2; exit 2; }
  [ -n "$ACC_ELEM" ] || { echo "security-check: --accept needs a non-empty <element>" >&2; exit 2; }
fi

# --- where things live ----------------------------------------------------------------------
ROOT="$PROJECT_ROOT"
# Two-tree checkout: PROJECT_ROOT can be the folder holding the .mpr (app/) while docs/, .claude/
# and bin/ sit one level up. Same probe as constants-audit.sh's register lookup.
if [ ! -d "$ROOT/.claude" ] && [ -d "$ROOT/../.claude" ]; then ROOT=$(cd "$ROOT/.." && pwd); fi
if [ -n "${MXTK_SECURITY_OUT:-}" ]; then
  mkdir -p "$MXTK_SECURITY_OUT" 2>/dev/null || { echo "security-check: cannot create MXTK_SECURITY_OUT=$MXTK_SECURITY_OUT" >&2; exit 4; }
  SNAPDIR="$MXTK_SECURITY_OUT"; ACC="$MXTK_SECURITY_OUT/security-accepted.tsv"; STATE="$MXTK_SECURITY_OUT/security-check.last"
else
  SNAPDIR="$ROOT/docs/security"; ACC="$ROOT/.claude/loop/security-accepted.tsv"; STATE="$ROOT/.claude/loop/security-check.last"
fi
SNAP="$SNAPDIR/access-snapshot.txt"; APPROVED="$SNAPDIR/access-approved.txt"; APPROVALS="$SNAPDIR/approvals.tsv"
TEMPLATE="$SNAPDIR/accept-template.tsv"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/security-check.XXXXXX") || { echo "security-check: cannot make a temp dir" >&2; exit 4; }
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'exit 4' INT TERM HUP

# --- JSON helpers (no python) ---------------------------------------------------------------
jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\t\r' '  ' | awk 'BEGIN{ORS=""} {if (NR>1) printf "\\n"; print}'; }
jlist() {  # jlist <file> — one JSON string per line, as an array body
  awk 'BEGIN{first=1} { s=$0; gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); gsub(/\t/," ",s); gsub(/\r/,"",s);
       printf "%s\"%s\"", (first?"":","), s; first=0 }' "$1"
}

verdict=""; NEWN=0; ACCN=0; rc=0
FIND_ALL="$TMP/find.all"; FIND_NEW="$TMP/find.new"; CHG="$TMP/changes.txt"
: > "$FIND_ALL"; : > "$FIND_NEW"; : > "$CHG"

write_state() {  # write_state <verdict> <new> <access_changes>
  [ "$MODE" = check ] || return 0
  mkdir -p "${STATE%/*}" 2>/dev/null || return 0
  { printf 'verdict=%s\nnew=%s\naccess_changes=%s\ndate=%s\nmodel=%s\n' \
      "$1" "$2" "$3" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${MODEL_SIG:-}"; } > "$STATE.tmp" 2>/dev/null && mv "$STATE.tmp" "$STATE" 2>/dev/null
  return 0
}

emit_result() {  # emit_result <verdict> <new> <access_changes> <exit>   (prints the RESULT line, json -> stderr)
  local line="MXTK-RESULT security verdict=$1 new=$2 access_changes=$3 exit=$4"
  if [ "$JSON" = 1 ]; then echo "$line" >&2; else echo "$line"; fi
}

could_not_run() {  # could_not_run <message...>
  local msg="$*"
  MODEL_SIG="${MODEL_SIG:-}"
  write_state could-not-run 0 0
  if [ "$JSON" = 1 ]; then
    printf '{"verdict":"could-not-run","exit":4,"error":"%s","new_findings":[],"access_changes":[],"counts":{"new":0,"access_changes":0}}\n' "$(jesc "$msg")"
    emit_result could-not-run 0 0 4
    echo "security-check: could not run - $msg" >&2
  else
    echo "security-check: COULD NOT RUN - $msg" >&2
    emit_result could-not-run 0 0 4
    echo "This is the instrument failing, not the project passing: no verdict was reached." >&2
  fi
  exit 4
}

# --- find the model and mxcli ---------------------------------------------------------------
MPR=$(find_mpr 2>"$TMP/mprerr") || could_not_run "no single .mpr found ($(tr '\n' ' ' < "$TMP/mprerr" | cut -c1-200))"
[ -f "$MPR" ] || { [ -f "$PROJECT_ROOT/$MPR" ] && MPR="$PROJECT_ROOT/$MPR"; }
[ -f "$MPR" ] || could_not_run "model file not found: $MPR"
MXCLI="${MXCLI:-}"
if [ -z "$MXCLI" ]; then
  MXCLI=$(find_project_mxcli 2>/dev/null || true)
  [ -n "$MXCLI" ] || { for c in "$ROOT/mxcli" ./mxcli mxcli; do
    if [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; then MXCLI="$c"; break; fi
  done; }
fi
[ -n "$MXCLI" ] || could_not_run "no mxcli on PATH or at $PROJECT_ROOT/mxcli"

MODEL_SIG=""
if [ -f "$SELF_DIR/model-stamp.sh" ]; then
  MODEL_SIG=$(PROJECT_ROOT="$ROOT" bash "$SELF_DIR/model-stamp.sh" fingerprint 2>/dev/null | head -1 | tr -d '\r') || MODEL_SIG=""
fi

# mx <command> <outfile>: run one read-only mxcli command, strip the banner lines, return its status.
NOISE='^(WARNING: |Using project|Connected to: |Loading cached catalog|Loading catalog|.? ?Catalog ready|✓ Catalog ready)'
mx() {
  local raw="$TMP/raw.$$" r
  "$MXCLI" -p "$MPR" -c "$1" 2>&1 | tr -d '\r' > "$raw"; r=${PIPESTATUS[0]}
  grep -v -E "$NOISE" "$raw" > "$2"
  # a failing command whose whole output was banner: keep the raw text so the message can show it
  if [ "$r" -ne 0 ] && [ ! -s "$2" ]; then cp "$raw" "$2"; fi
  rm -f "$raw"
  return $r
}
first_lines() {  # first_lines <file>: the first 3 non-empty, non-banner lines (all lines if only banner), on one line
  local t; t=$(grep -v '^[[:space:]]*$' "$1" | grep -v -E "$NOISE")
  [ -n "$t" ] || t=$(grep -v '^[[:space:]]*$' "$1")
  printf '%s\n' "$t" | head -3 | tr '\n' ' ' | sed 's/[[:space:]]*$//' | cut -c1-300
}
mx_or_die() {  # mx_or_die <command> <outfile>
  local r=0
  mx "$1" "$2" || r=$?
  [ "$r" -eq 0 ] || could_not_run "'$1' failed (mxcli exit $r): $(first_lines "$2")"
}

# --- 1. lint findings -----------------------------------------------------------------------
# Parse the text report. A finding line is: <indent><symbol> <message> [RULE-ID]; its detail lines
# start with "at" or "→". Output: rule<TAB>message, all findings; the count is checked against the
# report's own total.
# 1a. The security rules must be installed, or the lint run below reports far fewer findings and
# a clean result would be false. Required ids are listed by `mxcli lint --list-rules`.
LR="$TMP/listrules.txt"
"$MXCLI" lint --list-rules -p "$MPR" 2>&1 | tr -d '\r' > "$LR"; lr_rc=${PIPESTATUS[0]}
sed -n 's/^[[:space:]]*\([A-Z][A-Z0-9-]*[0-9]\)[[:space:]]*(.*/\1/p' "$LR" | LC_ALL=C sort -u > "$TMP/listed.ids"
[ -s "$TMP/listed.ids" ] || could_not_run "'mxcli lint --list-rules' listed no rules (exit $lr_rc): $(first_lines "$LR")"
missing_rules=""
for rr in $SECURITY_REQUIRED_RULES; do
  LC_ALL=C grep -qxF "$rr" "$TMP/listed.ids" || missing_rules="$missing_rules $rr"
done
[ -z "$missing_rules" ] || could_not_run "the project's security lint rules are not installed - not listed by mxcli lint:${missing_rules}. Without them a clean result would be false. Run 'mxcli init' in the project folder (the toolkit's bin/sync-project.sh <project-root> does this and restores the toolkit's rule fixes), then run this check again."

LINT_RAW="$TMP/lint.raw"
"$MXCLI" lint -p "$MPR" 2>&1 | tr -d '\r' > "$LINT_RAW"; lint_rc=${PIPESTATUS[0]}
if grep -q '^No issues found' "$LINT_RAW"; then total_reported=0
else total_reported=$(sed -n 's/^\([0-9][0-9]*\) issues\{0,1\}:.*/\1/p' "$LINT_RAW" | tail -1); fi
[ -n "$total_reported" ] || { grep -v -E "$NOISE" "$LINT_RAW" > "$TMP/lint.msg"; [ -s "$TMP/lint.msg" ] || cp "$LINT_RAW" "$TMP/lint.msg"
  could_not_run "mxcli lint produced no recognisable report (exit $lint_rc): $(first_lines "$TMP/lint.msg")"; }
awk '
  /^[ \t]+[^ \t]+[ \t]/ {
    line=$0; sub(/[ \t]+$/, "", line)
    first=line; sub(/^[ \t]+/, "", first); tok=first; sub(/[ \t].*$/, "", tok)
    if (tok == "at" || tok == "→") next
    if (!match(line, /\[[A-Za-z0-9_-]+\]$/)) next
    rule=substr(line, RSTART+1, RLENGTH-2)
    msg=first; sub(/^[^ \t]+[ \t]+/, "", msg); sub(/[ \t]*\[[A-Za-z0-9_-]+\]$/, "", msg)
    gsub(/\t/, " ", msg)
    print rule "\t" msg
  }' "$LINT_RAW" > "$TMP/lint.parsed"
parsed_n=$(wc -l < "$TMP/lint.parsed" | tr -d ' ')
[ "$parsed_n" = "$total_reported" ] \
  || could_not_run "parsed $parsed_n findings from the lint report but it states $total_reported: the report format changed, so a clean result could not be trusted"
LC_ALL=C awk -F'\t' -v re="$SECURITY_RULES_RE" '$1 ~ re' "$TMP/lint.parsed" | LC_ALL=C sort -u > "$FIND_ALL"

# Windows line endings: everything read from the approved and accepted files is compared as a
# normalised copy (no CR); the user's files are never rewritten.
norm_copy() { if [ -f "$1" ]; then tr -d '\r' < "$1" > "$2"; else : > "$2"; fi; }
cksum_norm() { tr -d '\r' < "$1" | cksum | awk '{print $1}'; }
ACC_N="$TMP/accepted.n"; APPROVED_N="$TMP/approved.n"
norm_copy "$ACC" "$ACC_N"; norm_copy "$APPROVED" "$APPROVED_N"

# Who decided: the git user name, else $USER, else "unknown". No e-mail address.
who_am_i() {
  local w; w=$(git -C "$ROOT" config user.name 2>/dev/null | head -1)
  case "$w" in *@*) w="" ;; esac   # an e-mail address is never recorded
  case "${USER:-}" in *@*) USER_NAME="" ;; *) USER_NAME="${USER:-}" ;; esac
  [ -n "$w" ] || w="$USER_NAME"
  [ -n "$w" ] || w="unknown"
  printf '%s' "$w" | tr '\t\r\n' '   '
}
record_decision() {  # record_decision <approve|accept> <reason> <file whose checksum is recorded>
  mkdir -p "$SNAPDIR" 2>/dev/null
  [ -f "$APPROVALS" ] || printf '# date\tkind\twho\treason\tcksum of the file this decision wrote (approved copy / accepted list) - appended by security-check.sh; verified on every check\n' > "$APPROVALS"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%d)" "$1" "$(who_am_i)" "$2" "$(cksum_norm "$3")" >> "$APPROVALS"
}
last_cksum() {  # last_cksum <kind>: checksum on the latest approvals row of that kind ("" if none)
  [ -f "$APPROVALS" ] || return 0
  awk -F'\t' -v k="$1" '!/^#/ && $2==k { c=$5 } END { print c }' "$APPROVALS" | tr -d '\r'
}
# R4: the approved copy and the accepted list must be what --approve / --accept last wrote.
INTEGRITY_MSG=""
if [ -f "$APPROVED" ]; then
  [ "$(last_cksum approve)" = "$(cksum_norm "$APPROVED")" ] && [ -n "$(last_cksum approve)" ] \
    || INTEGRITY_MSG="the approved copy was not written by --approve: ask the person who approves access to run it again - after reading the changes in git, bin/security-check.sh --approve --reason \"<who approved, and why>\" re-confirms it ($APPROVED does not match the checksum in $APPROVALS)."
fi
if [ -z "$INTEGRITY_MSG" ]; then
  if [ -f "$ACC" ]; then
    [ -n "$(last_cksum accept)" ] && [ "$(last_cksum accept)" = "$(cksum_norm "$ACC")" ] \
      || INTEGRITY_MSG="the accepted list was not written by --accept (for example after a git merge of two lists): ask the person who approves access to review it (git diff) and, if it is right, re-confirm it with bin/security-check.sh --approve --reason \"<who approved, and why>\" ($ACC does not match the checksum in $APPROVALS)."
  elif [ -n "$(last_cksum accept)" ]; then
    INTEGRITY_MSG="the accepted list $ACC is missing but $APPROVALS records acceptances: restore it from git, or ask the person who approves access to re-confirm with bin/security-check.sh --approve --reason \"<who approved, and why>\"."
  fi
fi
if [ -n "$INTEGRITY_MSG" ] && [ "$MODE" != approve ]; then
  if [ "$MODE" != check ]; then echo "security-check: $INTEGRITY_MSG Nothing was recorded; --approve is the way to re-confirm." >&2; exit 1; fi
  write_state approval-mismatch 0 0
  if [ "$JSON" = 1 ]; then
    printf '{"verdict":"approval-mismatch","exit":1,"error":"%s","new_findings":[],"access_changes":[],"counts":{"new":0,"access_changes":0}}\n' "$(jesc "$INTEGRITY_MSG")"
    emit_result approval-mismatch 0 0 1
  else
    echo "security-check: $(basename "$MPR")"
    echo
    echo "APPROVAL NOT TRUSTED - $INTEGRITY_MSG"
    emit_result approval-mismatch 0 0 1
    echo "Not clean. Nothing was compared: a person must look at this first."
  fi
  exit 1
fi

accepted_pairs() {  # the first two columns of the accepted list, as rule<TAB>key lines
  # a line accepts a finding only with a rule id, an element AND a non-empty reason
  # A reason of only spaces or tabs is no reason: trim before testing.
  awk -F'\t' '!/^[ \t]*#/ && NF>=3 && $1!="" { r=$3; gsub(/^[ \t]+|[ \t]+$/,"",r); if (r!="") print $1 "\t" $2 }' "$ACC_N"
}
accepted_pairs | LC_ALL=C sort -u > "$TMP/acc.pairs"
# classify every non-comment line of the accepted list: ok / stale / noreason / badrule
classify_accepted() {  # -> status<TAB>rule<TAB>element<TAB>reason, one per line
  # a rule id is real only if it is in the security set AND mxcli lists it (SEC999 has the shape, not the rule)
  awk -F'\t' -v re="$SECURITY_RULES_RE" '
    FILENAME==ARGV[1] { known[$1]=1; next }
    FILENAME==ARGV[2] { cur[$1 "\t" $2]=1; next }
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    { r = (NF>=3) ? $3 : ""; gsub(/^[ \t]+|[ \t]+$/,"",r)
      st = ($1 !~ re || !($1 in known)) ? "badrule" : (r=="") ? "noreason" : (($1 "\t" $2) in cur) ? "ok" : "stale"
      print st "\t" $1 "\t" $2 "\t" $3 }' "$TMP/listed.ids" "$FIND_ALL" "$ACC_N"
}
classify_accepted > "$TMP/acc.cls"
STALEN=$(awk -F'\t' '$1=="stale"' "$TMP/acc.cls" | wc -l | tr -d ' ')
LC_ALL=C comm -23 "$FIND_ALL" "$TMP/acc.pairs" > "$FIND_NEW"

shq() { printf '%s' "$1" | sed 's/[\\"$`]/\\&/g'; }   # for the printed, copy-pasteable accept command
list_findings() {  # list_findings <file of rule<TAB>msg>: "  [RULE - words] message" (no words for an id not in the table)
  while IFS="$(printf '\t')" read -r r m; do
    d=$(rule_desc "$r")
    if [ -n "$d" ]; then printf '  [%s - %s] %s\n' "$r" "$d" "$m"; else printf '  [%s] %s\n' "$r" "$m"; fi
  done < "$1"
}
print_accept_cmds() {  # print_accept_cmds <file of rule<TAB>msg>
  awk -F'\t' '{ print $1 "\t" $2 }' "$1" | while IFS="$(printf '\t')" read -r r m; do
    printf '      bin/security-check.sh --accept %s "%s" --reason "<why this is acceptable>"\n' "$r" "$(shq "$m")"
  done
}

# --- --accept: lint only, then record ------------------------------------------------------
if [ "$MODE" = accept ]; then
  : > "$TMP/cand"
  while IFS="$(printf '\t')" read -r r m; do
    [ "$r" = "$ACC_RULE" ] || continue
    case "$m" in *"$ACC_ELEM"*) printf '%s\t%s\n' "$r" "$m" >> "$TMP/cand" ;; esac
  done < "$FIND_ALL"
  cn=$(wc -l < "$TMP/cand" | tr -d ' ')
  if [ "$cn" = 0 ]; then
    echo "security-check: no current $ACC_RULE finding contains '$ACC_ELEM'. Nothing accepted. Current $ACC_RULE findings:" >&2
    awk -F'\t' -v r="$ACC_RULE" '$1==r { print "  " $2 }' "$FIND_ALL" >&2; exit 2
  elif [ "$cn" -gt 1 ]; then
    echo "security-check: '$ACC_ELEM' matches $cn $ACC_RULE findings - be more specific (no accept-all). Matches:" >&2
    awk -F'\t' '{ print "  " $2 }' "$TMP/cand" >&2; exit 2
  fi
  IFS="$(printf '\t')" read -r r m < "$TMP/cand"
  if LC_ALL=C grep -qxF "$(printf '%s\t%s' "$r" "$m")" "$TMP/acc.pairs"; then
    echo "security-check: already accepted: [$r] $m"; exit 0
  fi
  mkdir -p "${ACC%/*}" 2>/dev/null || { echo "security-check: cannot create ${ACC%/*}" >&2; exit 4; }
  [ -f "$ACC" ] || printf '# rule\tfinding (lint message)\treason accepted\tdate - security-check.sh --accept; one decision per line, commit this file\n' > "$ACC"
  printf '%s\t%s\t%s\t%s\n' "$r" "$m" "$REASON" "$(date -u +%Y-%m-%d)" >> "$ACC"
  record_decision accept "$REASON" "$ACC"
  echo "security-check: accepted [$r] $m"
  echo "  reason: $REASON"
  echo "  recorded in $ACC - commit it. Re-run bin/security-check.sh for the verdict."
  exit 0
fi

# --- --accept-file: many reasoned decisions, all or nothing ----------------------------------------
if [ "$MODE" = acceptfile ]; then
  tr -d '\r' < "$ACC_FILE" > "$TMP/af.in"
  : > "$TMP/af.ok"; : > "$TMP/af.bad"; ln=0; seen=""
  while IFS="$(printf '\t')" read -r r m rs || [ -n "$r" ]; do
    ln=$((ln+1))
    case "$r" in ""|"#"*) continue ;; esac
    rs=$(printf '%s' "$rs" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ -z "$rs" ]; then echo "  line $ln: [$r] has no reason - a decision with no reason is not recorded" >> "$TMP/af.bad"; continue; fi
    if ! printf '%s' "$r" | grep -Eq "$SECURITY_RULES_RE" || [ -z "$m" ]; then echo "  line $ln: '$r' is not a security rule id with an element" >> "$TMP/af.bad"; continue; fi
    : > "$TMP/af.cand"
    # an element equal to a whole finding message (what the template holds) names exactly that finding
    if LC_ALL=C grep -qxF "$(printf '%s\t%s' "$r" "$m")" "$FIND_ALL"; then printf '%s\t%s\n' "$r" "$m" > "$TMP/af.cand"
    else
      while IFS="$(printf '\t')" read -r fr fm; do
        [ "$fr" = "$r" ] || continue
        case "$fm" in *"$m"*) printf '%s\t%s\n' "$fr" "$fm" >> "$TMP/af.cand" ;; esac
      done < "$FIND_ALL"
    fi
    cn=$(wc -l < "$TMP/af.cand" | tr -d ' ')
    if [ "$cn" = 0 ]; then echo "  line $ln: no current $r finding contains '$m'" >> "$TMP/af.bad"; continue; fi
    if [ "$cn" -gt 1 ]; then echo "  line $ln: '$m' matches $cn $r findings - be more specific" >> "$TMP/af.bad"; continue; fi
    IFS="$(printf '\t')" read -r fr fm < "$TMP/af.cand"
    key="${fr}|${fm}"
    case "$seen" in *"||$key||"*) echo "  line $ln: [$fr] $fm is listed twice" >> "$TMP/af.bad"; continue ;; esac
    seen="$seen||$key||"
    printf '%s\t%s\t%s\n' "$fr" "$fm" "$rs" >> "$TMP/af.ok"
  done < "$TMP/af.in"
  nok=$(wc -l < "$TMP/af.ok" | tr -d ' ')
  if [ -s "$TMP/af.bad" ]; then
    echo "security-check: --accept-file: NOTHING was accepted. Fix these lines in $ACC_FILE:" >&2
    cat "$TMP/af.bad" >&2; exit 2
  fi
  [ "$nok" -gt 0 ] || { echo "security-check: --accept-file: $ACC_FILE has no finding lines. Nothing accepted." >&2; exit 2; }
  mkdir -p "${ACC%/*}" 2>/dev/null || { echo "security-check: cannot create ${ACC%/*}" >&2; exit 4; }
  [ -f "$ACC" ] || printf '# rule\tfinding (lint message)\treason accepted\tdate - security-check.sh --accept; one decision per line, commit this file\n' > "$ACC"
  added=0
  while IFS="$(printf '\t')" read -r r m rs; do
    if LC_ALL=C grep -qxF "$(printf '%s\t%s' "$r" "$m")" "$TMP/acc.pairs"; then echo "  already accepted: [$r] $m"; continue; fi
    printf '%s\t%s\t%s\t%s\n' "$r" "$m" "$rs" "$(date -u +%Y-%m-%d)" >> "$ACC"; added=$((added+1))
  done < "$TMP/af.ok"
  record_decision accept "--accept-file: $added finding(s), reason per finding in the accepted list" "$ACC"
  echo "security-check: accepted $added finding(s) from $ACC_FILE (each with its own reason)"
  echo "  recorded in $ACC - commit it. Re-run bin/security-check.sh for the verdict."
  exit 0
fi

# --- 2. access snapshot ---------------------------------------------------------------------
TAB="$(printf '\t')"
REC="$TMP/records"; : > "$REC"

tbl_rows() {  # tbl_rows <file> <header-regex>: first column of each data row; 3 = not a table, not empty
  if grep -Eq "$2" "$1"; then
    awk -F'|' -v h="$2" '/^\|/ && $0 !~ /^\|[-| ]+\|?$/ && $0 !~ h { v=$2; gsub(/^[ \t]+|[ \t]+$/, "", v); if (v != "") print v }' "$1"
    return 0
  fi
  grep -Eqi '^\(0 |no [a-z ]+(found|defined)|^$' "$1" && return 0
  [ -s "$1" ] || return 0
  return 3
}

# project security: "Key: value" lines
mx_or_die "show project security" "$TMP/o.sec"
grep -Eq '^Security Level:' "$TMP/o.sec" || could_not_run "'show project security' has no 'Security Level:' line - format changed"
awk -F': ' '/^[^ \t].*: / || /^[ \t]+[A-Za-z ]+: / { k=$1; v=substr($0, index($0, ": ")+2); gsub(/^[ \t]+|[ \t]+$/, "", k); gsub(/^[ \t]+|[ \t]+$/, "", v);
    if (k != "" && v != "") print "security\t" k "\t" v }' "$TMP/o.sec" >> "$REC"

# user roles
mx_or_die "show user roles" "$TMP/o.ur"
tbl_rows "$TMP/o.ur" '^\| *Name ' > "$TMP/ur.names"; [ $? -ne 3 ] || could_not_run "'show user roles' is not the table this parser was written against"
: > "$TMP/mr.mapped"
while IFS= read -r ur; do
  [ -n "$ur" ] || continue
  case "$ur" in *[!A-Za-z0-9_]*) cmd="describe user role '$ur'" ;; *) cmd="describe user role $ur" ;; esac
  mx_or_die "$cmd" "$TMP/o.dur"
  grep -q 'create or modify user role' "$TMP/o.dur" || could_not_run "'$cmd' has no 'create or modify user role' statement - format changed: $(first_lines "$TMP/o.dur")"
  flat=$(tr '\n' ' ' < "$TMP/o.dur")
  case "$flat" in *ModuleRoles:*) ml=${flat#*ModuleRoles:}; ml=${ml#*\(}; ml=${ml%%\)*} ;; *) ml="" ;; esac
  printf '%s\n' "$ml" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | while IFS= read -r mr; do
    printf 'user-role-has\t%s\t%s\tyes\n' "$ur" "$mr"
  done >> "$REC"
  printf '%s\n' "$ml" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' >> "$TMP/mr.mapped"
  grep -E '^[[:space:]]*(ManageAllRoles|CheckSecurity):' "$TMP/o.dur" | sed 's/[[:space:],;]*$//; s/^[[:space:]]*//' | while IFS= read -r fl; do
    printf 'user-role-flag\t%s\t%s\t%s\n' "$ur" "${fl%%:*}" "${fl#*: }"
  done >> "$REC"
done < "$TMP/ur.names"
LC_ALL=C sort -u "$TMP/mr.mapped" > "$TMP/mr.mapped.s"

# module roles (every module at once) and which of them no user role holds
mx_or_die "show module roles" "$TMP/o.mr"
tbl_rows "$TMP/o.mr" '^\| *Qualified Name ' > "$TMP/mr.names"; [ $? -ne 3 ] || could_not_run "'show module roles' is not the table this parser was written against"
while IFS= read -r mr; do
  [ -n "$mr" ] || continue
  printf 'module-role\t%s\tdefined\n' "$mr" >> "$REC"
  LC_ALL=C grep -qxF "$mr" "$TMP/mr.mapped.s" || printf 'module-role-unmapped\t%s\tyes\n' "$mr" >> "$REC"
done < "$TMP/mr.names"

# demo users
mx_or_die "show demo users" "$TMP/o.du"
if grep -Eq '^\| *User Name ' "$TMP/o.du"; then
  awk -F'|' '/^\|/ && $0 !~ /^\|[-| ]+\|?$/ && $0 !~ /User Name/ { n=$2; r=$3; gsub(/^[ \t]+|[ \t]+$/, "", n); gsub(/^[ \t]+|[ \t]+$/, "", r);
      c=split(r, a, /, */); for (i=1;i<=c;i++) for (j=i+1;j<=c;j++) if (a[j] < a[i]) { t=a[i]; a[i]=a[j]; a[j]=t }
      s=""; for (i=1;i<=c;i++) s = s (i>1?", ":"") a[i]; print "demo-user\t" n "\t" s }' "$TMP/o.du" >> "$REC"
elif [ -s "$TMP/o.du" ] && ! grep -Eqi '^\(0 |no demo' "$TMP/o.du"; then
  could_not_run "'show demo users' is not the table this parser was written against"
fi

# page and microflow access, from the project-wide security matrix
mx_or_die "show security matrix" "$TMP/o.sm"
grep -q '^Security Matrix' "$TMP/o.sm" || could_not_run "'show security matrix' has no 'Security Matrix' heading - format changed"
grep -q '^## Page Access' "$TMP/o.sm" && grep -q '^## Microflow Access' "$TMP/o.sm" \
  || could_not_run "'show security matrix' lacks its '## Page Access' and '## Microflow Access' sections - format changed, so page and microflow access would go unchecked"
awk '
  /^## Microflow Access/ { sec="microflow-access"; verb="execute"; next }
  /^## Page Access/      { sec="page-access"; verb="open"; next }
  /^## /                 { sec=""; next }
  sec != "" && /^[ \t]+[^ \t].*: / {
    line=$0; sub(/^[ \t]+/, "", line); i=index(line, ": "); el=substr(line, 1, i-1); roles=substr(line, i+2)
    c=split(roles, a, /, */); for (k=1;k<=c;k++) if (a[k] != "") print sec "\t" el "\t" a[k] "\t" verb
  }' "$TMP/o.sm" >> "$REC"

# entities: rights, row restriction text, attribute rights - per rule, per role
mx_or_die "show entities" "$TMP/o.en"
grep -Eq '^\| *Entity ' "$TMP/o.en" || could_not_run "'show entities' is not the table this parser was written against"
tbl_rows "$TMP/o.en" '^\| *Entity ' | grep -v '^System\.' | LC_ALL=C sort -u > "$TMP/ent.names"
while IFS= read -r ent; do
  [ -n "$ent" ] || continue
  mx_or_die "show access on $ent" "$TMP/o.ac"
  awk 'NF { print; exit }' "$TMP/o.ac" | grep -Eq '^(Access rules for |No access rules on )' \
    || could_not_run "'show access on $ent' starts with neither 'Access rules for' nor 'No access rules on' - format changed: $(first_lines "$TMP/o.ac")"
  awk -v E="$ent" '
    function rights_norm(s,   c, a, i, out, w) {
      c=split(s, a, /, */); out=""
      split("create read write delete", ord, " ")
      for (w=1; w<=4; w++) for (i=1;i<=c;i++) if (a[i]==ord[w]) out = out (out==""?"":",") a[i]
      for (i=1;i<=c;i++) if (a[i]!="create" && a[i]!="read" && a[i]!="write" && a[i]!="delete" && a[i]!="") out = out (out==""?"":",") a[i]
      return out
    }
    function trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }
    function flush(   r, m) {
      if (!inrule) return
      for (r=1; r<=nroles; r++) {
        print "entity-rights\t" E "\t" roles[r] "\t" (xp==""?"-":xp) "\t" rights_norm(rt)
        if (def != "") print "entity-default\t" E "\t" roles[r] "\t" (xp==""?"-":xp) "\t" def
        for (m=1; m<=nmem; m++) print "member-access\t" E "\t" roles[r] "\t" (xp==""?"-":xp) "\t" mem[m] "\t" acc[m]
      }
      inrule=0
    }
    # Nothing is dropped: a line this parser does not know becomes an entity-raw fact, so an
    # unknown line CHANGES the snapshot instead of vanishing. A line after "where" that is not a
    # known line is the rest of the row restriction and is recorded as part of it.
    /^[ \t]*$/ { inwhere=0; next }
    /^No access rules on / { print "entity-no-rules\t" E "\tyes"; next }
    /^Access rules for /   { flush(); inwhere=0; next }
    /^Rule [0-9]+: /      { flush(); inrule=1; inwhere=0; s=$0; sub(/^Rule [0-9]+: /, "", s); hdr=s; nroles=split(s, roles, /, */); rt=""; def=""; xp=""; nmem=0; next }
    inrule && /^  Rights: /                { inwhere=0; s=$0; sub(/^  Rights: /, "", s); rt=s; next }
    inrule && /^  Default member access: / { inwhere=0; s=$0; sub(/^  Default member access: /, "", s); def=s; next }
    inrule && /^  where /                  { s=$0; sub(/^  where /, "", s); xp=s; inwhere=1; next }
    inrule && /^  [A-Za-z0-9_.]+: (ReadOnly|ReadWrite|None)$/ {
      inwhere=0; s=$0; sub(/^  /, "", s); i=index(s, ": "); nmem++; mem[nmem]=substr(s, 1, i-1); acc[nmem]=substr(s, i+2); next }
    inrule && inwhere { xp = xp " <NL> " trim($0); next }
    { l=$0; gsub(/\t/, " ", l); print "entity-raw\t" E "\t" (inrule ? hdr : "-") "\t" l "\tyes" }
    END { flush() }' "$TMP/o.ac" >> "$REC"
done < "$TMP/ent.names"

[ -s "$REC" ] || could_not_run "the access snapshot came out empty - nothing was read from the model"
{ printf '# security-check access snapshot v1 - normalised and sorted; one fact per line; do not edit by hand\n'
  LC_ALL=C sort -u "$REC"; } > "$TMP/snap"
mkdir -p "$SNAPDIR" 2>/dev/null || could_not_run "cannot create $SNAPDIR"
cp "$TMP/snap" "$SNAP" 2>/dev/null || could_not_run "cannot write $SNAP"

summary_counts() {  # one line per record kind
  grep -v '^#' "$SNAP" | awk -F'\t' '{ n[$1]++ } END { for (k in n) printf "  %-22s %d\n", k, n[k] }' | LC_ALL=C sort
}

# --- --approve ------------------------------------------------------------------------------
if [ "$MODE" = approve ]; then
  if [ -f "$ACC" ]; then
    BADN=$(awk -F'\t' '$1=="noreason" || $1=="badrule"' "$TMP/acc.cls" | wc -l | tr -d ' ')
    if [ "$BADN" -gt 0 ]; then
      echo "security-check: --approve REFUSED: the accepted list ($ACC) has $BADN line(s) that must be fixed or deleted first; nothing was recorded:" >&2
      awk -F'\t' '$1=="noreason" { print "  no reason, accepts nothing: [" $2 "] " $3 } $1=="badrule" { print "  not a security rule id: [" $2 "] " $3 }' "$TMP/acc.cls" >&2
      exit 1
    fi
  fi
  cp "$SNAP" "$APPROVED.tmp" && mv "$APPROVED.tmp" "$APPROVED" || { echo "security-check: cannot write $APPROVED" >&2; exit 4; }
  sum=$(cksum_norm "$APPROVED")
  record_decision approve "$REASON" "$APPROVED"
  if [ -f "$ACC" ]; then
    # --approve re-confirms the accepted list too (a merged list has no matching checksum otherwise):
    # show what is being confirmed, then record its checksum.
    echo "Accepted findings you are confirming with this approval ($ACC):"
    awk -F'\t' '$1=="ok" { print "  accepts a current finding: [" $2 "] " $3 "  - reason: " $4 }
                 $1=="stale" { print "  matches no current finding (stale): [" $2 "] " $3 "  - reason: " $4 }' "$TMP/acc.cls"
    [ "$STALEN" -eq 0 ] || echo "  $STALEN stale line(s) kept: they accept nothing today."
    record_decision accept "re-confirmed by --approve: $REASON" "$ACC"
  fi
  nrec=$(grep -vc '^#' "$APPROVED")
  echo "security-check: access snapshot approved ($nrec facts) -> $APPROVED"
  echo "  reason: $REASON"
  echo
  echo "Add this row to the Decisions table in PROJECT.md (the register is the lead's to write):"
  echo "| security | Access snapshot approved (docs/security/access-approved.txt, cksum $sum): $REASON | CONFIRMED | $(date -u +%Y-%m-%d) |"
  nnew=$(wc -l < "$FIND_NEW" | tr -d ' ')
  if [ "$nnew" -gt 0 ]; then
    echo
    echo "$nnew security finding(s) are still NEW (not accepted). Approving the snapshot does not accept them:"
    list_findings "$FIND_NEW"
    echo "Accept each one you agree with (a person runs these):"
    print_accept_cmds "$FIND_NEW"
  fi
  exit 0
fi

# --- check: compare -------------------------------------------------------------------------
# Translate the difference between the approved and the current snapshot into sentences that
# name the role and the element. Records: kind <TAB> key fields <TAB> value (the LAST field).
translate_changes() {  # translate_changes <approved> <current> -> sentences on stdout (sorted)
  LC_ALL=C grep -v '^#' "$1" | LC_ALL=C sort -u > "$TMP/a.recs"
  LC_ALL=C grep -v '^#' "$2" | LC_ALL=C sort -u > "$TMP/c.recs"
  LC_ALL=C comm -23 "$TMP/a.recs" "$TMP/c.recs" > "$TMP/lost.recs"
  LC_ALL=C comm -13 "$TMP/a.recs" "$TMP/c.recs" > "$TMP/gained.recs"
  awk -F'\t' '
    function lastf(r,   n, a) { n=split(r, a, "\t"); return a[n] }
    function keyof(r,   v) { v=lastf(r); return substr(r, 1, length(r)-length(v)-1) }
    function up(s) { return toupper(s) }
    function words(s,   c, a, i, o) { c=split(s, a, ","); o=""; for (i=1;i<=c;i++) o = o (o==""?"":", ") up(a[i]); return o }
    function setdiff(x, y,   cx, ax, cy, ay, i, j, f, o) {  # words in x not in y (comma lists)
      cx=split(x, ax, ","); cy=split(y, ay, ","); o=""
      for (i=1;i<=cx;i++) { f=0; for (j=1;j<=cy;j++) if (ax[i]==ay[j]) f=1; if (!f && ax[i]!="") o = o (o==""?"":",") ax[i] }
      return o }
    function rowtxt(x) { return (x=="-") ? "ALL rows" : "only rows where " x }
    function out(s) { print s; n++ }
    function entity_rights_msg(role, E, xp, old, new,   add, rem) {
      add=setdiff(new, old); rem=setdiff(old, new)
      if (add != "") out(role " can now " words(add) " " E " (" rowtxt(xp) ")")
      if (rem != "") out(role " can no longer " words(rem) " " E " (" rowtxt(xp) ")")
    }
    FILENAME == ARGV[1] { L[$0]=1; next }
    { G[$0]=1 }
    END {
      # pair lost and gained records that share every field but the last
      for (r in L) { lk[keyof(r)] = r }
      for (r in G) { gk[keyof(r)] = r }
      for (k in gk) { r=gk[k]; split(r, f, "\t"); kind=f[1]; nv=lastf(r)
        if (k in lk) { ov=lastf(lk[k]); paired[k]=1
          if (kind=="security") { if (f[2]=="Guest Access" && nv=="true") out("ANONYMOUS ACCESS: project security Guest Access was turned ON (was " ov ")"); else out("project security: " f[2] " changed from " ov " to " nv) }
          else if (kind=="user-role-flag") out("user role " f[2] ": " f[3] " changed from " ov " to " nv)
          else if (kind=="demo-user") out("demo user " f[2] ": roles changed from [" ov "] to [" nv "]")
          else if (kind=="entity-rights") entity_rights_msg(f[3], f[2], f[4], ov, nv)
          else if (kind=="entity-default") out(f[3] " default attribute access on " f[2] " (" rowtxt(f[4]) ") changed from " ov " to " nv)
          else if (kind=="member-access") {
            if (nv=="ReadWrite") out(f[3] " can now WRITE " f[5] " (was " ov ")")
            else if (ov=="ReadWrite") out(f[3] " can no longer WRITE " f[5] " (now " nv ")")
            else if (nv=="None") out(f[3] " can no longer READ " f[5])
            else out(f[3] " can now READ " f[5] " (was " ov ")")
          }
          else out("changed: " kind " " k " from " ov " to " nv)
        } }
      # row restriction removed / added: same entity+role+rights, xpath differs
      for (k in gk) { if (k in paired) continue; r=gk[k]; split(r, f, "\t"); if (f[1]!="entity-rights") continue
        for (k2 in lk) { if (k2 in paired) continue; split(lk[k2], g, "\t"); if (g[1]!="entity-rights" || g[2]!=f[2] || g[3]!=f[3]) continue
          if (f[4]=="-" && g[4]!="-") { out(f[3] " can now see ALL rows of " f[2] ": the row restriction " g[4] " was REMOVED (rights " words(f[5]) ")"); paired[k]=1; paired[k2]=1; ruleevt[f[2] "\t" f[3] "\t" f[4]]=1; ruleevt[g[2] "\t" g[3] "\t" g[4]]=1; break }
          if (f[4]!="-" && g[4]=="-") { out(f[3] " is now limited on " f[2] " to rows where " f[4] " (was ALL rows)"); paired[k]=1; paired[k2]=1; ruleevt[f[2] "\t" f[3] "\t" f[4]]=1; ruleevt[g[2] "\t" g[3] "\t" g[4]]=1; break }
        } }
      for (k in gk) { if (k in paired) continue; r=gk[k]; split(r, f, "\t"); kind=f[1]; nv=lastf(r)
        if (kind=="security") out("project security: " f[2] " is now " nv)
        else if (kind=="user-role-has") out("user role " f[2] " now includes module role " f[3])
        else if (kind=="user-role-flag") out("user role " f[2] ": " f[3] " is now " nv)
        else if (kind=="module-role") out("module role " f[2] " was ADDED")
        else if (kind=="module-role-unmapped") out("module role " f[2] " is mapped to NO user role (nobody can hold it)")
        else if (kind=="demo-user") out("demo user " f[2] " was added with roles [" nv "]")
        else if (kind=="page-access") out(f[3] " can now OPEN page " f[2])
        else if (kind=="microflow-access") out(f[3] " can now EXECUTE microflow " f[2])
        else if (kind=="entity-no-rules") out("entity " f[2] " has NO access rules")
        else if (kind=="entity-raw") out("access rule line on " f[2] " (rule for " f[3] ") not understood by this check, now present: " f[4])
        else if (kind=="entity-rights") { ruleevt[f[2] "\t" f[3] "\t" f[4]]=1; out(f[3] " can now " words(nv) " " f[2] " (" rowtxt(f[4]) ")") }
        else if (kind=="entity-default") { }
        else if (kind=="member-access") { if (!((f[2] "\t" f[3] "\t" f[4]) in ruleevt) && nv!="None") out(f[3] " can now " (nv=="ReadWrite"?"WRITE ":"READ ") f[5]) }
        else out("added: " kind " " k " " nv)
      }
      for (k in lk) { if (k in paired) continue; r=lk[k]; split(r, f, "\t"); kind=f[1]; ov=lastf(r)
        if (kind=="security") out("project security: " f[2] " (was " ov ") is no longer reported")
        else if (kind=="user-role-has") out("user role " f[2] " no longer includes module role " f[3])
        else if (kind=="user-role-flag") out("user role " f[2] ": " f[3] " (was " ov ") is no longer reported")
        else if (kind=="module-role") out("module role " f[2] " was REMOVED")
        else if (kind=="module-role-unmapped") { }
        else if (kind=="demo-user") out("demo user " f[2] " was removed")
        else if (kind=="page-access") out(f[3] " can no longer open page " f[2])
        else if (kind=="microflow-access") out(f[3] " can no longer execute microflow " f[2])
        else if (kind=="entity-no-rules") out("entity " f[2] " no longer reports missing access rules")
        else if (kind=="entity-raw") out("access rule line on " f[2] " (rule for " f[3] ") not understood by this check, no longer present: " f[4])
        else if (kind=="entity-rights") { ruleevt[f[2] "\t" f[3] "\t" f[4]]=1; out(f[3] " lost its rule on " f[2] " (" rowtxt(f[4]) "; was " words(ov) ")") }
        else if (kind=="entity-default") { }
        else if (kind=="member-access") { if (!((f[2] "\t" f[3] "\t" f[4]) in ruleevt) && ov!="None") out(f[3] " lost access to " f[5] " (was " ov ")") }
        else out("removed: " kind " " k " " ov)
      }
    }' "$TMP/lost.recs" "$TMP/gained.recs" | LC_ALL=C sort -u
}

if [ ! -f "$APPROVED" ]; then
  verdict=not-approved; rc=3; NEWN=$(wc -l < "$FIND_NEW" | tr -d ' '); ACCN=0
else
  NEWN=$(wc -l < "$FIND_NEW" | tr -d ' ')
  if cmp -s "$APPROVED_N" "$SNAP"; then ACCN=0
  else
    translate_changes "$APPROVED_N" "$SNAP" > "$CHG"
    ACCN=$(wc -l < "$CHG" | tr -d ' ')
    if [ "$ACCN" = 0 ]; then
      diff "$APPROVED_N" "$SNAP" | grep -E '^[<>]' | head -40 > "$CHG"
      ACCN=$(wc -l < "$CHG" | tr -d ' ')
    fi
  fi
  if [ "$NEWN" -gt 0 ]; then verdict=new-findings; rc=1
  elif ! cmp -s "$APPROVED_N" "$SNAP"; then verdict=access-changed; rc=1
  else verdict=clean; rc=0; fi
fi
write_state "$verdict" "$NEWN" "$ACCN"

if [ "$JSON" = 1 ]; then
  nf="$TMP/nf.txt"; awk -F'\t' '{ print "[" $1 "] " $2 }' "$FIND_NEW" > "$nf"
  tot=$(wc -l < "$FIND_ALL" | tr -d ' ')
  printf '{"verdict":"%s","exit":%s,"new_findings":[' "$verdict" "$rc"
  awk -F'\t' 'BEGIN{f=1} { m=$2; gsub(/\\/,"\\\\",m); gsub(/"/,"\\\"",m); printf "%s{\"rule\":\"%s\",\"message\":\"%s\"}", (f?"":","), $1, m; f=0 }' "$FIND_NEW"
  printf '],"access_changes":['
  jlist "$CHG"
  printf '],"counts":{"new":%s,"access_changes":%s,"security_findings":%s}}\n' "$NEWN" "$ACCN" "$tot"
  emit_result "$verdict" "$NEWN" "$ACCN" "$rc"
  case "$verdict" in
    clean) echo "security-check: clean" >&2 ;;
    not-approved) echo "security-check: nothing approved yet - run without --json for the commands" >&2 ;;
    *) echo "security-check: not clean - run without --json for the details" >&2 ;;
  esac
  exit "$rc"
fi

echo "security-check: $(basename "$MPR")"
tot=$(wc -l < "$FIND_ALL" | tr -d ' ')
if [ "$verdict" = not-approved ]; then
  echo
  echo "FIRST RUN - nothing has been approved yet, so there is nothing to compare with."
  echo
  echo "Security findings from lint ($tot):"
  if [ "$tot" = 0 ]; then echo "  (none)"; else
    while IFS="$TAB" read -r r m; do
      if LC_ALL=C grep -qxF "$(printf '%s\t%s' "$r" "$m")" "$TMP/acc.pairs"; then t="accepted"; else t="NEW"; fi
      d=$(rule_desc "$r")
      if [ -n "$d" ]; then printf '  [%s - %s] %s  (%s)\n' "$r" "$d" "$m" "$t"; else printf '  [%s] %s  (%s)\n' "$r" "$m" "$t"; fi
    done < "$FIND_ALL"
  fi
  if [ "$NEWN" -gt 0 ]; then
    echo
    echo "A person accepts each finding they agree with (an agent must not):"
    print_accept_cmds "$FIND_NEW"
  fi
  if [ "$NEWN" -gt 0 ] && [ -e "$TEMPLATE" ]; then
    echo "Kept your existing $TEMPLATE (delete it to get a fresh one)."
  elif [ "$NEWN" -gt 0 ]; then
    { printf '# security-check --accept-file template: rule<TAB>finding<TAB>reason. Fill in a reason for each finding you accept, delete the lines you do not, then:  bin/security-check.sh --accept-file <this file>\n'
      awk -F'\t' '{ print $1 "\t" $2 "\t" }' "$FIND_NEW"; } > "$TEMPLATE" 2>/dev/null \
      && echo "To accept many at once: a person fills in the reason column of $TEMPLATE (left EMPTY on purpose) and runs bin/security-check.sh --accept-file $TEMPLATE"
  fi
  echo
  echo "Access snapshot written to $SNAP - what it holds:"
  summary_counts
  echo
  echo "Show it to the person who owns the access decisions. When they approve it:"
  echo "  bin/security-check.sh --approve --reason \"<who approved, and why>\""
  emit_result "$verdict" "$NEWN" "$ACCN" "$rc"
  echo "Exit 3: no baseline yet. This is never a pass."
  exit "$rc"
fi

if [ "$NEWN" -gt 0 ]; then
  echo
  echo "NEW security finding(s): $NEWN (of $tot; the rest are accepted)"
  list_findings "$FIND_NEW"
  echo "  A person accepts a finding they agree with:"
  print_accept_cmds "$FIND_NEW"
fi
if [ "$ACCN" -gt 0 ]; then
  echo
  echo "ACCESS CHANGED since the approved snapshot ($ACCN):"
  sed 's/^/  - /' "$CHG"
  echo "  If this is intended, a person approves it:  bin/security-check.sh --approve --reason \"<who approved, and why>\""
fi
[ "$STALEN" -eq 0 ] || echo "$STALEN accepted line(s) match no current finding (stale)"
emit_result "$verdict" "$NEWN" "$ACCN" "$rc"
case "$verdict" in
  clean) echo "Clean: $tot security finding(s), all accepted; the access snapshot equals the approved copy."
         echo "This check covers new security lint findings and changes to the recorded access facts (roles, pages, microflows, entity and attribute rights, row restrictions, project security settings); it does not cover published REST/OData services and their roles, nanoflow or workflow access, or which roles a user role may assign." ;;
  *) echo "Not clean. What is wrong is listed above; a person decides whether to fix it or approve it." ;;
esac
exit "$rc"
