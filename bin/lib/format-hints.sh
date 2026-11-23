#!/usr/bin/env bash
# format-hints.sh — the full accepted shape of every format a gate PARSES, printed with the FAIL.
#
# WHY (#821 point 1, two simulated builds 2026-11-20). Each gate FAIL named what was missing but
# not the line it would accept, so the next run revealed the next requirement: a prototype LOOK
# took five gate runs (no PROTOTYPE-SHA → no PROOF-OF-LOOK → shots not on disk → no register row),
# the build-plan row ids were rewritten by sed after a FAIL, and the agents read gate source 10
# and 19 times before their first model write. A FAIL now prints, once per run and per format, a
# minimal example that passes — every line the parser wants, at once.
#
# THE RULE FOR THIS FILE: an example here must pass the parser it describes. Each one is checked
# against the real parser by tests/wave2/test-fast-lane-format-hints.sh, which writes the example
# into a project scaffolded by bin/init-project.sh and runs the gate on it; change a parser, change
# its example, and that fixture says which.
#
# Sourced by bin/gate-check.sh (and the obligation check it sources). Bash 3.2 safe.
#
#   mxtk_format_hint <id>        print the shape (ids: intake, build-plan, coverage-ledger,
#                                look-report, prototype-look, report-disposition)
#   mxtk_format_hint_once <id>   the same, at most once per process (MXTK_FH_SHOWN)

MXTK_FH_SHOWN="${MXTK_FH_SHOWN:-}"

mxtk_format_hint_once() {
  case " $MXTK_FH_SHOWN " in *" $1 "*) return 0 ;; esac
  MXTK_FH_SHOWN="$MXTK_FH_SHOWN $1"
  mxtk_format_hint "$1"
}

mxtk_format_hint() {
  case "$1" in
    intake) cat <<'EOF'
  Accepted shape — intake.md (Stage P): every '## N.' section carries ONE marker line, at the start of a line:
      ## 1. Entry mode: migration, requirements-driven, or change an existing app?
      Answered (CONFIRMED): requirements-driven
      ## 7. Is an SME available — who, and at what cadence?
      Unverified — how to verify: ask the sponsor at the Stage 0 checkpoint
      ## 15. Pipeline mode: `high-speed`, `balanced` (default) or `high-quality`?
      Assumed (auto-mode): balanced
    Also accepted: Answer: / A: / Decision: (a qualifier in parentheses is fine). Not accepted: "_Not yet
    asked._", "Status: Not Answered", a bare "Unverified".
EOF
      ;;
    build-plan) cat <<'EOF'
  Accepted shape — architecture/build-plan.md (Stage 4), a minimal plan for one module that passes:
      | # | Kind | Step | Depends on |
      |---|---|---|---|
      | 1 | BRIEF | Module brief — Rooms (architecture/modules/Rooms/module-brief.md) | — |
      | 2 | BUILD | Rooms domain model and access rules | 1 |
      | 3 | BUILD | Rooms pages | 2 |
      | 4 | HARNESS | bin/verify-module.sh Rooms, then LOOK + CONFIRM (module-review.md) | 3 |
      | 5 | RUN | bin/gate-check.sh <project> 5 | 4 |
    Row ids are numbers (1, 01, 3a, 1.1), never R03. Kind is BRIEF, BUILD, PROVE, RUN or HARNESS. Owed: one
    `verify-module.sh <Module>` row per module; one HARNESS/RUN row naming process-coherence-pass per 3 modules
    once there are 2 or more (2-4 modules: 1, 5-7: 2, ...); the LAST numbered row is `gate-check.sh <project> 5`;
    every Depends-on number is a row of the plan. The first BRIEF row's module needs its brief:
    architecture/modules/<M>/module-brief.md, architecture/modules/<M>-brief.md, or '## Module brief — <M>' in the plan.
    Then a Decisions row in PROJECT.md: | 4 | Build plan approved | CONFIRMED | ... |
EOF
      ;;
    coverage-ledger) cat <<'EOF'
  Accepted shape — a coverage ledger (architecture/coverage-ledger.md, or architecture/modules/<M>/coverage-ledger.md):
      | pointer | type | title | slice | writeMode | acceptance | status |
      |---|---|---|---|---|---|---|
      | /domainEntities/0/name | entity | Room | 1 | create | Room exists | claimed by row 2 |
      | /useCases/0/* (3) | useCase | Book a room | 1 | create | journey passes | claimed by row 3 |

      | pointer | category | reason |
      |---|---|---|
      | /id | provenance | the BRD's own id, not a requirement |
    One row per BRD leaf pointer (never one per model element). A wildcard or a comma list carries the count of
    leaves it covers in "(N)", and claims ONE element (/useCases/0/*), never a whole section (/useCases/*). Every
    leaf is claimed exactly once (7-column table) or ledgered with a category and a reason (3-column table).
    The BRDs it is measured against: analysis/<source>/knowledge-base/brd/*.brd.json. List every leaf:
    project-bin/coverage-preflight.sh --summary (run from the project root)
EOF
      ;;
    look-report) cat <<'EOF'
  Accepted shape — a LOOK report, design/ui-reviews/ui-review-<YYYY-MM-DD>-<Module>.html (module-review.md stage 5):
      Rooms · 2 of 2 pages reviewed
      VALID AT: 1a2b3c4
      PROOF-OF-LOOK: Rooms.Room_Overview = shots/2026-11-20/Rooms.Room_Overview.png
      PROOF-OF-LOOK: Rooms.Booking_New = shots/2026-11-20/Rooms.Booking_New.png
    The first line counts "N of M". VALID AT is the model commit the shots were taken on. One PROOF-OF-LOOK per
    reviewed page (at least N), the path relative to the report; each file on disk, at least 10 KB, newer than the
    VALID AT commit, committed with the report. The report names the module. A page with no review needs
    --waive look/<Module> --reason "...".
EOF
      ;;
    prototype-look) cat <<'EOF'
  Accepted shape — design/ui-reviews/prototype-look-<YYYY-MM-DD>.html (design-artifacts.md Step 3d):
      4 of 4 screen-widths captured
      PROTOTYPE-SHA: <the sha256 bin/assemble-prototype.js printed for design/prototype.html>
      PROOF-OF-LOOK: rooms@390 = shots/2026-11-20/rooms-390.png
      PROOF-OF-LOOK: rooms@360 = shots/2026-11-20/rooms-360.png
      PROOF-OF-LOOK: rooms@320 = shots/2026-11-20/rooms-320.png
      PROOF-OF-LOOK: rooms@1280 = shots/2026-11-20/rooms-1280.png
    That is one screen. M = screens x 4 widths (390, 360, 320, 1280); one PROOF-OF-LOOK per screen-width (at least
    N), the path relative to the report, each file on disk and at least 10 KB. Re-assembling the prototype changes
    its sha and makes the report STALE.
EOF
      ;;
    report-disposition) cat <<'EOF'
  Accepted shape — docs/improvement-register.md, one row per finding of the newest report, dated that report's day:
      | Date | Module/Cluster | Source pass | Defect class | Severity | Finding | Disposition |
      |---|---|---|---|---|---|---|
      | 2026-11-20 | Rooms | module-review stage 4 | layout | P2 | Booking list overflows at 390 | fixed same session |
    (skills/finding-disposition.md; project-bin/report-disposition-check.sh <project> says which report and date.)
EOF
      ;;
    *) return 1 ;;
  esac
}
