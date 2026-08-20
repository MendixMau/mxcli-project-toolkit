# CAC-1b — Extraction Scope Checkpoint

**Fires after:** Stage 1 Analysis — every extraction path has run or been declared unavailable
**Feeds into:** Stage 2 Requirements — the BRD set
**Template:** See `checkpoint-template.md` for format rules.
**Gate:** none. Stage 1 is advisory — `gate-check.sh <project> 1` reports and exits 0. This
checkpoint is held because it is worth holding, not because something stops you otherwise. If it
was skipped, run it late against the BRDs that already exist; see "Running this late", below.

---

## Why this checkpoint exists

CAC-1 confirms scope **in**: what we intend to cover, decided before extraction from a capability
map. It is the right conversation and it cannot do this job, because at CAC-1 nobody yet knows
what extraction will actually produce.

Added 2026-08-20, from a customer round. Extraction ran across a whole corpus rather than the
subsystems under discussion. Nothing downstream noticed, and nothing downstream *could* have:
every remaining gate in the runbook measures quality, and the output was perfectly good BRDs about
the wrong things. **A validation-clean BRD for a subsystem nobody asked for passes Stage 2, passes
coverage-check, and is discovered during the build.**

The delta between intended and actual scope is visible for exactly one moment — after the
extraction report exists and before the BRD set does. That moment is this checkpoint.

**Run it before any BRD is written.** Not "before enrichment", not "before validation" — before
scaffolding. A BRD set is precisely the artifact that makes narrowing feel expensive, and a
checkpoint that asks "shall we throw some of this away?" gets a different answer depending on
whether the thing being thrown away exists yet.

---

## What to Surface

**If CAC-1 recorded a slice, build the table below** — it is then the entire checkpoint, and it
has three columns because two of them are already on record: the work is the diff, not a fresh
inventory.

**If it did not** — the ordinary one-app case, where nobody narrowed anything because there was
nothing to narrow — there is no left-hand column and a three-column table would be theatre. The
surface is then the single sentence in Q1: name what extraction covers, say BRDs will follow for
all of it, and move on. Do not manufacture an "intended" column so the table has something in it;
`## Upstream / downstream` at the foot of this file already forbids inventing one retroactively.

Pull **intended scope** from `PROJECT.md` → `## Decisions` → the CAC-1 slice ordering, and from
`triage.md` → "Recommended Scope Subset".

Pull **actual output** from `analysis/<source>/knowledge-base/extraction-report.html` and the KB
itself — module/capability names, entity counts, screen counts, logic counts.

| Capability | Intended at CAC-1 | Extraction produced | Delta |
|---|---|---|---|
| Order Management | in slice 1 | 6 entities, 8 screens | — matches |
| Reporting | deferred | 11 entities, 20 screens | **extra** — extracted but out of scope |
| Notifications | in slice 1 | nothing | **missing** — expected, not found |

Then state the three numbers plainly, because they are what the user is actually deciding about:
**N capabilities in scope, M extracted, and the count of entities/screens attributable to the
difference.** "We extracted 31 entities; 11 of them belong to Reporting, which you deferred" is
the sentence that makes this checkpoint work.

### Two deltas, and they are not symmetrical

- **Extra** — extraction reached past the confirmed scope. Cheap to fix now (exclude it from the
  BRD set), expensive to fix later (it is built). This is the failure mode the checkpoint was
  created for.
- **Missing** — a capability that was in scope produced nothing. This is *not* a scope question,
  it is an extraction failure or a source gap, and narrowing scope to hide it is the wrong answer.
  Route it back to Stage 1: does the extractor not cover this shape, or is it genuinely not in the
  source? Say which, in chat, before asking Q1.

**Do not present "extra" as a bonus.** More coverage than asked for reads as generosity and is
recorded as progress; it is unreviewed work that will be maintained, tested and demoed as though
someone chose it.

---

## Predefined Questions

### Q1 — The extra

**Default: do not ask. State it.** The common case is one app dropped in a folder, and there the
answer is obvious to everyone in the room. A checkpoint that asks anyway is friction, and friction
is what gets a checkpoint routed around rather than fixed — the same reasoning
`bin/source-sufficiency.sh`'s header gives for not refusing thin input.

So the default path is one line in chat, always written, never skipped in silence:

> "Extraction covers Orders, Inventory, Shipping and Users — that's the app you gave me. BRDs for
> all of it unless you say otherwise."

That costs the user nothing to read and no turn to answer, and it is what makes a wrong scope
visible: if that list holds something they did not expect, they say so right there. **Silence does
not do that job.** Until 2026-08-20 the skip path was "the delta is empty, move on", which in
practice meant nothing was said at all — and a delta computes as empty both when extraction
matched the agreed slice *and* when no slice was ever agreed, which is the case this checkpoint
exists for. The statement is the fix; it is cheap enough to be unconditional.

**When to ask a real question instead:** when the output is not plausibly one coherent app
matching what has been discussed. Any of:

- capabilities appear that nobody has mentioned in this project — the failure this checkpoint was
  created for (*"extraction reached far past the subsystems under discussion"*)
- the output plainly spans more than one system, not one app with several modules
- CAC-1 recorded a slice and the output exceeds it
- the volume is large enough that "all of it at once" is not a credible first pass, so a first
  slice is a genuine decision rather than a formality

**Do not ask on ritual.** "No scope decision is on record" is not by itself a reason to ask — for
a single app it is the expected state and the statement above covers it. Ask when there is
something to decide, not when a field is empty.

**How to generate options:** Name the out-of-scope capabilities and their weight (entities +
screens). Recommend narrowing unless the user's Stage 0 answer was an explicit full-scope
commitment.

> "Extraction produced [M] capabilities; [K] of them weren't in the slice you confirmed at Stage 0
> — [names], about [N] entities and [S] screens. What do you want in the BRD set?"
> - A) Only the confirmed slice — park the rest; the extraction output stays on disk and nothing is re-run if you want it later *(recommended)*
> - B) All of it — treat the wider extraction as the real scope, and re-confirm the slice ordering for the larger set
> - C) The slice plus [specific capability] — [reason it earns its place]

**Record as:** `PROJECT.md` → `## Decisions` → `Extraction scope:` — list what is **in** and what
is **out**, by name. Both halves, in the Decisions table rather than as a free-text note
elsewhere — "what is out" is the half that gets lost, and the next session reads the table.

**The statement path records too, and records honestly.** When no question was asked, the row is
still written — `Extraction scope: all of <app>, in full (Orders, Inventory, Shipping, Users);
out: nothing` — marked `ASSUMED`, not `CONFIRMED`, unless the user actually answered. Stating a
scope and having nobody object is not the same as being asked and choosing, and the register
should not claim otherwise. `ASSUMED` here is earned the way `interview-protocol.md` requires:
the user was told, in chat, in a sentence they could have objected to.

If the answer is A or C, **say what happens to the excluded output**: it is not deleted, it is not
BRD'd, and Stage 2's coverage denominator is the confirmed set — not everything on disk. A
coverage figure quoted against the wrong denominator is how "100% covered" and "half the app is
missing" end up both being true.

---

### Q2 — Extraction quality on the in-scope set

**When to ask:** Always. Scope and quality are separate questions and this is the cheapest moment
to ask the second one — the user is already looking at the numbers.

**How to generate options:** From the extraction report's own quality signals — unresolved FKs,
files parsed vs. skipped, capabilities with suspiciously low counts relative to their size in the
CAC-1 capability map.

> "Within the confirmed scope, [capability] extracted [N] entities from [F] files but [X] files
> were skipped / [Y] FKs are unresolved. How do you want to proceed?"
> - A) Proceed to BRDs and carry the gaps as `openQuestions` — they surface again at the Stage 2 gate *(recommended when gaps are few and localised)*
> - B) Fix the extractor and re-run Stage 1 for [capability] before any BRD is written
> - C) Proceed, and close the gaps with an SME pass (Path C) in parallel with BRD scaffolding

**Record as:** `PROJECT.md` → `## Decisions` → `Extraction quality accepted:` with the named gaps.

---

## Open Question

> "Is there anything in the extraction result that doesn't look like your system — names you
> don't recognise, modules you thought were dead, or something you expected to see and don't?"

**What to do with the answer:**
- *Names you don't recognise* → often a vendored library or a dead branch that triage should have
  filtered. Exclude, and note the miss so `source-triage.md`'s capability map improves.
- *Thought it was dead* → a scope question that just changed, not a quality one. Re-run Q1.
- *Expected and missing* → the "missing" delta above; back to Stage 1, do not narrow around it.

---

## Entry-mode notes

This checkpoint runs in **every mode that produces a knowledge base** — the word "extraction" in
the title is about the *output*, not about whether an AST extractor ran.

| Mode | What "extraction produced" means here |
|---|---|
| Migration | Path A extractor output, plus anything Paths B/C added. |
| Requirements-driven | The KB that `kb-generation.md` built from the document corpus. The same over-reach happens — a document set covers more ground than the slice under discussion, and an LLM extraction pass will happily represent all of it. |
| Greenfield | No KB, no checkpoint. Scope was settled at CAC-1 and there is no extraction result to diff it against. |

---

## Running this late

Nothing blocks on this checkpoint, so it will sometimes get skipped — most often because the
extractor half of Stage 0 genuinely did not apply to the source and the scope half got waved
through with it. That is recoverable, and the recovery is not "go back and do it properly".

Run the same two questions against the BRD set that already exists. The left-hand column of the
delta table is whatever scope statement you have — a CAC-1 decision if one was recorded, otherwise
the user's own description of what the project is for, obtained by asking. The right-hand column
is the capability list the BRDs actually cover. Everything else works unchanged.

Late is not worse input. At CAC-1 the intended scope is a guess about what a corpus contains; here
you can read what came out. What late costs is *narrowing effort* — parking a capability once BRDs
exist for it feels like throwing work away, which is exactly why it gets rationalised into scope.
Name that pressure out loud when you present the table, or it will quietly decide the answer.

Do not re-run extraction to make this checkpoint look like it happened on time.

---

## Upstream / downstream

**Upstream:** `checkpoint-scope.md` (CAC-1) — when that one recorded a slice, this checkpoint
diffs against it. When it did not, this checkpoint is not void: it falls back to Q1's statement
path, which is the right answer for the ordinary one-app project and needs no left-hand column.
Never invent an intended scope retroactively so the table has one.

Send the user back to CAC-1 only when the statement cannot honestly be made — the output spans
things nobody has mentioned, or more than one system. Then the missing scope conversation is the
actual problem and it is cheaper to have it now than to BRD around it.

**Downstream:** `checkpoint-brd.md` (CAC-2) — capability grouping, over the set this checkpoint
confirmed.
