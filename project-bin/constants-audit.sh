#!/usr/bin/env bash
# constants-audit.sh — classify every constant in the model, without ever printing a value.
#
# WHY THIS EXISTS (field-found 2026-09-16 on a Mendix build project deployed to a free-node sandbox).
# `Encryption.EncryptionKey` shipped as `default ''`. Locally that was invisible: the value
# came from app/.mxcli/constants.json, which is gitignored and machine-local. In the deployed
# sandbox it was empty, and MxGenAIConnector — which encrypts a GenAI key's access token while
# storing it — refused every route into its admin page with a message that names the WRONG
# subsystem:
#
#     For the key import to work, the Encryption module must be configured correctly.
#
# Half a day went into "the GenAI resource pack must be missing" before anyone read that as
# "a constant has no value here". A free Mendix node has no Constants tab at all, and the
# Deploy API does not expose environment settings to a PAT (v4 404s on .../settings/constants,
# v1 rejects a PAT outright) — so on a free node the MODEL DEFAULT is the only channel there is.
#
# This script answers the one question that would have caught it in seconds:
#   "which constants would be empty in an environment that cannot set constants?"
# and the one that the fix creates:
#   "which constants carry a secret that is now shipped in the model — or worse, to the browser?"
#
# IT NEVER PRINTS A CONSTANT'S VALUE. Only EMPTY vs SET, the type, and the flags. An audit that
# echoes the secrets it is auditing is a leak with a checklist attached — and it would land in
# CI logs, in scrollback, and in whatever transcript the agent session is writing.
#
# Findings (exit 1):
#   CLIENT-SECRET  a secret-named constant marked "Exposed to client" — the value is served to
#                  every browser session. Always a defect; no environment setting can hide it.
#   EMPTY          no model default. Fine on a licensed node whose Portal sets it; a silent
#                  runtime failure on a free node, in a Docker run, or on any fresh clone.
#   MODEL-SECRET   a secret-named constant that DOES carry a model default. Deliberate on a demo
#                  (that value is now in git, Team Server and every clone); never right for
#                  anything holding real data. Waive it with a reason, or override per
#                  environment and empty the default.
#
# Waivers live in the project's own register, one line each, anywhere in docs/constants-register.md:
#   Waived constant <Qualified.Name>: <reason>
# A waiver is a decision on the record, not a mute button — the run reports WAIVED and its reason.
#
# Usage:
#   bin/constants-audit.sh                 # verdict table + summary
#   bin/constants-audit.sh --json          # machine-readable, same data
#   MPR_FILE=Other.mpr bin/constants-audit.sh
#
# Exit: 0 clean (or every finding waived) · 1 findings · 2 instrument fault
#
# Field run: a Mendix build project (BRD-driven, ~30 modules), 2026-09-16, Mendix 11.14.0 — 30 constants, 3 findings, all three
# true readings of the model: the EncryptionKey default this incident added (MODEL-SECRET), an
# empty LegacyEncryptionKey (EMPTY), and FeedbackModule.LocalStorageKey, which the name
# heuristic calls a secret and is not (CLIENT-SECRET) — waived in that project with a reason.
# That third one is the heuristic being a floor, exactly as documented, not a defect to tune away.
# Companion skill (the judgement this script deliberately does NOT make):
#   skills/learned-constants-and-secrets.md

set -u

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
. "$SELF_DIR/_common.sh" 2>/dev/null || { echo "constants-audit: cannot source _common.sh" >&2; exit 2; }

JSON=0
for a in "$@"; do
  case "$a" in
    --json) JSON=1 ;;
    -h|--help) sed -n '2,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "constants-audit: unknown argument '$a'" >&2; exit 2 ;;
  esac
done

MPR=$(find_mpr) || exit 2

# mxcli is on PATH in a wired project and at ./mxcli in some checkouts. Probe, do not assume:
# a bare `mxcli` that does not exist reports "command not found" as exit 127, which a caller
# reads as a finding rather than as "the instrument could not run".
MXCLI=""
for c in "$PROJECT_ROOT/mxcli" "./mxcli" mxcli; do
  if [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; then MXCLI="$c"; break; fi
done
[ -n "$MXCLI" ] || { echo "constants-audit: no mxcli on PATH or at $PROJECT_ROOT/mxcli" >&2; exit 2; }

RAW=$("$MXCLI" -p "$MPR" -c "SHOW CONSTANTS" 2>&1) || {
  echo "constants-audit: 'SHOW CONSTANTS' failed against $MPR" >&2
  printf '%s\n' "$RAW" | tail -5 >&2
  exit 2
}

# SHOW CONSTANTS renders a 7-column pipe table:
#   | Qualified Name | Module | Name | Folder | Type | Default | Exposed |
# Verbatim header captured from mxcli 11.14.0 and asserted below — a column that moves must
# break this loudly, not shift every value one field to the left and report nonsense. This is
# the header-row class of bug that made an earlier instrument count 13 pages in a 6-page model.
HEADER=$(printf '%s\n' "$RAW" | grep -m1 '^| *Qualified Name')
case "$HEADER" in
  *"| Module"*"| Name"*"| Folder"*"| Type"*"| Default"*"| Exposed"*) ;;
  "") echo "constants-audit: no constants table in 'SHOW CONSTANTS' output" >&2; exit 2 ;;
  *)  echo "constants-audit: SHOW CONSTANTS columns are not the 7 this parser was written against." >&2
      echo "                 Re-read the header and update the field numbers before trusting a verdict." >&2
      exit 2 ;;
esac

# The register lives at the REPO root, which is not always the model root. On a two-tree
# checkout (repo at the top, `mxcli new` app under app/) find_mpr resolves PROJECT_ROOT to
# app/, and a register probed only there is silently absent — every waived constant comes back
# as a finding, which is the failure mode that reads as "the tool is wrong" and gets it muted.
# Probe both, model root first. Same class of bug as F-020/F-042.
REGISTER=""
for r in "$PROJECT_ROOT/docs/constants-register.md" "$PROJECT_ROOT/../docs/constants-register.md"; do
  [ -f "$r" ] && { REGISTER="$r"; break; }
done

# A name-based secret heuristic, stated out loud because it is one: it catches the conventional
# spellings and misses a secret called "Foo". It is a floor, not a classifier — the skill's
# register is what makes the classification real.
SECRET_RE='[Kk][Ee][Yy]$|[Ss]ecret|[Pp]assword|[Pp]wd|[Tt]oken|[Cc]redential|ApiKey|APIKey|[Pp]assphrase|PrivateKey'

FINDINGS=0; WAIVED=0; TOTAL=0; EMPTIES=0; SECRETS=0
ROWS=""; JROWS=""

# Read the body rows. The `---|---` separator and the header are skipped by the Qualified-Name
# test: a real row's first field is Module.Name.
while IFS= read -r line; do
  case "$line" in '|'*) ;; *) continue ;; esac
  qname=$(printf '%s\n' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
  case "$qname" in
    ''|'Qualified Name'|*---*) continue ;;
    *.*) ;;
    *) continue ;;
  esac
  type=$(printf '%s\n' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$6); print $6}')
  dflt=$(printf '%s\n' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$7); print $7}')
  expo=$(printf '%s\n' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$8); print $8}')

  TOTAL=$((TOTAL + 1))

  # $dflt is used ONLY for this emptiness test and is never echoed, never stored in a variable
  # that reaches output, and never written to the JSON.
  if [ -z "$dflt" ]; then state=EMPTY; EMPTIES=$((EMPTIES + 1)); else state=SET; fi
  if printf '%s' "$qname" | grep -Eq "$SECRET_RE"; then secret=yes; SECRETS=$((SECRETS + 1)); else secret=no; fi
  case "$expo" in [Yy]es|true|True) client=yes ;; *) client=no ;; esac

  verdict=OK
  [ "$state" = EMPTY ] && verdict=EMPTY
  [ "$secret" = yes ] && [ "$state" = SET ] && verdict=MODEL-SECRET
  [ "$secret" = yes ] && [ "$client" = yes ] && verdict=CLIENT-SECRET

  reason=""
  if [ "$verdict" != OK ] && [ -n "$REGISTER" ]; then
    reason=$(grep -m1 "^Waived constant $qname:" "$REGISTER" 2>/dev/null | sed "s/^Waived constant $qname: *//")
    if [ -n "$reason" ]; then verdict=WAIVED; WAIVED=$((WAIVED + 1)); fi
  fi
  [ "$verdict" != OK ] && [ "$verdict" != WAIVED ] && FINDINGS=$((FINDINGS + 1))

  # The table shows the first line of the reason only. A waiver is prose — one real waiver's runs to
  # four sentences — and printing it whole turns a 30-row table into a wall. The register is
  # the place to read it; this column only has to prove a reason exists.
  short=$(printf '%s' "$reason" | cut -c1-58)
  [ "${#reason}" -gt 58 ] && short="$short…"

  ROWS="$ROWS$(printf '%-13s %-44s %-10s %-8s %s' "$verdict" "$qname" "$type" "$state" "$short")
"
  jreason=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
  JROWS="$JROWS    {\"constant\":\"$qname\",\"type\":\"$type\",\"default\":\"$state\",\"secretName\":\"$secret\",\"clientExposed\":\"$client\",\"verdict\":\"$verdict\",\"waiver\":\"$jreason\"},
"
done <<EOF
$RAW
EOF

[ "$TOTAL" -gt 0 ] || { echo "constants-audit: parsed 0 constants from a table that had a header — the row format moved." >&2; exit 2; }

if [ "$JSON" = 1 ]; then
  printf '{\n  "instrument": "constants-audit",\n  "model": "%s",\n  "total": %d,\n  "empty": %d,\n  "secretNamed": %d,\n  "findings": %d,\n  "waived": %d,\n  "constants": [\n%s  ]\n}\n' \
    "$(basename "$MPR")" "$TOTAL" "$EMPTIES" "$SECRETS" "$FINDINGS" "$WAIVED" "$(printf '%s' "$JROWS" | sed '$ s/,$//')"
else
  echo "Constants audit — $(basename "$MPR") · $TOTAL constants · no values are printed"
  echo ""
  printf '%-13s %-44s %-10s %-8s %s\n' VERDICT CONSTANT TYPE DEFAULT WAIVER
  printf '%s' "$ROWS" | grep -v '^OK  ' | sort
  echo ""
  echo "  $TOTAL constants · $EMPTIES with no model default · $SECRETS secret-named · $WAIVED waived"
  if [ "$FINDINGS" -gt 0 ]; then
    echo "  ✗ $FINDINGS finding(s). EMPTY = blank in any environment that cannot set constants"
    echo "    (free node, Docker run, fresh clone). MODEL-SECRET = the value is in git."
    echo "    CLIENT-SECRET = the value is served to every browser; fix, never waive."
    echo "    Decide per constant in skills/learned-constants-and-secrets.md, then either fix it"
    echo "    or record: 'Waived constant <Qualified.Name>: <reason>' in docs/constants-register.md"
  else
    echo "  ✓ no unwaived findings"
  fi
fi

[ "$FINDINGS" -gt 0 ] && exit 1
exit 0
