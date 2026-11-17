#!/usr/bin/env bash
# ready-claims.sh — a READY line that bin/ready.sh did not write is not READY. ONE copy, sourced by
# bin/gate-check.sh (Stage 6) and bin/ci-gates.sh (the CI gate an agent cannot skip).
#
# WHY (field run, 2026-11, unattended). The build agent wrote READY into its own status file and
# was graded done with 0 of ~78 pages looked at. bin/ready.sh is now the only writer of READY; this
# is the check that a READY line anywhere else is backed by it.
#
# A READY CLAIM is a line in a status file whose first word (after list, quote and bold markup, or
# a `Status:` / `State:` / `Verdict:` label) is READY, or a table cell that is exactly READY.
# Status files: PROJECT.md, RESUME.md / STATUS*.md / PROGRESS*.md at the root, and every .md under
# docs/ except ready.sh's own output (docs/progress/ready-*.md, review-packets/, look-reviews/,
# must-haves/). Not CLAUDE*.md, README or agent text: they explain the rule, they claim nothing.
# BACKED means the line names an evidence file docs/progress/ready-<date>-<scope>.md that exists,
# whose verdict line (line 3, written by ready.sh) starts "READY:", and which docs/progress/ready.log
# lists as READY. Each scope's latest row in ready.log is held to the same test, so a hand-appended
# READY row with no evidence behind it is caught too; an older READY that a later run withdrew is not.
#
# What it cannot see: a claim made only in chat, a commit message, or an uncommitted file. A
# hand-forged evidence file passes this check; bin/ci-gates.sh then compares it with the committed
# look summary, which is where a forged claim and the ledger disagree.
#
# Sourced, never executed. Side-effect free. Bash 3.2.

# mxtk_ready_claim_faults <project-root> — one line per unbacked READY claim:
#   <relpath>:<line>: <text> — <why>
# Returns 0 when there is none, 1 when there is at least one.
mxtk_ready_claim_faults() {
  local root="$1" f rel log="$1/docs/progress/ready.log" out="" ev line n text why
  _rc_backed() {  # <evidence-rel> — 0 when ready.sh's READY evidence and its log row agree
    [ -f "$root/$1" ] || return 1
    sed -n 3p "$root/$1" | grep -q '^READY:' || return 1
    [ -f "$log" ] && awk -F'\t' -v e="$1" '$2 == "READY" && $4 == e { f=1 } END { exit !f }' "$log"
  }
  {
    for f in "$root/PROJECT.md" "$root"/RESUME.md "$root"/STATUS*.md "$root"/PROGRESS*.md; do [ -f "$f" ] && printf '%s\n' "$f"; done
    [ -d "$root/docs" ] && find "$root/docs" -type f -name '*.md' \
      ! -path '*/docs/progress/ready-*' ! -path '*/docs/progress/review-packets/*' \
      ! -path '*/docs/progress/look-reviews/*' ! -path '*/docs/progress/must-haves/*' 2>/dev/null
  } | sort -u > "${TMPDIR:-/tmp}/mxtk-rc.$$"
  while IFS= read -r f; do
    rel="${f#"$root"/}"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      n="${line%%:*}"; text="${line#*:}"
      ev="$(printf '%s' "$text" | grep -oE 'docs/progress/ready-[A-Za-z0-9_.-]+\.md' | head -1)"
      if [ -z "$ev" ]; then why="no bin/ready.sh evidence named (docs/progress/ready-<date>-<scope>.md)"
      elif ! _rc_backed "$ev"; then why="$ev is not a READY written by bin/ready.sh (missing, not READY, or not in docs/progress/ready.log)"
      else continue; fi
      out="$out$rel:$n: $(printf '%s' "$text" | cut -c1-100) — $why
"
    done <<EOF
$(tr -d '\r' < "$f" | grep -nE '^[[:space:]>*_#-]*(\*\*)?((Status|State|Verdict)[[:space:]]*:[[:space:]]*)?(\*\*)?READY(\*\*)?([[:space:]]*$|[[:space:]]*[:(]|[[:space:]]+[—–-]|[[:space:]]+(for|—)[[:space:]])|\|[[:space:]]*(\*\*)?READY(\*\*)?[[:space:]]*\|')
EOF
  done < "${TMPDIR:-/tmp}/mxtk-rc.$$"
  rm -f "${TMPDIR:-/tmp}/mxtk-rc.$$"
  if [ -f "$log" ]; then
    # Only each scope's LATEST row is a standing claim: a later NOT-READY run withdraws an earlier
    # READY (and overwrites that day's evidence file), so judging old rows would fault an honest log.
    while IFS='	' read -r _iso v sc ev _k; do
      [ "$v" = READY ] || continue
      _rc_backed "$ev" || out="${out}docs/progress/ready.log: READY $sc — $ev is missing or does not say READY
"
    done <<EOF
$(awk -F'\t' 'NF >= 4 { last[$3] = $0; if (!($3 in o)) ord[++k] = $3; o[$3] = 1 } END { for (i=1; i<=k; i++) print last[ord[i]] }' "$log")
EOF
  fi
  [ -z "$out" ] && return 0
  printf '%s' "$out"
  return 1
}
