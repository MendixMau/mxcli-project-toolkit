# Conversion Runbook — The Interview-Driven Stage Pipeline

**Applies to:** any mxcli project — see Entry Modes below for where your project type enters the pipeline.
**Requires:** bash and Python 3 — this skill runs toolkit shell scripts. Run `bin/doctor.sh` once on a new machine; it names anything missing and how to get it. Windows: use Git Bash, and see the Prerequisites section of `conversion-runbook.md`.

**Purpose:** The spine the toolkit was missing. Each stage below has an owning skill and each skill is good — but until now nothing said *what a stage must produce before the next one starts*, *what the user has to decide*, or *whose job it is to ask them*. This skill is that layer: a stage completes when a decision is on record, not when the agent stops typing.

**Upstream:** `bootstrap-project.md` (Stage P scaffolding), `query-the-model.md` (the lookup-before-ask discipline every gate depends on).

## Skills always loaded — every session, before any stage artifact

This table is the canonical baseline set. It is rendered from the toolkit's one routing
table; a skill missing here is a skill no agent will find.

<!-- Generated from bin/lib/skill-routing.tsv by bin/render-routing.sh.
     Do not hand-edit between the markers: add or change the ROW, then re-render. -->
<!-- ROUTING:BEGIN readme-baseline -->
| Always relevant for | Reference this |
|---|---|
| Any pipeline work at all — every session, before producing any stage artifact (not just "when unsure"); READMEs and the guide are orientation only | `skills/conversion-runbook.md` |
| Any question before asking the user or writing anything — query the model, then read the source, then ask the human, in that order | `skills/query-the-model.md` |
| Before writing any .js or .sh for a check, gate or report — and before adding a rule to an existing one: judgement goes in a skill, code only fetches facts a reader cannot | `skills/skills-over-scripts.md` |
| Any pass whose input is missing, stale or unresolvable — before recording UNMEASURED, N/A or a silent skip: name what was missing, say what you assessed against instead, still deliver a verdict | `skills/degrade-to-judgement.md` |
| Putting a question TO the user — any gate, any stage: ask in chat not in a file, two named options plus your recommendation, one batch per gate then end the turn | `skills/interview-protocol.md` |
| Any stage transition — the 2+1 format every CAC uses, and the one-register rule (answers land in PROJECT.md, never in a separate state file). The seven CACs themselves are routed per stage in the situational table | `skills/checkpoints/checkpoint-template.md` |
| Setting up or completing a project's dev-process subagents — once, at project start, not "on demand" | `skills/agent-roles.md` |
| Deciding whether to extract at all, before any BRD gets generated | `skills/source-triage.md` |
| Taking in a new source — before generating anything from it. Grades what the source can support; nothing else in this toolkit reads a source | `bin/source-sufficiency.sh` |
| Deciding who answers a question — before putting any batch to the user. gap/conflict/choice/user-only is what keeps a gate batch at four questions instead of 127 | `bin/question-kinds.sh` |
| Writing BRDs, especially several in parallel — "build" before the fan-out, "check" before any BRD is called done | `bin/facts-lock.sh` |
| Building any module — before the first script. The mdl-agent's single per-module input | `skills/module-brief.md` |
| Writing ANY MDL script — before the first line. Step 0 picks the write mode, then the STOP table overrides it for corrupting operations | `skills/learned-mdl-preflight.md` |
| Placing any document in a module — before the first `create`. Feature group, then Pages/Microflows/Services/Resources; the path comes from the brief's folder plan, and the table says which types mxcli can actually place | `skills/module-folder-convention.md` |
| Writing or fixing any microflow — MDL gotchas plus annotation discipline | `skills/learned-microflow-patterns.md` |
| Building any page or snippet — before the first widget. Wireframe, tokens, gallery reuse, cross-check; no wireframe means STOP | `skills/ui-preflight-pages.md` |
| Writing or reviewing any page or snippet — the spacing scale (8/16/24/32/48), section rhythm, and the page-header scaffold every full page starts with; sections at 0px apart and pages with no H1 are the defects it retires | `skills/design-spacing.md` |
| After every page-building script, and any time the UI looks wrong — the cheap repeatable look during the build: one page, one screenshot, three questions. Feeds Gate: UI, never replaces it | `skills/ui-loop.md` |
| Building or using the in-app design gallery | `skills/learned-stylegallery.md` |
| Before exec'ing ANY page script — compares the drafted MDL's shell against the wireframe's: page column, layout/nav shell, one H1. Measured 0/10 pages on a real first build, repaired wholesale 47 scripts later | `project-bin/check-page-shell.sh` |
| After drafting and again after exec'ing any page script — scores the page MDL (or `mxcli describe` output on stdin) against its wireframe: headings/actions/content/classes, weighted. The scored companion to check-page-shell's binary gate; 32% median measured without it, 90% first-draft with it. Every run is appended to the project's docs/PAGE-FIDELITY.tsv — first non-stub row per page = first-build score of record vs the ≥80% target (forward-reference stubs score with --stub, exempt) | `project-bin/page-fidelity.js` |
| Choosing CLI vs MCP+MDL vs hand-rolled MCP, or any MCP write session — three co-equal write modes, not CLI-only | `skills/learned-mcp-patterns.md` |
| Reviewing any module before calling it done — the ONE pass: build, gate, prove, LOOK (is it logical, does it look right, does it match our design, over every page not just the tested ones), confirm with the denominator stated | `skills/module-review.md` |
| Before calling any module tested — what testing a module means, and the false-green register of confirmed ways a test reports green over a broken feature | `skills/testing-shape.md` |
| Finishing any module — before calling it done. One command that runs every instrument and keeps "instrument faulted" apart from "feature failed"; in a wired project run the installed copy at bin/verify-module.sh | `project-bin/verify-module.sh` |
| A CE error or behavior that looks like a known mxcli quirk rather than a modeling mistake | `bug-logs/mxcli-bugs.md` |
| Any time an exit code, a tool's output or a subagent's report is about to become a stated finding — verify before you conclude | `skills/tool-output-is-not-ground-truth.md` |
<!-- ROUTING:END -->
**Downstream:** every stage skill listed in §2 — this runbook sequences them, it does not replace their content.
**Root pointer:** `CONVERSION-RUNBOOK.md` at the repo root is a thin pointer to this skill plus "how to start"; this file is the executable detail. `toolkit-guide.html` at the repo root is the same journey as a visual page, and doubles as the shared CSS shell/token source for every stage HTML surface.

**Do not open `toolkit-guide.html` because you read this line.** Opening is governed by the first-touch rule in the toolkit's `CLAUDE.md` — open only if `<project-root>/.claude/.guide-shown` is absent, then `touch` it. You are reading this file *every session*; an unconditional "open it at kickoff" here means a browser tab every session, which is exactly the bug this wording replaced.

---

## Prerequisites — run this once on a new machine

This runbook drives shell scripts. They need **bash** and a **Python 3**, and on Windows neither
is guaranteed. Do not discover that partway into a stage; find out now:

```bash
bin/doctor.sh                      # probe the machine
bin/doctor.sh /path/to/project     # and a specific project's wiring
```

It prints, in plain language, what is present and what is missing, and exits non-zero if
something will break a stage. Everything below assumes it came back clean.

| Platform | What to install | Notes |
|---|---|---|
| macOS | nothing, usually | bash 3.2 and Python 3 are there or one `brew install python3` away. |
| Linux | `apt install python3 sqlite3` (or your equivalent) | |
| Windows | **Git for Windows** (gives you Git Bash), and Python 3 from python.org with *"Add python.exe to PATH"* ticked | Run every toolkit command from the Git Bash prompt, not PowerShell or cmd. |

**Windows, the one trap worth naming.** A `python3` that opens the Microsoft Store when you type
it is the *Store alias stub*, not an interpreter. The toolkit detects and skips it, but you
should still turn it off: Settings → Apps → Advanced app settings → App execution aliases.

**Git Bash, not WSL.** WSL is a separate Linux machine: it cannot see Studio Pro or reach a
Mendix app running on the Windows side without extra network and path plumbing, and the toolkit
does none of that plumbing for you. Git Bash runs in the Windows filesystem and process space,
which is where Studio Pro, mxcli and your model all live. `bin/doctor.sh` detects WSL and warns.

**What does not work on Windows yet, and is not a mistake on your part.** The Studio Pro
automation scripts — `project-bin/save-sp.sh`, `project-bin/restart-sp.sh`, and the Studio Pro
handling inside `project-bin/exec.sh` — are macOS-only: they are built on `osascript`, `lsof` and
`open -a`. On Windows, drive Studio Pro by hand at the points where those scripts would run.
Everything else in the pipeline works.


## Entry Modes — Where Your Project Enters the Pipeline

The stages are the same for everyone; what differs is where you enter and which analysis paths exist for you.

**The entry mode is a Stage-P interview decision, not a silent inference.** The agent proposes a mode *with evidence* ("you have specs in X and source in Y, so…") and records it `CONFIRMED` in `PROJECT.md` before any stage is skipped. A skipped stage in the wrong mode is a gap; in the confirmed mode it's correct. Classification rules — apply in order, first match wins:

1. **Any legacy/source code exists** (even a reference implementation you're not "migrating" — if it encodes behavior you want, it gets analyzed) → **Migration** (or at minimum, Stage 1 Path A runs on it).
2. **Any requirements artifacts exist** — specs, BRDs, context docs, wireframes, workshop outputs → **Requirements-driven**. Having "complete" specs does *not* mean skipping to Stage 5: stages 2–4 are where those specs become validated BRDs, an architecture, module boundaries, a design system, and an ordered plan. Skipping them means improvising all of that mid-build.
3. **Neither** — you're genuinely starting from a conversation → **Greenfield**. This is the narrowest mode, not the default for "no legacy system."

(Real misrouting incident, 2026-07-14: a project with full specs + analyzable source was classified greenfield "because there's nothing to migrate," proposing to skip 0–4 — exactly what rules 1–2 exist to prevent.)

| You're starting from… | Mode | Stages that run | What changes |
|---|---|---|---|
| **Legacy source code** (± docs, ± SME) | **Migration** | P, 0–7 (all) | The default everything below describes. Path A (code extractors) always runs. |
| **Requirements only** — BRDs, specs, workshop outputs, wireframes; no legacy code | **Requirements-driven** | P, 0–6 (skip 7) | Stage 0 runs, and its *extraction* rows are marked N/A — see "Stage 0 runs in every entry mode" below. Use `document-discovery.md` over the requirements corpus for the inventory. Stage 1 runs Path B (`kb-generation.md`) + Path C (SME) only; Path A is declared not-applicable, not "skipped". Stages 2–6 run unchanged — BRDs come from documents instead of extraction. Stage 7 only if legacy data exists somewhere to cut over. |
| **Just an idea / a running start on the model** | **Greenfield** | P (light), 0 (scope only), 5–6 | Stages 1–4 collapse to whatever plan the user already has. Stage 0 does **not** collapse: with no corpus there is nothing to grade, but the scope conversation is exactly as load-bearing as it is anywhere else, so Stage 0 reduces to CAC-1's brainstorm and its sign-off. If you find yourself inventing requirements mid-build, you're actually in requirements-driven mode — back up to Stage 2. |

### Stage 0 runs in every entry mode

**Stage 0 is the scope stage. It is not the extractor stage.** Reuse-vs-build-new is one question
*inside* it, and it is the only part that needs a codebase.

This distinction was implicit until 2026-08-20, when a customer round made the cost of leaving it
implicit measurable. A project whose source was markdown files plus database tables was classified
requirements-driven — reasonably, given the rules above. The mode's row then said "skip 0", so
Stage 0 was skipped **whole**: no source characterisation, no `analysis/` folder, no triage
artifact, and — the expensive one — **no scope conversation**, because CAC-1 fires after Stage 0
and Stage 0 never ran. Extraction was then run anyway and pulled in far more than the subsystems
under discussion, which nothing downstream was positioned to notice: Stage 2's gate checks that
BRDs are *validation-clean*, and a hundred clean BRDs describing things nobody asked for pass it.

So: **no entry mode may skip Stage 0, because no entry mode may skip the scope conversation.**
What varies is how much of the stage is applicable, and inapplicability is *recorded*, never
inferred:

| Stage 0 component | Migration | Requirements-driven | Greenfield |
|---|---|---|---|
| Source inventory + sufficiency grade (`bin/source-sufficiency.sh`) | runs | runs — over the requirements corpus | N/A (no corpus) |
| Reuse-vs-build-new extraction call (`source-triage.md`) | runs | **N/A** — record the reason, don't delete `triage.md` | **N/A** — record the reason |
| Business capability map + coverage matrix | runs | capability map runs; coverage matrix N/A | N/A |
| **Scope brainstorm + slice ordering (CAC-1)** | **runs** | **runs** | **runs** |
| Sign-off (`## Sign-off` in `triage.md`) | required | required | required |

**N/A is an answer and it is written down.** Mark the row `N/A` in `triage.md` with the reason,
and sign the file off. Do not delete `triage.md` to express "this doesn't apply" — `gate-check.sh`
then reports *"triage.md not found"*, which reads as an unanswered gate rather than a settled one,
and the difference between those two is the whole point of having a gate.

**No pipeline at all — à-la-carte tool use.** An existing Mendix app that just needs an audit, lint pass, or a regression/e2e test net doesn't enter this pipeline: no intake, no stages, no gates. Route straight to `existing-app-assurance.md` (which points at `query-the-model.md`, `e2e-harness-base.md`, `learned-db-assertions.md`, and the bundled lint/graph/quality skills). The pipeline is for *producing* an app; the tool shelf is for everything else.

## When to Use This Skill

- Starting any conversion (legacy source → Mendix), requirements-driven build, or greenfield mxcli build.
- You're not sure whether a stage is "done" — check its gate row in §2, not your own sense of completion.
- A decision got made without the user's sign-off and it's now biting — that's this skill's gate being skipped, not a one-off mistake. Fix the gate, don't just redo the decision.

---

## 1. The Interview Protocol — How a Gate Works

Every gate in §2 runs the same six-step shape. This is the thing that should be visible in every stage transcript:

1. **The agent does its homework first.** It never asks what it can derive. Anything answerable from the source, the extraction, or the model must be answered from there — see `query-the-model.md` for exactly which source answers which class of question. The intake rule already enforces the fallback: `"Unverified — how to verify: …"`, never a guess.
2. **The agent proposes, with evidence.** 2–4 concrete options, a recommendation, and *why* — citing the artifact that supports it. ("Your source has 4 auth roles, 3 of which are never checked; I recommend collapsing to 2.")
3. **The agent states its assumptions out loud** — the list of things it took for granted to reach that recommendation, so the user can correct the premise, not just the conclusion.
4. **The question is actually asked, in the chat** — multiple choice, "other" always available. On Claude Code render it with `AskUserQuestion` (clickable options); on Copilot, Cursor, Windsurf, Aider or anything else, plain numbered markdown in the chat — `AskUserQuestion` is a Claude Code built-in that cannot be installed, and "I can't call that tool" is not a licence to skip the question (real dry run, 2026-08-19; see `interview-protocol.md` §3 "Asking on a non-Claude agent"). **Then, on every harness, the agent ends its turn and waits.** Do not answer your own question and keep working in the same turn — a gate that never reaches the user's screen is not a gate. Finding the answer in the source does not waive the question: source evidence powers the *recommendation* (step 2), it never replaces the *asking*.
5. **The decision is written to two places**: the stage's HTML proposal doc (the artifact, customer-showable) and `PROJECT.md` (the register), marked `CONFIRMED`.
6. **`ASSUMED` is earned by asking, never by skipping.** An answer may be recorded `ASSUMED` only after the question was actually posed and the user said "don't know" / "you decide" — that is delegation-by-consent, recorded with the risk if wrong. Deriving an answer yourself and not asking is a protocol violation, not an `ASSUMED`.

**The gate's own questions are not the only questions — raise the accumulated batch too.** Steps 1–6 govern the questions the *gate* asks. But the pipeline generates a second stream all the time: every `openQuestions` entry a BRD records, every row added to `analysis/sme-questions.md`. Those were never wired to anything, and they rotted. Measured on one real project (2026-08-12): 46 rows in `sme-questions.md` against 7 mentions of an answer, ~35 unresolved BRD `openQuestions`, one status reading *"Open — routed to sme-questions.md F1/F2"* — routed to a file nobody opens. Several were not merely unasked but already **decided**: *"ASSUMED drafting position (a), hardcode — taken to keep this BRD buildable… NOT a settled product decision"* is a real product choice (hardcode vs. build a configurable rules engine) taken unilaterally and never shown to anyone. And 23 distinct free-text status strings meant nothing could count them, which is why nothing ever surfaced them.

So, **as a required step at every gate, before the gate's own questions**:

```bash
bin/open-questions.sh <project-root> --stage <N>
```

It prints a numbered, chat-ready batch — question, where it came from, and, where a BRD already took a drafting position, what was assumed. **Put it in the chat, then end the turn and wait.** The user only has to confirm or overturn each position; they should never have to go find them.

**How the batch is asked is not free-form — `interview-protocol.md` owns it.** The gate can only detect *that* you asked; it cannot detect that you asked badly, and 39 bare questions pasted in one block technically unblocks the gate while handing the user the analysis the stage was meant to do. The four rules: ask in the chat (not in a file), two named options plus your recommendation on every question, one batch per gate then stop, and write the answer back where the collector can see it. Alongside the batch, generate the report the user actually reads:

```bash
bin/questions-report.sh <project-root> --stage <N>    # → docs/open-questions.html
```

`gate-check.sh` writes it for you whenever the open-questions row blocks a gate. Give the user the path — it is openable, sortable and forwardable to a customer SME in a way a terminal dump is not, and it flags every question that arrived without a proposed answer.

The vocabulary is controlled, and only these six values are legal in a `status`:

| State | Meaning | Blocks a gate? |
|---|---|---|
| `UNRAISED` | never put in front of the user — the default for anything not positively past it | **yes** |
| `RAISED` | put to the user at a named gate, awaiting their reply | no |
| `ANSWERED` | the user decided; requires a non-empty `answer` | no |
| `ASSUMED` | agent took a position **and** the user consented after seeing it; requires `consentBy` + `consentAt` | no |
| `MOOT` | descoped by another decision; the reason is in the text | no |
| `UNRECOGNISED` | the normaliser could not place it — counts as **not done** | **yes** |

An `ASSUMED` with no `consentBy`/`consentAt` is not an assumption, it is the defect: it normalises to `UNRAISED` and blocks. `bin/gate-check.sh <project-root> <N>` enforces this and will not pass a stage carrying unraised questions. Unlike protocol staleness (which notifies), this one blocks — it is the project's own state, and an architecture built on decisions the customer never saw is exactly what §1 exists to prevent.

Note the ruling this encodes, from the user, 2026-08-12: *"At each gate, also give the option for the model to make assumptions. But it should at least raise the questions right?"* **Raising is mandatory. Assuming is permitted only after raising.** Nothing here forbids the agent from having a position — it forbids the user finding out later.

A proposal beats a questionnaire because it asks the user to **correct** something rather than supply it cold — and by the time each gate arrives, the agent has read the source and has evidence to put behind its recommendation.

**Unattended mode is opt-in, never inferred.** The "default + record + proceed" behavior (skipping the wait, not the question — questions still get logged in `PROJECT.md` open-questions) is only legal when the user explicitly said to run unattended, recorded at Stage P in `PROJECT.md` (`Interview mode: unattended`). Default is **attended**: every gate question is asked in chat and the turn ends there. (Real incident, 2026-07-14: an attended run produced architecture diagrams and a design system through Stage 3 without a single question reaching the user — "a solo run never stalls" was read as "never ask." It means "an *authorized* solo run doesn't deadlock," nothing more.)

**Reused decisions must be shown, not silently applied.** A question may only be skipped because "it was already decided upstream" if (a) that decision was itself answered by the user in chat — an agent-recorded `CONFIRMED` the user never saw is a protocol violation, not a decision — and (b) the agent **quotes the prior decision back in chat** when skipping ("skipping acceptance criteria — you confirmed at Stage 3: *'happy path + validation rules per module'*, PROJECT.md row 12"). If the user doesn't recognize the quoted decision, it wasn't theirs: re-ask it. (Real incident, 2026-07-14: Stage 4's ✋ questions were skipped citing Stage-3 decisions that had themselves been self-recorded without an interview — laundering one silent decision into a skip-license for the next gate.)

**Two open brainstorms are part of the pipeline — not everything is multiple choice.** Closed 2+1 questions capture decisions; they never surface what the user wanted to say unprompted. Two moments are explicitly *divergent conversation*, run before their gate's predefined questions:

- **Scope brainstorm (Stage 0, before triage sign-off):** present the source/requirements map with effort signals, then discuss openly — full rebuild or a slice? What is this project actually for (POC, replacement, demo)? What matters most to you, what can be dropped, what's missing from the map entirely? No option lists; talk until the user says the scope feels right, then record it.
- **Build-scope brainstorm (Stage 4, before the plan locks):** present the module/script map with rough effort, then discuss openly — build everything or a subset? Ordering by value? Anything to add, defer, or kill? Same rule: conversation first, then the closed gate questions, then `CONFIRMED`.

And at **every** checkpoint, after the 2+1 questions: one standing open-floor question — "anything else you want changed, added, or worried about — scope, priorities, anything?" — before the gate closes.

**Lightweight-change carve-out — small, unambiguous, already-decided changes skip dispatch, never skip the record.** Not every BRD/architecture edit needs the six-step protocol or a `ba-agent`/`architect-agent` round-trip. If the change is small in scope (renaming a field, adding one or two entities/attributes whose shape was already settled in the current conversation, fixing a stale line that contradicts an already-CONFIRMED decision) *and* unambiguous (no real alternatives to weigh, nothing left for the user to correct), the acting agent may edit the BRD/architecture doc directly instead of dispatching a subagent. It still MUST: (a) log a `PROJECT.md` decision row for the change, (b) set or flip the drift-sync marker on any BRD/wireframe it touched, per §3b. What this carve-out buys back is the interview/dispatch overhead, not the paper trail — a change made without a recorded decision or marker is exactly the drift this runbook exists to catch, however small the diff. Anything touching module boundaries, the security model, a new integration, or requiring a judgment call between real alternatives still runs the full protocol. (Real incident, 2026-07-23: a "flip 2 entities to persistent + add 2 new entities" change — already fully settled in conversation — was routed through ba-agent twice and architect-agent once, ~270k combined tokens, for what was fundamentally a handful of document edits. The user called it out directly. The fix isn't skipping the record, it's skipping the dispatch when there's nothing left to decide.)

**The packaged form of this protocol is a checkpoint — and checkpoints are mandatory where they exist.** `skills/checkpoints/` ships ready-made Context-Aware Checkpoints (CAC) for the six busiest transitions (scope, BRD, architecture, design, build, cutover) — each runs the protocol above as a "2 predefined questions + 1 open question" script, derived from what the pipeline actually found. Run the raw six steps only where no checkpoint exists. **A checkpoint fires *before* the next stage's artifacts are produced** — creating architecture diagrams or a design system before their checkpoint ran is a protocol violation: stop, run the checkpoint, and be prepared to throw the premature artifact away. Either way the decisions land in `PROJECT.md` — checkpoints keep no state file of their own.

A checkpoint is fixed (2+1, one fire, no follow-up). When the user believes a topic needs more
than that — "grill me on the security model" — see `skills/grill-mode.md`: on-demand, sustained,
adaptive Q&A on one topic, invoked at any moment, that follows up on hedgy answers instead of
stopping at two questions.

---

## 1b. The Live Checklist Protocol — Progress Is Shown in the Chat

Gates inform the user at stage *transitions*; this protocol informs them *during* a stage.
The failure it fixes (reported by a live user, 2026-07-14): the agent works silently against
file-based checklists for a whole stage, and the user has no idea what is being done until
the next gate. File checklists are the record; **the chat is the display.**

Rules — these apply to every stage and every per-module build loop:

1. **Post the checklist at stage/module start.** Before the first unit of work, print the
   stage's checklist in chat as a numbered list with status marks. For a build module this is
   the confirmed coverage checklist + the build-step sequence; for a pipeline stage it is that
   stage's gate row broken into its concrete steps. Keep it ≤ ~12 items — group, don't dump.
2. **Status marks:** ✅ done · 🔄 in progress · ⬜ pending · ❌ failed/blocked · ⏭ skipped
   (always with a one-line reason).
3. **Update as you go, compactly.** After each item completes or fails, post a one-line delta
   ("✅ 4/9 — domain model applied, 12 entities, 0 CE errors"). Repost the *full* checklist at
   milestones (roughly every 3–4 items, and always right before a gate) so the user never has
   to scroll back to reconstruct state.
4. **No silent stretches.** Never complete more than two checklist items without a chat line.
   Long single items (an extractor run, a big exec) get a line when they start, not only when
   they finish.
5. **Subagent work counts.** When work is delegated, the main session posts which item the
   subagent owns before dispatch, and updates the checklist from its verdict when it returns.
   Delegation is not an exemption from visibility.
6. **Chat mirrors the file, never replaces it.** `PROJECT.md`, the build plan, and stage
   checklists remain the durable record; the chat checklist is a view of them. If they
   disagree, the file is wrong or stale — fix it immediately.

The final full-checklist repost before a gate doubles as the gate's evidence: the user should
be able to approve the gate by reading that one message.

---

## 2. The Stage Matrix

Eight stages (plus Stage P kickoff). For each: what the user co-defines, what the agent produces, the review surface, the gate, and who owns it. `✋` marks a hard stop — the pipeline does not proceed past it without an explicit `CONFIRMED` decision. At non-✋ gates unknowns may resolve to `ASSUMED` — but only per §1 step 6: the question was asked and the user delegated; never because asking was skipped.

**Stages are sequential; gates are paste-proven.** Never start stage N+1's work — including launching background agents for it — before stage N's gate is closed: its `✋` decisions `CONFIRMED` **and** `bin/gate-check.sh <project-root> N` run with its output **pasted in chat**. Self-attesting "stage complete" without showing the gate-check output is a protocol violation. Parallelism is fine *within* a stage (e.g. Stage 3's blueprint and design tracks), never *across* stages — Stage 4 consumes Stage 3's *approved* outputs, so a build plan drafted alongside the architecture is a plan built on unreviewed guesses. (Real incident, 2026-07-14: Stage 3 and Stage 4 agents launched in parallel, then both stages self-declared complete with open questions outstanding, no wireframes, and gate-check never run.)

**"Let's ideate" means stop producing.** If the user asks to ideate, discuss, or explore a direction (branding, design, scope — anything), that is a request for a brainstorm conversation *now*: no artifact generation, no background agents, until the conversation converges and the user says to proceed. Producing the artifact first and offering to "review the direction together" afterwards inverts the protocol. (Same incident: the user answered a layout question with "let's ideate further on the actual design" — and the design system was generated anyway.)

**Every stage transition has a packaged checkpoint. Here is where they attach.** The `skills/checkpoints/`
CAC files run the §1 interview protocol at the busiest transitions; they write to `PROJECT.md`,
never to a separate state file. Until 2026-08-20 this runbook — the file every session is required
to read — **named none of them**, and they were reachable only from `skills/migration-pipeline.md`.
A requirements-driven session never loads that skill, so it never fired a single checkpoint, and
CAC-1's scope brainstorm silently did not exist outside migration mode. Checkpoints are wired to
*stages* here, not to pipeline phases, precisely so that a project running no pipeline still gets
them.

| Fires at the close of | Checkpoint | The question it exists to force |
|---|---|---|
| Stage 0 | `checkpoint-scope.md` (CAC-1) | Scope **in** — full scope or a slice, and in what order? Opens with a brainstorm, not options. |
| Stage 1 | `checkpoint-extraction.md` (CAC-1b) | Scope **out** — is what extraction produced what you meant? |
| Stage 2 (scaffold) | `checkpoint-brd.md` (CAC-2) | Capability grouping and enrichment order. |
| Stage 2 (validated) | `checkpoint-architecture.md` (CAC-3) | Hidden business rules before architecture locks. |
| Stage 3 | `checkpoint-design.md` (CAC-4) | Branding and UI direction. Opens with a brainstorm. |
| Stage 4 | `checkpoint-build.md` (CAC-5) | Build order and slice boundaries. Opens with a brainstorm. |
| Stage 6 | `checkpoint-cutover.md` (CAC-6) | Cutover readiness. `✋`, `CONFIRMED` only. |

**These rows are routing, not specs.** Before producing any stage artifact, open the stage's owning skill file and follow *its* output list end-to-end — the summary here (and in the README / `toolkit-guide.html`) names the highlights, not the full deliverable. (Real incident, 2026-07-14: a Stage-3 run worked from the summary, produced a design system, and skipped the one-wireframe-per-screen requirement that only `design-artifacts.md` spells out — half the deliverable, and the half the build loop depends on.)

### What a gate verdict means — and how a project that joined late says so

`bin/gate-check.sh` has five verdicts, and the difference between the first two is the point:

| Verdict | Means | Exit code on a stage query |
|---|---|---|
| `PASS` | Checked, and it holds. | 0 |
| `PENDING` | The artifact is not there at all. **Not started is not failed.** | 3 |
| `FAIL` | Something *is* there and it is wrong — or a `✋` stage has its artifacts but no `CONFIRMED` decision. | 1 |
| `WAIVED` | Declared out of scope for this project, in the register, with a reason. | 0 |
| `MANUAL` | Not machine-checkable; paste the stage's own evidence. | 2 |

An informational run (no stage argument) exits 0 whatever it finds — it is a status report.

**Not every project starts at Stage P, and the ones that don't are not behind.** A project that
wires the toolkit in mid-build, or whose entry mode does not run a stage, would otherwise carry a
permanent red row for an artifact nobody intends to produce — which teaches the reader that the
board is noise, and by the time that lesson lands a *real* failure looks identical. So the project
says where it stands, once, in the decision register:

```
Adopted at stage: 5 — build was underway before the toolkit was wired in; analysis lives in Confluence
Waived stage 6: QA runs in the client's own Cypress suite
```

One line per waived stage — a waiver is one stage's reason, and a shared reason stops being true
the moment a second stage is waived for a different one. The older aggregate spelling
(`Waived stages: 1, 2 — reason`) is still read, and is fine to hand-write for a contiguous block
that genuinely shares one reason.

Write them with `bin/gate-check.sh <project> --adopt 5 --reason "..."` or `--waive 2 --reason "..."`,
or by hand — the register line is the authority either way, and deleting it puts the stage straight
back under the gate. `--reason` is required: an unexplained skip is the thing gates exist to prevent.
Stage P is never covered by `--adopt`; the kickoff interview is how the toolkit learns what the
project is, and it costs one conversation.

**A waiver cannot hide a defect.** It excuses an empty stage, and it excuses an unsigned `✋`
decision on work the project did its own way. It does **not** touch a stage whose artifacts exist
and are inconsistent — a validation report reading *"NOT clean, 14 findings outstanding"* keeps
failing under any waiver, because that is a fact about the project and no line in a register makes
it stop being one. Entry-mode waivers are narrower still: they only ever apply to a stage with
nothing in it, since the entry mode is a statement about the *shape* of the project, not about any
artifact in it.

**Upgrading the toolkit is an offer, not a demand.** When a `git pull` changes protocol a project
depends on, `gate-check` names the stages it touches and offers three answers with equal billing:
read and ack it, ignore it for now, or record that it is not needed here. A mid-build project
hearing only "the protocol moved" guesses, and the safe-looking guess — regenerate the artifact —
is the expensive one. Acking never obliges anyone to produce anything; it records that they read it.

### Stage P — Kickoff

| | |
|---|---|
| **User defines** | Which source folder. Licence/security constraints on storing the client source. Is an SME available, and who? |
| **Agent produces** | Workspace scaffold (`bin/init-project.sh`), `CLAUDE.local.md` (paths, tools, routing), `PROJECT.md` (empty register), **all six agent stubs** (`bin/init-agents.sh <session-root>` — stubs are inert until completed, so all six exist from day one), `intake.md` (8 questions, no guesses). Complete ba/architect placeholders + domain context now (per `agent-roles.md`); complete mdl/gate/test/**review** at Stage 5 kickoff — review-agent owns `module-review.md` stage 4, the LOOK, and a project that leaves it a stub reviews no pages. |
| **Surface** | `index.html` — the project dashboard, created here, grows every stage. |
| **Gate** | Every intake question has an answer or an explicit "Unverified — how to verify". No blanks. |
| **Owner** | `ba-agent` |

### Stage 0 — Triage & Scope ✋

**Runs in every entry mode** — see "Stage 0 runs in every entry mode" under Entry Modes for which
components are N/A where. **Closes with CAC-1** (`skills/checkpoints/checkpoint-scope.md`): the
scope brainstorm is the part no mode may skip.

**Write `triage.md` (and `assessment.md`) at the project root, not under `analysis/`.**
`gate-check.sh`'s `ANALYSIS_BASE` falls back to the project root until Stage 1 creates
`analysis/<source>/knowledge-base/` — before that folder exists, a Stage 0 artifact written under
`analysis/` is invisible to the gate, which then reports the misleading *"triage.md not found"*
rather than reading what is actually there.

**First, characterise the source, then grade it. `bin/source-sufficiency.sh init <root>` → fill the
`inventory` → fill every dimension → `report`.** Nothing else in this toolkit reads a source;
`facts-lock`, `coverage-check`, `open-questions` and `gate-check` all read BRDs. Skip this and a
two-page epic deck and a validated spec enter the pipeline indistinguishably, and the gap only
surfaces at the Stage 2 interview gate disguised as a question backlog — PROJECT-C's 127 questions
were largely a silent source, not a decision backlog.

#### Two passes, and the order is the point

The rubric has an `inventory` section and a `dimensions` section, and `report` refuses to score
until the inventory is filled.

- **Pass 1 — inventory: what is this source even about?** One row per file, filled by *opening* it:
  what kind of thing it is, which rubric dimensions it can speak to, any boundary the source states
  about *itself* (quote it verbatim — a source that says what it does not cover is the cheapest
  scope signal you will ever get), and the components it names. The report prints this as a source
  overview, with a component index and the list of dimensions no source claims.
- **Pass 2 — dimensions: is it good enough to build from?** The grade, as below.

Then, and only then, **the open scope question** ("Scope brainstorm", further down this section):
present the overview, say what the corpus appears to cover versus what the user described at Stage
P, and discuss it openly. No option lists.

Doing this out of order is a real, reported failure (2026-08-19): a Stage 0 run on a four-file
documents-only corpus produced a correct ten-dimension grade and then asked the user a closed,
rubric-shaped gate question — because the grade was the only artifact in front of it. The
instruction to present a source map already existed here; nothing produced the map, so the agent
asked what the tooling gave it something to ask about. **An uncovered dimension is an open question
for a human. A low rating is a closed one. Reach the first list before the second.**

Three things come out of pass 2, and each changes what you do next:

- **A band.** `SPECIFICATION` / `OUTLINE` / `SKETCH`, with the honest sentence for describing the
  output. Below `SPECIFICATION` the output is a *proposal informed by* the source, not a conversion
  of it — say that every time you present it, including in the Stage 3 and 4 gates.
- **A recommended interview mode**, derived from the gap-versus-contradiction split rather than the
  score. Thin-and-consistent is safe to run fast: an agent can take a position on silence and record
  it, but it cannot resolve a contradiction without overruling somebody. Feed the recommendation to
  `bin/interview-mode.sh --set` **after the user agrees to it**, never before — see `interview-protocol.md`.
- **Shape-changing gaps.** Silences that redesign the model rather than fill in a detail. These are
  the Stage 0 gate questions. Everything else waits for Stage 2.

**A thin source is not a rejection.** Colleagues bring epic decks because that is frequently all
that exists, and a pipeline that answers "come back with better requirements" gets routed around
rather than fixed. The report exits 0 at 0%. The only real failure is thin input whose output is
later presented as a faithful conversion.

**If the corpus is genuinely prose only, `source-triage.md`'s extraction rows do not apply** —
there is nothing to extract from a PDF of epics. Run the sufficiency report, take the
shape-changing gaps to the gate, and mark the extraction rows N/A rather than unanswered.

**Decide that on evidence, and decide it per artifact — not off the entry-mode label.** Open the
folder first. A schema, a table dump, an ORM model, an OpenAPI contract or entity/field tables
inside a spec are extractable structure, and each earns a Coverage Matrix row and the two-way
reuse-or-build call exactly as a codebase would. A mode-shaped `N/A` is precisely how the misroute
in the next paragraph happens: the corpus reads like requirements, the whole of it goes down Path
B, and the entities that were sitting in the schema are re-typed out of prose three stages later.

**"Does not apply" stops at the extraction rows. It never reaches the scope brainstorm.** Read
that sentence as licence to move on to Stage 1 and you have skipped the one thing Stage 0 exists
for. Finish the stage: run CAC-1, get the slice ordering, sign `triage.md` off.

**A source that is documents plus a database is not a documents-only source.** A schema, a table
dump, or an ORM model file is extractable structure and grades as such — the presence of markdown
alongside it does not downgrade it. This is the shape that misroutes most often in presales
(2026-08-20): the corpus *reads* like requirements, so it gets treated as prose, and the entities
that were sitting right there in the schema get re-derived by hand later.

| | |
|---|---|
| **User defines** | Reuse-vs-build-new extraction pipeline (agent proposes with a coverage matrix — two-way call, not three-way, made per extractable structure found in the source and never off the entry-mode label; see `source-triage.md`). Policy per missing dependency: acquire / stub / declare-not-implemented. Slice ordering if the source is too big for one pass — **a slice is an ordering, not an exclusion**. |
| **Agent produces** | `assessment.md` (inventory, 6 areas, risks), `triage.md` (pipeline decision, capability + coverage matrix, boundary handling, multi-app flag) — **scaffolded by `bin/init-project.sh`**, so it is filled in rather than composed from memory. If "build new": the new extractor, validated against hand-built ground truth. |
| **Surface** | `source-sufficiency.html` (`bin/source-sufficiency.sh report`), `triage.html` (`bin/triage-report.sh <project>`) |
| **Gate ✋** | User signs off on the extraction-pipeline decision, every missing-dependency policy, the interview mode the sufficiency report recommends, and each shape-changing gap. No BRDs are written before this. |
| **Owner** | `ba-agent` |

### Stage 1 — Analysis

Three extraction methods, not two. Each is either **done** or **explicitly declared unavailable by a named person** — never silently skipped.

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

| | |
|---|---|
| **User defines** | Do documents exist that aren't in the folder (specs, manuals, field-label sheets, screenshots)? DB schema? Sample data? Who has them? SME access for what neither code nor docs answer. **Then, at CAC-1b: does the extraction output match the intended scope — accept, narrow, or re-extract.** |
| **Agent produces** | **Path A — code → AST extractors** (always runs *in migration mode*; N/A with attribution otherwise). **Path B — documents → LLM extraction** (`kb-generation.md`). **Path C — SME interview** (closes `openQuestions` that neither code nor docs answer). Plus CAC-1b's scope-out surface — the delta table when CAC-1 recorded a slice to diff against, otherwise the one-line statement of what extraction covers (a single app dropped in a folder needs stating, not interrogating). |
| **Surface** | `<kb>/extraction-report.html` — `bin/extraction-report.sh <project-root>`. One renderer for every entry mode: it reads the knowledge base, not the source, so a Path B document corpus gets the same surface as a Path A extraction, one page per knowledge base at the path the gate looks for. Each section carries a `report-schema.md` verdict, and no zero is printed unless a second record (the pre-merge `extracted/*.json`, or `reports/summary.md`) agrees with it — one method returning zero renders `manual`, not a green. Until 2026-08-20 this was `node generate-report.js` inside each pipeline, so requirements-driven and greenfield projects could not produce the file their own Stage 1 gate requires, despite this row promising it. |
| **Gate** | 4 extraction quality checks pass with evidence. Paths B and C are done or declared-unavailable, with attribution (who declared it, when). Advisory — `bin/gate-check.sh <project> 1` reports and exits 0. Record CAC-1b's outcome as a Stage-1 `Extraction scope:` decision naming what is in and what is out, so the next session isn't guessing. |
| **Owner** | `ba-agent` |

### Stage 2 — Requirements

| | |
|---|---|
| **User defines** | Confirms business rules the code implies. Answers `openQuestions` (via SME). Narrative is never invented. |
| **Agent produces** | BRD scaffolds → enrichment from `KB.md` → validation to clean. `F{NNN}.brd.json`. |
| **Surface** | `analysis/brd-report.html` — `bin/brd-report.sh <project-root>`. One renderer for every entry mode: it reads BRDs, not source, so a requirements-driven or greenfield project gets the same surface as a migration, and so does a BRD no extractor produced. Each section carries a `report-schema.md` verdict, so a section that is empty because this kind of BRD has nothing to put there reads differently from one that is empty because something broke. Until 2026-08-19 this was `enrichment-summary.html`, built three times inside three pipelines against three different BRD key shapes — each copy rendered blanks for the other two’s output, and non-migration projects got no surface at all despite this row promising one. |
| **Gate** | Every BRD validation-clean; `validation-report.md` has 0 issues; **every `openQuestions` entry raised in chat** — `bin/open-questions.sh <root> --stage 2` reports 0 blocking, which `gate-check.sh` enforces. "Chased to closure" was the old wording and it was unenforceable: a question logged with a self-answer read as closed. |
| **Owner** | `ba-agent` |

### Stage 3 — Architecture & Design ✋

The biggest gap before this runbook existed. Module boundaries, wiring diagrams and fit-gap were already handled well by `modularize-domain.md` and `architecture-blueprint.md`. Everything else on this row was a silent gap the pipeline never asked about.

| | |
|---|---|
| **User defines** | ① One Mendix app or several (if flagged at Stage 0). ② **Module boundaries** (agent proposes with `modularize-domain.md` criteria). ③ **Buy vs build vs stub, per fit-gap item** — the confirming step `brd-to-build-plan.md` assumed already happened. ④ **Target security / role model** — not just whether auth existed in the source, but what the target should be. ⑤ **Data volumes, concurrency, NFRs** — these decide indexing, pagination, datagrid-vs-paged-gallery, loop batch sizes. ⑥ **Integration contracts** — real or stub, endpoint, credentials, owner, test environment. ⑦ **Branding inputs** — logo, palette, type, spacing, per `design-artifacts.md`. |
| **Agent produces** | `.mx-brd.json`, `architecture/` (module defs, layer diagram, wiring diagram, `fit-gap.md`, `blueprint.html` checkpoint render — plus a workflow diagram and/or agent-wiring diagram in `blueprint.md`/`blueprint.html` when CAC-3's Q3 flags real scope for either, plus cross-persona journey diagrams + journey list — `architecture-blueprint.md` Step 3d — whenever the BRDs carry more than one persona; single-persona skip recorded as a one-line note, never silent), `design/` per `design-artifacts.md`'s full output list: `ds.css` + `design-system.html` + **`wireframes/*.html`, one annotated wireframe per screen** — the design system without the wireframes is half the deliverable and fails the gate. |
| **Surface** | `module-design.html` · `architecture/blueprint.html` (generated render of `blueprint.md` — architecture-blueprint.md Step 7, never hand-edited) · `design-system.html` + `wireframes/*.html` |
| **Gate ✋** | Boundaries approved. Marketplace calls made. Role model, volumes, integrations and branding **each asked and answered**: `CONFIRMED`, or explicitly delegated by the user ("you decide" → `ASSUMED` with risk). Never `ASSUMED` without the question having reached the user. **No architecture/design artifact is produced before its checkpoint ran.** |
| **Owner** | `architect-agent` (interviews run by `ba-agent`) |

### Stage 4 — Build Plan ✋

| | |
|---|---|
| **User defines** | **Acceptance criteria per module** — what "done" means beyond CE-error-free. **Environment / DTAP / deployment target.** Iteration granularity. |
| **Agent produces** | `architecture/build-plan.md` — numbered, dependency-ordered (marketplace imports → module roles → entities + entity grants → associations → microflows + execute grants → pages + view grants → demo users), grants **co-located** with the element they protect (never a deferred security script), the role-to-access table for every element, with pending decisions promoted to the top. Plus the first module's **module brief** (`architecture/modules/<Module>/module-brief.md`, per `module-brief.md`) — subsequent briefs are produced just-in-time as each module's build begins. Plus the **coverage ledger** (`architecture/modules/<Module>/coverage-ledger.md` per module; `architecture/coverage-ledger.md` for a single-BRD project — `coverage-ledger.md` §"Where the ledger lives"), generated per `coverage-ledger.md` from the BRDs and the plan's `claims:` blocks. `claims` is authored *here*, row by row, as the plan is written (`brd-to-build-plan.md` Step 5b) — required on new rows only; a plan written before the convention existed is an accepted state that reports coverage NOT MEASURED, not a defect. |
| **Surface** | `build-plan.html` |
| **Gate ✋** | Pending-decisions list empty or fully answered. Role-to-access table complete for every element. **Coverage check run** (procedure in `coverage-ledger.md`): UNCLAIMED, PHANTOM and DOUBLE-CLAIMED all empty, and the leaf counts **pasted in chat** — like `gate-check.sh` output, never attested. Every ledger entry carries a category and a reason; every `open-question` entry appears in the pending-decisions list and some row's `blockedBy`. **Every CONFIRMED decision from Stages 0–3 maps to a build-plan row id or a ledger `descoped` entry** — a confirmed decision with no build disposition is how scoped work silently vanishes (a real WMS incident: the CONFIRMED Phone-Web nav profile, wireframe and all, was never built and nothing flagged it). User approves — the coverage verdict is signed off alongside the plan. |
| **Owner** | `architect-agent` for the build plan; `ba-agent` drives each module brief (pulling `architect-agent` for the technical layer). |

> **Before Stage 5 starts — run the build-ready check:** `bin/gate-check.sh <project-dir> build-ready`.
> It asserts, in one shot, that the project is actually wired to build: `CLAUDE.local.md` has a
> `## Wiring` block, baseline routing includes the UI-quality skills, all 6 agents are present with no
> placeholders, at least one module brief exists, and wireframes + a design system are present. It
> fails loud listing every missing item. This is the preflight that catches a project that looks
> wired but is UI-blind (a real WMS-class miss).

### Stage 5 — Build

**Not migration-specific.** This is the standard Mendix build discipline — greenfield builds start here. Already well codified: layer1 (entities/associations/enums, `security-setup.mdl` last) → layer2 (microflows) → layer3 (pages); the guard chain (uncommitted → SP-open → concurrent-writer → snapshot → exec → mxbuild gate → auto-restore → manual SP reopen); the stale-build protocol; the STOP conditions in `learned-mdl-preflight.md`.

| | |
|---|---|
| **User defines** | Confirms the per-module **business-rule coverage checklist** — the definition of "done" for the module, not CE-error-free. The coverage *checklist* (per-module business rules, out of `module-brief.md`) is a different artifact from Stage 4's coverage *ledger* (`coverage-ledger.md`, BRD-leaf traceability across the whole plan) — same word, different producer and denominator. |
| **Agent produces** | Working modules, one at a time, each closed out by **one `module-review.md` pass** (below). Fixtures — the data and identities the module's checks need — are established here too, per `fixture-seeding.md`, which owns *what this app actually needs and which channel should supply it*; the project-bundled `.ai-context/skills/demo-data.md` is one channel (direct SQL insert), not the decision. You cannot validate a coverage checklist against an empty database, so seeding is part of Build. **Never seed from inside the harness** — a harness that repairs its own fixture can no longer report that the fixture was missing. |
| **Surface** | `design/ui-reviews/ui-review-<YYYY-MM-DD>.html` — the module-review report, one per pass |
| **Gate** | Every build-plan script passes its gates **and** its coverage checklist. CE-error-free ≠ done. **And the module-review report's headline states its denominator** — pages reviewed of pages that exist, journeys executed of journeys that exist. "All green" is a banned phrase whenever the denominator is not stated. |
| **Owner** | `mdl-agent` → `gate-agent`, with `review-agent`/`test-agent` on stages 3–4 of the review |

**Closing a module: there is ONE pass, `module-review.md`.** It replaces `module-completion-loop.md`
and `ui-review-loop.md`, which were two skills for one job — and the one that got skipped was always
the looking. Both files are now tombstones pointing here. Five stages, one report:

```
1. BUILD    mdl-agent drafts + validates MDL (mxcli check --references, 0 errors)
2. GATE     bin/exec.sh (snapshot -> exec -> mxbuild -> auto-restore on failure); 0 errors, lint clean
3. PROVE    the mechanical rungs: UI (Playwright) + Data (OQL/DB) + wiring-sweep
            (every clickable element, not just what a journey visits) + monkey
            pass. Deep form, when an instrument is green and you cannot say what
            would have made it red: journey-proof.md
4. LOOK     THE INTELLIGENCE CHECK — every screen in the module, not the ones a test
            visited. Is it logical? Does it look right? Does it match our design?
            Stages 1-3 cannot answer any of those. This is the stage that gets skipped,
            and the stage the escaped defects come from.
5. CONFIRM  one report, explicit denominator, a human look, then next module
```

`bin/verify-module.sh` runs the mechanical instruments of stage 3 in one shot and keeps
**"instrument faulted"** apart from **"feature failed"**. It does not perform stage 4, and a green
run buys no exemption from it — per `skills-over-scripts.md`, judgement lives in the skill and code
only fetches facts a reader cannot.

**Every N=2–3 modules, also run `process-coherence-pass.md`** — the cross-module seam check (does
the whole persona journey actually chain across the modules just closed, not just within each
one). Do not wait for Stage 6 to run it for the first time; that is how a wiring defect planted
early survives every later module-review pass, each of which only looks at its own module.
`process-coherence-pass.md` leads with `mxcli lint` QUAL004 and the `GRAPH_DEAD_ASSETS`/
`GRAPH_INTEGRATION_SURFACE` tables, not hand-rolled `SHOW REFERENCES` queries.

### Stage 6 — Test

Also not migration-specific — the shared E2E discipline (`e2e-harness-base.md`, plus the
mxcli-bundled `.ai-context/skills/test-app.md` inside the project) run across the whole app, not
per-module. Stage 5 closed each module with its own `module-review.md` pass; Stage 6 is where the
**app-wide** passes run and where the seams *between* modules are exercised — all-green modules say
nothing about the seams.

**Read `testing-shape.md` before writing or judging any test here.** It defines what testing a
module means, so it is the same thing every time, and it carries the **false-green register**: the
confirmed ways a test reports green while the feature is broken. Alongside it, `measured-claims.md`
holds the rule that gives evidence its force — *a claim not measured in that register may not be
cited as evidence.*

| | |
|---|---|
| **User defines** | Test scope beyond the golden path; which edge cases matter. |
| **Agent produces** | Playwright golden-path + edge-case tests, DB assertions, results reported verbatim. A full-app **`module-review.md`** pass: the diagnostic punch-list (`design/ui-reviews/ui-review-<YYYY-MM-DD>.html`) covering render/interaction/reuse/wireframe-divergence across **every** page, with the `ba-agent` conformance cross-check. `journey-proof.md` for any journey whose green you cannot explain — five rungs, each proven non-vacuous by a deliberately-broken control. `monkey-test.md` **after** the journeys pass, never before: a monkey run against a broken module reports the breakage as a crash and buries the real finding. `process-coherence-pass.md`, which asks what none of the above can — is the piece being tested even the right piece, and do the individually-passing pieces chain into the process the requirements describe. Optionally `e2e-evidence-report.md`, to repackage an already-rigorous run for a stakeholder who will not run anything. |
| **Surface** | `test-report.html` · `design/ui-reviews/ui-review-<YYYY-MM-DD>.html` · `docs/report.json` — the append-only contract instruments write and renderers only read (`report-schema.md`), so a renderer can be swapped without touching a harness |
| **Gate** | Golden path + edge cases + DB assertions pass. **`module-review` app-wide: zero open P1** (blank required fields, unclickable nav, empty grids, wrong-page wiring, silent save failures). **The headline states the denominator** — pages reviewed of pages that exist, journeys executed of journeys that exist, and any dimension left UNMEASURED named explicitly. A pass over 2 of 6 journeys reported as "all green" has already cost one demo. Failures fixed and re-run. |
| **Owner** | `test-agent` (E2E) + `review-agent` (the review pass is diagnostic; fixes route back through the build loop, and are never applied from inside the harness) |

> **Instruments vs. judgement.** `harness-architecture.md` is the map of the machine — which part
> owns what, which parts run standalone, and what a missing part must report (degrade loudly, never
> silently). Whether a result *means* anything is decided by the skills above, not by the scripts.

### Stage 7 — Cutover

Migration-specific — greenfield builds have no legacy system to cut over from and skip this stage. Runs **after** Stage 6, deliberately: don't migrate real production data and flip users onto an app that hasn't passed its E2E gate yet.

| | |
|---|---|
| **User defines** | Is legacy data migrated, or is the app going live empty/with only the Stage 5 seed data? Who cuts over, and when? Rollback plan? |
| **Agent produces** | Legacy-data migration scripts (if any), cutover checklist. |
| **Gate ✋** | Stage 6 passed. Decision recorded in `PROJECT.md` — even if the decision is "throw the legacy data away". |
| **Owner** | `ba-agent` → `mdl-agent` |

### Wrap-up

Promote proven patterns into `skills/learned-*.md`. **Every point where the pipeline's silence forced an improvised decision is a runbook defect** — fix it in this file or the relevant stage skill, not by working around it locally on the next project. Log new mxcli bugs in `bug-logs/mxcli-bugs.md`. Archive the project workspace.

---

## 3. The Three Project Files (No Overlap)

| File | Job | Lifetime |
|---|---|---|
| `CLAUDE.local.md` | Machine context: absolute paths, tool versions, skill routing. What agents auto-load every session. | The conversion |
| **`PROJECT.md`** | The human record: scope, dependencies (missing source deps, marketplace, integrations), every decision with its options and rationale, assumptions marked `ASSUMED` / `CONFIRMED`, open questions. Written at every gate. Carries the dependency + open-issues register (`architecture-blueprint.md` Step 5 writes here — there is no separate `architecture/open-issues.md`). | Outlives the build |
| `architecture/build-plan.md` | The executable sequence the build loop consumes and ticks off. | Dies when the build finishes |

`fit-gap.md` stays separate from `PROJECT.md` — it's analysis, not decisions.

---

## 3b. Requirements drift-sync — BRDs stay the source of truth after Stage 2

The BRDs (`analysis/knowledge-base/brd/*.brd.json`) are what every downstream stage reads:
`architect-agent` builds the blueprint from them, `mdl-agent` synthesizes scripts from them,
`gate-agent` checks coverage against them, a module brief inherits whatever they say. `PROJECT.md`'s
Decisions table is an **append-only log of what was decided** — it is not itself the current
definition of behavior. So when a Stage-3+ decision (an architecture refinement, a build-time
judgment call, a bug found mid-scripting) changes something a BRD or wireframe *already asserts* and
the BRD is never updated, the two diverge silently, and the next agent to read that BRD inherits a
stale assertion. This is a real, observed failure mode, not a hypothetical — see the incident note in
`iterative-build-loop.md` → "Requirements Drift-Sync Rule" (where the detection mechanics — which
BRD fields count as "asserted" — live).

**Ownership is split, on purpose:**
- **Whoever confirms the decision** (`architect-agent`, `mdl-agent`, `gate-agent`, or `ba-agent`
  itself) is responsible for **marking** it at the moment it logs the decision to `PROJECT.md`.
- **`ba-agent`** owns the actual **BRD/wireframe edit** (the flush) — it is the BRD artifact owner.

**Cadence — mark always, flush just-in-time, gate at the boundary** (do *not* batch by a fixed
count; the cost that matters is the drift *window*, not the sync *frequency*):
1. **Mark** every BRD-touching decision immediately, inline in its `PROJECT.md` Notes cell, using the
   marker convention below. This is ~free — one tag on a row you're already writing.
2. **Flush** (ba-agent re-syncs the named BRD/wireframe) before the next agent *reads* that artifact —
   batched, just-in-time, the same "never stockpiled" discipline the build loop uses for MDL. This
   avoids re-syncing a decision that gets revised again in the same session.
3. **Gate**: a BRD-touching decision must be flushed before any stage gate it precedes. `gate-check.sh`
   enforces this mechanically (see below) — nothing crosses a stage boundary with a pending marker.

**Marker convention** (the exact string `gate-check.sh` greps for):
- Pending: append `[sync: <files> UNSYNCED]` to the decision's Notes cell (e.g. `[sync: F003, F001 UNSYNCED]`).
- Flushed: `ba-agent` flips it to `[sync: <files> synced <YYYY-MM-DD>]`.
- Touches no BRD: no marker (the default) — or `[sync: none]` to record a conscious "checked, nothing to sync".

**Enforcement:** `bin/gate-check.sh` computes a **BRD drift-sync** line alongside the protocol-freshness
check and **blocks every stage gate** while any `[sync: … UNSYNCED]` marker remains in `PROJECT.md`
(message names the offending rows). Projects that never adopt the convention have no markers → the
check is inert (PASS) for them. This is the layer that makes the rule survive deadline pressure — a
prose-only rule was skipped for a week on a real project, which is exactly how the drift it now guards
against was introduced.

**Wireframes** follow the same mark/flush/gate rule, filtered further: only re-render a wireframe when
the decision changes something *visually observable* (new field, button, flow, state/color) — not for
logic-only changes invisible in the UI.

---

## 4. Decision Flow: mxcli vs MCP vs Studio Pro GUI

Before writing any MDL, check the STOP table in `learned-mdl-preflight.md`:

```
Write MDL  →  check the STOP table
                ├─ clean            → mxcli exec (SP closed)
                ├─ STOP → MCP       → mxcli --mcp exec (SP open) — bypasses the BSON serializer
                ├─ STOP → GUI       → Studio Pro by hand (settings, security-bearing drops)
                └─ no MDL syntax    → hand-rolled MCP (pg_patch_page)
Crashed anyway? → bin/restore-mpr.sh  (restores .mpr AND mprcontents/ — either alone is useless)
                → log it in bug-logs/mxcli-bugs.md
```

An MPR is two parts: `Project.mpr` (SQLite index) and `mprcontents/` (BSON units with the actual model). `bin/exec.sh` snapshots **both** automatically before every batch; 5 rotate; `bin/restore-mpr.sh` rolls back; git commits at phase gates are the real history. Ad-hoc `.mpr.backup` copies are banned.

---

## Checklist Before Calling a Stage "Done"

- [ ] Run `bin/gate-check.sh <project-dir> <stage>` — a stage isn't done until this passes (`PASS` or `WAIVED`). This is mechanical (file-existence/grep checks), not something to self-attest from memory. `PENDING` means not started, `FAIL` means something is there and it is wrong — see "What a gate verdict means" in §2.
- [ ] The stage's gate ran the full 6-step interview protocol (§1) for every user-facing decision — not just a yes/no on something already built.
- [ ] Every decision is written to both the stage HTML surface and `PROJECT.md`, marked `CONFIRMED` or `ASSUMED` (never silently defaulted with no record).
- [ ] `✋` gates have an explicit `CONFIRMED` decision — no `ASSUMED` allowed to pass a hard stop.
- [ ] `query-the-model.md` was followed before any question was asked (nothing asked that a query or a read could have answered).
- [ ] The stage's surface HTML is linked from `index.html`.
- [ ] Any point where the pipeline was silent and forced an improvised decision is logged as a runbook defect, not just patched locally.
