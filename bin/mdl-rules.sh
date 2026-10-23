#!/usr/bin/env bash
# mdl-rules.sh — print the MDL rules one script needs, by the kinds of statement it writes.
#
#   bin/mdl-rules.sh page entity           # the core (kind `any`) plus the page and entity rules
#   bin/mdl-rules.sh --for <script.mdl>    # the kinds that script's statements write, then the same
#   bin/mdl-rules.sh --render              # rewrite skills/generated/rules-<kind>.md
#   bin/mdl-rules.sh --check               # coverage + drift of those files (CI); prints nothing else
#
# Kinds: page, microflow, access, workflow, entity, any. The output is the always-needed core
# (learned-mdl-preflight.md's Step 0, its `any` STOP rows, gotchas and final self-check; the
# detection-gaps ladder; retesting-learned-rules.md), then the sections bin/lib/mdl-rule-kinds.tsv
# maps to each kind asked for, then one closing line:
#   Rules for kinds <K>: STOP rows <n>/<n> listed
# The mdl helper reports that count back as "STOP rows for kinds <K>: n/n checked" in its PREFLIGHT.
#
# WHY (lazy-load PR 2, 2026-10-23). The mdl helper preloaded every kind-specific skill at Stage 5 —
# 29,388 words — although a page script needs none of the microflow rules and a microflow script
# none of the page rules. This prints the rules for the statements actually being written, the
# way bin/runbook-slice.sh prints one stage of the runbook and bin/bug-lookup.sh one ledger entry.
# The skills keep every word; only who preloads them changes. Harnesses that cannot run a script
# (Copilot, Cursor, Windsurf) read the same output as a file: skills/generated/rules-<kind>.md.
#
# --for reuses exec.sh's statement classifier (`project-bin/exec.sh --subjects`, the one lexer
# exec.sh, affected-tests.sh and the change class share) rather than a second copy of it. Subject
# kinds map: page|snippet|layout → page; microflow|nanoflow|rule → microflow; access|userrole|role
# → access; workflow → workflow; entity|association|enumeration → entity. Anything else (module,
# constant, mapping, unmapped) gets the core only, and the header names it.
#
# Never prints empty: a heading the table names that is gone, a bullet lead or register ERE that
# selects nothing, or a STOP count that does not add up exits 1 with the reason on stderr and
# nothing on stdout. Reads skills only: no mxcli, no mxbuild, no project. bash 3.2 + POSIX awk.
#
# Exit: 0 printed / clean · 1 lookup failed, coverage gap or drift · 2 usage (unknown kind, no file)
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TSV="${MXTK_MDL_RULES_TSV:-$ROOT/bin/lib/mdl-rule-kinds.tsv}"
GEN_DIR="$ROOT/skills/generated"
ALL_KINDS="page microflow access workflow entity any"
LC_ALL=C; export LC_ALL

usage() { sed -n '4,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "mdl-rules: $*" >&2; exit 1; }
[ -f "$TSV" ] || die "no kind table at $TSV"

valid_kind() { case " $ALL_KINDS " in *" $1 "*) return 0 ;; esac; return 1; }

# _extract <kinds...> — the rules text for those kinds (plus any) on stdout, or exit 1. One awk
# program reads the table and every file it names: rows are grouped by (file, selector, heading),
# so two kinds selecting the same gotcha or register row print it once, and a whole-file row
# suppresses that file's section rows.
_extract() {
  awk -v want=" any $* " -v root="$ROOT" -v tsv="$TSV" '
    function err(m) { print "mdl-rules: " m > "/dev/stderr"; failed = 1 }
    function load(f,    p, l, n) {
      if (f in N) return N[f] > 0
      p = root "/" f; n = 0
      while ((getline l < p) > 0) L[f, ++n] = l
      close(p); N[f] = n
      if (n == 0) err("cannot read " f)
      return n > 0
    }
    function hlevel(s) { if (s !~ /^#+ /) return 0; match(s, /^#+/); return RLENGTH }
    function htext(s) { sub(/^#+[ \t]+/, "", s); return s }
    # findh: the line number of the first heading in f whose text starts with h, else 0.
    function findh(f, h,    j) {
      for (j = 1; j <= N[f]; j++) if (hlevel(L[f, j]) && index(htext(L[f, j]), h) == 1) return j
      return 0
    }
    # send: the line after the section starting at s ends (next heading at its level or above).
    function send(f, s,    lv, j) {
      lv = hlevel(L[f, s])
      for (j = s + 1; j <= N[f]; j++) if (hlevel(L[f, j]) && hlevel(L[f, j]) <= lv) return j
      return N[f] + 1
    }
    function emit(s) { buf = buf s "\n" }
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function src(f, h) { emit(""); emit("> Source: `" f "`" (h == "" ? "" : " § " h)) }
    function cells(line, c,    n, i) {   # split a table row; c[1..n] are the cells, trimmed
      n = split(line, c, "|"); for (i = 1; i <= n; i++) c[i] = trim(c[i]); return n
    }
    BEGIN {
      while ((getline row < tsv) > 0) {
        if (row ~ /^[ \t]*#/ || row ~ /^[ \t]*$/) continue
        nf = split(row, t, "\t")
        if (nf < 4) { err("malformed table row: " row); continue }
        if (index(want, " " t[1] " ") == 0) continue
        f = t[2]; sel = t[3]; arg = t[4]; h = arg; part = ""
        if (sel == "bullet" || sel == "rows") {
          k = index(arg, "::"); if (k == 0) { err("no :: in " sel " arg: " arg); continue }
          h = substr(arg, 1, k - 1); part = substr(arg, k + 2)
        }
        if (sel == "file" || sel == "top") h = ""
        key = f SUBSEP sel SUBSEP h
        if (!(key in seen)) { seen[key] = ++ng; gf[ng] = f; gs[ng] = sel; gh[ng] = h }
        g = seen[key]
        if (sel == "bullet") { nb[g]++; lead[g, nb[g]] = part }
        if (sel == "rows")   ere[g] = (ere[g] == "" ? "" : ere[g] "|") "(" part ")"
        if (sel == "file")   whole[f] = 1
      }
      close(tsv)
      stops_listed = 0; stops_total = 0
      for (g = 1; g <= ng; g++) {
        f = gf[g]; sel = gs[g]; h = gh[g]
        if (sel != "file" && (f in whole)) continue
        if (!load(f)) continue
        if (sel == "file") { src(f, ""); for (j = 1; j <= N[f]; j++) emit(L[f, j]); continue }
        if (sel == "top") {
          src(f, "top"); n0 = 0
          for (j = 1; j <= N[f] && L[f, j] !~ /^## /; j++) { emit(L[f, j]); n0++ }
          if (n0 == 0) err(f ": nothing above its first ## heading")
          continue
        }
        s = findh(f, h)
        if (!s) { err(f ": heading not found: \"" h "\" (" sel ") — fix bin/lib/mdl-rule-kinds.tsv"); continue }
        e = send(f, s)
        if (sel == "section") {
          src(f, h); for (j = s; j < e; j++) emit(L[f, j])
          if (e - s < 2) err(f ": section \"" h "\" is empty")
          continue
        }
        if (sel == "bullet") {
          src(f, h)
          for (j = s; j < e && L[f, j] !~ /^- /; j++) emit(L[f, j])
          for (i = 1; i <= nb[g]; i++) hit[i] = 0
          for (; j < e; j++) {
            if (L[f, j] !~ /^- /) continue
            on = 0
            for (i = 1; i <= nb[g]; i++) if (index(substr(L[f, j], 3), lead[g, i]) == 1) { on = 1; hit[i]++ }
            if (!on) continue
            emit(L[f, j])
            for (x = j + 1; x < e && L[f, x] !~ /^- / && L[f, x] !~ /^#/ && L[f, x] !~ /^[ \t]*$/; x++) emit(L[f, x])
          }
          for (i = 1; i <= nb[g]; i++) if (!hit[i]) err(f ": no bullet under \"" h "\" starts with " lead[g, i])
          continue
        }
        if (sel == "rows" || sel == "stop") {
          src(f, h); tab = 0; matched = 0
          for (j = s; j < e; j++) {
            line = L[f, j]
            if (line !~ /^\|/) { if (tab < 3 || sel == "stop") emit(line); if (tab) tab = 3; continue }
            tab++
            if (tab <= 2) { emit(line); continue }          # header and separator
            n = cells(line, c)
            if (sel == "rows") {
              if (tolower(c[2]) ~ ere[g]) { emit(line); matched++ }
            } else {
              kd = c[n - 1]
              if (kd == "") { emit(line); continue }       # the retired-numbers row: kept for citations
              if (index(want, " " kd " ")) { emit(line); stops_listed++ }
            }
          }
          if (tab == 0) err(f ": no table under \"" h "\"")
          if (sel == "rows" && matched == 0) err(f ": no row under \"" h "\" matches /" ere[g] "/")
          if (sel == "stop") stops_file = f SUBSEP h
          continue
        }
        err("unknown selector " sel " in " tsv)
      }
      if (stops_file == "") err("the table has no stop row for kind any — nothing would list the STOP table")
      if (failed) exit 1
      printf "%s", buf
      printf "STOPS\t%d\n", stops_listed > "/dev/stderr"
    }'
}

# _stop_total <kinds...> — the denominator, counted by a second, independent pass over the STOP
# table: rows whose Kind cell is one of the kinds (or any). The two must agree or the run fails.
_stop_total() {
  local f h
  f="$(awk -F'\t' '$1 == "any" && $3 == "stop" { print $2; exit }' "$TSV")"
  h="$(awk -F'\t' '$1 == "any" && $3 == "stop" { print $4; exit }' "$TSV")"
  awk -v want=" any $* " -v h="$h" '
    index($0, "## " h) == 1 { on = 1; next }
    on && /^## / { exit }
    on && /^\|/ { n = split($0, c, "|"); k = c[n - 1]; gsub(/^[ \t]+|[ \t]+$/, "", k)
                  if (k != "" && k != "Kind" && k !~ /^-+$/ && index(want, " " k " ")) t++ }
    END { print t + 0 }' "$ROOT/$f"
}

# print_rules <label> <kinds...> — the full output: header, rules, closing count line.
print_rules() {
  local label="$1"; shift
  local body errf listed total kl
  errf="$(mktemp "${TMPDIR:-/tmp}/mdl-rules.XXXXXX")"
  if ! body="$(_extract "$@" 2>"$errf")"; then
    grep -v '^STOPS	' "$errf" >&2; rm -f "$errf"; exit 1
  fi
  listed="$(sed -n 's/^STOPS	//p' "$errf")"; rm -f "$errf"
  total="$(_stop_total "$@")"
  kl="any"; for k in "$@"; do [ "$k" = any ] || kl="$kl, $k"; done
  [ "$listed" = "$total" ] || die "STOP rows for kinds $kl: listed $listed, the table has $total — fix bin/mdl-rules.sh"
  cat <<EOF
# MDL rules for kinds: $kl
<!-- Generated by bin/mdl-rules.sh from bin/lib/mdl-rule-kinds.tsv — do not hand-edit; edit the skills or the table, then bin/mdl-rules.sh --render. -->

$label These are the rules for the statement kinds your script writes — read every line before
the first MDL line, check every STOP row below against every planned operation, and put the closing
count in your PREFLIGHT as "STOP rows for kinds $kl: n/n checked". A script that also writes a kind
not listed here needs that kind's rules too: \`bin/mdl-rules.sh --for <script>\` after drafting.
Each block names the skill it comes from; the skill is the authority if they ever differ.
$body

Rules for kinds $kl: STOP rows $listed/$total listed
EOF
}

# kinds_for <script> — "<kinds>|<other subject kinds>": the rule kinds for the statement kinds the script writes.
kinds_for() {
  local subj kinds="" other=""
  subj="$(bash "$ROOT/project-bin/exec.sh" --subjects "$1")" || { echo "mdl-rules: classifier failed on $1" >&2; exit 1; }
  while IFS=$'\t' read -r sk _name where; do
    [ -n "$sk" ] || continue
    case "$sk" in
      page|snippet|layout)         k=page ;;
      microflow|nanoflow|rule)     k=microflow ;;
      access|userrole|role)        k=access ;;
      workflow)                    k=workflow ;;
      entity|association|enumeration) k=entity ;;
      *) k=""; case " $other " in *" $sk "*) : ;; *) other="${other:+$other }$sk" ;; esac ;;
    esac
    [ -n "$k" ] || continue
    case " $kinds " in *" $k "*) : ;; *) kinds="${kinds:+$kinds }$k" ;; esac
  done <<EOF
$subj
EOF
  printf '%s|%s\n' "$kinds" "$other"   # "|", not a tab: IFS whitespace would drop an empty first field
}

render_to() { # render_to <dir> — one rules-<kind>.md per kind
  local d="$1" k
  mkdir -p "$d"
  for k in $ALL_KINDS; do
    print_rules "Kinds asked for: $k." "$k" > "$d/rules-$k.md.tmp"   # the same bytes as `bin/mdl-rules.sh <k>`
    mv "$d/rules-$k.md.tmp" "$d/rules-$k.md"
  done
}

# coverage — the denominators: every STOP row has a known Kind; every bullet under a `bullet`
# heading and every row under a `rows` heading is selected by at least one table row.
coverage() {
  local bad=0 f h line g k
  awk -F'\t' '!/^#/ && NF >= 4' "$TSV" | while IFS=$'\t' read -r k f sel arg; do
    valid_kind "$k" || { echo "  table: unknown kind '$k' ($f $sel)"; }
    [ -f "$ROOT/$f" ] || echo "  table: no such file $f"
    case "$sel" in file|top|section|stop|bullet|rows) : ;; *) echo "  table: unknown selector '$sel'" ;; esac
  done > "$WORK/cov"
  # STOP rows: every non-retired row's Kind is a known kind.
  h="$(awk -F'\t' '$3 == "stop" { print $4; exit }' "$TSV")"; f="$(awk -F'\t' '$3 == "stop" { print $2; exit }' "$TSV")"
  awk -v h="$h" -v ok=" $ALL_KINDS " '
    index($0, "## " h) == 1 { on = 1; next }
    on && /^## / { exit }
    on && /^\|/ { r++; if (r <= 2) next
                  n = split($0, c, "|"); k = c[n - 1]; gsub(/^[ \t]+|[ \t]+$/, "", k)
                  if (k == "" && $0 ~ /retired/) next
                  if (!index(ok, " " k " ")) { id = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", id); print "  STOP row " id ": Kind \"" k "\" is not one of" ok } }' \
    "$ROOT/$f" >> "$WORK/cov"
  # Bullets and register rows: the union of the table's selections covers every one.
  awk -F'\t' '!/^#/ && ($3 == "bullet" || $3 == "rows") { split($4, a, "::"); print $2 "\t" $3 "\t" a[1] }' "$TSV" | sort -u |
  while IFS=$'\t' read -r f sel h; do
    awk -v h="$h" -v sel="$sel" -v f="$f" -v tsv="$TSV" '
      BEGIN { FS = "\n"
        while ((getline r < tsv) > 0) { if (r ~ /^#/) continue; split(r, t, "\t")
          if (t[2] != f || t[3] != sel) continue; k = index(t[4], "::")
          if (substr(t[4], 1, k - 1) != h) continue
          p = substr(t[4], k + 2); if (sel == "bullet") L[++nl] = p; else E = (E == "" ? "" : E "|") "(" p ")" } }
      /^#+ / && !on { x = $0; sub(/^#+[ \t]+/, "", x); if (index(x, h) == 1) { on = 1; match($0, /^#+/); lv = RLENGTH; next } }
      on && /^#+ / { match($0, /^#+/); if (RLENGTH <= lv) exit }
      on && sel == "bullet" && /^- / { hit = 0; for (i = 1; i <= nl; i++) if (index(substr($0, 3), L[i]) == 1) hit = 1
                                       if (!hit) print "  " f " § " h ": bullet reaches no kind: " substr($0, 1, 70) }
      on && sel == "rows" && /^\|/ { r++; if (r <= 2) next; n = split($0, c, "|"); x = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", x)
                                     if (tolower(x) !~ E) print "  " f " § " h ": register row reaches no kind: " substr(x, 1, 70) }' \
      "$ROOT/$f"
  done >> "$WORK/cov"
  if [ -s "$WORK/cov" ]; then
    echo "COVERAGE: rules that reach no kind, or a table row that names nothing (bin/lib/mdl-rule-kinds.tsv):"
    cat "$WORK/cov"; bad=1
  fi
  return $bad
}

case "${1:-}" in
  ""|-h|--help) usage ;;
  --render)
    render_to "$GEN_DIR"
    echo "mdl-rules: rendered $(for k in $ALL_KINDS; do printf 'rules-%s.md ' "$k"; done)into skills/generated/"
    exit 0 ;;
  --check)
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/mdl-rules-check.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
    rc=0
    coverage || rc=1
    if ! ( render_to "$WORK/gen" ) 2>"$WORK/err"; then
      echo "LOOKUP FAILED while rendering:"; sed 's/^/  /' "$WORK/err"; rc=1
    else
      drift=""
      for k in $ALL_KINDS; do
        cmp -s "$WORK/gen/rules-$k.md" "$GEN_DIR/rules-$k.md" 2>/dev/null || drift="$drift rules-$k.md"
      done
      for g in "$GEN_DIR"/rules-*.md; do
        [ -f "$g" ] || continue
        [ -f "$WORK/gen/$(basename "$g")" ] || drift="$drift $(basename "$g")(stray)"
      done
      if [ -n "$drift" ]; then
        echo "DRIFTED: skills/generated/ no longer matches the skills and the kind table:$drift"
        echo "    → run bin/mdl-rules.sh --render and commit the result (never hand-edit those files)"
        rc=1
      fi
    fi
    [ "$rc" -eq 0 ] && echo "mdl-rules: kind table covers every STOP row, gotcha and register row; skills/generated/ in sync."
    exit $rc ;;
  --for)
    [ -n "${2:-}" ] && [ -f "$2" ] || { echo "mdl-rules: --for needs an existing .mdl script (got '${2:-}')" >&2; exit 2; }
    IFS='|' read -r KINDS OTHER <<EOF
$(kinds_for "$2")
EOF
    note="Script \`$(basename "$2")\` writes: ${KINDS:-no page, microflow, access, workflow or entity statement}."
    [ -z "$OTHER" ] || note="$note Also: $OTHER (core rules only)."
    # shellcheck disable=SC2086
    print_rules "$note" $KINDS
    exit 0 ;;
  --*) usage ;;
esac

for k in "$@"; do
  valid_kind "$k" || { echo "mdl-rules: unknown kind '$k' — one of: $ALL_KINDS" >&2; exit 2; }
done
print_rules "Kinds asked for: $*." "$@"
