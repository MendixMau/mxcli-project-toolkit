#!/usr/bin/env bash
# Stage P scaffold — creates intake.md / PROJECT.md skeletons for a new conversion project
# and renders the initial index.html dashboard via gate-check.sh.
#
# Idempotent: never overwrites a file that already exists. Safe to re-run.
#
# Usage: bin/init-project.sh <project-dir> [--ignore-sources|--track-sources]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# What a project gets installed — agents and project-bin scripts — comes from ONE manifest
# that sync-project.sh and init-agents.sh read too. This script used to carry its own copy
# and fell two scripts behind sync's (conformance-check.sh, graph-sweep.sh), which are the
# instruments review-agent.md needs. A fresh project got neither the agent nor its tools.
. "$SCRIPT_DIR/lib/install-manifest.sh"
. "$SCRIPT_DIR/lib/install-lint-rules.sh"

# The baseline routing block this script writes into CLAUDE.local.md is NOT a heredoc copy of
# the README's table any more. It is rendered from bin/lib/skill-routing.tsv — the same table
# gate-check.sh's stage map, the agent templates and sync-project.sh read. A hand-kept copy
# here is how facts-lock.sh ended up routed in 1 of 6 projects.
. "$SCRIPT_DIR/lib/skill-routing.sh"

# The intake.md template. ONE copy, in bin/lib/intake-template.sh, because sync-project.sh
# repairs the same file and needs the same text — see that file's header for what the two
# hand-kept copies cost.
. "$SCRIPT_DIR/lib/intake-template.sh"

# The triage.md template — Stage 0's one required artifact. Same one-copy arrangement as the
# intake template above, for the same reason: sync-project.sh refreshes untouched scaffolds and
# needs the identical text. Until this existed, gate-check.sh REQUIRED triage.md and nothing
# wrote it; the one project that hand-typed it drifted on the reuse-vs-build-new question the
# skill bolds twice. See bin/lib/triage-template.sh's header.
. "$SCRIPT_DIR/lib/triage-template.sh"

# The docs/progress/RESUME.md starter. Same one-copy arrangement as the two templates above.
# wire-agents.sh stamps "Read docs/progress/RESUME.md first, and nothing else yet" into all six
# generated entry points, and until this existed nothing in the init path created docs/ at all —
# so a project's very first instruction, in every tool, pointed at a missing file. See the header
# of bin/lib/resume-template.sh.
. "$SCRIPT_DIR/lib/resume-template.sh"

# SOURCES_MODE: ask | ignore | track. "ask" prompts only when stdin is a TTY; with no TTY it
# ignores and says so. Ignoring is the default because a source drop is routinely hundreds of
# MB of someone else's code, and the first time you find out it was committed is when you try
# to push. --track-sources is for the case where the source genuinely belongs in this repo.
SOURCES_MODE="ask"
PROJECT_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --ignore-sources) SOURCES_MODE="ignore" ;;
    --track-sources)  SOURCES_MODE="track" ;;
    -h|--help)
      echo "Usage: $0 <project-dir> [--ignore-sources|--track-sources]"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 <project-dir> [--ignore-sources|--track-sources]" >&2
      exit 1
      ;;
    *)
      if [ -n "$PROJECT_DIR" ]; then
        echo "Unexpected extra argument: $1" >&2
        exit 1
      fi
      PROJECT_DIR="$1"
      ;;
  esac
  shift
done

if [ -z "$PROJECT_DIR" ]; then
  echo "Usage: $0 <project-dir> [--ignore-sources|--track-sources]" >&2
  exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
  mkdir -p "$PROJECT_DIR"
  echo "Created: $PROJECT_DIR"
fi

INTAKE="$PROJECT_DIR/intake.md"
PROJECT_MD="$PROJECT_DIR/PROJECT.md"

if [ -f "$INTAKE" ]; then
  echo "Skip: intake.md already exists — not overwritten."
else
  # The pre-filled bodies must carry NO answer marker.
  #
  # They used to read "Unverified — how to verify: ...", which is one of the two forms
  # check_stage_P() accepts — so `gate-check.sh <dir> P` reported
  #   "PASS — all 9 intake questions carry an answer marker"
  # on a project that was two seconds old, before a single question had been asked. The
  # generator was manufacturing the gate's own pass condition. Reported from a Copilot/Windows
  # dry run, 2026-08-19, and reproduced here.
  #
  # "Unverified — how to verify: ..." stays a legitimate ANSWER: it means the question was
  # asked and the answer is pending. It is not a legitimate PLACEHOLDER. So the scaffold says
  # "_Not yet asked._" instead, which normalises (check_stage_P strips leading [ \t>*_-]) to
  # "not yet asked._ how to verify: ..." — matching neither marker branch, failing the gate,
  # and naming the section. Same shape as the "- Status: Not Answered" case pinned by
  # tests/wave2/test-stage-p.sh T3.
  #
  # sync-project.sh's q9_current_text() mirrors Q9 below verbatim. Change both together, or
  # --repair-intake writes the false-green back into a project.
  #
  # WHY THESE NINE, and why the interview-mode question is pinned at "## 9."
  #
  # The nine used to be almost entirely logistical — which source folder, which stray
  # documents, fresh-or-continuation, which Mendix version. Four of those broke the runbook's
  # own first rule (§1 step 1: "never ask what it can derive"), and the Copilot dry run of
  # 2026-08-19 showed it in the agent's own words: its recommendation for "fresh or
  # continuation?" was "(a) — this project was just reset to a clean slate", and for the
  # Mendix version, "let me inspect the .mpr and confirm rather than guessing". Those are not
  # questions, they are the agent asking the human to rubber-stamp its own homework. A fifth
  # (single-app vs multi-app split) could not be answered at all at Stage P — its own hint
  # said "assess during Stage 0 triage".
  #
  # Meanwhile the questions that decide how the whole pipeline should run were not asked
  # anywhere gate-check can see:
  #   - the ENTRY MODE, which conversion-runbook.md §"Entry Modes" calls "a Stage-P interview
  #     decision, not a silent inference" — and which has already caused one real misrouting
  #     (2026-07-14, a specs+source project classified greenfield, proposing to skip 0-4);
  #   - what the project IS (POC / hard-date replacement / open-ended) and what drives it,
  #     which lived only in the Stage 0 scope brainstorm (runbook §1, "What is this project
  #     actually for (POC, replacement, demo)?") — ungated, so nothing checked it happened;
  #   - the standing open-floor question the runbook mandates at every checkpoint.
  # The logistical questions were gated; the strategic ones were not. That is backwards.
  #
  # So: Q1-Q8 are the things only a human can answer, at a stage where they can answer them.
  # The derivable four become agent homework, presented as "I found X — confirm?" per the
  # six-step protocol's step 2. The multi-app split moves to Stage 0 and DTAP to Stage 3,
  # where each is actually answerable.
  #
  # Q9 STAYS AT NUMBER 9, with this exact heading. "## 9." is hardcoded as the locator for the
  # interview-mode question in gate-check.sh (q9_section, the stale-scaffold hint),
  # sync-project.sh (q9_current_text, q9_stale_scaffold_text, the append-if-missing guard) and
  # four places across tests/wave2/. Renumber it and sync stops finding it, concludes it is
  # missing, and appends a SECOND copy. Add new questions at 1-8; never renumber 9.
  mxtk_intake_template > "$INTAKE"
  echo "Created: intake.md"
fi

# Hoisted out of the PROJECT.md branch below. It used to be assigned only when
# PROJECT.md did NOT already exist, which is fine while the only reader is that
# same branch — but this scaffold is idempotent and re-run routinely, so on the
# second run the variable was simply unset. The leak-guard registration further
# down reads it, and an unset name there writes a bare `\b\b` to the denylist:
# a pattern that matches every file. Assign it once, unconditionally.
PROJECT_NAME="$(basename "$PROJECT_DIR")"

if [ -f "$PROJECT_MD" ]; then
  echo "Skip: PROJECT.md already exists — not overwritten."
else
  # Stamp the toolkit sha this scaffold was built from.
  #
  # This line used to read "(set at session start — see CLAUDE.local.md)", which no sha pattern
  # matches, so gate-check.sh's freshness check FAILed on a project that was seconds old and
  # every stage request exited 1. A brand-new project could not pass its own freshness gate
  # until a human performed the four-step ritual — the gate blocking the very state it exists
  # to certify. Stamping it here is correct rather than a workaround: at this instant the
  # project provably IS current, because these files were just generated from this commit.
  TOOLKIT_SHA="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "")"
  if [ -n "$TOOLKIT_SHA" ]; then
    TOOLKIT_COMMIT_LINE="Toolkit commit: $TOOLKIT_SHA"
  else
    # Not a git clone (a tarball install, say). Leave the prose, which still FAILs the freshness
    # check — correct here, because freshness genuinely cannot be established without a repo.
    TOOLKIT_COMMIT_LINE="Toolkit commit: (set at session start — see CLAUDE.local.md's session-start ritual)"
  fi
  cat > "$PROJECT_MD" <<EOF
# PROJECT.md — ${PROJECT_NAME} Decision Register

Every gate decision lands here as \`CONFIRMED\` or \`ASSUMED\`, never silently decided. See
\`conversion-runbook.md\` §1 for the interview protocol this file supports.

## Current stage

**Stage P — Kickoff**, in progress.

${TOOLKIT_COMMIT_LINE}

<!-- Where this project joins the pipeline: nothing recorded, so it starts at Stage P — the
     usual case. If work was already done outside the toolkit, record it once and the earlier
     stages report WAIVED instead of a red row nobody can clear:
       bin/gate-check.sh <project> --adopt 5 --reason "..."     every stage before 5
       bin/gate-check.sh <project> --waive 2 --reason "..."     just that one (one line per stage)
     Intake Q10 asks this. Never infer it from what happens to be on disk. (No example line is
     written out here on purpose: gate-check reads these labels back out of this file, and a
     sample value would waive stages in every project that never deleted it.) -->

## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.
EOF
  echo "Created: PROJECT.md"
fi

TRIAGE="$PROJECT_DIR/triage.md"
# ENTRY MODE IS NOT KNOWN HERE, and no prompt is added to find out.
#
# triage.md is migration-scoped (conversion-runbook.md, Stage 0: a documents-rather-than-codebase
# source skips it). But entry mode is intake QUESTION 1 — it is decided in the Stage P interview,
# which happens after this script runs, and the runbook is explicit that it is "a Stage-P
# interview decision, not a silent inference". Asking here would either duplicate Q1 or, on a
# TTY-less agent shell, answer it by default — which is the silent inference the runbook forbids.
#
# So the file is written unconditionally and says so in its own header: which entry modes it
# applies to, when to delete it, and — for the documents-only case — why deleting it is the wrong
# move (gate-check then reports "triage.md not found", an unanswered gate rather than a settled
# one; the runbook's documents-only path marks the extraction rows N/A instead).
#
# It cannot self-sign: the "Confirmed by:" line ships bracketed placeholders and check_stage_0
# refuses those explicitly. A fresh scaffold FAILS Stage 0, deliberately.
if [ -f "$TRIAGE" ]; then
  echo "Skip: triage.md already exists — not overwritten."
else
  mxtk_triage_template > "$TRIAGE"
  echo "Created: triage.md (Stage 0 scaffold — migration entry mode; see its header)"
fi

TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# docs/progress/RESUME.md — the file every generated entry point tells an agent to read FIRST.
# Written here so that instruction is true on a project that is two seconds old. Never
# overwritten: after the first close-the-loop this file is the project's own, and clobbering it
# on a re-run of init would destroy exactly the state it exists to carry.
RESUME="$PROJECT_DIR/docs/progress/RESUME.md"
if [ -f "$RESUME" ]; then
  echo "Skip: docs/progress/RESUME.md already exists — not overwritten."
else
  mkdir -p "$PROJECT_DIR/docs/progress"
  mxtk_resume_template "$TOOLKIT_ROOT" > "$RESUME"
  echo "Created: docs/progress/RESUME.md (starter — the first close-the-loop overwrites it)"
fi

CLAUDE_LOCAL="$PROJECT_DIR/CLAUDE.local.md"
if [ -f "$CLAUDE_LOCAL" ]; then
  echo "Skip: CLAUDE.local.md already exists — not overwritten."
else
  cat > "$CLAUDE_LOCAL" <<EOF
# CLAUDE.local.md — toolkit wiring (generated by init-project.sh)

## Wiring — single source of truth for all paths (agents read THIS block, not per-agent copies)

Every subagent resolves project paths from here. Keep it correct; refresh after a toolkit pull with
\`$TOOLKIT_ROOT/bin/sync-project.sh\`. Paths below are the toolkit conventions — **confirm each exists
at build time and correct any that differ**; a path that doesn't resolve is a wiring failure the
\`build-ready\` gate will catch.

| Key | Path | Notes |
|---|---|---|
| Toolkit root | \`$TOOLKIT_ROOT\` | The process authority |
| Toolkit commit | see \`PROJECT.md\` \`Toolkit commit:\` | Authoritative there; ritual keeps it fresh |
| Project MPR | \`$(ls "$PROJECT_DIR"/*.mpr 2>/dev/null | head -1 | xargs -r basename || echo "<name>.mpr")\` | The model file |
| MDL source dir | \`mdlsource/\` | Numbered build scripts |
| Module briefs | \`architecture/modules/<Module>/\` | one \`module-brief.md\` per module |
| Wireframes | \`design/wireframes/\` | one annotated HTML per screen |
| Design system | \`design/ds.css\` + \`design/design-system.html\` | tokens + component showcase |
| StyleGallery MDL | \`mdlsource/gallery/\` | or "not built yet" |
| Architecture | \`architecture/blueprint.md\` | blueprint + fit-gap |
| Build plan | \`architecture/build-plan.md\` | numbered, dependency-ordered |
| Business rules | \`analysis/<source>/knowledge-base/\` | BRDs (\`F<NNN>.brd.json\`) |
| UI review reports | \`design/ui-reviews/\` | \`ui-review-<date>.html\` (\`module-review.md\`) |

## Session-start ritual (before any pipeline work)

The toolkit's rules change; your memory of them is stale by default. At the start of every
session that will touch the pipeline:

1. \`git -C $TOOLKIT_ROOT pull --ff-only\`
2. \`$TOOLKIT_ROOT/bin/gate-check.sh <project-root>\` — it reports protocol freshness and
   tells you whether anything you depend on moved.
3. If it says an update is available, **you (the agent) handle it — never ask the user to type
   a command.** Run \`$TOOLKIT_ROOT/bin/gate-check.sh <project-root> --ack-protocol --verbose\`,
   which shows what changed and **records nothing**. Re-read the named files. Then tell the user
   in plain language what changed and what it means for what they are building, and ask whether
   to take the update. Only if they say yes:
   \`$TOOLKIT_ROOT/bin/gate-check.sh <project-root> --ack-protocol --approved-in-chat\` — that
   rewrites the \`Toolkit commit:\` line in \`PROJECT.md\` and records which files, how many
   lines, and that it was approved in chat, in \`docs/BUILD-LOG.md\`.
4. State in chat which commit you're working from.

An ack asserts a human was told what changed, so it cannot happen unattended: without a TTY and
without \`--approved-in-chat\` it refuses and names the routes out. \`--approved-in-chat\` is a
claim you are making on the record — set it only after you actually asked and they actually
answered. There is no env-var auto-yes.

By default the output is written for whoever is in the room, not for a maintainer: plain
language, no commit ids, no file paths. Add \`--verbose\` for the ids, paths and diffstat.

**Protocol staleness NEVER blocks a gate.** It prints a notice with lettered options and the
stage verdict is reported on its own merits either way — a project is not broken because
someone else pushed to a shared repo. CI that genuinely wants the old behaviour opts in with
\`--strict-protocol\`.

## The toolkit is the process authority

This project uses the shared toolkit at \`$TOOLKIT_ROOT\`. For ANY pipeline work
(analysis, BRDs, architecture, design, build plan, build, test, cutover):

1. **Read \`$TOOLKIT_ROOT/skills/conversion-runbook.md\` FIRST — every session.** It is the
   executable spec. The toolkit README and toolkit-guide.html are orientation only; stage
   summaries anywhere are routing, not deliverable lists.
2. **Before producing any stage artifact, open that stage's owning skill** and follow its
   full output list (e.g. Stage 3 design work = \`design-artifacts.md\`, incl. one wireframe
   per screen — not just a design system).
3. **Every gate question is asked in chat, then the turn ends and waits** (runbook §1).
   \`ASSUMED\` is earned by asking — the user said "you decide" — never by skipping.
4. **Before calling a stage done:** \`$TOOLKIT_ROOT/bin/gate-check.sh <project-root> <stage>\`.

EOF
  echo "Created: CLAUDE.local.md (runbook-first wiring + baseline routing)"
  # Baseline routing is appended here, not carried in the heredoc above: one table
  # (bin/lib/skill-routing.tsv), rendered by one function, so a skill added to the table
  # reaches a brand-new project and every existing one (via sync-project.sh) alike.
  routing_sync_claude_local "$CLAUDE_LOCAL" "$TOOLKIT_ROOT" || true
fi

# One-command install: agents are scaffolded here too, not as a separate step.
"$SCRIPT_DIR/init-agents.sh" "$PROJECT_DIR" all

# ── Crash net ────────────────────────────────────────────────────────────────
# The guard-chain scripts are PROJECT-LOCAL: they are invoked as ./bin/exec.sh
# from the project root, resolve that project's .mpr, and call its ./mxcli. So
# they are installed into the project rather than run from the toolkit, the same
# way the agent stubs are.
#
# They were cited by README, the runbook and toolkit-guide.html for months while
# shipping nowhere — every project either hand-rolled them or went without a
# snapshot/restore net entirely. Installing them here is what makes those
# citations true.
#
# Existing files are NOT overwritten: a project may have locally hardened its
# copy, and clobbering that on a re-run of init/sync would be its own incident.
CRASHNET_SRC="$SCRIPT_DIR/../project-bin"
if [ -d "$CRASHNET_SRC" ]; then
  mkdir -p "$PROJECT_DIR/bin"
  # List from bin/lib/install-manifest.sh — the same one sync-project.sh installs from.
  for s in $MXTK_PROJECT_BIN; do
    if [ -f "$PROJECT_DIR/bin/$s" ]; then
      echo "Kept (already present): bin/$s"
    elif [ -f "$CRASHNET_SRC/$s" ]; then
      cp "$CRASHNET_SRC/$s" "$PROJECT_DIR/bin/$s"
      chmod +x "$PROJECT_DIR/bin/$s"
      echo "Created: bin/$s"
    fi
  done
fi

# ── Verification engine (tests/e2e/) ─────────────────────────────────────────
# The other half of the crash net above, and it never travelled: project-bin/verify-module.sh
# HAS been installed for weeks and it DRIVES project-tests/e2e/journey-runner.js, which existed
# in exactly one project. A conductor and no orchestra — on a fresh project verify-module.sh's
# first runtime rung exits 2 and the whole gate reads as fault, i.e. the harness reporting
# itself broken. Four skills cite tests/e2e/* paths and skill-routing.tsv routes verify-module.sh
# as a BASELINE skill for stages 5-6, so every one of those citations was false here.
#
# Separate script rather than another loop, because these are .js into a nested directory while
# the loop above copies flat shell scripts into bin/. install-tests.sh is idempotent by the same
# contract as the crash net: a file the project has already changed is KEPT and reported, and
# project.config.js — the one file a project is expected to edit — is written only when absent,
# even under --force. tests/e2e/artifacts/ is run output and is never named by the manifest, so
# it is never touched.
if [ -x "$SCRIPT_DIR/install-tests.sh" ]; then
  "$SCRIPT_DIR/install-tests.sh" "$PROJECT_DIR" || {
    echo "Verification engine did not install. The scaffold is otherwise fine; re-run:"
    echo "  $SCRIPT_DIR/install-tests.sh $PROJECT_DIR"
  }
fi

# ── Agent wiring ─────────────────────────────────────────────────────────────
# Every AI coding agent gets the same entry point, not just Claude. Until this
# call existed, init-project.sh wrote CLAUDE.local.md and stopped, so a project
# opened in Copilot/Cursor/Windsurf had no routing at all: it found PROJECT.md,
# read a 60k decision register as an orientation doc, and guessed at next steps.
#
# wire-agents.sh is idempotent and preserves any file that already exists, so a
# re-run of init on a live project cannot clobber a hand-tuned CLAUDE.md.
# opencode and vibe are NOT included by default — they cannot use a pointer file
# and cost ~54k lines of duplicated skills each. Opt in with --with-skill-copies.
"$SCRIPT_DIR/wire-agents.sh" "$PROJECT_DIR" || {
  echo "Agent wiring did not complete. The scaffold is otherwise fine; re-run:"
  echo "  $SCRIPT_DIR/wire-agents.sh $PROJECT_DIR"
}

# ── Starlark lint rules ──────────────────────────────────────────────────────────────────
# mxcli seeds .claude/lint-rules/ with its own copies; three of them are broken as shipped
# (two match no entity at all and report a clean pass forever). Install the toolkit's fixed
# versions over the stock ones, and conv020 — which mxcli does not ship — alongside them.
# Nothing a human edited is overwritten: see bin/lib/install-lint-rules.sh.
#
# THIS MUST RUN AFTER wire-agents.sh. That script runs `mxcli init`, and `mxcli init` re-seeds
# .claude/lint-rules/ from stock without asking — wire-agents.sh's PRESERVE list covers
# AGENTS.md and CLAUDE.md but not the rules directory. This call used to sit ABOVE the wiring,
# so every freshly scaffolded project ended up with all three repaired rules reverted to stock,
# and two of those report a clean pass forever in that state (lint-rules/README.md). Silent, and
# a fresh project's very first lint run was already lying. Measured on a scaffold produced by
# this script, 2026-08-19: all three differed from the toolkit copies.
#
# Running last is a real fix, not a race: install-lint-rules.sh classifies a stock-reverted rule
# explicitly ("REVERTED TO STOCK — `mxcli init` overwrote the toolkit version") and restores it,
# while still refusing to clobber anything a human edited.
mxtk_install_lint_rules "$(cd "$SCRIPT_DIR/.." && pwd)" "$PROJECT_DIR" 0 ""

# --- sources/ drop folder ----------------------------------------------------------------
#
# Intake Q1 and Q2 ask what is being migrated and where the source lives, and until now the
# scaffold gave it nowhere to go — so a Copilot dry run (2026-08-19) invented `source/`,
# singular, which nothing in the toolkit matches. `sources/` is the name the toolkit's own
# .gitignore already uses; picking it here is what stops the two spellings from both existing.
#
# Idempotent in the way that matters: an existing sources/ is never touched, and the README is
# only written when it is absent, so a user who replaced it with their own notes keeps them.
SOURCES_DIR="$PROJECT_DIR/sources"
if [ -d "$SOURCES_DIR" ]; then
  echo "Skip: sources/ already exists — not touched."
else
  mkdir -p "$SOURCES_DIR"
  echo "Created: sources/"
fi

# analysis/ — THE OUTPUT SIDE, and it was never scaffolded (fixed 2026-08-20).
#
# Every rendered surface in the pipeline lands here: triage.html (bin/triage-report.sh),
# source-sufficiency.html, brd-report.html (bin/brd-report.sh), open-questions.html. gate-check.sh
# resolves $ANALYSIS_BASE against it. sources/ was created here from day one; analysis/ was not,
# on the unstated assumption that an extraction pipeline would `mkdir -p` it on its way past.
#
# That assumption holds for exactly one entry mode. A requirements-driven or greenfield project
# runs no pipeline, so nothing ever created the folder, so every surface the runbook promises had
# nowhere to be written — reported from a customer round on 2026-08-20, where the absence of
# analysis/ was the first visible symptom of a much larger hole (Stage 0 being skipped entirely).
# The folder is cheap and mode-independent; the pipeline it was waiting on is not.
ANALYSIS_DIR="$PROJECT_DIR/analysis"
if [ -d "$ANALYSIS_DIR" ]; then
  echo "Skip: analysis/ already exists — not touched."
else
  mkdir -p "$ANALYSIS_DIR"
  echo "Created: analysis/"
fi

if [ -f "$ANALYSIS_DIR/README.md" ]; then
  echo "Skip: analysis/README.md already exists — not overwritten."
else
  cat > "$ANALYSIS_DIR/README.md" <<'EOF'
# analysis/

Generated analysis output and every customer-showable surface the pipeline renders. Unlike
`../sources/`, nothing here is hand-authored — each file has a script or skill that produces it,
and the honest way to change one is to re-run its producer.

| File | Produced by | Stage |
|---|---|---|
| `source-sufficiency.html` | `bin/source-sufficiency.sh report` | 0 |
| `triage.html` | `bin/triage-report.sh <project>` | 0 |
| `extraction-report.html` | the extraction pipeline, or `kb-generation.md` for a document corpus | 1 |
| `brd-report.html` | `bin/brd-report.sh <project>` | 2 |
| `open-questions.html` | `bin/questions-report.sh <project> --stage N` | any gate |

**This folder exists in every entry mode.** A requirements-driven or greenfield project runs no
extraction pipeline, but it still produces a sufficiency grade, a scope decision and a BRD report
— `bin/brd-report.sh` reads BRDs, not source, so the Stage 2 surface is the same page whatever
wrote the BRDs.

**Where the knowledge base goes:** under `analysis/<source-name>/knowledge-base/`, not at the top
level, so a project with two source systems keeps them apart. `bin/lib/discover-brds.sh` is the
one thing that resolves that path — never hardcode it.
EOF
  echo "Created: analysis/README.md"
fi

if [ -f "$SOURCES_DIR/README.md" ]; then
  echo "Skip: sources/README.md already exists — not overwritten."
else
  cat > "$SOURCES_DIR/README.md" <<'EOF'
# sources/

Drop the legacy application source here — one subfolder per source system.

```
sources/
  outsystems-export/     # .oml / .osp exports, or an unpacked OS 11 XML tree
  legacy-api/            # a clone or copy of the backing service
  docs/                  # specs, BRDs, screenshots, anything the SME hands over
```

**What this folder is for:** it is the input to Stage 0 triage. Nothing here is read
automatically — `skills/source-triage.md` decides what is in scope, and only then does an
extraction pipeline run against it.

**Where it is declared:** intake questions 1 and 2 (`../intake.md`) record *what* is being
migrated and *where* it came from. Keep those answers and this folder in agreement; if the
source lives outside this workspace (a network share, a client VPN clone), say so in Q2
rather than symlinking it in.

**Version control:** whether this folder is committed was decided at scaffold time — check
`../.gitignore`. Source drops are routinely large and frequently belong to the client, so the
default is to ignore them.
EOF
  echo "Created: sources/README.md"
fi

# Gitignore decision. Only relevant if the project is (or becomes) a git repo, but writing the
# entry unconditionally is harmless and survives a later `git init`.
GITIGNORE="$PROJECT_DIR/.gitignore"
if [ -f "$GITIGNORE" ] && grep -qE '^/?sources/?$' "$GITIGNORE"; then
  echo "Skip: sources/ already listed in .gitignore."
else
  case "$SOURCES_MODE" in
    ask)
      if [ -t 0 ]; then
        printf 'Add sources/ to .gitignore? Source drops are often large and client-owned. [Y/n] '
        read -r _reply || _reply=""
        case "$_reply" in
          [Nn]*) SOURCES_MODE="track" ;;
          *)     SOURCES_MODE="ignore" ;;
        esac
      else
        # No TTY (CI, a piped run, an agent shell). Ignoring silently would be a decision made
        # on the user's behalf without telling them, so it is made loudly instead.
        SOURCES_MODE="ignore"
        echo "No TTY — defaulting to gitignoring sources/. Re-run with --track-sources, or"
        echo "  remove the 'sources/' line from .gitignore, to commit the source drop instead."
      fi
      ;;
  esac

  if [ "$SOURCES_MODE" = "ignore" ]; then
    if [ -f "$GITIGNORE" ] && [ -s "$GITIGNORE" ] && [ -n "$(tail -c 1 "$GITIGNORE")" ]; then
      printf '\n' >> "$GITIGNORE"
    fi
    printf '# Legacy source drop — see sources/README.md\nsources/\n' >> "$GITIGNORE"
    echo "Created/updated: .gitignore (sources/ ignored)"
  else
    echo "sources/ will be tracked by git — not added to .gitignore."
  fi
fi

# ---------------------------------------------------------------------------
# Register this project's name with the toolkit's leak guard.
#
# Scaffold time is the ONE moment the toolkit knows a project's name for
# certain. bin/check-no-client-data.sh hard-fails when .leakguard-deny is
# ABSENT, but has no way to notice one that is merely STALE — and a stale
# denylist reports "✅ no client data detected" just as confidently as a
# correct one.
#
# Real incident, 2026-08-20: .leakguard-deny was last edited on 5 Aug and held
# 19 patterns. Five projects started after that date. None of their names were
# in it, so ~200 occurrences across ~41 tracked files passed every pre-commit
# run in a PUBLIC repo. The guard was working perfectly; it was looking at the
# wrong list. Capturing the name here is the fix — a "is the denylist stale?"
# heuristic inside the guard would only be guessing.
#
# .leakguard-deny is gitignored by design (a tracked denylist publishes exactly
# the names it exists to suppress — the 2026-08-03 finding), so this writes to
# the toolkit CLONE, never to the project, and never to anything committed.
DENYFILE="$TOOLKIT_ROOT/.leakguard-deny"
if [ -w "$TOOLKIT_ROOT" ]; then
  # Dedupe with a FIXED-STRING search, not a regex one. The obvious version —
  # matching the name with `[^A-Za-z0-9]` boundaries — never fires, because the
  # stored form is `\bName\b` and the character immediately before the name is
  # the `b` of `\b`, which is alphanumeric. Every re-run appended a duplicate.
  # -F also removes any need to escape names containing `.`, `+` or `-`.
  if [ ! -f "$DENYFILE" ] || ! grep -qiF -- "$PROJECT_NAME" "$DENYFILE" 2>/dev/null; then
    {
      [ -f "$DENYFILE" ] || printf '# Leak-guard denylist — gitignored. See bin/check-no-client-data.sh header.\n'
      printf '\\b%s\\b\n' "$PROJECT_NAME"
    } >> "$DENYFILE" 2>/dev/null && {
      echo ""
      echo "Registered \"$PROJECT_NAME\" with the toolkit leak guard ($DENYFILE)."
      echo "  The guard will now refuse any toolkit commit that mentions it by name."
      echo "  If you also need variants (a client name, a codename, an internal host),"
      echo "  add them there — one extended-regex pattern per line."
    }
  fi
else
  # Not fatal — a read-only toolkit clone is a legitimate setup — but say so,
  # because the alternative is a name silently outside the guard's view.
  echo ""
  echo "NOTE: could not register \"$PROJECT_NAME\" with the toolkit leak guard"
  echo "  ($TOOLKIT_ROOT is not writable). Add \\b$PROJECT_NAME\\b to"
  echo "  $DENYFILE by hand, or this project's name is invisible to the guard."
fi

GUIDE="$SCRIPT_DIR/../toolkit-guide.html"
# First-touch sentinel. This is the same file every agent must test before opening the guide
# (see CLAUDE.md "First-touch rule"); writing it here is what stops the next session — and the
# one after that — from opening a browser tab the user has already seen.
GUIDE_SENTINEL="$PROJECT_DIR/.claude/.guide-shown"
if [ -f "$GUIDE" ] && [ -z "${MXTK_NO_GUIDE:-}" ] && [ ! -e "$GUIDE_SENTINEL" ]; then
  # Best-effort auto-open of the visual guide; never fail the scaffold over it.
  # Suppress with MXTK_NO_GUIDE=1 (e.g. headless/CI runs).
  if command -v open >/dev/null 2>&1; then open "$GUIDE" || true
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$GUIDE" >/dev/null 2>&1 || true
  fi
  # Record it even if the open failed: a browser we could not launch is not a reason to
  # re-prompt forever, and the user can always ask for the guide by name.
  mkdir -p "$(dirname "$GUIDE_SENTINEL")" 2>/dev/null || true
  : > "$GUIDE_SENTINEL" 2>/dev/null || true
  echo ""
  echo "Opened the visual guide in your browser (toolkit-guide.html) — it explains the stages,"
  echo "the gates, and what happens when something looks broken. Set MXTK_NO_GUIDE=1 to suppress."
  echo "Recorded .claude/.guide-shown, so later sessions will not reopen it. Delete it to see it again."
fi
echo ""
echo "Next steps (not done by this script):"
echo "  - Complete each agent stub's {{PLACEHOLDER}}s per skills/agent-roles.md when its stage"
echo "    starts (ba/architect at Stage P kickoff, mdl/gate/test at Stage 5). Stubs refuse to"
echo "    run until completed, so a half-setup fails loudly instead of silently."
echo "  - Stage 0 triage: choose/reuse an extraction pipeline (needs triage first, see source-triage.md)."
echo "  - Optional, NOT installed by this script: the context-cost hooks. They are user-global —"
echo "    they fire in every repo on this machine — so installing them is your explicit choice."
echo "    Read README.md \"Context cost\" first (the numbers are the point), then:"
echo "      bin/install-claude-hooks.sh          # prints the tier table, installs nothing"
echo ""

"$SCRIPT_DIR/gate-check.sh" "$PROJECT_DIR" || true

echo "Done. index.html dashboard rendered at $PROJECT_DIR/index.html"
