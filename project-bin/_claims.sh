#!/usr/bin/env bash
# _claims.sh — the single reader of build-plan `claims:` blocks.
#
# Producer of the format: skills/brd-to-build-plan.md Step 5b. Issue #74: only the plainest
# shape was ever parsed by project-bin/coverage-preflight.sh's own inline `extract_claims`,
# so real build plans silently reported LEVEL 3 NOT MEASURED / "predates the claims
# convention" even though they carried claims blocks — the plan just used a shape nothing
# read. Five shapes are in the field, all handled here:
#
#     claims:                     plain — one indented pointer per line, no fence
#       /pages/0/buildComposition/rowClick
#
#     ```                         fenced — a bare ``` fence wraps the WHOLE block, `claims:`
#     claims:                     itself is the first line INSIDE the fence. This is the
#       F001/domainEntities/...   shape Step 5b's own worked example uses, and the shape a
#     ```                         real build plan gets when an agent copy-pastes that example.
#
#     claims:                     fenced-under — `claims:` on its own line, THEN a fence opens
#     ```                         on the next line. Older convention, kept for compatibility.
#       /pages/0/...
#     ```
#
#     ```claims                   fenced with a language tag, no `claims:` line at all.
#       /pages/0/...
#     ```
#
#     claims: (a note)            note — the claims: line itself carries prose; pointers
#       /pages/0/...              still follow, indented, same as plain.
#
# Pointer syntax accepted in the CELL itself (validated leaf by leaf, one pointer per line):
#   - leading-slash pointers:  /pages/0/buildComposition/rowClick
#   - BRD-prefixed pointers, no leading slash:  F001/domainEntities/Dashboard/attributes/*
#   - a trailing `(N)` count, digits only — the wildcard/count contract `bin/coverage-check.sh`
#     `expand_claims` enforces. `_claims.sh` reports N in its own `count` column but never
#     expands the wildcard itself — expand_claims stays the one place that authority lives.
#   - a trailing free-text note in parens, e.g. `F005/domainEntities/Account (Administration,
#     not created here)` — kept off the pointer, discarded, not treated as a count.
#   - a trailing `[F001]` bracket annotation — kept off the pointer, reported in the `brd`
#     column (older, undocumented convention; kept for compatibility, not the primary form).
#   - `A..B` ranges, e.g. `F001/businessRules/BR001..BR004` — passed through as ONE literal
#     pointer. This script does not expand ranges; that is `expand_claims`'s job too, unchanged.
#
# A line that is prose, not a pointer (a stray fit-gap reference, a Stage-0 gate name with no
# path shape) is never silently folded into "the row" or dropped: it is reported on stderr as
# `claims-line-unparsed`, so "no claims" and "unparsable claims" stay distinguishable (issue
# #67 point 4). A `claims:`/fence pair with zero valid pointers inside is `claims-block-empty`.
#
# Emits one TSV row per pointer on stdout:
#   file <TAB> lineno <TAB> phase <TAB> row <TAB> pointer <TAB> count <TAB> brd <TAB> form
# lineno is the pointer's own line in `file`. `phase` is the nearest preceding `#.. Phase <n>`
# heading ("-" if none). `row` is the nearest preceding non-blank, non-heading, non-fence line
# — the build-plan row identity the pointer is claimed under. count/brd are "-" when absent.
# form is one of: plain | note | inline | fenced | fenced-tag.
#
# Bash 3.2 compatible (stock macOS), awk only — no Python, so coverage-preflight.sh keeps
# working on a machine with none. No non-ASCII bytes inside any awk regex or bracket expression
# (a literal em/en-dash there is not portable across awk implementations); phase-heading text is
# taken as the leading digit run only, never matched against a dash.
#
# Lives in project-bin/, not bin/lib/: project-side scripts cannot source toolkit-side libs
# (_common.sh's own header records that), so this installs into <project>/bin/ alongside
# coverage-preflight.sh and is sourced the same way: `. "$(dirname "$0")/_claims.sh"`.

mxtk_extract_claims_tsv() {
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

    # A pointer body is valid when, after stripping one trailing bracket/paren annotation, it
    # (a) contains no embedded whitespace and (b) starts with an optional identifier run
    # followed immediately by "/" — this one test covers both /leading-slash and BRD-prefixed
    # F001/... forms, and rejects prose ("Stage-0 gate G3 ...", "fit-gap row 10 ...") whether
    # or not that prose happens to contain a slash later on.
    function looks_like_pointer(s) {
      return (s !~ / /) && (s ~ /^[A-Za-z0-9_.:-]*\//)
    }

    function emit(raw,  body, cnt, brd) {
      body = trim(raw); cnt = "-"; brd = "-"
      if (match(body, /\[[^]]+\][ \t]*$/)) {
        brd = substr(body, RSTART + 1, RLENGTH - 2); gsub(/[ \t]/, "", brd)
        body = trim(substr(body, 1, RSTART - 1))
      }
      if (match(body, /\([0-9]+\)[ \t]*$/)) {
        cnt = substr(body, RSTART + 1, RLENGTH - 2); gsub(/[^0-9]/, "", cnt)
        body = trim(substr(body, 1, RSTART - 1))
      } else if (match(body, /\([^()]*\)[ \t]*$/)) {
        # a trailing free-text note, not a count — discard it, it is not part of the pointer
        body = trim(substr(body, 1, RSTART - 1))
      }
      if (brd == "-" && match(body, /^F[0-9]+\//)) {
        brd = substr(body, 1, RLENGTH - 1)   # peek only; stays part of the pointer path
      }
      if (!looks_like_pointer(body)) {
        print "claims-line-unparsed\t" FILENAME "\t" FNR "\t" phase "\t" row "\t" trim(raw) > "/dev/stderr"
        return
      }
      print FILENAME "\t" FNR "\t" phase "\t" row "\t" body "\t" cnt "\t" brd "\t" form
      seen++
    }

    function closeblock() {
      if (inblock && seen == 0) print "claims-block-empty\t" FILENAME "\t" bstart "\t" phase "\t" row > "/dev/stderr"
      inblock = 0; fence = 0; pend = 0
    }

    BEGIN { FS = "\n"; phase = "-"; row = "-"; inblock = 0; fence = 0; genfence = 0 }

    /^[ \t]*#{1,6}[ \t]+Phase[ \t]+[0-9]/ {
      closeblock()
      line = $0; sub(/^[ \t]*#+[ \t]+Phase[ \t]+/, "", line)
      if (match(line, /^[0-9]+/)) { phase = substr(line, RSTART, RLENGTH) } else { phase = trim(line) }
      row = "-"; next
    }

    # A bare ``` fence line. Three cases: closing an active claims fence, closing an unrelated
    # (non-claims) fence we were passing through opaque, or opening a new one of either kind —
    # which one it turns out to be is only known once (if ever) a `claims:` line appears inside.
    /^[ \t]*```[ \t]*$/ {
      if (inblock && fence) { closeblock(); genfence = 0; next }
      if (inblock && pend) { fence = 1; form = "fenced"; pend = 0; next }
      if (genfence) { genfence = 0; next }
      genfence = 1; bstart = FNR; next
    }

    # ```claims — a fenced block with a language tag and no separate claims: line.
    /^[ \t]*```[ \t]*claims[ \t]*$/ { closeblock(); inblock = 1; fence = 1; genfence = 0; form = "fenced-tag"; seen = 0; bstart = FNR; next }

    /^[ \t]*claims:[ \t]*$/ {
      closeblock(); inblock = 1; seen = 0; bstart = FNR
      if (genfence) { fence = 1; form = "fenced"; pend = 0 } else { fence = 0; form = "plain"; pend = 1 }
      next
    }
    /^[ \t]*claims:[ \t]*\(/ {
      closeblock(); inblock = 1; seen = 0; bstart = FNR
      if (genfence) { fence = 1; form = "fenced"; pend = 0 } else { fence = 0; form = "note"; pend = 1 }
      next
    }
    /^[ \t]*claims:[ \t]*\// {
      closeblock(); line = $0; sub(/^[ \t]*claims:[ \t]*/, "", line)
      inblock = 1; fence = 0; form = "inline"; seen = 0; bstart = FNR
      emit(line); pend = 0; next
    }

    {
      # Inside a bare fence that has not (yet, or ever) turned out to be a claims block:
      # opaque — swallow it whole, never let it touch `row`.
      if (genfence && !inblock) { next }

      # `claims:` (or `claims: (note)`) was seen with no fence yet. A bare ``` line on the very
      # next line is caught by the fence rule above (older "fenced-under" convention) before
      # ever reaching here, so any line that does reach here is not a fence-open — the pending
      # decision resolves to "no fence" and this line is just the first content line of the block.
      if (inblock && pend) { pend = 0 }

      if (inblock && fence) { if (trim($0) != "") emit($0); next }

      if (inblock) {
        if ($0 ~ /^[ \t]+[^ \t]/) { emit($0); next }
        closeblock()
      }

      if (trim($0) != "" && $0 !~ /^[ \t]*#{1,6}[ \t]/) { row = trim($0) }
    }

    END { closeblock() }
  ' "$@"
}
