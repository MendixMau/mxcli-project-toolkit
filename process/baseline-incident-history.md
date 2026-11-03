# Baseline incident history — the full stories behind the always-on rules

**Read on demand, never at session start.** The always-on (baseline) skills state each rule
with a one-line failure example and a pointer here. This file holds the long form: the
incident narratives, measurements and design history that used to sit inline in those skills,
moved verbatim so the evidence survives while the baseline stays inside the
`bin/render-routing.sh --check` word budget (CLAUDE.md skill-authoring rule 6, "write for the
trigger, then stop").

Each section id (`R1`, `ST1`, …) is what the pointer in the skill cites. The section text is
the original wording, unedited — when a rule's justification is challenged, cite from here.
Nothing in this file is a rule on its own; the rule lives in the skill that points here.

## R1 — Entry-mode misrouting incidents

_From `skills/conversion-runbook.md`._

(Real misrouting incident, 2026-07-14: a project with full specs + analyzable source was classified greenfield "because there's nothing to migrate," proposing to skip 0–4 — exactly what rules 2–3 exist to prevent. Second incident, 2026-09-22: `intake.md` Q1 offered only three modes, so a session changing a live app could not pick the fourth even though `gate-check.sh` already recognised it — rule 1 and the table row below are the fix.)

## R2 — Why Stage 0 runs in every entry mode (2026-08-20)

_From `skills/conversion-runbook.md`._

This distinction was implicit until 2026-08-20, when a customer round made the cost of leaving it
implicit measurable. A project whose source was markdown files plus database tables was classified
requirements-driven — reasonably, given the rules above. The mode's row then said "skip 0", so
Stage 0 was skipped **whole**: no source characterisation, no `analysis/` folder, no triage
artifact, and — the expensive one — **no scope conversation**, because CAC-1 fires after Stage 0
and Stage 0 never ran. Extraction was then run anyway and pulled in far more than the subsystems
under discussion, which nothing downstream was positioned to notice: Stage 2's gate checks that
BRDs are *validation-clean*, and a hundred clean BRDs describing things nobody asked for pass it.

## R3 — Why the docs-ready path exists (2026-09-09)

_From `skills/conversion-runbook.md`._

**Why this path exists (2026-09-09).** A project of exactly this shape was slow and token-hungry
through Stages 1–4, for measured reasons: every session read the raw HTML (3–10× the tokens of
its text), and the ledger asked for one disposition per file — every sidecar `.png`, `.css` and
`.js` included — for a corpus nothing extracts. Nothing below skips a gate; it names the shortest
honest route through them, and every command here was run against the gates before it was written.

## R4 — The accumulated open-questions stream that rotted (2026-08-12)

_From `skills/conversion-runbook.md`._

**The gate's own questions are not the only questions — raise the accumulated batch too.** Steps 1–6 govern the questions the *gate* asks. But the pipeline generates a second stream all the time: every `openQuestions` entry a BRD records, every row added to `analysis/sme-questions.md`. Those were never wired to anything, and they rotted. Measured on one real project (2026-08-12): 46 rows in `sme-questions.md` against 7 mentions of an answer, ~35 unresolved BRD `openQuestions`, one status reading *"Open — routed to sme-questions.md F1/F2"* — routed to a file nobody opens. Several were not merely unasked but already **decided**: *"ASSUMED drafting position (a), hardcode — taken to keep this BRD buildable… NOT a settled product decision"* is a real product choice (hardcode vs. build a configurable rules engine) taken unilaterally and never shown to anyone. And 23 distinct free-text status strings meant nothing could count them, which is why nothing ever surfaced them.

## R5 — Attended run with no questions (2026-07-14)

_From `skills/conversion-runbook.md`._

(Real incident, 2026-07-14: an attended run produced architecture diagrams and a design system through Stage 3 without a single question reaching the user — "a solo run never stalls" was read as "never ask." It means "an *authorized* solo run doesn't deadlock," nothing more.)

## R8 — Settled change routed through three subagents (2026-07-23)

_From `skills/conversion-runbook.md`._

(Real incident, 2026-07-23: a "flip 2 entities to persistent + add 2 new entities" change — already fully settled in conversation — was routed through ba-agent twice and architect-agent once, ~270k combined tokens, for what was fundamentally a handful of document edits. The user called it out directly. The fix isn't skipping the record, it's skipping the dispatch when there's nothing left to decide.)

## R9 — Gate script never run through a full Stage 5 (2026-09-19)

_From `skills/conversion-runbook.md`._

**Why (measured, 2026-09-19, two field builds of the same app).** A full Stage-5 build closed with all seven screens built, a green mxbuild
   gate, and 11 of 37 acceptance rows confirmed. `gate-check.sh` had run exactly once, at
   scaffold time. The `look` obligation, the wiring sweep, journeys and coherence were all
   `PENDING` and nobody saw it, because nothing asked. When the gate was finally run as a
   deliberate second pass, the seven screens scored 0, 18, 40, 40, 58, 58 and 69 percent against
   their own wireframes on an element checklist — one screen matched none of its wireframe's
   elements at all. Every one of those defects was visible to a gate that never ran.

## R10 — Why dispatch is written down (2026-09-14)

_From `skills/conversion-runbook.md`._

**Why this is written down (2026-09-14).** The six agent stubs have carried model tiers since
they were generated (`architect-agent` on the strong tier, the other five on the mid tier), and
§2's Owner rows name who is accountable for each stage. Nothing said *when* the main session
hands work over — so in the token-path A/B (nine runs, Stages P–4) the main session did nearly
everything itself, at its own model's price, and only two skills (`brd-generation.md`,
`image-transcription.md`) ever asked for a fan-out. Owner is accountability; this table is the
runtime rule.

## R12 — Checkpoints named nowhere in the runbook (until 2026-08-20)

_From `skills/conversion-runbook.md`._

**Every stage transition has a packaged checkpoint. Here is where they attach.** The `skills/checkpoints/`
CAC files run the §1 interview protocol at the busiest transitions; they write to `PROJECT.md`,
never to a separate state file. Until 2026-08-20 this runbook — the file every session is required
to read — **named none of them**, and they were reachable only from `skills/migration-pipeline.md`.
A requirements-driven session never loads that skill, so it never fired a single checkpoint, and
CAC-1's scope brainstorm silently did not exist outside migration mode. Checkpoints are wired to
*stages* here, not to pipeline phases, precisely so that a project running no pipeline still gets
them.

## R16 — Grade before inventory: a rubric question instead of a scope conversation (2026-08-19)

_From `skills/conversion-runbook.md`._

Doing this out of order is a real, reported failure (2026-08-19): a Stage 0 run on a four-file
documents-only corpus produced a correct ten-dimension grade and then asked the user a closed,
rubric-shaped gate question — because the grade was the only artifact in front of it. The
instruction to present a source map already existed here; nothing produced the map, so the agent
asked what the tooling gave it something to ask about.

## R17 — Documents plus a database misrouted as prose (2026-08-20)

_From `skills/conversion-runbook.md`._

(The paragraph below followed "Does not apply stops at the extraction rows" and restated the rule of the preceding "Decide that on evidence" paragraph; it was merged into that paragraph.)

**A source that is documents plus a database is not a documents-only source.** A schema, a table
dump, or an ORM model file is extractable structure and grades as such — the presence of markdown
alongside it does not downgrade it. This is the shape that misroutes most often in presales
(2026-08-20): the corpus *reads* like requirements, so it gets treated as prose, and the entities
that were sitting right there in the schema get re-derived by hand later.

## R18 — Why CAC-1b exists: extraction over-reach (2026-08-20)

_From `skills/conversion-runbook.md`._

**Closes with CAC-1b** (`skills/checkpoints/checkpoint-extraction.md`) — the scope-out
confirmation. It is a checkpoint you run, not a gate that stops you, and the reason is worth
keeping in front of you.

Stage 0 confirms scope *in*: what we intend to cover. It cannot confirm scope *out*, because
nobody knows what extraction will actually produce until it has produced it. On the customer round
that prompted this, extraction ran across the whole corpus rather than the subsystems under
discussion, and the over-reach was invisible until modules were being built — every downstream
gate measured *quality*, and the output was perfectly good BRDs about the wrong things. A
validation-clean BRD for a subsystem nobody asked for is a clean pass at every remaining gate in
this runbook.

So before any BRD is written: put the extraction result next to the Stage 0 scope decision, name
the delta, and get a decision on it. Do it before the BRDs rather than after — writing them first
makes narrowing feel expensive, which is exactly when people stop narrowing.

**Nothing enforces this and nothing should.** A script can only check that a `CONFIRMED` row
exists in `PROJECT.md`, and an agent can type that row without asking anyone — so the check
cannot tell the conversation from the string, which is the only thing worth telling apart. (A
blocking version of this gate existed for part of 2026-08-20 and was removed the same day; see
`skills/skills-over-scripts.md`.) If the checkpoint gets skipped, run it late against the BRD set
you already have — with the extraction report in hand you can see what actually came out, which
is better input than the triage map ever was.

## R19 — Stage 1 surface history (until 2026-08-20)

_From `skills/conversion-runbook.md`._

Until 2026-08-20 this was `node generate-report.js` inside each pipeline, so requirements-driven and greenfield projects could not produce the file their own Stage 1 gate requires, despite this row promising it.

## R20 — Stage 2 surface history (until 2026-08-19)

_From `skills/conversion-runbook.md`._

Until 2026-08-19 this was `enrichment-summary.html`, built three times inside three pipelines against three different BRD key shapes — each copy rendered blanks for the other two’s output, and non-migration projects got no surface at all despite this row promising one.

## AR1 — "Five" agents, and the review that never looked (2026-08-20)

_From `skills/agent-roles.md`._

> **This file said "five" until 2026-08-20, and that cost the review.** `review-agent` — the owner
> of `module-review.md` stage 4, the LOOK — has been scaffolded by `bin/lib/install-manifest.sh`
> and routed to its skills for some time, but this file never listed it. So every session that set
> agents up "per `agent-roles.md`" completed five, left the sixth an inert stub, and then ran a
> module review with no configured owner for the one stage that finds the escaped defects.
> Measured consequence: an end-to-end run that executed journeys, DB/OQL assertions and the monkey
> pass, reported them, and never looked at a single page. **The count is load-bearing. It is six.**

## ST1 — "Already used as triage input" — the deck nobody read (2026-09-02)

_From `skills/source-triage.md`._

> **A claim that another document already handled a file is a claim to verify, not an
> answer.** Real incident, 2026-09-02, a VBA migration: intake Q4 ("documents not yet accounted
> for?") was closed with *"the .pptx is already inside `source/` and was already used as triage
> input by the Group A–D triage pass"*. The triage was derived from the `.cls` exports and never
> named the deck; its 22 diagrams — the only place the workflow engine's X/M/E semantics were
> written down — went unread for two months of BRDs, blueprint and build plan, and a `CONFIRMED`
> architecture decision had to be reversed. The wrong answer *reads* right because it cites a
> document. The right form is the ledger's: **name the artifact, and let the gate grep it.** A
> text read of a deck is not the deck either — a 25-slide, 22-image container is consumed when
> the disposition says `--pages 25 --media 22`, not when its title appears in a summary.

## ST2 — Mixed corpora routed wholesale down the document path

_From `skills/source-triage.md`._

Mixed corpora are where this goes wrong, and they are the normal case in presales. The folder
*reads* like requirements, so the whole thing is sent down the document path (`kb-generation.md`,
Path B) and comes back as prose — including the entities that were sitting in the schema, which
then get re-derived by hand three stages later. Prose is the right reading method for prose and
the wrong one for structure. Choosing per artifact is this step's job; routing a whole corpus by
how it looks at a glance is the failure it exists to prevent.

## ST3 — Field evidence for read-vs-parse: one export, one spec, one inventory (2026-09-07)

_From `skills/source-triage.md`._

**Field evidence, 2026-09-07** — a no-code app replacement whose corpus was one data export
(`.ods`), one 3.5 MB reverse-engineering spec (`.html`) and one workflow inventory (`.md`):

- The **export parser corrected the documents written about it**: 53 stored columns against
  128–175 documented (~120 are computed in the platform — neither attributes to model nor data to
  migrate), four different spellings of one foreign key across four sheets, 15 sheets where the
  spec documented 17, plus per-sheet volumes. No reading of any document produces one of those.
- A **regex classifier over the spec's prose scored ~50% precision and ~50% recall** against a
  user-confirmed sample, and was deleted the same day. It read the spec's "what the recording
  covered" bullets as requirements, truncated sentences at inline HTML tags, and matched none of
  the negative-form statements ("there is no role model", "no reminders, no escalation") that
  carried some of the sharpest requirements in the document. The same agent's plain read of the
  same file, at intake, was better in one pass.
- The user's question is the rule in one line: *"do we need an extractor for html & md files?
  Can't we just analyse and conclude what it should be? But when it's ppt and images better yes?"*

## ST4 — Why "both, not either" is spelled out (2026-09-07)

_From `skills/source-triage.md`._

**Why this is spelled out (2026-09-07).** `conversion-runbook.md`'s Stage-0 applicability table
said the extraction call was **`N/A` for requirements-driven**, flatly — while this skill and the
shipped `triage.md` header said `N/A` only where the corpus holds no extractable structure, "on
evidence, never on the entry-mode label". The runbook is the file every session is required to
read first, so the unconditional version was the one that got followed. On the project that
surfaced it — requirements-driven, corpus of one spec, one workflow inventory and **one platform
data export** — following the runbook literally would have marked extraction `N/A` and left the
export unparsed. That parser went on to correct the very documents written about the app: 53
stored columns against 128–175 documented, four spellings of one foreign key across four sheets,
15 sheets where the spec said 17. Same shape as the `toolkit-guide.html` first-touch incident in
`CLAUDE.md`: a rule stated conditionally in its owning file and unconditionally in the front
door, where the front door wins. The runbook now defers here.

## IP1 — Branding question batch-approved as a recommended default (2026-08-19)

_From `skills/interview-protocol.md`._

*Real incident, 2026-08-19 (PROJECT-B).* "Are there branding inputs?" went in as line 7
of a seven-item Stage 3 gate batch, carrying the recommended default *"no branding assets
provided — use Atlas defaults."* The user approved the batch. There was in fact a real art
direction — top-bar layout, industrial look, grey background, cool colours, the client wordmark in
the shell — and a WCAG 2.1 AA target, and neither had ever been asked for. Both surfaced only
when the user challenged the finished design system and asked why nobody had checked. The
question had been treated as a `gap`. The recommendation was the entire defect: it converted
"I don't know" into "I've decided", and a batch approval swallowed it.

## IP2 — "AskUserQuestion doesn't seem installed" — the Copilot dry run (2026-08-19)

_From `skills/interview-protocol.md`._

*Why this is spelled out (real incident, 2026-08-19).* A dry run of this toolkit on GitHub
Copilot on Windows produced the question *"AskUserQuestion doesn't seem installed, is that
something we can include in the setup?"* It cannot be. Until then every call site here named
the tool as **the** mechanism, so on a non-Claude agent the instruction was simply
unfollowable — and an unfollowable gate is not a loud failure, it is a silent skip. Same shape
as the Stage P false-green: the enforcement quietly evaporates and nothing says so.

## IP3 — "X already covers this" — the verbatim intake answer (2026-09-02)

_From `skills/interview-protocol.md`._

Verbatim, from a real intake (2026-09-02, Q4 "documents not yet accounted for?"):

> the `.pptx` is already inside `source/<track>/` and was already used as triage input by the
> Group A–D triage pass (see `<track>-triage.md`) — nothing additional exists outside the folder.

The triage never named the deck. Two months of downstream artifacts inherited the gap, because
once Q4 read "answered" nothing had a reason to look again. The answer *cited a document*, which
is exactly why it was believed.

## UI1 — Design system ported, never reached the app (2026-09-09)

_From `skills/ui-preflight-pages.md`; moved verbatim 2026-10-14._

Measured 2026-09-09: 55 tokens were ported into the right file at the right stage, 0 of 35
framework knobs were bound, 0 of 20 component classes existed in the built stylesheet, and two
build phases of pages were written on top of it. The pages were structurally correct. `mx
check`, `mxcli lint`, the MDL suite and two e2e journeys were all green, because none of them
reads a stylesheet. It was found by a human opening a screenshot and asking why the UI was
poor. The three failures were a bridge written against the wrong layer (SCSS variables where
the theme runs `$use-css-variables: true`), component classes never ported at all, and a theme
module whose `:root` loses the cascade to the framework's own customization file.

## UI2 — First-build page fidelity, ToeicBuddy field run (2026-08-25/26)

_From `skills/ui-preflight-pages.md`; moved verbatim 2026-10-14._

**Measured, ToeicBuddy field run 2026-08-25/26** (`process/first-build-page-fidelity-2026-08-27.md`):
first-build fidelity across 10 pages was **32% median** against a target of 80%. All 14
wireframes declared a 900px page column and **0 of 10** pages capped their width — repaired
wholesale at script 67, fifty-five scripts later, after rendering at 1360px. All 10 were
built on a sidebar layout against wireframes drawing a top bar — repaired at script 20.
The script's header carries the full evidence for each check.

## UI3 — Fidelity score vs. element checklist, seven screens (2026-09-19)

_From `skills/ui-preflight-pages.md`; moved verbatim 2026-10-14._

**A fidelity score is not a LOOK pass, and must never be accepted as one.**
`page-fidelity.js` matches identifiers in the page MDL against the wireframe's text. It
cannot see where an element sits, only that the name occurs. Measured on a
field build of 2026-09-19, scoring
seven screens both ways on the same commit:

| Screen | Fidelity (text match) | Element checklist (present / placed / behaves) |
|---|---:|---:|
| S1 Requests overview | 100% | 58% |
| S4 Approval queue | 100% | 40% |
| S3 Request detail | 55% | 69% |

Two screens scored a perfect 100 while missing more than half their wireframe: the elements
were named in the MDL and laid out wrongly. S3 runs the other way, because its grid's decimal
formatting is not expressible as text the instrument greps for. So a high fidelity score
closes nothing — the `look` obligation is discharged by a person or an agent opening the
rendered page, at 1280px and at 390px, and writing down what it saw. Use the fidelity score
for the rework curve between LOOK passes, never in place of one.

## UI4 — Controlled A/B, and the build script that cited Step 3 (2026-08-31)

_From `skills/ui-preflight-pages.md`; moved verbatim 2026-10-14._

**Measured again, controlled A/B, 2026-08-31** (`process/preflight-skill-baseline-2026-08-31.md`):
5 fresh drafting agents with this file inlined produced **zero** judgement-step violations
(layout, H1, inline styles, invented classes) across all 5 reps; 5 without it reproduced every
field defect. The content works when read — the failure mode is dispatching a page build with
a *reference* to this file instead of its text (see the delivery rule at the top).

The build script that produced those pages **cited this file's Step 3 by name**. That is
the point: the pre-flight was run, and its output was a paragraph nobody could fail. A
shell defect is uniform across every page built the same way, so no page stands out as a
diff and per-page review does not surface it — which is exactly what a mechanical check
is for, and exactly what human judgement is worst at.

## TO1 — Three false findings from one session (2026-07-29)

_From `skills/tool-output-is-not-ground-truth.md`; moved verbatim 2026-10-14, its headings demoted one level._

### Three real instances from one session

#### 1. "All your work is gone" — read during a write

Read the `.mpr` while Studio Pro was mid-rewrite, saw 6 microflows instead of 13, and told the user
the whole session's work was lost. It was not; the file was simply being written at that instant.

**Antidote:** confirm against an independent source before declaring loss.
```bash
git hash-object Project.mpr            # working tree
git rev-parse <commit>:Project.mpr     # committed
```
Identical hashes mean the tree *is* the checkpoint, whatever a stale read said. Also re-run the
query — caches (`.mxcli/catalog.db`) lag.

#### 2. "mxcli converts v2→v1 on read" — correlation asserted as cause

The project kept flipping from MPR v2 to a single-file form. Noticed the conversions happened
around read-only `mxcli` commands and reported mxcli as the culprit — plausible, and wrong. A
subagent later checked mtime before and after its own mxcli calls: unchanged. Something else was
doing it.

**Antidote:** to claim tool T causes effect E, run T in isolation and observe E. Timing correlation
in a tree with multiple concurrent writers is not evidence. Instrument (record state before/after
your own calls) rather than infer.

#### 3. "These filters are unbound" — a lossy DESCRIBE

`DESCRIBE PAGE` emitted `dropdownfilter fEquipType` with no `Attributes:` property. Reported as a
live shipping bug across two pages, and a corrective script was drafted. The user pushed back:
the filters had been tested working many times. They were right.

Two compounding errors:
- **`grep` flattened the hierarchy**, hiding that the filters sat in a deliberately built filter bar
  with paired labels.
- **Disconfirming evidence was already in hand and ignored.** `mxcli check` on the corrective script
  emitted `MDL-WIDGET07: property columnsFilterable is not recognized and will be silently dropped`
  — an explicit admission that mxcli's model of that widget family is incomplete. A tool that does
  not understand a sibling property cannot be trusted to round-trip a child one.

Had it been executed, it would have rebuilt a working page containing `customContent` columns —
the single highest-risk construct for load-time BSON corruption in this stack. **All risk, zero
benefit, from a finding that never existed.**

## TO2 — `$?` after a pipeline — three instances (2026-08-04)

_From `skills/tool-output-is-not-ground-truth.md`; moved verbatim 2026-10-14._

Real instances from the one session:

| Observed | Concluded | Actually |
|---|---|---|
| `coverage-check ... \| tail; exit=0` with 323 UNCLAIMED | "exit 0 on a dirty ledger — new bug!" | exit **1**, correct |
| `gate-check ... \| head; exit=0` printing "Gate BLOCKED" | "a blocked gate passes — 5th false-PASS!" | exit **1**, correct |
| `exec.sh ... \| tail; EXIT=` (empty) | inconclusive | exit **3**, correct |

## TO3 — A passing gate is not a working model — the workflow red pins (2026-08-05)

_From `skills/tool-output-is-not-ground-truth.md`; moved verbatim 2026-10-14, its headings demoted one level._

### The instance

Scripted a Mendix workflow with five `CALL MICROFLOW` activities.

- `mxcli check --references` → `Check passed!`
- `mxcli exec` → `Created workflow`
- `mx check` (Studio Pro's own validator) → **`0 errors`**
- Studio Pro **opened the model** without complaint

Four green signals. Every activity was a **red pin** that could not be clicked, and the app would
have refused to boot: `Class 'Workflows$CallMicroflowTask' could not be found`.

mxcli `v0.16.0` writes a `$Type` that Mendix renamed at 11.9. `mx check` does not validate that
name. The upstream fix commit states this outright — *"Both checkers passed... the runtime refused
to load the ENTIRE model at boot."*

### Why it cost a day rather than an hour

A six-variant probe had been run to find the trigger boundary, varying `WITH`-clause forms. **Every
arm was graded by `mx check`.** All six passed, so the conclusion was "syntax X is safe" — and all
six were broken in exactly the same way, because the variable that mattered was never varied.

> A control that cannot distinguish your arms will confirm whichever hypothesis you brought.

The probe was well-designed in every respect except the one that counted: nobody asked *what is
this gate actually sensitive to?*

## MF1 — `mxcli layout` probe history (2026-09-25)

_From `skills/microflow-preflight.md`; moved verbatim 2026-10-14._

**`mxcli layout` is a domain-model command.** The mxcli team's answer to microflow
positioning (2026-09-25) is a standalone layout command rather than anything in `create
microflow`. On v0.24.0 and on upstream `main` at that date, `mxcli layout --help` says
*"Arrange the entities of a domain model"*; it moves entities only, and there is no microflow or
nanoflow mode yet. Measured: `mxcli layout -p app.mpr --dry-run` on a scratch copy of a PoC
model listed 10 entity moves and no microflow. **Before relying on it for a microflow, probe
your binary:** `mxcli layout --help` — the capability-probe rule. Until a microflow mode ships,
the remedy for a bad microflow layout stays the one in this file: no `@position`, and the
`SUB_` split for the defect below.

## MP1 — `marketplace install` #879 — the v0.21.0 re-probe (2026-09-10)

_From `skills/learned-mdl-preflight.md`; moved verbatim 2026-10-14._

- ~~`marketplace install` on a split-model project (#879)~~ — **RESOLVED in v0.21.0, STOP LIFTED (probed 2026-09-10).** Install no longer shells out to `mx module-import`; it copies units with mxcli's own writer and MPR v2 survives. The destructive path is now opt-in behind `--allow-format-change`, so the failure can only happen on purpose. Measured on a real 501-unit project: 501 → 1075 `.mxunit`, `.mpr` 84 KB → 156 KB (an index, not the 35 MB blob #879 produced), native mxbuild **0 errors**. **Read `bug-logs/mxcli-bugs.md` → the #879 entry before your first install** — the corruption is gone, and three *new* operational traps replaced it (packages do not carry their dependencies; two `mxcli fix` repairs are mandatory, not advisory; a bundled widget can silently fail to land and the installer cannot self-repair it).

## PF1 — `learned-mdl-preflight.md`: version notes, retired rows, full root causes (2026-10-23)

_From `skills/learned-mdl-preflight.md`; moved verbatim 2026-10-23 (lazy-load PR 1). The skill keeps every row's If/Then text, one failure clause per live row and a `Kind` column; below is the table as it stood before the move, retired rows included._

Re-probed on mxcli v0.24.0 / Mendix 11.13.0 (2026-09-30); rules that now work or that `mxcli check` catches were removed.

**Version context:** a retired row keeps its number (other skills cite `STOP #n`) and says why it went. If in doubt about a rule, retest on your version and stamp the result in `bug-logs/mxcli-bugs.md`.

**Version notes (mxcli ≥ v0.20.0):**
- ALTER PAGE addresses DataGrid2 columns by **derived** name (bound attribute, else caption — MDL-WIDGET16); a bare column name in REPLACE is refused in favour of `grid.column`.
- **Still corrupting, STOP stays:** workflow `DECISION` activities (BUG-76 — project unloadable, `EnumerationValueIdentifier`). **v0.24.0 narrows it:** the bare-enum form is refused by `MDL-WF03` (never force it with `--no-check`), and a Boolean decision with `true`/`false` outcome keywords builds at 0 native errors — `learned-workflow-patterns.md` §8 Warning 1.
- ~~`marketplace install` on a split-model project (#879)~~ — **RESOLVED in v0.21.0, STOP LIFTED (probed 2026-09-10).** The destructive path is now opt-in behind `--allow-format-change`, so the failure can only happen on purpose. **Read `bug-logs/mxcli-bugs.md` → the #879 entry before your first install** — the corruption is gone, and three *new* operational traps replaced it (packages do not carry their dependencies; two `mxcli fix` repairs are mandatory, not advisory; a bundled widget can silently fail to land and the installer cannot self-repair it). Probe measurements: `process/baseline-incident-history.md` § MP1.
- The 10–12-writes-per-session cap from BUG-97 is downgraded to snapshot-plus-read-back: 16 sequential writes were clean on v0.20.0.

| # | If your script will… | Then… | Root cause |
|---|---|---|---|
| 1 🔎 | Use `visible:` or `editable:` **conditional expressions** on containers **inside a `datagrid customContent` column** | **STOP → Studio Pro by hand** | mxcli writes blank `AttributeIdentifier` → `StorageLoadException` on SP open. **BUG-18, still open on v0.13.0** (found 2026-07-03 after v0.13.0 release). **Primary real-world trigger: per-value badge pattern** — multiple containers with `Visible: [State = ENUM.Value]` inside a column. mxbuild passes clean; SP load fails. *Re-probe 2026-09-30 (v0.24.0): `mx check` 0 errors and the BSON is identical to the plain-container case; Studio Pro load could not be tested, so the STOP stays.* Safe CLI alternative: `dynamictext (Attribute: "State")` renders enum caption natively. Do NOT use `ContentParams: [{1} = toString("State")]` inside customContent — resolves as attribute path → CE1613. Per-value colours: set them in Studio Pro. |
| 1b | Put `Editable:` on an input widget in `CREATE PAGE` | **Write it as an expression, `Editable: [<expr>]` — never the quoted string `Editable: '<expr>'`.** (`Visible: [<expr>]` and `ALTER PAGE … SET Visible/Editable = [<expr>]` work.) | v0.24.0: the quoted form is dropped with no message — `describe` shows no `Editable` — so the field is silently always editable. `check` and `exec` are both silent; read the page back with `describe page`. |
| 1c | *(retired 2026-09-30 — ALTER PAGE SET Visible/Editable stores correctly, `mx check` 0 errors)* | | |
| 2 | *(retired 2026-09-30 — settings and security-level writes work in the CLI)* | | |
| 3 | *(retired 2026-09-30 — dropping an attribute that has grants works)* | | |
| 4 | Bind a widget to the `AutoChangedBy` system attribute | **STOP → omit it, or bind `AutoChangedDate` instead** | v0.24.0: `check` passes, then `mx check` gives `[CE1613] The selected attribute 'Mod.Entity.changedBy' no longer exists`. `AutoChangedDate` binds clean. `mxcli lint` does not flag it. |
| 5 | *(retired 2026-09-30 — scalar arguments from a page button to a microflow work; an unbound parameter is CE1571)* | | |
| 6 | *(retired 2026-09-30 — COMBOBOX in association mode works)* | | |
| 6b | *(retired 2026-09-30 — `DropdownFilter` in association mode works)* | | |
| 7 | *(retired 2026-09-30 — cross-module association traversal as a datasource works)* | | |
| 8 | *(retired 2026-09-30 — `CREATE ASSOCIATION` on an existing name is refused; use `create or modify association`)* | | |
| 9 | *(retired 2026-09-30 — inline association-set in CHANGE/CREATE works, cross-module too — set it from the owner side, see `learned-microflow-patterns.md`)* | | |
| 10 | *(retired 2026-09-30 — `mxcli check` refuses `count()` (MDL044) and exec will not run it; write `length($list)`)* | | |
| 11 | *(retired 2026-09-30 — an association path as XPath comparand works)* | | |
| 12 🔎 | Put anything but a bare attribute or a quoted literal in a `dynamictext`'s `ContentParams` — `toString(Attr)`, `$currentObject/Attr`, `if … then … else`, any function | **Bind a bare attribute (`{1} = Attr`) or a quoted literal, nothing else.** A computed label becomes data: a stored or derived String attribute, bound bare. Tone variants go in `DynamicClasses`, which takes a real expression (and there *needs* the prefix: `'if $currentObject/State = Enum.Value then ...'`). | v0.24.0 (BUG-142): every unquoted value is stored as an attribute path, so an expression is CE1613 at mxbuild ("The selected attribute '<Entity>.<expression text>' no longer exists"). `check` now refuses the `toString`, `concat` and `$currentObject` forms, but **`if … then … else` passes `check` and `exec`** and fails only at `mx check`; `mxcli lint` does not flag it. A bare Boolean renders "Yes"/"No", not `true`/`false`. `Attribute: Attr` is the documented shorthand for the bare form (`learned-datagrid-customcontent-binding.md`). |
| 13 | *(retired 2026-09-30 — `check` refuses an unqualified association name in a retrieve XPath (CE0161) and exec refuses; write `Module.Assoc`)* | | |
| 15 | *(retired 2026-09-30 — quoted attribute names in CHANGE work; `describe` normalises them)* | | |
| 14 | Narrow an existing entity grant (fewer attributes or rights than the rule already has) | **`revoke` first, then `grant` the narrower set.** A lone narrowing `grant` merges into the existing rule instead of replacing it (BUG-145). | v0.24.0: revoke + re-grant no longer drops another role's grant (`mx check` 0 errors); the merge on a lone `grant` remains. |
| 17 | *(retired 2026-09-30 — uppercase `AND`/`OR` with `!=` builds at 0 errors)* | | |
| 18 | Write **any workflow MDL** — `CREATE`/`ALTER WORKFLOW`, a `CALL MICROFLOW` step, a `JUMP TO`, user-task outcomes | **STOP → read [[learned-workflow-patterns]] first, then script. Create every callee microflow in an EARLIER script than the workflow that calls it.** Read the BRD lifecycle + wireframe before writing a single outcome. | v0.24.0: with the callee already in the model, `check` and `exec` refuse a call-microflow with an unmapped parameter, a missing callee, and a `JUMP TO` that is not a real activity name (MDL-WF05). With the callee created **in the same script**, `check --references` skips the call and `exec` auto-fills the `WITH` mapping — a non-context parameter gets `(Name = '$WorkflowContext')` — and `mx check` fails with CE0117 at the call. A context-typed parameter auto-maps fine. `mxcli lint` does not flag it. Earlier incidents: 2026-07-24 ×2, 2026-08-21, 2026-08-31 (`learned-workflow-patterns.md` §7, §13, §14, §21). |
| 16 🔎 | Write an access-rule XPath constraint with a **path expression inside the `[%CurrentUser/...%]` substitution token** — `[Assoc = '[%CurrentUser/Module.OtherAssoc%]']`, especially crossing module boundaries | **Never put a path inside the CurrentUser substitution. Keep it bare (`'[%CurrentUser%]'`) and do the ENTIRE multi-hop/cross-module traversal on the left-hand side instead**, qualifying the entity name at every module crossing (same rule as the "cross-module association expression paths" MDL gotcha, extended here to access-rule XPath constraints, not just microflow expressions). Was: `[Decision_Partner = '[%CurrentUser/PLM.Account_Partner%]']`. **Fix (confirmed working):** `[PLM.Decision_Partner/PLM.Partner/Administration.Account_Partner = '[%CurrentUser%]']` — walk Partner→Account fully on the left, compare directly to the (already-an-Account) CurrentUser token. | This is genuinely invalid Mendix XPath, not an mxcli-specific bug — `CE0161` "Error(s) in XPath constraint" is Mendix correctly rejecting it every time it's checked, which is why it kept resurfacing across three separate incidents on a PLM parts-flow project (2026-07-22/23, `bug-logs/mxcli-bugs.md`) that were originally misdiagnosed as mxcli corrupting the domain model on unrelated grant rewrites. In fact the "unrelated entity broke too" symptom was just two independently-broken rules (both using the same invalid CurrentUser-path form) surfacing together once a full `mx check` ran — not one rule corrupting the other. Once rewritten to the correct bare-CurrentUser/full-LHS-chain form, the earlier "Studio Pro GUI only, module-wide" restriction no longer applies — **confirmed mxcli-safe 2026-07-23** via `test-05-currentuser-xpath-chain.mdl` (rebuilt all 4 role grants on the affected entity through mxcli exec, reproducing the corrected XPath verbatim, `mx check: 0 errors`). Use mxcli directly for this pattern; no GUI fallback needed. |
| 21 | `DROP` + `CREATE`, `create or modify` or `create or replace` any document **another script also edits** — an aggregator microflow, an after-startup chain, a navigation profile | **STOP → `describe` the live document first, diff your restatement against that dump, and name in the script header which call sites you preserved. A new owner adds `-- supersedes: <script>`; drafting ahead of unrun scripts, `bin/describe-baseline.sh stamp <script>` after the DESCRIBE (exec.sh only warns).** mxcli has no `ALTER MICROFLOW` for an existing body, and `ALTER NAVIGATION` **does not exist at all** (the parser rejects it: `no viable alternative at input 'alternavigation'`). Whole-document restatement is therefore the only write mxcli offers, which makes losing a sibling script's edit the *default* outcome, not an unlikely one. | Confirmed 2026-08-26 on a field run: two scripts each did DROP+CREATE on one shared seed aggregator. The second restated it as it had been *before* the first ran, and a demo-data seed call silently vanished. Every instrument was green — `mx check` reported **0 errors** because an uncalled microflow is perfectly legal, and `mxcli lint`'s orphan rule (QUAL004, `orphaned_elements.star`) exempts the `ACT_` prefix as a presumed UI entry point, so an `ACT_` microflow with no callers at all reports clean. It was found by opening a page and reading "0 to 0 of 0". |
| 22 | Write a script containing ANY non-idempotent statement — `alter entity … add attribute`, bare `CREATE ASSOCIATION`, bare `CREATE MICROFLOW`/`CREATE PAGE` on a name that may already exist | **STOP → use the `create or modify` form for every statement, and give every document exactly ONE owning script.** mxcli is **not transactional across statements**: the first failure stops the script and every statement below it is not run. The property to hold is that `mdlsource/` replays cleanly against an EMPTY app; that is one command and it is the only thing that proves it. | v0.24.0: `check` passes; `exec` now fails loudly (`Error: attribute 'Note' already exists on entity Mod.Order`, exit 1) and a later `CREATE MICROFLOW` in the script is **not created** — the earlier statements stay written. `mx check` reports 0 errors on the partial model, so the only signal is the exit code: never ignore it. Field case (2026-08-31, mxcli v0.20.0): script `09b` re-ran after its attributes existed, died on statement 1, and two microflows at the end were never applied; `ACT_Version_Delete` quietly lost a call, found by `DESCRIBE MICROFLOW` on a hunch. Compounded by rule 21 one level up: six scripts held a grant on the same three entities, so whichever ran last decided their security. The fix for both is the same: one owner per document, `create or modify` throughout, and a from-empty replay in CI or at wrap-up. |
| 23 | Name any document or entity that **might already exist** — `create or modify` on an entity, or any `create or replace` on a page, layout or microflow | **STOP → run `mxcli diff -p <app>.mpr <script>.mdl --format struct` FIRST.** It is read-only, it takes a second, and it prints exactly what the script would add and what it would REMOVE. (`exec` itself only warns — v0.24.0: `create or modify entity Mod.Order drops 6 existing member(s)` — and then writes.) Read the `-` lines before you exec, every time. Rules 21 and 22 tell you to write `create or modify` and to give each document one owner; this is the check that the name you chose is actually free. | Confirmed 2026-09-01 (a dashboard-publishing migration, mxcli v0.20.0). A new script declared `create or modify non-persistent entity DashboardPublishing."ViewerContext"` with one attribute, believing the name unused. The entity already existed, owned by an earlier page script, carrying four attributes — `VersionLabel`, `HasContent`, `Html`, `DashboardTitle` — which are the entire datasource of the app's viewing page. `diff --format struct` reported `+ Attribute SharedCount` and **four `- Attribute` lines**, i.e. `create or modify` on an entity does not merge into the attribute set, it **replaces** it. Renaming the new entity took ten seconds; the alternative was a page that renders nothing, on a model that would have passed `mx check` and mxbuild clean, since an entity losing four attributes is a perfectly valid model. **This is the cheapest guard in the file — the whole rule is `diff` before `exec`.** On v0.24.0 it also prints false `~ Modified` and `- Attribute` lines (BUG-146): check each `- Attribute` against `DESCRIBE ENTITY` before trusting or dismissing it. |
| 24 | Put a `DesignProperties: [...]` entry on a widget (Form orientation, Label width, Spacing, …) in an app scaffolded by `mxcli new` (any `--theme`) | **STOP → grep the theme first: `grep -l '<property name>' themesource/*/web/design-properties.json`. If it is not there, use the Atlas class instead (`Class: 'form-vertical'`, `spacing-outer-bottom-large`).** `mxcli new`'s theme layer ships a `design-properties.json` that does not carry Atlas's FormBase entries, so mxbuild rejects the property with CE6083 "not supported by your theme". v0.24.0: `check` only warns (MDL-WIDGET11), `exec` writes, `mx check` fails; lint does not flag it. `design-spacing.md` says design properties and classes write the identical model; that holds only when the theme declares the property. | Greenfield pilot 2026-09-04, mxcli v0.20.0, Mendix 11.13.0, signal theme: `DesignProperties: ['Form orientation': 'Vertical']` on a DataView → exec ok, CE6083 at the gate, auto-restored. `Class: 'form-vertical'` built clean — and then changed nothing on screen, because in that theme the form layout is decided by the theme's own dataview rules, not the class (ui-loop.md "which side is wrong", row 1). The look caught it; no gate could. |
| 25 | Write a microflow with any loop, >20 planned activities, or a list built from a list | **STOP → run `microflow-preflight.md` and post its checklist first.** | Lint runs only after exec and counts only top-level activities (a loop body is invisible to CONV009/QUAL003); CONV011 commit-in-loop and MPR008 overlap findings came back on field builds after the write, not before. |
| 26 🔎 | Bind a DataGrid 2 column over an **association** | **STOP → write the column path unquoted.** Use `Attribute: Assoc_A_B/Name`, never `"Assoc_A_B/Name"`. This is the one place a quote-every-identifier convention must break. | A quoted path is stored as one attribute named `Assoc_A_B/Name`. v0.24.0: passes `check --references`, then `[CE1613] attribute 'Mod.Entity."Assoc_A_B/Name"' no longer exists` at `mx check`; the unquoted form builds at 0 errors, and so does `sort by Assoc/Attr`. `BUG-DRAFT-dg2-association-path-bindings` |
| 27 | *(retired 2026-09-30 — marketplace install by content id and by `--file` both stamp `FromAppStore`, `AppStoreGuid`, `PackageId` and `Version` (BSON-verified; `SHOW MODULES` shows `Marketplace v<version>`); how Studio Pro groups the module was not testable)* | | |
| 28 | Change an existing microflow near a `return` in a dense flow | **Plan drop + create in one script, after `show access on microflow` (re-grant what it lists).** A passing `check -p --references` skips exec's free-room test. | v0.25.0: `check` passed, exec refused `insert before return $LiveResult: there is no free room for the fragment`. BUG-156 |
| 29 | Use a constant in a nanoflow | **Set `ExposedToClient: true`, or use a microflow.** | `check` passes; mxbuild CE0117. #445 |
| 30 | Put a `dynamicimage` on a React-client page | **Use the pluggable `image` widget.** | `check` passes; mxbuild CE0582; lint MPR012 flags it. #445 |
| 31 | Bind a data-view widget's attribute across 2+ associations | **One hop per step: nest a data view.** | `check` passes; mxbuild CE1613. A database-sourced Gallery allows it: `learned-page-patterns.md` §ContentParams Multi-Hop. #445 |
| 32 | Give a widget's `show page` any argument outside a data view/list/grid row, or besides its context object | **Call a microflow that shows the page.** | v0.26.0 `check` refuses: MDL-PAGEARG01. BUG-70/95. #445 |
| 33 | Change a flow's return type, update callers in a **later** script | **STOP → one script: the change and every caller update.** Find callers: `SHOW CALLERS OF Mod.TheFlow`. | v0.27.0, none→Boolean via `create or modify`: `mx check` CE0112 at a Studio Pro-authored caller after script 1 (mxcli-written: none); `check`/`exec` silent. Workflows: `learned-workflow-patterns.md` §16 |
