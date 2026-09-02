# Post-mortem — the evidence hierarchy was inverted (2026-09-02)

**Source.** Written by the build session of a legacy-modernisation project — an MS Access + VBA
application (~95 `.cls` form modules) over SQL Server, rebuilt on Mendix — after a module's
architecture had to be thrown away at build time and a second wave of corrections landed after
that. Anonymised for the toolkit; the numbers are the project's own.

**What each failure changed in the toolkit** is listed at the end. The skills cite this document;
this document does not restate the skills.

---

## The one-sentence version

**The evidence hierarchy was inverted.** A complete production database sat unqueried for months
while the analysis was derived from VBA source, and from BRDs that were themselves derived from that
VBA. Every significant correction, when it finally came, came from the database — and it came late
enough to invalidate work already built.

Everything below is a consequence of that, or a mechanism that let it go undetected.

---

## Failure 1 — The best evidence was available and unused

The project's own data-request document recorded the production data as **"unrecoverable"**. It was
not. A `.bak` file sat in the source folder and restored cleanly into a container: 47 tables, 926
live workflow runs, the full configuration tables.

Once queried, it answered in minutes questions that had been open for months, and *overturned* the
answers already written:

| Claim in the artifacts | What the database said |
|---|---|
| Approval is a 15-step sequential chain | A 7-leg parallel split; sequential execution would add ~54 days per run |
| A config table "enforces nothing at runtime" | 175 live rules for the current workflow version — the most actively maintained table in the app |
| Assignment is by role/department | Assignment is by *named human nomination*, captured per run |
| Classification is captured on the start form | It is captured at the first workflow station |
| Two stations don't exist in the current config | They are *retired*, and carry status on ~690 of 926 historical runs |

**Why it went unchallenged:** "unrecoverable" was written down once, early, and thereafter cited
rather than retested. It became a fact by repetition. Nobody re-ran the check because the artifact
already had an answer in the box.

**Lesson.** Rank your evidence explicitly and write the ranking into the process:

> production data > declared configuration tables > client statements > source code > *our own
> earlier conclusions*

That last term is the one that matters. Our own prior conclusions kept being treated as peers of
primary evidence instead of as the weakest tier.

---

## Failure 2 — Absence of evidence recorded as a finding

The single most repeated error. In each case an artifact asserted that something *did not exist*,
and in each case it did:

- A BRD stated a validation routine was an **"unrecoverable missing dependency"** and the rule table
  therefore "enforces NOTHING at runtime." The routine is called on line 313 of a source file that
  was in the repository the whole time.
- Two workflow stations were modelled as absent because they have no row in the *current*
  configuration. They are retired — and 692 and 691 of 926 historical runs carry their status.
- A classification vocabulary was modelled with four values because the lookup marks two of them
  *inactive*. Those two inactive values are referenced by **20 of the 60** live conditional rules.
  Modelling four would have silently dropped a third of the rule set on import.

**The pattern:** "I looked and did not find it" was written down as "it is not there." The two are
different claims and only one of them is supportable.

**Lesson.** A negative finding needs *stronger* evidence than a positive one, not weaker. Require
that any "does not exist / not implemented / unrecoverable" claim names what was searched, and
carries an expiry — re-test it when new sources land. "Retired is not absent" turned out to be a
project-wide rule, hit twice in different tables.

---

## Failure 3 — Counting presence instead of reading content

This happened **three times in one working session**, after the failure mode had already been
written down:

1. A column was non-empty on 692 runs → recorded as "real people completed this station 692 times."
   Every one of those 692 values was the literal string `'nicht relevant'` — a skip sentinel. The
   true count of humans was **zero**.
2. Source coverage was measured by grepping table names across the analysis documents → **45 of 47
   "covered."** Junk: table names like `Status`, `Protokoll`, `Exclusiv` match ordinary English prose.
3. The same measurement with a stricter quoted-identifier regex → **47 of 47 "covered."** Also junk:
   one of the documents being searched is a *schema dump that lists every table by name*.

Two mechanical attempts, opposite directions, both confidently wrong.

**Lesson.** Being *mentioned* is not being *mined*, and being *populated* is not being *used*.
Any metric that counts occurrences without reading them will produce a number, and the number will
be believed because it is a number. On this project the conclusion was to stop trying to measure
coverage automatically and hand-assign it with a required evidence link — a specific finding, not a
mention.

---

## Failure 4 — Intake answers treated as facts rather than claims

The costliest single instance: a 25-slide functional-description deck sat **unread for two months**
while four questions it directly answers stayed open. The intake questionnaire had *asked exactly
the right question* — and closed it by asserting that a downstream pass had already consumed the
deck. Nothing verified that. The assertion propagated as a fact.

**Structural cause, and this is the generalisable part:** the process tracked **questions**
obsessively — an open-questions register, a decision register, a blocking gate hook — and tracked
**sources** not at all. The knowledge base was organised by *output* (module, requirement
document), so the question *"have we actually read X?"* could not be answered by looking at it.
A file could be listed, referenced, even discussed, and still never opened.

**Lesson.** Track the input side with the same rigour as the output side. A source ledger needs, per
file: read / partially read / never opened, and for "partially" — which part, and what remains. The
dangerous state is the one that *looks* like coverage in a directory listing. On this project, once
such a ledger was finally built, it showed **39 of 95 source files were named in no analysis or
architecture document at all** — after the stages that consumed them had been marked complete.

---

## Failure 5 — Gates that check for artifacts, not for truth

Every stage gate passed. The gates verified that documents existed, were well-formed, and answered
their checklist. None verified that the claims inside them were true, because there was no
mechanism to — the checklists were written from the same understanding that produced the documents.

A concrete instance from the tooling layer: the model-editing tool's `check` command passed a script
clean that would have **silently deleted 34 attributes** from an entity, because a "create or
modify" statement with a partial member list drops every member it does not list. Syntactically
valid, semantically catastrophic. It was caught only by running it against a throwaway copy of the
model first and diffing the result.

**Lesson.** Distinguish *conformance* checks from *correctness* checks and don't let the first stand
in for the second. Where a claim is checkable against primary evidence, the gate should check it,
not check that someone wrote a paragraph about it. And for anything destructive: dry-run against a
sandbox copy, diff, then run for real. Tool output is not ground truth — the linter, the syntax
help and the schema-describe command all lied on this project at least once.

---

## Failure 6 — Architecture derived from the lossy artifact

The build stage produced a complete sequential-chain implementation — workflow definition, ~20
scripts, pages, microflows — which was then abandoned wholesale when the client said "it's parallel"
and the configuration table confirmed it.

The sequential reading was a *reasonable inference from the VBA*, which processes stations in a loop
by ascending number. It just wasn't what the system does. The topology lived in a database column
holding a delimited predecessor list — declarative configuration, ignored while the imperative code
that consumed it was read closely.

**Lesson.** In config-driven legacy systems the code is the *interpreter*, not the *specification*.
Read the tables it reads. A useful tell: if the application has an admin screen for editing
something, that something is data and its current values are the requirement — not whatever the code
appears to hardcode.

---

## Failure 7 — Numbers stated with unearned precision

Smaller, but corrosive to trust. A briefing document asserted that "~130 production runs" worked a
particular station manually. Measured: **19**. The *conclusion* built on it was correct and
survived — but the figure was overstated roughly sevenfold, and had been cited as justification.

**Lesson.** Any number in an analysis artifact either carries the query that produced it or is
marked as an estimate. There is no third category. "~130" with no provenance is not a weaker fact
than "19" with a query — it is not a fact.

---

## What actually fixed it

For reuse, the things that worked, cheapest first:

1. **Restore the production data and query it.** Highest return by an enormous margin. Roughly one
   afternoon; overturned five months of conclusions.
2. **A source ledger with hand-assigned status and required evidence links.** Answers "what have we
   not read?" — which no output-organised knowledge base can.
3. **An explicit, written evidence hierarchy**, including the clause that our own earlier
   conclusions rank *below* primary sources.
4. **Sandbox-and-diff before any destructive operation**, given that the tooling's own validation
   passes destructive changes.
5. **Re-running every open question against each newly-read source**, as standing procedure rather
   than when someone remembers.
6. **Recording corrections in a numbered register** with the measurement attached, so a superseded
   claim can't quietly resurface — several did, in documents that cited each other.

---

## The uncomfortable meta-lesson

None of these failures came from carelessness, and none would have been caught by review. The
documents were thorough, internally consistent, cross-referenced, and confident. They were also
built on a foundation nobody had gone back to check, and the pipeline's structure — output-organised,
question-tracking, artifact-gated — was very good at propagating an early wrong premise into
increasingly elaborate downstream work.

**The failure mode of a careful analysis pipeline is not sloppiness. It is a confident early
assumption that never gets retested, formatted well enough that re-testing feels redundant.**

---

## What changed in the toolkit because of this (2026-09-02)

| Failure | Where it landed |
|---|---|
| 1 — evidence inverted | `skills/query-the-model.md` → "The evidence hierarchy": production data > configuration tables > client statements > source code > our own earlier conclusions. `bin/lib/source-formats.tsv` routes `.bak`/`.mdf`/`.bacpac`/`.dmp` to "restore in a container and query", ranked top when present. |
| 2 — absence as finding | `skills/brd-validation.md` check 7: a negative claim names what was searched and carries an expiry; `retired ≠ absent`. |
| 3 — counting presence | `bin/source-ledger.sh`: per-file dispositions carry `evidence` (a finding, not a mention); a pattern disposition is accepted only when the artifact is an extractor output that lists the file by name. The name-grep stays as the floor that catches "never opened" and prints its hit count, never as the verdict. (The grep itself then failed Failure 3's own test: it lowercased bytes, ASCII-only, so 18 umlaut-named modules read as "unnamed" — a mechanical coverage count, confidently wrong, found by a fresh unattended run of the same corpus. Fixed the same day; the real count of unnamed modules is 15, not 33.) |
| 4 — intake claims | `bin/source-ledger.sh` (this morning's commit) and `skills/interview-protocol.md` → "An answer that points at another document is a claim". |
| 5 — artifacts not truth | `skills/learned-mdl-preflight.md` STOP row 23 (`diff` before `exec`) already; `skills/source-triage.md` anti-pattern "conformance is not correctness". |
| 6 — lossy artifact | `skills/source-triage.md` → "Config-driven systems: the code is the interpreter"; `skills/query-the-model.md` hierarchy puts configuration tables above code. |
| 7 — unearned numbers, fix 6 | `skills/brd-validation.md` check 7 (numbers carry a query or are marked estimate); `skills/improvement-register.md` → "Corrections" (a superseded claim, the measurement that superseded it, and where the old claim still lives). |
| fix 5 — re-run questions | `bin/open-questions.sh` reports every non-final question older than the newest inventory change as `RE-CHECK`, naming the source that arrived after it. |
