# Interview protocol — how a question is put to the user

**Read this before raising any question, at any gate, in any stage.**

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

## Who can answer this? — gap, conflict, choice

Interview mode sets *how much* gets asked. This sets *what is even eligible* to be asked, and it
is the bigger lever: it is why a gate batch is four questions instead of 127.

Every question exists for one of three reasons, and they need different answerers. Tag each BRD
`openQuestion` with `"kind"`, then run `bin/question-kinds.sh <root>`.

| kind | what it means | who answers |
|---|---|---|
| `gap` | The source is silent. No stated position is being overridden, because nobody stated one. | **An agent.** Take a position, record it with the rejected alternative and the cost if wrong. |
| `conflict` | The source says two things that cannot both be true. | **The user, always.** Resolving it means overruling somebody who will turn up at UAT. |
| `choice` | The source is clear on the *what* and silent on a fork that costs real money or is expensive to undo. | **The user.** An agent could pick; the person who eats the cost should. |

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

`bin/open-questions.sh` prints whatever drafting position the BRD recorded. Where it prints a
question with no position, **that is a defect in the stage that wrote it** — the collector and
`bin/questions-report.sh` both mark those. Do not simply forward them; take a position first,
or state explicitly why you cannot.

### 3. Batch per gate, then end the turn and wait.

Not one question per turn — that is an interrogation, and the user answers three and loses
interest. Not all 74 either. One batch, scoped to the gate you are trying to pass
(`--stage N`), grouped so related questions are decided together.

Then **end the turn**. Do not ask and keep working. Do not ask and assume in the same message.

In Claude Code, put the batch through `AskUserQuestion` where it fits — options are clickable
and the answers come back structured. Fall back to prose in chat when a question needs more
than four options or a free-text answer. Either way the batch also goes in the chat text, so
it survives in the transcript.

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
