#!/usr/bin/env bash
# script-owners.sh — which mdlsource/ scripts create or restate each document.
#
#   bin/script-owners.sh docs   <script.mdl>   one row per document the script creates or restates:
#                                              KIND <tab> Module.Name <tab> line <tab> create|modify|replace
#   bin/script-owners.sh report [project-root] every document owned by more than one script, run order
#   bin/script-owners.sh count  [project-root] "<multi-owner> <documents>" (gate-check.sh reads it)
#   bin/script-owners.sh check  <script.mdl> [project-root]
#                                              one row per co-owner of a document the script restates:
#                                              REVERT / UNCHECKED (exit 1, exec.sh WARNs) or NOTE (exit 0)
#   bin/script-owners.sh record <script.mdl>   exec.sh, after a kept write: last writer of every doc it names
#   bin/script-owners.sh last-writer "<KIND Module.Name>"   that script's key, or nothing
#   bin/script-owners.sh live <KIND> <Module.Name>          one DESCRIBE: present | absent (exit 3: failed)
#
# A document is a microflow, nanoflow, page or snippet named by `create`, `create or modify` or
# `create or replace`. `alter` is not ownership. `check` looks only at what the script RESTATES
# (or modify / or replace): a plain `create` on an existing name is refused by mxcli.
#
# WHY (#269, field 2026-10-05..09, mxcli v0.25.0). Three toolkit-built apps had 99/579, 130/357 and
# 38/159 documents created by more than one script (worst case 5). Re-running an older script (a
# replay, a rebuild, an agent "re-applying slice 2") silently put back what the later scripts
# changed; check, mxbuild and lint stayed green. Nothing recorded which script owns a document.
#
# WHO WINS. `-- supersedes: 05-x.mdl, 07-y.mdl` in the new script, or `-- superseded-by: 12-z.mdl` in
# the old one (basenames or paths). For script S and another owner O of a document S restates:
#   either header says S wins            → nothing
#   O runs before S, no header           → NOTE (not WARN, not in BUILD-LOG), only the first time S
#                                          runs (no ledger row yet): S is the new owner; add the header
#   O runs after S, or O supersedes S    → REVERT if O's write is live: replaying S reverts it
# Run order: path order with digit runs zero-padded per component (2-core before 11-fixes, 9-a
# before 10-b; no `sort -V`, older macOS sort lacks it) and a leading `done-` ignored
# (iterative-build-loop.md renames an executed script done-<name>).
#
# "O's write is live". Neither S nor O has ever run on this machine → S is new: nothing. Else the
# LAST-WRITER LEDGER: last writer is S or a script before S → O's work is not in the model. Else ONE
# DESCRIBE per document (absent → nothing to revert, e.g. a fresh model), at most 5 per check; the
# rest print as UNCHECKED. No ./mxcli → REVERT. The ledger knows only exec.sh's writes: restore-mpr.sh
# appends a RESTORE row and rows before the last one are ignored (DESCRIBE decides again); a
# Studio Pro edit is invisible to it.
#
# LEDGER: <root>/.claude/loop/script-owners/written.tsv, epoch <tab> key <tab> KIND Module.Name
# (key = root-relative path, done- removed), or epoch <tab> RESTORE <tab> <snapshot>. MACHINE-LOCAL,
# NOT COMMITTED: the folder carries its own `*` .gitignore (as app-restart.sh's does). So a fresh
# clone starts with an empty ledger. `record` compacts it to the last row per (script, document)
# plus the last RESTORE row, through a temp file and mv; exec.sh calls it while it holds the
# exec lock.
#
# Lexer: exec.sh's change-class blanking (comments, strings, $$-bodies, bracket depth), with string
# literals allowed to span lines. Golden input is real MDL: mxcli v0.23.0/v0.26.0 DESCRIBE captures,
# the StyleGallery mdlsource tree, skills/agents-examples (tests/wave2/test-restatement-guard.sh).
# *.test.mdl is skipped. mdlsource/ is <root>/mdlsource, else <root>/app/mdlsource (two-tree).
# Happy-path cost (no co-owner): one grep over mdlsource/ for the restated names, the lexer over
# the hits, no mxcli. Producers/consumers: mdlsource/ (every build step) and the ledger (exec.sh
# `record`, restore-mpr.sh) → exec.sh `check`, gate-check.sh `count`. bash 3.2, BSD awk, Git Bash.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

usage() { sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

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
        if (c == "\047") {
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
      if (tolower(s) !~ /^create[ \t]/) next
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

# Run-order key of a root-relative path: done- dropped from the file name, every digit run
# zero-padded to 10 so 2-core < 11-fixes and 9-a < 10-b under a byte sort. Prints "key<TAB>path".
_SO_ORDER='
    function pad(s,    out, d) {
      out = ""
      while (match(s, /[0-9]+/)) { d = substr(s, RSTART, RLENGTH); while (length(d) < 10) d = "0" d
        out = out substr(s, 1, RSTART - 1) d; s = substr(s, RSTART + RLENGTH) }
      return out s
    }
    { n = split($0, a, "/"); sub(/^done-/, "", a[n]); k = pad(a[1]); for (i = 2; i <= n; i++) k = k "/" pad(a[i]); print k "\t" $0 }'

so_docs() { awk -v INDEX=0 "$_SO_AWK" "$1"; }
so_key() { basename "$1" | sed 's/^done-//'; }                          # header-name identity
so_sortkey() { printf '%s/%s\n' "$(dirname "$1")" "$(so_key "$1")"; }   # ledger key
so_before() {  # true when path $1 runs strictly before path $2
  printf '%s\n%s\n' "$1" "$2" | awk "$_SO_ORDER" | awk -F'\t' 'NR == 1 { a = $1 } NR == 2 { exit !(a < $1) }'
}
so_header() {  # $1 = script, $2 = supersedes|superseded-by → one name per line, done- removed
  sed -nE "s/^[[:space:]]*--[[:space:]]*$2:[[:space:]]*(.*)$/\1/p" "$1" 2>/dev/null \
    | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]].*$//' \
    | sed -E 's#.*/##; s/^done-//' | grep -v '^$' || true
}
so_root() {
  if [ -n "${1:-}" ]; then (cd "$1" 2>/dev/null && pwd) || echo "$1"
  elif [ -n "${PROJECT_ROOT:-}" ]; then (cd "$PROJECT_ROOT" 2>/dev/null && pwd) || echo "$PROJECT_ROOT"
  else pwd
  fi
}
so_mdldir() {
  if [ -d "$1/mdlsource" ]; then echo mdlsource
  elif [ -d "$1/app/mdlsource" ]; then echo app/mdlsource
  fi
}
so_scripts() {  # $1 = root [, $2 = fixed-strings file: only scripts containing one] → run order
  local d; d="$(so_mdldir "$1")"; [ -n "$d" ] || return 0
  if [ -n "${2:-}" ]; then ( cd "$1" && grep -rlF -f "$2" "$d" 2>/dev/null )
  else ( cd "$1" && find "$d" -type f -name '*.mdl' 2>/dev/null )
  fi | awk '/\.mdl$/ && !/\.test\.mdl$/' | awk "$_SO_ORDER" | LC_ALL=C sort | cut -f2
}
so_index() {  # $1 = root [, $2 = prefilter] → "KIND Module.Name <tab> script", run order, ONE awk
  local f files=()
  while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done <<EOF
$(so_scripts "$1" "${2:-}")
EOF
  [ "${#files[@]}" -gt 0 ] || return 0
  ( cd "$1" && awk -v INDEX=1 "$_SO_AWK" "${files[@]}" )
}

LEDGER_REL=".claude/loop/script-owners/written.tsv"
so_last_writer() {  # $1 = root, $2 = "KIND Module.Name"; rows before the last RESTORE ignored
  [ -f "$1/$LEDGER_REL" ] || return 0
  awk -F'\t' -v d="$2" '$2 == "RESTORE" { w = "" } $3 == d { w = $2 } END { if (w != "") print w }' "$1/$LEDGER_REL"
}
so_has_run() {  # $1 = root, $2 = ledger key → true when that script has any ledger row
  [ -f "$1/$LEDGER_REL" ] && awk -F'\t' -v k="$2" '$2 == k { f = 1; exit } END { exit !f }' "$1/$LEDGER_REL"
}
so_rel() {  # $1 = script, $2 = root → root-relative path, or "" outside the root
  local abs; abs="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
  case "$abs" in "$2"/*) printf '%s\n' "${abs#"$2"/}" ;; *) echo "" ;; esac
}
# One DESCRIBE through the project's ./mxcli. Not found (captured, mxcli v0.26.0, all four kinds,
# tests/wave2/fixtures/restatement-guard/): exit 1, empty stdout, "Error: <kind> not found: <Doc>"
# on stderr. A parse error or "no describable document" (v0.24.0) is a failed call, never absent.
so_live() {  # $1 = root, $2 = KIND, $3 = Doc
  local out err rc=0 all
  out="$(cd "$1" && PROJECT_ROOT="$1" && . "$HERE/_common.sh" >/dev/null 2>&1 \
         && mx="$(find_project_mxcli)" && mpr="$(find_mpr 2>/dev/null)" \
         && "$mx" -p "$mpr" -c "DESCRIBE $2 $3" 2>&1 </dev/null; echo "rc=$?")"
  rc="${out##*rc=}"; all="${out%rc=*}"
  if [ "$rc" = 0 ]; then echo present; return 0; fi
  if printf '%s\n' "$all" | grep -qF "not found: $3" && ! printf '%s\n' "$all" | grep -qE 'Parse error|no describable document'; then
    echo absent; return 0
  fi
  return 3
}

cmd="${1:-}"
case "$cmd" in
  docs) [ -f "${2:-}" ] || usage; so_docs "$2" ;;
  live) [ $# -eq 3 ] || usage; so_live "$(so_root "")" "$2" "$3"; exit $? ;;
  last-writer) [ -n "${2:-}" ] || usage; so_last_writer "$(so_root "")" "$2" ;;
  report|count)
    ROOT="$(so_root "${2:-}")"
    SUMMARY="$(so_index "$ROOT" | awk -F'\t' 'NF == 2 {
        if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 }
        c[$1]++; s[$1] = s[$1] (c[$1] > 1 ? ", " : "") $2 }
      END { m = 0
        for (i = 1; i <= n; i++) if (c[order[i]] > 1) { m++; printf "  %s — %d scripts: %s\n", order[i], c[order[i]], s[order[i]] }
        printf "SUMMARY\t%d\t%d\n", m, n }')"
    M="$(printf '%s\n' "$SUMMARY" | awk -F'\t' '$1 == "SUMMARY" { print $2 }')"
    N="$(printf '%s\n' "$SUMMARY" | awk -F'\t' '$1 == "SUMMARY" { print $3 }')"
    if [ "$cmd" = count ]; then echo "${M:-0} ${N:-0}"; exit 0; fi
    [ -n "$(so_mdldir "$ROOT")" ] || { echo "no mdlsource/ under $ROOT — nothing to report"; exit 0; }
    printf '%s\n' "$SUMMARY" | grep -v '^SUMMARY' || true
    echo "multi-owner: ${M:-0} of ${N:-0} document(s) created by more than one mdlsource/ script"
    [ "${M:-0}" -gt 0 ] && echo "  → edit the owning script, use alter, or mark the winner: -- supersedes: <older script> (skills/learned-mdl-preflight.md STOP 21)"
    exit 0
    ;;
  record)
    [ -f "${2:-}" ] || usage
    ROOT="$(so_root "")"; REL="$(so_rel "$2" "$ROOT")"
    [ -n "$REL" ] || exit 0          # a scratch script outside the project owns nothing
    LD="$(dirname "$ROOT/$LEDGER_REL")"
    mkdir -p "$LD" 2>/dev/null || exit 0
    [ -f "$LD/.gitignore" ] || printf '*\n' > "$LD/.gitignore"
    so_docs "$2" | awk -F'\t' -v k="$(so_sortkey "$REL")" -v t="$(date +%s)" '!s[$1 " " $2]++ { print t "\t" k "\t" $1 " " $2 }' >> "$ROOT/$LEDGER_REL"
    # Compact: the last row per (script, document) and the last RESTORE row, order kept.
    T="$(mktemp "$LD/.written.XXXXXX")" || exit 0
    awk -F'\t' '{ k = ($2 == "RESTORE") ? "RESTORE" : $2 "\t" $3; last[k] = NR; line[NR] = $0; key[NR] = k }
      END { for (i = 1; i <= NR; i++) if (last[key[i]] == i) print line[i] }' "$ROOT/$LEDGER_REL" > "$T" \
      && mv "$T" "$ROOT/$LEDGER_REL" || rm -f "$T"
    exit 0
    ;;
  check)
    [ -f "${2:-}" ] || usage
    S="$2"; ROOT="$(so_root "${3:-}")"
    S_REL="$(so_rel "$S" "$ROOT")"; S_KEY="$(so_key "$S")"
    S_RAN=0; [ -n "$S_REL" ] && so_has_run "$ROOT" "$(so_sortkey "$S_REL")" && S_RAN=1
    DOCS="$(so_docs "$S" | awk -F'\t' '$4 != "create" { print $1 " " $2 }' | LC_ALL=C sort -u)"
    [ -n "$DOCS" ] || exit 0
    # Only scripts containing a restated document's bare name are lexed (quoted or not, it is in
    # the text): 600 scripts cost ~350 ms through the lexer, the grep a few.
    PAT="$(mktemp "${TMPDIR:-/tmp}/so-pat.XXXXXX")" || exit 2
    printf '%s\n' "$DOCS" | sed 's/.*\.//' > "$PAT"
    PAIRS="$(so_index "$ROOT" "$PAT" | DOCS="$DOCS" awk -F'\t' -v me="$S_REL" '
      BEGIN { n = split(ENVIRON["DOCS"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") w[a[i]] = 1 }
      ($1 in w) && $2 != me')"
    rm -f "$PAT"
    [ -n "$PAIRS" ] || exit 0
    MY_SUP="$(so_header "$S" supersedes)"; MY_SUPBY="$(so_header "$S" superseded-by)"
    OUT="$(NL_SEEN=""; NL_DESC=0
    # rc 0: O's work on doc $1 is not in the model; 1: it is (or unknown); 2: DESCRIBE cap reached.
    not_live() {  # $1 = "KIND Module.Name", $2 = O
      local w live rc=1
      if [ "$S_RAN" = 0 ] && ! so_has_run "$ROOT" "$(so_sortkey "$2")"; then return 0; fi   # S is new
      case "$NL_SEEN" in *"|$1="*) rc="${NL_SEEN#*"|$1="}"; return "${rc%%|*}" ;; esac
      w="$(so_last_writer "$ROOT" "$1")"
      if [ -n "$w" ] && [ -n "$S_REL" ] && { [ "$w" = "$(so_sortkey "$S_REL")" ] || so_before "$w" "$S_REL"; }; then
        rc=0
      elif [ "$NL_DESC" -ge 5 ]; then
        return 2
      else
        NL_DESC=$((NL_DESC + 1))
        live="$(so_live "$ROOT" "${1%% *}" "${1#* }")" && [ "$live" = absent ] && rc=0
      fi
      NL_SEEN="$NL_SEEN|$1=$rc|"
      return "$rc"
    }
    revert() {  # $1 doc $2 O $3 message
      local r=0; not_live "$1" "$2" || r=$?
      case "$r" in
        0) ;;
        2) printf 'UNCHECKED\t%s\t%s\tCONFLICT (not checked: 5 DESCRIBE calls per exec) — %s\n' "$1" "$2" "$3" ;;
        *) printf 'REVERT\t%s\t%s\t%s\n' "$1" "$2" "$3" ;;
      esac
    }
    while IFS='	' read -r d o; do
      [ -n "$o" ] || continue
      ob="$(so_key "$o")"
      if printf '%s\n' "$MY_SUP" | grep -qxF "$ob" || so_header "$ROOT/$o" superseded-by | grep -qxF "$S_KEY"; then continue; fi
      if printf '%s\n' "$MY_SUPBY" | grep -qxF "$ob" || so_header "$ROOT/$o" supersedes | grep -qxF "$S_KEY"; then
        revert "$d" "$o" "superseded: $o supersedes this script — replaying it reverts $o"
      elif [ -z "$S_REL" ]; then
        printf 'REVERT\t%s\t%s\towned by %s; this script is outside the project\n' "$d" "$o" "$o"
      elif so_before "$o" "$S_REL"; then
        [ "$S_RAN" = 0 ] && printf "NOTE\t%s\t%s\tolder owner %s — the new owner should say '-- supersedes: %s'\n" "$d" "$o" "$o" "$ob"
      else
        revert "$d" "$o" "newer owner $o — replaying this script reverts it"
      fi
    done <<EOF
$PAIRS
EOF
)"
    [ -n "$OUT" ] || exit 0
    printf '%s\n' "$OUT"
    printf '%s\n' "$OUT" | grep -qE '^(REVERT|UNCHECKED)	' && exit 1
    exit 0
    ;;
  *) usage ;;
esac
