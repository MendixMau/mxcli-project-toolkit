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
