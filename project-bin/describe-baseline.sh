#!/usr/bin/env bash
# describe-baseline.sh — record, at draft time, what each document a script restates looked like;
# say, at exec time, whether it still looks that way.
#
#   bin/describe-baseline.sh stamp  <script.mdl>   DESCRIBE every document the script restates and
#                                                 write one header line per document at the top:
#                                                   -- baseline: Module.Doc sha256=<hex>
#                                                   -- baseline: Module.Doc absent
#                                                 Re-stamping replaces the old lines. Run it right
#                                                 after the DESCRIBE you drafted from.
#   bin/describe-baseline.sh verify <script.mdl>   re-DESCRIBE each baselined document and compare.
#                                                 exit 0 all match · 1 drift (one DRIFT row each)
#                                                 · 2 no baseline header · 3 could not DESCRIBE
#   bin/describe-baseline.sh record-applied <script.mdl>
#                                                 after a gate pass: record each document's live
#                                                 hash as written BY this script (applied.tsv)
#   bin/describe-baseline.sh live <KIND> <Doc>     prints sha256=<hex> or absent
#   bin/describe-baseline.sh applied-by <Doc> <sha256=hex>
#                                                 the scripts whose recorded write left that hash
#
# verify reads SAME — not DRIFT — in the two cases that are not a stale draft:
#   the live body is this script's own recorded write (a re-run after a clean exec), and
#   a baselined document is absent (a rebuild onto a fresh model: the script creates it).
# Without the applied record a re-run of a stamped script read DRIFT, and under exec approval
# `ask` that refused every re-run and every from-empty rebuild.
#
# "Restates" = `create or modify|create or replace microflow|nanoflow|page|snippet` — the
# statements whose body replaces whatever is live (script-owners.sh docs, one parser). A plain
# `create` fails on an existing name, so it needs no baseline.
#
# WHY (#261, field 2026-10-10, Mendix 11.14.0, mxcli v0.24.0). Script A changed the messages of
# three microflows. Script B, drafted in the same batch from a DESCRIBE taken BEFORE A ran,
# restated them whole; executing B put four old messages back. check --references, mxbuild
# (0 errors) and lint all passed: a whole restatement is valid MDL whatever it replaces. Caught
# later by a module review and a failing end-to-end journey. The draft-ahead pattern (agents
# drafting later rows while earlier rows execute) makes this the default outcome, not a fluke.
#
# The hash is of the DESCRIBE text (CR stripped). Any change — another script, Studio Pro, a
# hand fix — moves it. A moved hash is not proof of loss, only that the drafter's picture is
# stale: re-DESCRIBE, merge, re-stamp. The DESCRIBE text itself is kept beside the snapshots
# (.claude/loop/describe-baseline/<hash>.mdl) so verify can print the first lines of the diff.
#
# What a baseline cannot see: anything DESCRIBE does not print. Module-role visibility and
# layout-grid row visibility are absent from DESCRIBE (v0.25.0, #309), so a restatement drops
# them with the hash unchanged — learned-mdl-preflight.md has the STOP row for that.
#
# DESCRIBE runs through the project's own ./mxcli: `mxcli -p <app>.mpr -c "DESCRIBE <KIND> <Doc>"`.
# A missing document: exit non-zero and "<kind> not found: <Doc>", recorded as `absent`. That
# text is real mxcli output recorded in this repo, never imagined: `Error: entity not found:
# ZKT35.Widget (duration: 1.022958ms)`, EXIT 1 (a 2026-08-07 retest log under bug-logs/)
# and `Error: constant not found: Nope.X`, rc 1 (v0.24.0, project-bin/conformance-check.sh). No
# capture for a missing MICROFLOW/PAGE exists here, so the match is on the shape — non-zero exit,
# no DESCRIBE body, "not found:" followed by this document's name — and never on a parse error
# or "no describable document named" (both verbatim v0.24.0, conformance-check.sh), which say
# nothing about the model and fail the call (exit 3).
# Golden DESCRIBE output: mxcli v0.23.0 captures in tests/wave2/fixtures/context-pack/capture/.
# Consumer: exec.sh runs `verify` before every MDL write that carries a baseline header
# (warn-first; MXTK_RESTATE_GUARD=refuse or exec approval `ask` makes drift a refusal).
# Producer: this script's `stamp`, run by whoever drafts the script (learned-mdl-preflight.md
# STOP 21). Bash 3.2 / Git Bash; no Python.
set -u

usage() {
  sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/_common.sh"

CMD="${1:-}"; SCRIPT="${2:-}"
case "$CMD" in
  stamp|verify|record-applied) [ -f "$SCRIPT" ] || usage ;;
  live) [ $# -eq 3 ] || usage ;;
  applied-by) [ $# -eq 3 ] || usage ;;
  *) usage ;;
esac
OWNERS="$HERE/script-owners.sh"
[ -f "$OWNERS" ] || { echo "describe-baseline: $OWNERS is not installed (run sync-project.sh)" >&2; exit 3; }

CACHE="$PROJECT_ROOT/.claude/loop/describe-baseline"
APPLIED="$CACHE/applied.tsv"   # epoch <tab> script key <tab> Doc <tab> sha256=<hex>

# A script's key: its path relative to the project root with a leading done- taken off the file
# name (iterative-build-loop.md renames an executed script done-<name>); script-owners.sh sorts
# and matches on the same key.
script_key() {  # $1 = script path
  local abs rel b
  abs="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
  rel="${abs#"$PROJECT_ROOT"/}"
  b="$(basename "$rel" | sed 's/^done-//')"
  printf '%s/%s\n' "$(dirname "$rel")" "$b"
}
# applied_keys <Doc> <sha256=hex> → every script key whose recorded write left that hash.
applied_keys() {
  [ -f "$APPLIED" ] || return 0
  awk -F'\t' -v d="$1" -v h="$2" '$3 == d && $4 == h && !seen[$2]++ { print $2 }' "$APPLIED"
}

# KIND <tab> Doc for every restated document, first occurrence order, unique.
restated() {
  bash "$OWNERS" docs "$SCRIPT" | awk -F'\t' '$4 == "modify" || $4 == "replace" { k = $1 "\t" $2; if (!(k in s)) { s[k] = 1; print k } }'
}

MXCLI=""
MPR=""
need_mxcli() {
  [ -n "$MXCLI" ] && return 0
  MXCLI="$(find_project_mxcli)" || { echo "describe-baseline: no ./mxcli in $PROJECT_ROOT — cannot DESCRIBE" >&2; return 1; }
  MPR="$(find_mpr)" || return 1
}

# Prints the hash (or "absent") of DESCRIBE <kind> <doc>; keeps the text in the cache.
# Returns 1 when DESCRIBE failed for a reason other than "not found".
describe_hash() {  # $1 = KIND, $2 = Doc
  local out err rc h all body
  err="$(mktemp "${TMPDIR:-/tmp}/dbl-err.XXXXXX")"
  rc=0
  out="$("$MXCLI" -p "$MPR" -c "DESCRIBE $1 $2" 2>"$err")" || rc=$?
  # Which stream carries "Error: ..." is not recorded in the captures, so read both. The
  # "Connected to: <path>" line seen in the recorded REPL-style output is not part of the body.
  body="$(printf '%s\n' "$out" | tr -d '\r' | grep -v '^Connected to:' || true)"
  if [ "$rc" -ne 0 ]; then
    all="$(printf '%s\n' "$out"; cat "$err")"
    if [ -z "$(printf '%s' "$body" | grep -v '^Error:' | tr -d '[:space:]')" ] \
       && ! printf '%s\n' "$all" | grep -qE 'Parse error|no describable document' \
       && printf '%s\n' "$all" | grep -qiF "not found: $2"; then
      rm -f "$err"; echo absent; return 0
    fi
    printf '%s\n' "$all" | sed 's/^/    mxcli: /' >&2; rm -f "$err"; return 1
  fi
  rm -f "$err"
  h="$(printf '%s\n' "$body" | mxtk_sha256)"
  mkdir -p "$CACHE" 2>/dev/null && printf '%s\n' "$body" > "$CACHE/$h.mdl" 2>/dev/null
  echo "sha256=$h"
}

if [ "$CMD" = live ]; then
  need_mxcli || exit 3
  describe_hash "$2" "$3" || exit 3
  exit 0
fi
if [ "$CMD" = applied-by ]; then
  applied_keys "$2" "$3"
  exit 0
fi
if [ "$CMD" = record-applied ]; then
  # Every document the script names (create too: a re-run of a plain create is refused by
  # mxcli anyway, but its body is still the script's own write for a later co-owner).
  need_mxcli || exit 3
  KEY="$(script_key "$SCRIPT")"
  mkdir -p "$CACHE" 2>/dev/null || exit 3
  n=0
  while IFS='	' read -r kind doc; do
    [ -n "$doc" ] || continue
    v="$(describe_hash "$kind" "$doc")" || continue
    [ "$v" = absent ] && continue
    printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$KEY" "$doc" "$v" >> "$APPLIED"
    n=$((n + 1))
  done <<EOF
$(bash "$OWNERS" docs "$SCRIPT" | awk -F'\t' '{ k = $1 "\t" $2; if (!(k in s)) { s[k] = 1; print k } }')
EOF
  echo "describe-baseline: recorded $n applied document(s) for $KEY"
  exit 0
fi

if [ "$CMD" = stamp ]; then
  need_mxcli || exit 3
  DOCS="$(restated)"
  if [ -z "$DOCS" ]; then echo "describe-baseline: $SCRIPT restates no document — nothing to stamp"; exit 0; fi
  HDR=""
  while IFS='	' read -r kind doc; do
    [ -n "$doc" ] || continue
    v="$(describe_hash "$kind" "$doc")" || { echo "describe-baseline: DESCRIBE $kind $doc failed — nothing stamped" >&2; exit 3; }
    HDR="$HDR-- baseline: $doc $v
"
    echo "  $doc $v"
  done <<EOF
$DOCS
EOF
  TMP="$(mktemp "${TMPDIR:-/tmp}/dbl-script.XXXXXX")"
  { printf '%s' "$HDR"; grep -vE '^[[:space:]]*--[[:space:]]*baseline:' "$SCRIPT"; } > "$TMP"
  cat "$TMP" > "$SCRIPT"; rm -f "$TMP"
  echo "describe-baseline: stamped $(printf '%s' "$HDR" | grep -c .) document(s) in $SCRIPT"
  exit 0
fi

# ── verify ───────────────────────────────────────────────────────────────────
LINES="$(sed -nE 's/^[[:space:]]*--[[:space:]]*baseline:[[:space:]]*([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*)[[:space:]]+(sha256=[0-9a-f]{64}|absent).*$/\1 \2/p' "$SCRIPT")"
if [ -z "$LINES" ]; then
  echo "NOBASELINE	$(restated | wc -l | tr -d ' ')"
  exit 2
fi
need_mxcli || exit 3
KINDS="$(restated)"
KEY="$(script_key "$SCRIPT")"
RC=0
while read -r doc want; do
  [ -n "$doc" ] || continue
  kind="$(printf '%s\n' "$KINDS" | awk -F'\t' -v d="$doc" '$2 == d { print $1; exit }')"
  if [ -z "$kind" ]; then echo "STALEHEADER	$doc	the script no longer restates it — re-stamp"; continue; fi
  have="$(describe_hash "$kind" "$doc")" || { echo "UNKNOWN	$doc	DESCRIBE failed"; [ "$RC" -eq 0 ] && RC=3; continue; }
  if [ "$have" = "$want" ]; then echo "SAME	$doc"; continue; fi
  if [ "$have" = absent ]; then echo "SAME	$doc	absent: this script creates it (a rebuild)"; continue; fi
  if applied_keys "$doc" "$have" | grep -qxF "$KEY"; then echo "SAME	$doc	live body is this script's own recorded write"; continue; fi
  case "$want" in
    absent) why="created since the script was drafted" ;;
    *)      why="changed since the script was drafted" ;;
  esac
  echo "DRIFT	$doc	$why"
  old="$CACHE/${want#sha256=}.mdl"; new="$CACHE/${have#sha256=}.mdl"
  if [ -f "$old" ] && [ -f "$new" ] && command -v diff >/dev/null 2>&1; then
    diff -u "$old" "$new" | sed -n '3,14p' | sed 's/^/    /'
  fi
  RC=1
done <<EOF
$LINES
EOF
exit "$RC"
