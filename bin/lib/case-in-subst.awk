# case-in-subst.awk — used by bin/check-portability.sh (rule: case pattern inside $(...)).
#
# Prints the line number of every `case` pattern written WITHOUT the POSIX leading `(` while
# that case sits inside a $( ... ) command substitution. bash 3.2 (macOS /bin/bash) reads the
# pattern's unmatched `)` as the end of the substitution; `bash -n` does not see it because 3.2
# parses the substitution only when it runs (#552 script-owners.sh, #763 marketplace-check.sh).
#
# A small shell scanner, not a parser: it tracks a stack of contexts — $( ) "S", ( ) "P",
# "..." "D", ${ } "B", $(( )) / (( )) "A", case "C" (subject -> pattern -> body) — skips
# '...' (also across lines), comments and heredoc bodies, and reports a pattern-closing `)`
# when no leading `(` opened the pattern and an "S" is anywhere below the case on the stack.
# Known blind spots (false negatives, never false positives on the tree it shipped against):
# backtick substitutions and <( ) process substitutions are not tracked as "S"; ${...} bodies
# are opaque, so a $( ) inside one is not seen.
{
  line = $0
  if (hd != "") {                      # inside a heredoc body: skip to its terminator
    t = line; if (hdstrip) sub(/^\t+/, "", t)
    if (t == hd) hd = ""
    next
  }
  n = length(line); i = 1; pend = ""; pendstrip = 0
  if (sq) { j = index(line, "'"); if (j == 0) next; i = j + 1; sq = 0 }   # multi-line '...'
  while (i <= n) {
    c = substr(line, i, 1); c2 = substr(line, i, 2); c3 = substr(line, i, 3)
    top = (sp > 0) ? st[sp] : ""
    prev = (i > 1) ? substr(line, i - 1, 1) : " "
    if (top == "B") {                  # ${ ... }: nesting only, everything else is opaque
      if (c2 == "${") { st[++sp] = "B"; i += 2; continue }
      if (c == "}") { sp--; i++; continue }
      if (c == "\\") { i += 2; continue }
      i++; continue
    }
    if (c == "\\") { i += 2; continue }
    if (top == "D") {                  # inside "...": only $( ${ $(( and the closing quote count
      if (c == "\"") { sp--; i++; continue }
      if (c3 == "$((") { st[++sp] = "A"; i += 3; continue }
      if (c2 == "$(") { st[++sp] = "S"; i += 2; continue }
      if (c2 == "${") { st[++sp] = "B"; i += 2; continue }
      i++; continue
    }
    if (top == "A") {                  # arithmetic: parens nest, no heredocs, no words
      if (c2 == "))") { sp--; i += 2; continue }
      if (c == "(") { st[++sp] = "a"; i++; continue }
      i++; continue
    }
    if (top == "a") {
      if (c == "(") { st[++sp] = "a"; i++; continue }
      if (c == ")") { sp--; i++; continue }
      i++; continue
    }
    # ---- code context (top is "", S, P, or C) ----
    if (c == "'") { j = index(substr(line, i + 1), "'"); if (j == 0) { i = n + 1; sq = 1; break } i += j + 1; continue }
    if (c == "#" && (prev ~ /[ \t;|&(]/ || i == 1)) break
    if (c == "\"") { st[++sp] = "D"; i++; continue }
    if (c3 == "$((") { st[++sp] = "A"; i += 3; continue }
    if (c2 == "((" && (prev ~ /[ \t;|&(]/ || i == 1)) { st[++sp] = "A"; i += 2; continue }
    if (c2 == "$(") { st[++sp] = "S"; i += 2; continue }
    if (c2 == "${") { st[++sp] = "B"; i += 2; continue }
    if (c3 == "<<<") { i += 3; continue }
    if (c2 == "<<") {
      rest = substr(line, i + 2); strip = 0
      if (substr(rest, 1, 1) == "-") { strip = 1; rest = substr(rest, 2) }
      sub(/^[ \t]*/, "", rest); gsub(/["'\\]/, "", rest)
      if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*/)) { pend = substr(rest, 1, RLENGTH); pendstrip = strip }
      i += 2; continue
    }
    # words: case / in / esac
    if (c ~ /[a-z]/ && (i == 1 || prev ~ /[ \t;|&()]/)) {
      w = substr(line, i); match(w, /^[A-Za-z0-9_]+/); w = substr(w, 1, RLENGTH)
      after = substr(line, i + length(w), 1)
      isword = (after == "" || after ~ /[ \t;|&()]/)
      if (isword && top == "C" && cs[sp] == "pat" && !started[sp] && w == "esac") { sp--; i += 4; continue }
      if (isword && top == "C" && cs[sp] == "body" && w == "esac") { sp--; i += 4; continue }
      if (isword && top == "C" && cs[sp] == "subj" && w == "in") { cs[sp] = "pat"; started[sp] = 0; lead[sp] = 0; i += 2; continue }
      if (isword && w == "case" && !(top == "C" && cs[sp] == "pat")) { st[++sp] = "C"; cs[sp] = "subj"; i += 4; continue }
      if (top == "C" && cs[sp] == "pat") started[sp] = 1
      i += length(w); continue
    }
    if (top == "C" && cs[sp] == "pat") {
      if (c ~ /[ \t]/) { i++; continue }
      if (c == "(" && !started[sp]) { started[sp] = 1; lead[sp] = 1; i++; continue }
      if (c == ")") {
        if (!lead[sp]) { for (k = sp - 1; k > 0; k--) if (st[k] == "S") { print NR; break } }
        cs[sp] = "body"; i++; continue
      }
      started[sp] = 1
    }
    if (top == "C" && cs[sp] == "body" && (c2 == ";;" || c2 == ";&")) {
      cs[sp] = "pat"; started[sp] = 0; lead[sp] = 0
      i += (substr(line, i, 3) == ";;&") ? 3 : 2; continue
    }
    if (c == "(") { st[++sp] = "P"; i++; continue }
    if (c == ")") { if (top == "S" || top == "P") sp--; i++; continue }
    i++
  }
  if (pend != "") { hd = pend; hdstrip = pendstrip }
}
