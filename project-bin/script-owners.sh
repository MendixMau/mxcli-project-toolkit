#!/usr/bin/env bash
# script-owners.sh — which mdlsource/ scripts create or restate each document.
#
#   bin/script-owners.sh docs   <script.mdl>   one row per document the script creates or restates:
#                                              KIND <tab> Module.Name <tab> line <tab> create|modify|replace
#   bin/script-owners.sh report [project-root] every document owned by more than one script, with
#                                              its scripts in run order, then a summary line
#   bin/script-owners.sh count  [project-root] "<multi-owner> <documents>" (gate-check.sh reads it)
#   bin/script-owners.sh check  <script.mdl> [project-root]
#                                              exit 1 when the script restates a document another
#                                              script also owns and no supersedes header settles
#                                              who wins; one CONFLICT row each. exec.sh warns on it
#   bin/script-owners.sh record <script.mdl>   exec.sh, after a kept write: this script is now the
#                                              last writer of every document it names
#   bin/script-owners.sh last-writer "<KIND Module.Name>"   that script's key, or nothing
#
# A document is a microflow, nanoflow, page or snippet named by a `create`, `create or modify`
# or `create or replace` statement. `alter page` / `alter snippet` is NOT ownership: it edits in
# place, which is the write this script steers people towards. `check` only looks at the
# documents the script RESTATES (or modify / or replace): a plain `create` on an existing name
# is refused by mxcli, so it cannot revert anything.
#
# WHY (#269, field evidence 2026-10-05..09, mxcli v0.25.0). Three toolkit-built apps counted
# 99 of 579, 130 of 357 and 38 of 159 documents created by more than one script, worst case a
# published-API microflow restated in 5 scripts. Re-running an older script (a replay, a rebuild
# from a fresh .mpr, an agent "re-applying slice 2") silently puts back every change the later
# scripts made: the older body is valid MDL, so check, mxbuild and lint all stay green. Nothing
# recorded which script owns a document. #261 is the same loss inside one batch (a script
# drafted from a DESCRIBE taken before an earlier script ran); describe-baseline.sh covers that.
#
# HOW A SCRIPT SAYS WHO WINS. Header comments, anywhere in the file, basenames or paths:
#   -- supersedes: 05-orders.mdl, 07-orders-fix.mdl    (in the NEW script: it owns these docs now)
#   -- superseded-by: 12-orders-v2.mdl                 (in the OLD script: do not replay me)
# `check` on script S, for each document S restates that another script O also owns:
#   S supersedes O (either header says so)  → fine, S is the owner
#   O supersedes S                          → CONFLICT if O's write is live: replaying S reverts it
#   neither header, O runs before S         → CONFLICT: a new restatement needs a supersedes header
#   neither header, O runs after S          → CONFLICT if O's write is live: S is being replayed
# Run order is the path order under mdlsource/ (LC_ALL=C sort) with a leading `done-` taken off
# the file name: iterative-build-loop.md renames an executed script `done-<name>`, and a raw sort
# put done-05-x.mdl after 09-y.mdl. Header names match the same way.
#
# "O's write is live" — so a rebuild that replays scripts in run order stays quiet (warning there
# trains people to ignore the warning). First the last-writer ledger: exec.sh runs `record` after
# every kept write, so when the last recorded writer of the document is S itself or a script
# before S, O's work is not in the model and nothing is reverted. NO mxcli call for that. Only
# when the ledger cannot settle it does this ask the model, once per conflicting document
# (describe-baseline.sh live, one DESCRIBE): absent → nothing to revert (a fresh model). With no
# ./mxcli it stays a CONFLICT. The ledger knows only what exec.sh wrote: a Studio Pro edit or a
# restore-mpr.sh does not move it, so after a restore treat a quiet check with suspicion.
# Cost on the happy path (no co-owner): one grep over mdlsource/ for the restated names, the
# lexer over the scripts it finds, no mxcli at all.
#
# Not a parser: the same comment/string/$$-body blanking and bracket depth as exec.sh's change
# class lexer, then only statement heads at depth 0 are read, so a caption saying "create page"
# or a widget line never counts. Unlike that lexer, a string literal may span lines (a real
# `find($Clean, '<newline>')` in skills/agents-examples/single-call.example.mdl hid the next
# microflow from a per-line lexer). Golden input is real MDL: mxcli v0.23.0 and v0.26.0 DESCRIBE
# captures, the shipped StyleGallery mdlsource tree and skills/agents-examples/*.mdl
# (tests/wave2/test-restatement-guard.sh). `*.test.mdl` files are skipped: they are microflow
# tests, not build steps. mdlsource/ is <root>/mdlsource, else <root>/app/mdlsource (two-tree).
#
# Producer for every consumer (CLAUDE.md "Shipping an instrument" rule 5): the input is the
# project's own mdlsource/, written by every build step; the ledger
# (.claude/loop/script-owners/written.tsv: epoch <tab> key <tab> KIND Module.Name) is written by
# exec.sh's `record` call after every kept write. Consumers: exec.sh (check, every MDL write),
# gate-check.sh (count), describe-baseline.sh (last-writer). Never edits a script.
# Plain bash + awk: bash 3.2, BSD awk, Git Bash.
set -u

usage() {
  sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

_SO_AWK='
    function lex_line(line,    n, i, c, c2, tmp, o, cl) {
      clean = ""; n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1); c2 = substr(line, i, 2)
        if (instr)     { if (c == "\047") instr = 0; i++; continue }
        if (inblock)   { if (c2 == "*/") { inblock = 0; i += 2 } else i++; continue }
        if (indollar)  { if (c2 == "$$") { indollar = 0; i += 2 } else i++; continue }
        if (c2 == "/*") { inblock = 1; i += 2; continue }
        if (c2 == "$$") { indollar = 1; i += 2; continue }
        if (c2 == "--" || c2 == "//") break
        if (c == "\047") {                        # a literal may span lines: find(\$s, newline)
          i++; while (i <= n && substr(line, i, 1) != "\047") i++
          if (i > n) instr = 1
          i++; clean = clean "\047\047"; continue
        }
        if (c == "\"") { i++; continue }
        clean = clean c; i++
      }
      start_depth = depth
      tmp = clean; o = gsub(/[({]/, "", tmp); tmp = clean; cl = gsub(/[)}]/, "", tmp)
      depth += o - cl; if (depth < 0) depth = 0
    }
    FNR == 1 { depth = 0; instr = 0; inblock = 0; indollar = 0 }
    {
      sub(/\r$/, "")
      lex_line($0)
      if (start_depth != 0) next
      s = clean; sub(/^[ \t]+/, "", s)
      low = tolower(s)
      if (low !~ /^create[ \t]/) next
      rest = substr(s, 7); sub(/^[ \t]+/, "", rest)
      verb = "create"
      if (tolower(rest) ~ /^or[ \t]+(modify|replace)[ \t]/) {
        sub(/^[Oo][Rr][ \t]+/, "", rest)
        verb = tolower(rest); sub(/[ \t].*$/, "", verb)
        sub(/^[A-Za-z]+[ \t]+/, "", rest)
      }
      kind = tolower(rest); sub(/[ \t(].*$/, "", kind)
      if (kind != "microflow" && kind != "nanoflow" && kind != "page" && kind != "snippet") next
      sub(/^[A-Za-z]+[ \t]+/, "", rest)
      if (!match(rest, /^[A-Za-z_][A-Za-z0-9_]*[ \t]*\.[ \t]*[A-Za-z_][A-Za-z0-9_]*/)) next
      name = substr(rest, 1, RLENGTH); gsub(/[ \t]/, "", name)
      if (INDEX) { k = toupper(kind) " " name; if (!((FILENAME, k) in seen)) { seen[FILENAME, k] = 1; print k "\t" FILENAME } }
      else printf "%s\t%s\t%d\t%s\n", toupper(kind), name, FNR, verb
    }'

so_docs() { awk -v INDEX=0 "$_SO_AWK" "$1"; }

# A script's identity: its file name without a leading done- (the executed-script rename).
so_key() { basename "$1" | sed 's/^done-//'; }
# Sort key and ledger key: the root-relative path with that prefix removed from the file name.
so_sortkey() { printf '%s/%s\n' "$(dirname "$1")" "$(so_key "$1")"; }
# True when path $1 runs before path $2.
so_before() { [ "$(printf '%s\n%s\n' "$(so_sortkey "$1")" "$(so_sortkey "$2")" | LC_ALL=C sort | head -1)" = "$(so_sortkey "$1")" ]; }

# Header values: `-- supersedes: a.mdl, b.mdl` → one name per line, done- taken off.
so_header() {  # $1 = script, $2 = supersedes|superseded-by
  sed -nE "s/^[[:space:]]*--[[:space:]]*$2:[[:space:]]*(.*)$/\1/p" "$1" 2>/dev/null \
    | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]].*$//' \
    | sed -E 's#.*/##; s/^done-//' | grep -v '^$' || true
}

so_root() {  # $1 = optional project root
  if [ -n "${1:-}" ]; then (cd "$1" 2>/dev/null && pwd) || echo "$1"
  elif [ -n "${PROJECT_ROOT:-}" ]; then (cd "$PROJECT_ROOT" 2>/dev/null && pwd) || echo "$PROJECT_ROOT"
  else pwd
  fi
}
so_mdldir() {  # $1 = root → mdlsource dir relative to it (single tree, else two-tree app/)
  if [ -d "$1/mdlsource" ]; then echo mdlsource
  elif [ -d "$1/app/mdlsource" ]; then echo app/mdlsource
  fi
}

so_scripts() {  # $1 = root [, $2 = file of fixed strings] → build scripts under mdlsource/, run
  # order, root-relative. With $2, only the scripts that contain one of those strings (a grep
  # prefilter, so `check` lexes the few files that can name its documents, not all of them).
  local d; d="$(so_mdldir "$1")"; [ -n "$d" ] || return 0
  if [ -n "${2:-}" ]; then ( cd "$1" && grep -rlF -f "$2" "$d" 2>/dev/null )
  else ( cd "$1" && find "$d" -type f -name '*.mdl' 2>/dev/null )
  fi | awk '/\.mdl$/ && !/\.test\.mdl$/ { k = $0; n = split(k, a, "/"); sub(/^done-/, "", a[n]); k = a[1]; for (i = 2; i <= n; i++) k = k "/" a[i]; print k "\t" $0 }' \
    | LC_ALL=C sort | cut -f2
}

so_index() {  # $1 = root [, $2 = prefilter] → "KIND Module.Name <tab> script" per owner, run order. ONE awk.
  local f files=()
  while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done <<EOF
$(so_scripts "$1" "${2:-}")
EOF
  [ "${#files[@]}" -gt 0 ] || return 0
  ( cd "$1" && awk -v INDEX=1 "$_SO_AWK" "${files[@]}" )
}

LEDGER_REL=".claude/loop/script-owners/written.tsv"
so_last_writer() {  # $1 = root, $2 = "KIND Module.Name" → key of its last recorded writer
  [ -f "$1/$LEDGER_REL" ] || return 0
  awk -F'\t' -v d="$2" '$3 == d { w = $2 } END { if (w != "") print w }' "$1/$LEDGER_REL"
}
so_rel() {  # $1 = script, $2 = root → root-relative path, or "" when outside the root
  local abs; abs="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
  case "$abs" in "$2"/*) printf '%s\n' "${abs#"$2"/}" ;; *) echo "" ;; esac
}

cmd="${1:-}"
case "$cmd" in
  docs)
    [ -f "${2:-}" ] || usage
    so_docs "$2"
    ;;
  report|count)
    ROOT="$(so_root "${2:-}")"
    SUMMARY="$(so_index "$ROOT" | awk -F'\t' 'NF == 2 {
        if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 }
        c[$1]++; s[$1] = s[$1] (c[$1] > 1 ? ", " : "") $2
      }
      END {
        m = 0
        for (i = 1; i <= n; i++) if (c[order[i]] > 1) { m++; printf "  %s — %d scripts: %s\n", order[i], c[order[i]], s[order[i]] }
        printf "SUMMARY\t%d\t%d\n", m, n
      }')"
    M="$(printf '%s\n' "$SUMMARY" | awk -F'\t' '$1 == "SUMMARY" { print $2 }')"
    N="$(printf '%s\n' "$SUMMARY" | awk -F'\t' '$1 == "SUMMARY" { print $3 }')"
    if [ "$cmd" = count ]; then echo "${M:-0} ${N:-0}"; exit 0; fi
    if [ -z "$(so_mdldir "$ROOT")" ]; then echo "no mdlsource/ under $ROOT — nothing to report"; exit 0; fi
    printf '%s\n' "$SUMMARY" | grep -v '^SUMMARY' || true
    echo "multi-owner: ${M:-0} of ${N:-0} document(s) created by more than one mdlsource/ script"
    [ "${M:-0}" -gt 0 ] && echo "  → edit the owning script, use alter, or mark the winner: -- supersedes: <older script> (skills/learned-mdl-preflight.md STOP 33)"
    exit 0
    ;;
  record)
    [ -f "${2:-}" ] || usage
    ROOT="$(so_root "")"
    REL="$(so_rel "$2" "$ROOT")"
    [ -n "$REL" ] || exit 0          # a scratch script outside the project owns nothing
    KEY="$(so_sortkey "$REL")"
    mkdir -p "$(dirname "$ROOT/$LEDGER_REL")" 2>/dev/null || exit 0
    so_docs "$2" | awk -F'\t' -v k="$KEY" -v t="$(date +%s)" '!s[$1 " " $2]++ { print t "\t" k "\t" $1 " " $2 }' >> "$ROOT/$LEDGER_REL"
    exit 0
    ;;
  last-writer)
    [ -n "${2:-}" ] || usage
    so_last_writer "$(so_root "")" "$2"
    exit 0
    ;;
  check)
    [ -f "${2:-}" ] || usage
    S="$2"
    ROOT="$(so_root "${3:-}")"
    S_REL="$(so_rel "$S" "$ROOT")"   # so the script is not its own co-owner
    S_KEY="$(so_key "$S")"
    DBL="$(dirname "$0")/describe-baseline.sh"
    # 0 when O's work on doc $1 ("KIND Module.Name") is not in the model, so replaying S reverts
    # nothing. Ledger first (no mxcli); one DESCRIBE only when the ledger cannot settle it.
    NL_SEEN=""   # "|doc=rc|" per document already answered: one DESCRIBE per document at most
    not_live() {
      local w live rc=1
      case "$NL_SEEN" in *"|$1="*) rc="${NL_SEEN#*"|$1="}"; return "${rc%%|*}" ;; esac
      w="$(so_last_writer "$ROOT" "$1")"
      if [ -n "$w" ] && [ -n "$S_REL" ] && { [ "$w" = "$(so_sortkey "$S_REL")" ] || so_before "$w" "$S_REL"; }; then
        rc=0
      elif [ -f "$DBL" ] && live="$(PROJECT_ROOT="$ROOT" bash "$DBL" live "${1%% *}" "${1#* }" 2>/dev/null)" && [ "$live" = absent ]; then
        rc=0
      fi
      NL_SEEN="$NL_SEEN|$1=$rc|"
      return "$rc"
    }
    DOCS="$(so_docs "$S" | awk -F'\t' '$4 != "create" { print $1 " " $2 }' | LC_ALL=C sort -u)"
    [ -n "$DOCS" ] || exit 0
    # Every (document, other owner) pair in one pass; on the happy path this is empty. Only the
    # scripts that contain a restated document's bare name (quoted or not, it is in the text) are
    # lexed: 600 scripts cost 350 ms through the lexer, a grep over them a few.
    PAT="$(mktemp "${TMPDIR:-/tmp}/so-pat.XXXXXX")" || exit 2
    printf '%s\n' "$DOCS" | sed 's/.*\.//' > "$PAT"
    PAIRS="$(so_index "$ROOT" "$PAT" | DOCS="$DOCS" awk -F'\t' -v me="$S_REL" '
      BEGIN { n = split(ENVIRON["DOCS"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") w[a[i]] = 1 }
      ($1 in w) && $2 != me')"
    rm -f "$PAT"
    [ -n "$PAIRS" ] || exit 0
    MY_SUP="$(so_header "$S" supersedes)"
    MY_SUPBY="$(so_header "$S" superseded-by)"
    OUT="$(while IFS='	' read -r d o; do
      [ -n "$o" ] || continue
      ob="$(so_key "$o")"
      if printf '%s\n' "$MY_SUP" | grep -qxF "$ob" || so_header "$ROOT/$o" superseded-by | grep -qxF "$S_KEY"; then
        continue
      fi
      if printf '%s\n' "$MY_SUPBY" | grep -qxF "$ob" || so_header "$ROOT/$o" supersedes | grep -qxF "$S_KEY"; then
        not_live "$d" || echo "CONFLICT	$d	$o	superseded: $o supersedes this script — replaying it reverts $o"
      elif [ -z "$S_REL" ]; then
        echo "CONFLICT	$d	$o	owned by $o; this script is outside the project"
      elif so_before "$o" "$S_REL"; then
        echo "CONFLICT	$d	$o	older owner $o — a new restatement needs '-- supersedes: $ob'"
      else
        not_live "$d" || echo "CONFLICT	$d	$o	newer owner $o — replaying this script reverts it"
      fi
    done <<EOF
$PAIRS
EOF
)"
    [ -n "$OUT" ] || exit 0
    printf '%s\n' "$OUT"
    exit 1
    ;;
  *) usage ;;
esac
