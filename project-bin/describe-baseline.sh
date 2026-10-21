#!/usr/bin/env bash
# describe-baseline.sh — record, at draft time, what each document a script restates looked like;
# say, at exec time, whether it still looks that way.
#
#   bin/describe-baseline.sh stamp  <script.mdl>   DESCRIBE every document the script restates and
#                                                 write one header line per document at the top:
#                                                   -- baseline: Module.Doc sha256=<hex>
#                                                   -- baseline: Module.Doc absent
#                                                   -- baseline-mxcli: v0.26.0
#                                                 Re-stamping replaces the old lines. Run it right
#                                                 after the DESCRIBE you drafted from.
#   bin/describe-baseline.sh verify <script.mdl>   re-DESCRIBE each baselined document and compare.
#                                                 exit 0 all match · 1 a row to warn on: DRIFT,
#                                                 RESTAMP (mxcli upgraded since the stamp: DESCRIBE
#                                                 text may differ, so not called drift) or
#                                                 STALEHEADER · 2 no baseline header · 3 no DESCRIBE
#   bin/describe-baseline.sh live <KIND> <Doc>     prints sha256=<hex> or absent
#
# verify reads SAME, not DRIFT, in the two cases that are not a stale draft:
#   the last recorded writer of the document is this script (a re-run after a clean exec;
#   `script-owners.sh last-writer`, the ledger exec.sh writes after every kept write), and
#   a baselined document is absent (a rebuild onto a fresh model: the script creates it).
#
# COST. Opt-in: only a script that carries a `-- baseline:` header pays anything, one DESCRIBE
# per baselined document (one `mxcli -c` each; 0.25 s on a small public test model, v0.26.0).
# A script with no header costs exec.sh one sed over the script and no mxcli call.
#
# "Restates" = `create or modify|create or replace microflow|nanoflow|page|snippet`, the
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
# The hash is of the DESCRIBE text (CR stripped). Any change (another script, Studio Pro, a hand
# fix) moves it. A moved hash is not proof of loss, only that the drafter's picture is stale:
# re-DESCRIBE, merge, re-stamp. The DESCRIBE text is kept in .claude/loop/describe-baseline/
# <hash>.mdl so verify can print the first lines of the diff.
#
# What a baseline cannot see: anything DESCRIBE does not print.
#
# DESCRIBE runs through the project's own ./mxcli: `mxcli -p <app>.mpr -c "DESCRIBE <KIND> <Doc>"`.
# A missing document: exit 1, nothing on stdout, "Error: <kind> not found: <Doc>" on stderr after
# mxcli's WARNING banner, recorded as `absent`. Captured from mxcli v0.26.0 for a missing
# microflow, nanoflow, page and snippet (tests/wave2/fixtures/restatement-guard/). The match is
# non-zero exit, no DESCRIBE body, and "not found: <this Doc>" in either stream, never a parse
# error or "no describable document named" (verbatim v0.24.0, conformance-check.sh): those say
# nothing about the model and fail the call (exit 3).
# Golden DESCRIBE output: mxcli v0.23.0 captures in tests/wave2/fixtures/context-pack/capture/,
# v0.26.0 in tests/wave2/fixtures/restatement-guard/.
# Consumer: exec.sh runs `verify` before every MDL write that carries a baseline header and
# prints a WARN line on drift, never a refusal. Producer: this script's `stamp`, run by whoever
# drafts the script (learned-mdl-preflight.md STOP 21). Bash 3.2 / Git Bash; no Python.
set -u

usage() {
  sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/_common.sh"

CMD="${1:-}"; SCRIPT="${2:-}"
case "$CMD" in
  stamp|verify) [ -f "$SCRIPT" ] || usage ;;
  live) [ $# -eq 3 ] || usage ;;
  *) usage ;;
esac
OWNERS="$HERE/script-owners.sh"
[ -f "$OWNERS" ] || { echo "describe-baseline: $OWNERS is not installed (run sync-project.sh)" >&2; exit 3; }

CACHE="$PROJECT_ROOT/.claude/loop/describe-baseline"

# A script's key: its path relative to the project root with a leading done- taken off the file
# name (iterative-build-loop.md renames an executed script done-<name>). script-owners.sh's
# ledger records the same key.
script_key() {  # $1 = script path
  local abs rel b root
  root="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)"
  abs="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
  rel="${abs#"$root"/}"
  b="$(basename "$rel" | sed 's/^done-//')"
  printf '%s/%s\n' "$(dirname "$rel")" "$b"
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
  # The "Connected to: <path>" line seen in REPL-style output is not part of the body.
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
# "v0.26.0" from `mxcli --version` (captured: "mxcli version v0.26.0 (2026-10-11T18:37:07Z)").
mxcli_version() { "$MXCLI" --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1; }

if [ "$CMD" = live ]; then
  need_mxcli || exit 3
  describe_hash "$2" "$3" || exit 3
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
  V="$(mxcli_version)"; [ -n "$V" ] && HDR="$HDR-- baseline-mxcli: $V
"
  TMP="$(mktemp "${TMPDIR:-/tmp}/dbl-script.XXXXXX")"
  { printf '%s' "$HDR"; grep -vE '^[[:space:]]*--[[:space:]]*baseline(-mxcli)?:' "$SCRIPT"; } > "$TMP"
  cat "$TMP" > "$SCRIPT"; rm -f "$TMP"
  echo "describe-baseline: stamped $(printf '%s' "$HDR" | grep -c ' baseline: ') document(s) in $SCRIPT"
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
WAS_V="$(sed -nE 's/^[[:space:]]*--[[:space:]]*baseline-mxcli:[[:space:]]*(v[0-9.]+).*$/\1/p' "$SCRIPT" | head -1)"
NOW_V=""; [ -n "$WAS_V" ] && NOW_V="$(mxcli_version)"
RC=0
while read -r doc want; do
  [ -n "$doc" ] || continue
  kind="$(printf '%s\n' "$KINDS" | awk -F'\t' -v d="$doc" '$2 == d { print $1; exit }')"
  if [ -z "$kind" ]; then echo "STALEHEADER	$doc	the script no longer restates it — re-stamp"; RC=1; continue; fi
  have="$(describe_hash "$kind" "$doc")" || { echo "UNKNOWN	$doc	DESCRIBE failed"; [ "$RC" -eq 0 ] && RC=3; continue; }
  if [ "$have" = "$want" ]; then echo "SAME	$doc"; continue; fi
  if [ "$have" = absent ]; then echo "SAME	$doc	absent: this script creates it (a rebuild)"; continue; fi
  if [ "$(PROJECT_ROOT="$PROJECT_ROOT" bash "$OWNERS" last-writer "$kind $doc")" = "$KEY" ]; then
    echo "SAME	$doc	this script is its last recorded writer (a re-run)"; continue
  fi
  if [ -n "$NOW_V" ] && [ "$NOW_V" != "$WAS_V" ]; then
    echo "RESTAMP	$doc	re-stamp after mxcli upgrade ($WAS_V → $NOW_V): DESCRIBE text may differ"; RC=1; continue
  fi
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
