# Interview protocol — how a question is put to the user

**Read this before raising any question, at any gate, in any stage.**

**Requires:** bash and Python 3 — this skill runs toolkit shell scripts. Run `bin/doctor.sh` once on a new machine; it names anything missing and how to get it. Windows: use Git Bash, and see the Prerequisites section of `conversion-runbook.md`.

The pipeline has always *generated* questions. It has never been good at *asking* them.
Measured on one real project: 46 rows in `sme-questions.md` against 7 recorded answers, and
BRD statuses reading `ASSUMED drafting position (a), hardcode … NOT a settled product
decision` — real product decisions taken unilaterally and buried in a JSON field nobody opens.

`bin/gate-check.sh` now blocks on that (`Open questions (raised?)`). This skill is the other
half: it says what "raised" has to look like. A gate can only detect that you asked. It cannot
detect that you asked *badly* — a wall of 39 bare questions technically unblocks the gate and
is worse than useless, because the user now has to do the analysis the stage was meant to do.

---

## Interview mode — how much involvement this app wants

How much interviewing is right is a property of the app, not of the toolkit. Read it before
deciding whether to stop:

```bash
bin/interview-mode.sh <project-dir> --explain
```

| Mode | Behaviour |
|---|---|
| `steering` | Every consequential question goes to the user. The gate blocks until it does. **The default**, including for any project that has not stated one — an unconfigured project is one whose risk appetite nobody has declared. |
| `assist` | Questions batched at gates only. Low-consequence ones are assumed and reported rather than asked. |
| `auto` | Nothing blocks. You take positions and keep moving — **and record every one of them**. |

Set it with an `Interview mode:` line in `PROJECT.md` (project default), or
`bin/interview-mode.sh <dir> --set assist` (this session), or `$CLAUDE_INTERVIEW_MODE` (one
command). Any unrecognised value anywhere falls back to `steering` and says so: the failure
direction of a typo must be "asked too much".

**`remote` is a flag, not a fourth mode.** It says the user is not at the keyboard, so gates
message them and the run continues rather than parking. It changes the *channel*, never how
much gets decided for them.

**Do not set the mode yourself to get past a block.** How much the user is consulted is not a
choice you get to make on their behalf. Tell them the knob exists and let them turn it.

### What `auto` obliges you to do

`auto` buys speed by moving the safety net from *asking* to *recording*. If the recording is
sloppy the mode is simply the original failure — decisions buried in a JSON field — with
permission. Every position taken under `auto` records four things:

- the assumption you took;
- the alternative you rejected, named;
- what it costs if you are wrong, and whether it is reversible;
- `status: ASSUMED` with `consentBy: auto-mode` and `consentAt: <timestamp>`.

`consentBy: auto-mode` is deliberately not a human name. It is honest — no person agreed to
this — and it is machine-readable, so the report can lead with *"assumed while you were away,
overturn any of these"* instead of burying them among questions that were genuinely answered.

---

## Who can answer this? — gap, conflict, choice, user-only

Interview mode sets *how much* gets asked. This sets *what is even eligible* to be asked, and it
is the bigger lever: it is why a gate batch is four questions instead of 127.

Every question exists for one of four reasons, and they need different answerers. Tag each BRD
`openQuestion` with `"kind"`, then run `bin/question-kinds.sh <root>`.

| kind | what it means | who answers |
|---|---|---|
| `gap` | The source is silent. No stated position is being overridden, because nobody stated one. | **An agent.** Take a position, record it with the rejected alternative and the cost if wrong. |
| `conflict` | The source says two things that cannot both be true. | **The user, always.** Resolving it means overruling somebody who will turn up at UAT. |
| `choice` | The source is clear on the *what* and silent on a fork that costs real money or is expensive to undo. | **The user.** An agent could pick; the person who eats the cost should. |
| `user-only` | The answer is not a property of the source at all. It is a fact about the user's organisation, and it lives in their head or in a document you have never been shown. | **The user, and only the user** — with **no recommendation** and **never inside a batch**. See below. |

### `user-only` — the silence you are not entitled to fill

`gap` and `user-only` both begin "the source is silent", and they route in opposite directions.
That makes this the tag most often got wrong, and the one where being wrong invents an answer on
somebody's behalf.

The test is not "did the source say?" but **"could the source ever have said?"** A `gap` is
silence about something that was never written down anywhere — field lengths, a default sort
order. A `user-only` is silence that only means *you were not handed the document*. The brand
guideline exists or it does not, and the user knows which; your not having seen it is a fact
about your inputs, not about the world.

Typical `user-only` questions, none of which a source can answer:

- Is there a brand guideline, a style guide, an existing design system?
- What accessibility standard applies — WCAG 2.1 AA, something else, nothing stated?
- Expected concurrent users, data volumes, retention and residency requirements.
- Who is the SME for this area, and who signs the gate off?
- Licensing: is there a subscription for the marketplace module this needs?
- Cutover date, freeze windows, and what "done" means for this phase.

**Two constraints, and they are the whole point of the kind:**

1. **Never carry a recommendation.** Rule 2 below requires two options and a recommendation for
   every other kind. Here a recommendation is a fabrication with a default bolted on — you have
   no basis, and dressing a guess as analysis is what makes it get approved. Say plainly that you
   cannot know, and state what you will assume **only if they decline to answer**.
2. **Never batch-approvable.** It cannot be one line of a batch that can be cleared with "approve
   all as recommended", because there is no recommendation to approve. Ask it on its own.

*Real incident, 2026-08-19 (PROJECT-B).* "Are there branding inputs?" went in as line 7
of a seven-item Stage 3 gate batch, carrying the recommended default *"no branding assets
provided — use Atlas defaults."* The user approved the batch. There was in fact a real art
direction — top-bar layout, industrial look, grey background, cool colours, the client wordmark in
the shell — and a WCAG 2.1 AA target, and neither had ever been asked for. Both surfaced only
when the user challenged the finished design system and asked why nobody had checked. The
question had been treated as a `gap`. The recommendation was the entire defect: it converted
"I don't know" into "I've decided", and a batch approval swallowed it.

**Design-system questions specifically.** Branding and accessibility are `user-only` on every
project and are asked plainly and separately at the design step — not folded into a batched
recommended-default line. This is a standing checklist item in `design-artifacts.md`, not
something that comes up only after a user catches it being skipped.

**What the tooling can and cannot do here.** `bin/question-kinds.sh` counts `user-only`
separately, routes it to the human, and prints both constraints. It cannot tell that a question
tagged `gap` should have been `user-only` — a counter sees the tag, never the question. Getting
the tag right is yours.

**Do not ask a human a `gap`.** *"How long is the member name field?"* has no answer in anyone's
head — the source never said, and the user is being asked to invent a number so the agent doesn't
have to. That is the theatre that makes people stop reading gate batches, and once they stop
reading, the `conflict` two items below it gets waved through as well.

**Never re-tag a `conflict` as a `gap` because the right answer looks obvious.** Obviousness is
not authority. If one side of the contradiction is clearly wrong, say which and why *in the
question* — then still ask.

An untagged question counts as needing a human, and is reported as `UNCLASSIFIED` rather than
folded into `choice`, so untriaged work stays visible instead of inflating the user's list. Same
failure direction as interview mode: a mistake must resolve toward being asked too much.

Where the kinds come from: `bin/source-sufficiency.sh` at Stage 0 produces the first `choice`
list for a project — the silences that reshape the model rather than fill in a detail.

---

## The four rules

### 1. Ask in the chat. Do not ask in a file.

A question written into `sme-questions.md`, a BRD's `openQuestions`, a handoff doc, or a
report has not been asked. Those are the *record*; the chat is the *channel*. If the only
place a decision appears is a file, the user never saw it.

The user's words for this: *"usually they are very hidden and hard to steer."*

### 2. Every question carries two named options and your recommendation.

Never hand over a bare question. You have read the source; the user has not. The minimum
shape:

> **H1 — Mandatory fields (Mußfelder)**
> The legacy app validates required fields per workflow station, but the algorithm
> (`PflichtfelderPrüfen`) is missing from the corpus.
> - **(a) Hardcode** the required fields we observed per station. Buildable now; a rule change
>   later is a code change.
> - **(b) Configurable engine** — admin-editable rule table. Matches the legacy intent, adds
>   roughly a module of work, and we would be guessing at the rules anyway.
>
> **I recommend (a)** for the POC: (b) costs real time to model a ruleset we cannot verify.

Two options is the floor, not the target. Where the honest answer is "I need a number or a
name from you" (a threshold, a system owner, a cutover date), say so plainly and say what you
will assume if they shrug.

**Exception, and it is the one exception: `user-only` questions carry no recommendation.** A
threshold, a system owner, a cutover date, a brand guideline, an accessibility target — you have
no basis for a position on any of them, and offering one anyway is how it gets nodded through.
The shape there is *"I can't know this and you can"*, plus what you will assume only if they
decline. Everything else on this page still applies: it goes in the chat, and you stop.

`bin/open-questions.sh` prints whatever drafting position the BRD recorded. Where it prints a
question with no position, **that is a defect in the stage that wrote it** — the collector and
`bin/questions-report.sh` both mark those. Do not simply forward them; take a position first,
or state explicitly why you cannot.

### 3. Batch per gate, then end the turn and wait.

Not one question per turn — that is an interrogation, and the user answers three and loses
interest. Not all 74 either. One batch, scoped to the gate you are trying to pass
(`--stage N`), grouped so related questions are decided together.

Then **end the turn**. Do not ask and keep working. Do not ask and assume in the same message.

**`user-only` questions do not go in the batch.** A batch is answerable in one pass — often with
a single "approve all as recommended" — and that is exactly what must not happen to a question
with no recommendation behind it. Ask each one separately, before or after the batch, and wait
for its own answer. If that means two stops at one gate, take two stops.

**And approving a batch approves the decisions, not an execution run underneath them.** The
concrete choices you make while building the artefacts those decisions produce — role names, an
NFR number nobody gave you, page layouts, palette values, a specific technical workaround — are
new decisions, not consequences of the approved ones. Surface them per artefact. The cheapest
form that works: end each artefact with **"decided without you"** — at most five lines naming
what you chose on your own. On 2026-08-19 a seven-item Stage 3 approval was followed by twelve
files, an invented concurrency figure and an installed mock server with no check-in at all, and
the user's *"why did you not ask for any inputs for these steps!!!!"* is the only reason it
surfaced.

In Claude Code, put the batch through `AskUserQuestion` where it fits — options are clickable
and the answers come back structured. Fall back to prose in chat when a question needs more
than four options or a free-text answer. Either way the batch also goes in the chat text, so
it survives in the transcript.

#### Asking on a non-Claude agent

**This is the canonical statement. Every other file in the toolkit that names `AskUserQuestion`
points here rather than restating it.**

`AskUserQuestion` is a Claude Code **built-in harness tool**. It is not a package, not an MCP
server, not a skill, and there is nothing to install. Copilot, Cursor, Windsurf, Continue and
Aider — all of them wired by `bin/wire-agents.sh`, all of them first-class consumers of this
toolkit — have no equivalent and no way to add one.

So separate the *invariant* from its *rendering*. Three things hold on every agent:

1. **The question reaches the human, in the chat**, as a small set of numbered options with
   "something else" always available — never buried in a file, never a bare question.
2. **The agent then ends its turn and waits.** It does not answer its own question. It does not
   ask and keep working in the same message.
3. **`ASSUMED` is earned only by asking** and being told "you decide" — never by skipping.

Only (1)'s rendering is tool-specific:

| Harness | How the batch is rendered |
|---|---|
| Claude Code | `AskUserQuestion` — clickable options, structured answers. Preferred; also paste the batch as chat text so it survives compaction. |
| Copilot, Cursor, Windsurf, Continue, Aider, anything else | Plain numbered markdown in the chat — `1.` / `2.` / `3. Something else — tell me`. Then stop. |

Both satisfy the protocol. **Neither is optional**, and the *end-the-turn* half is not
tool-specific at all — it is the half that actually enforces the gate, and the half a harness
without `AskUserQuestion` will drop first, because "I can't call that tool" reads as "skip this
step" rather than "render it differently".

*Why this is spelled out (real incident, 2026-08-19).* A dry run of this toolkit on GitHub
Copilot on Windows produced the question *"AskUserQuestion doesn't seem installed, is that
something we can include in the setup?"* It cannot be. Until then every call site here named
the tool as **the** mechanism, so on a non-Claude agent the instruction was simply
unfollowable — and an unfollowable gate is not a loud failure, it is a silent skip. Same shape
as the Stage P false-green: the enforcement quietly evaporates and nothing says so.

### 4. Record the answer where the collector can see it.

An answer that lives only in the chat is lost at the next compaction. Write it back to the
source that raised it:

| Source | Where the answer goes |
|---|---|
| `analysis/**/sme-questions.md` | the row's answer/status column |
| `*.brd.json` `openQuestions[]` | `status`, plus `answer` |
| A decision that changes scope | also `PROJECT.md`, per `close-the-loop.md` |

States the collector recognises — anything else normalises to `UNRECOGNISED` and blocks:

| State | Means |
|---|---|
| `UNRAISED` | never put to the user. **Blocks.** |
| `RAISED` | asked, awaiting the answer. Does not block. |
| `ANSWERED` | settled, answer recorded. |
| `ASSUMED` | you took a position **and the user consented** to you taking it. Requires `consentBy` and `consentAt`. Without both it normalises to `UNRAISED` and blocks — a position the user never saw is not an assumption they made. |
| `MOOT` | descoped. Genuinely dead, not quietly dropped. |
| `UNRECOGNISED` | an unparseable status. **Blocks**, on purpose. |

Set `raisedAtGate` to the gate where you actually put it to the user. It is a different field
from `raisedAt` and the collector reads both.

---

## An answer that points at another document is a claim, not an answer

The one form of answer that reads as settled and cannot be trusted: *"X already covers this."*
Verbatim, from a real intake (2026-09-02, Q4 "documents not yet accounted for?"):

> the `.pptx` is already inside `source/<track>/` and was already used as triage input by the
> Group A–D triage pass (see `<track>-triage.md`) — nothing additional exists outside the folder.

The triage never named the deck. Two months of downstream artifacts inherited the gap, because
once Q4 read "answered" nothing had a reason to look again. The answer *cited a document*, which
is exactly why it was believed.

**Rule.** Before recording an answer of the form "X already handled Y": open X and find Y in it —
`grep -il "<Y's name>" X`. Zero hits means the answer is "not yet accounted for", whatever the
session remembers. Then record the disposition where the gate reads it, not in prose:
`bin/source-ledger.sh mark <project> <Y> --artifact X --by <who>` — the Stage 1 gate performs
the same grep and refuses a claim that does not hold up. For a source file the register line
`Waived source <Y>: <reason>` (written by `gate-check.sh --waive source/<Y>`) is the only
"we are deliberately not reading this" that counts. The same discipline applies one layer up:
an intake answer that says the source cross-checks a schema claim is verified against the
source, not against the memory of having checked.

## The report

```bash
bin/questions-report.sh <project-dir> [--stage N] [-o out.html]
```

Default output `<project-dir>/docs/open-questions.html`. It shows what was examined (BRD count,
sme-questions files, duplicates collapsed), the count per state, and every question grouped by
state with blocking states first. Questions arriving with no proposed answer are flagged
individually and counted in a banner.

`gate-check.sh` writes it automatically when the open-questions row blocks a gate. **Give the
user the path** — this is the artefact they asked for, and it is the thing they can open, read
in their own time, and forward to a customer SME.

Exit codes match the collector: `0` clean, `1` blocking questions exist, `2` usage/render
error, `3` **nothing was examined** — no BRDs and no `sme-questions.md`. Three is not clean; it
means the instrument read nothing, and the script refuses to write a report that would look
like an all-clear.

---

## Progress updates, not just questions

The same failure mode applies to status. Work that only appears in a terminal has not been
reported. At every gate, in the chat:

1. What was done since the last gate, in plain language.
2. What the gate checked and what it said — paste the verdict lines, not a paraphrase.
3. What is still open, with the report path.
4. The batch of questions, per the rules above.
5. Then stop.

A gate is a conversation with the user, not a script's exit code.

---

## Related

- `bin/open-questions.sh` — the collector; `--json` for machine use, no flag for a chat batch.
- `bin/questions-report.sh` — the HTML triage report.
- `skills/conversion-runbook.md` §1 — gate mechanics.
- `skills/close-the-loop.md` — writing a decision back into `PROJECT.md`.
- `skills/brd-generation.md` — the stage that must stop emitting bare questions.
- `skills/grill-mode.md` — a fixed gate batch not enough on one topic? On-demand, sustained,
  adaptive Q&A that follows up, invoked at any moment on any topic.
