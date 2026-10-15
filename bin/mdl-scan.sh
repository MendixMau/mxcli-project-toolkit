#!/usr/bin/env bash
# mdl-scan.sh — flag an MDL script that contains a STOP-row pattern, before anyone applies it.
#
#   bin/mdl-scan.sh <script.mdl> [-p <app.mpr>]
#
# One rule per row of skills/learned-mdl-preflight.md's STOP table that a text pattern in the
# script identifies (issue #349). The rules are data: bin/lib/mdl-scan-rules.tsv, whose header
# documents the columns and the three rule kinds. Rows that need model state or judgement are
# not here; they stay prose in the skill, unmarked.
#
# Output: one line per hit, `STOP-<n> <file>:<line> <message> → <fix> [warn|block]`.
# Exit:   0 clean · 1 at least one hit of a `block` rule · 3 hits, all of `warn` rules ·
#         2 usage error (no script, unreadable file, bad flag, rules file missing).
# Severity is a column of the rules file; its header says when a rule may go to `block`.
# exec.sh refuses on 1 and prints the hits as warnings on 3.
#
# -p is accepted and checked, so a caller can pass the model the same way it passes it to
# `mxcli check`. No current rule reads it: every row that needs model state stayed prose
# (the PR for #349 lists them). A future rule that uses it must stay read-only.
#
# WHY. The STOP table is prose an agent reads, or skips. Every rule here was a script that
# passed `mxcli check`, cost a full apply, and failed only at mxbuild or on Studio Pro open
# (bug ids in the rules file). A text scan costs milliseconds; a failed apply costs 22-65 s
# plus the restore (iterative-build-loop.md, "Gate cost").
#
# HOW IT READS A SCRIPT. Comments (`--`, `//`, `/* */`) and `$$ ... $$` bodies are removed
# and the line is lowercased. `line` rules see string literals (STOP-16 lives inside one);
# `customcontent` rules and all bracket counting see the line with literals blanked. A
# customContent column's body is known by `{ }` depth, not indentation; a column with no body
# is forgotten at the `)` that closes its header's scope or at the next `}`. A ContentParams
# list ends at its matching `]` by depth, not at the last `]` on the line. It is a line
# scanner, not a parser: a one-line column whose body opens and holds the conditional on the
# header line itself is not seen as inside the column.
#
# Golden input: the bad MDL captured in bug-logs/mxcli-bugs.md for each rule, and the
# StyleGallery example (applied, 0 errors in mx check) as the clean corpus —
# tests/wave2/test-mdl-scan.sh, tests/wave2/bench-mdl-scan.sh. Plain bash 3.2 + POSIX awk.
set -u

usage() { echo "usage: bin/mdl-scan.sh <script.mdl> [-p <app.mpr>]" >&2; exit 2; }

SCRIPT=""; MPR=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) [ $# -ge 2 ] || usage; MPR="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    -*) echo "mdl-scan: unknown option '$1'" >&2; usage ;;
    *) [ -z "$SCRIPT" ] || usage; SCRIPT="$1"; shift ;;
  esac
done
[ -n "$SCRIPT" ] || usage
[ -f "$SCRIPT" ] && [ -r "$SCRIPT" ] || { echo "mdl-scan: cannot read script: $SCRIPT" >&2; exit 2; }
if [ -n "$MPR" ] && [ ! -f "$MPR" ]; then echo "mdl-scan: -p: no such model: $MPR" >&2; exit 2; fi

RULES="${MDL_SCAN_RULES:-$(cd "$(dirname "$0")" && pwd)/lib/mdl-scan-rules.tsv}"
[ -r "$RULES" ] || { echo "mdl-scan: rules file missing: $RULES" >&2; exit 2; }

awk -F'\t' -v file="$SCRIPT" '
  FNR == NR {                                   # the rules file
    if ($0 ~ /^#/ || NF < 6) next
    n++; rid[n] = $1; rkind[n] = $2; rsev[n] = $3; rpat[n] = $4; rmsg[n] = $5; rfix[n] = $6
    next
  }
  function hit(i, ln) {
    printf "%s %s:%d %s → %s [%s]\n", rid[i], file, ln, rmsg[i], rfix[i], rsev[i]
    hits++; if (rsev[i] == "block") blocks++
  }
  # strip(line): sets code (comments and $$-bodies removed, strings kept) and bare (strings
  # blanked too). Same length, so an offset found in one cuts the other. inblock / indollar
  # carry across lines.
  function strip(line,    m, i, c, c2, instr) {
    code = ""; bare = ""; m = length(line); i = 1; instr = 0
    while (i <= m) {
      c = substr(line, i, 1); c2 = substr(line, i, 2)
      if (inblock)  { if (c2 == "*/") { inblock = 0; i += 2 } else i++; continue }
      if (indollar) { if (c2 == "$$") { indollar = 0; i += 2 } else i++; continue }
      if (instr) {
        code = code c; bare = bare " "
        if (c == "\047") instr = 0
        i++; continue
      }
      if (c2 == "/*") { inblock = 1; i += 2; continue }
      if (c2 == "$$") { indollar = 1; i += 2; continue }
      if (c2 == "--" || c2 == "//") break
      if (c == "\047") instr = 1
      code = code c; bare = bare (instr ? " " : c)
      i++
    }
    code = tolower(code); bare = tolower(bare)
  }
  # A ContentParams value is fine when it is a quoted literal, or a bare (optionally
  # double-quoted) identifier, or an unquoted identifier path. Anything else is an expression.
  function bad_value(v) {
    sub(/^[[:space:]]+/, "", v); sub(/[[:space:],]+$/, "", v)
    if (v ~ /^\047([^\047]|\047\047)*\047$/) return 0
    if (v ~ /^"?[a-z_][a-z0-9_]*"?$/) return 0
    if (v ~ /^[a-z_][a-z0-9_.]*(\/[a-z_][a-z0-9_.]*)*$/) return 0
    return 1
  }
  function check_params(text, ln, i,    rest, v) {
    rest = text
    while (match(rest, /\{[0-9]+\}[[:space:]]*=/)) {
      rest = substr(rest, RSTART + RLENGTH)
      if (match(rest, /,[[:space:]]*\{[0-9]+\}[[:space:]]*=/)) v = substr(rest, 1, RSTART - 1)
      else v = rest
      if (bad_value(v)) { hit(i, ln); return }
    }
  }
  # cp_feed(c, b): add one stretch of an open ContentParams list (code c, bare b) to cp_text,
  # counting [ ] in b. Returns 1 when the list closes, cutting c at its matching ].
  function cp_feed(c, b,    k, m, ch) {
    m = length(b)
    for (k = 1; k <= m; k++) {
      ch = substr(b, k, 1)
      if (ch == "[") cp_depth++
      else if (ch == "]" && --cp_depth == 0) { cp_text = cp_text " " substr(c, 1, k - 1); return 1 }
    }
    cp_text = cp_text " " c; return 0
  }
  {
    strip($0)
    incc = (ccn > 0)                            # inside a customContent column body?
    for (i = 1; i <= n; i++) {
      if (rkind[i] == "line" && code ~ rpat[i]) hit(i, FNR)
      else if (rkind[i] == "customcontent" && incc && bare ~ rpat[i]) hit(i, FNR)
      else if (rkind[i] == "contentparams") {
        if (cp_open) {                          # a ContentParams list still open from above
          if (cp_feed(code, bare)) { check_params(cp_text, cp_line, i); cp_open = 0 }
        } else if (match(bare, /contentparams[[:space:]]*:[[:space:]]*\[/)) {
          k0 = RSTART + RLENGTH; cp_text = ""; cp_line = FNR; cp_depth = 1
          if (cp_feed(substr(code, k0), substr(bare, k0))) check_params(cp_text, cp_line, i)
          else cp_open = 1
        }
      }
    }
    if (bare ~ /^[[:space:]]*column[[:space:]]/) { pending = 0; colbase = pdepth }
    if (bare ~ /showcontentas[[:space:]]*:[[:space:]]*customcontent/) pending = 1
    m = length(bare)
    for (j = 1; j <= m; j++) {
      c = substr(bare, j, 1)
      if (c == "(") pdepth++
      else if (c == ")") { pdepth--; if (pending && pdepth < colbase) pending = 0 }  # header scope ended, no body
      else if (c == "{") { depth++; if (pending) { cc[++ccn] = depth; pending = 0 } }
      else if (c == "}") { pending = 0; if (ccn > 0 && cc[ccn] == depth) ccn--; depth-- }
    }
  }
  END { exit (blocks > 0 ? 1 : (hits > 0 ? 3 : 0)) }
' "$RULES" "$SCRIPT"
