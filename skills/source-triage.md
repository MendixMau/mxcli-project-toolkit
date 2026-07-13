# Source Triage — Coverage, Scope, and the Go/No-Go Gate Before Extraction
**Applies to:** migration.
**Purpose:** Before generating any BRD, decide whether this toolkit's pipelines already cover the source stack or a new extractor needs building, and — if the source is large — recommend a bounded scope subset (an ordering, not an exclusion) instead of processing everything at once.
**Upstream:** `migration-pipeline.md` Phase 1 (Source Analysis) — run this immediately after identifying the platform (1.1) and before scoping the extraction (1.3).
**Downstream:** `migration-pipeline.md` Phase 2/3 (extraction + BRD scaffolding) — **gated** on this skill's output. `modularize-domain.md` (module boundaries within *one* app — assumes the "how many apps" question this skill raises is already answered).
**Companion:** `assess-migration.md` (the manual technical/functional inventory this skill's coverage matrix checks against), `qa-loop-goal-pattern.md` (how to validate a newly-built extractor once this triage says one is needed).

---

## When to Use This Skill

- Starting a migration from a new or unfamiliar source stack
- Deciding whether to reuse an existing pipeline (`pipelines/outsystems/`, `pipelines/java-angular/`, `pipelines/node-express-react/`) or build a new one for this source shape
- The source app is large enough that "migrate everything at once" feels risky, or big enough that even module-level decomposition (`modularize-domain.md`) might not be sufficient
- You're about to run `node run.js 3` (BRD scaffolding) on a stack nobody has validated extraction quality for yet

---

## Core Principle

**Do not generate BRDs, let alone start the Mendix build, until this triage produces three things:** an extraction-approach decision, a coverage/gap list, and — if the source is large — a bounded scope recommendation. Running Phase 3 before this is settled produces BRDs for a scope nobody agreed to, from a pipeline nobody confirmed is reliable for this stack.

**Always stand up an extractor — reuse where one already covers this stack, build new otherwise.** Field finding: reading source without an extractor missed information even on small, cleanly structured apps — manual reading is not a substitute for the coverage an extractor gives you, it's a different (weaker) tool. The extractor *is* the coverage gate: it's what lets Step 3 below actually answer "is this reliable enough to trust," instead of relying on how thorough a manual read happened to be. There is no manual-only path anymore.

---

## Step 1: Reuse or Build New?

This is a two-way call, not three-way — decide explicitly which side of it you're on, don't default into whichever the last project did:

| Signal | Lean toward |
|---|---|
| Source platform already covered by `pipelines/outsystems/`, `pipelines/java-angular/`, or `pipelines/node-express-react/` **and its layout assumptions actually match this source** (check the pipeline's own README/companion skill — e.g. `source-node-express-react.md`'s layout table — before assuming "same stack name" means "reuse cleanly") | **Reuse existing pipeline** — run Phase 2 as documented. |
| Source platform matches nothing in `migration-pipeline.md` 1.1's platform table, or matches a pipeline whose layout assumptions don't fit this source (e.g. `node-express-react`'s regex passes assume a specific directory layout the current source doesn't use) | **Build new pipeline** (or extend the closest existing one) — validate it against hand-built ground truth per `qa-loop-goal-pattern.md` before trusting its output, regardless of app size. |

**This call is the user's, not the agent's.** Lay out the signal (stack match, layout fit, effort) and a recommendation, then wait for the user to pick — don't silently record a decision and proceed to Phase 2 on your own read of the signal, even when it looks one-sided. Record the decision explicitly as one of: **Reuse existing pipeline / Build new pipeline**, with who confirmed it. If "build new," `qa-loop-goal-pattern.md` governs validating the new extractor/linker/mapper against real source until output quality is genuinely high — don't skip straight to trusting its first run, and don't fold pipeline-development time into the migration timeline as if it were a fixed cost. A small app still gets an extractor; it just means the extractor is small too — see Core Principle above.

---

## Step 2: Business Capability Map

Map technical modules/components/services to business capabilities — not source file or class names. This is the shared input both Step 4 (scope) and `modularize-domain.md` (module boundaries) need later; do it once, here.

| Business capability | Source components | Rough size (entities/screens) | Owner / team (if known) |
|---|---|---|---|
| e.g. Order Management | `OrderController`, `OrderService`, 3 JSPs | 4 entities, 5 screens | Sales team |
| e.g. Inventory | `ItemController`, `StockService` | 2 entities, 3 screens | Warehouse team |

---

## Step 3: Coverage Matrix — What Can Actually Be Extracted, Mapped, and Trusted

Per business capability, answer the questions that decide whether its BRD comes from automation or a human:

- Can this be extracted automatically (does an extractor for this source shape exist)?
- Does a mapper exist to turn that extraction into a BRD?
- Is the output reliable enough to trust without heavy rework (check against `migration-pipeline.md` Phase 2's quality checklist once a sample run exists)?
- If not: does this need a new extractor, a new mapper, or is it just better done manually?

| Capability | Extractable? | Mapper → BRD? | Reliable? | Verdict |
|---|---|---|---|---|
| e.g. Order Management | Yes (Java extractor) | Yes (`domain-entity-mapper`, `microflow-mapper`) | Yes — sample checked | **Ready** |
| e.g. Reporting (JasperReports) | No extractor for this | — | — | **Manual** |
| e.g. Legacy batch jobs | Extracts fine | No mapper for cron/batch shape yet | Untested | **Extract-only** — needs a mapper built |

Verdict vocabulary (mirrors `architecture-blueprint.md`'s fit-gap vocabulary on purpose, so the two stay legible together): **Ready** (extract + map today, trust the output) · **Extract-only** (JSON extracts fine, no mapper yet) · **Manual** (skip automation, write this capability's BRD by hand) · **Defer** (out of scope for this phase, revisit later) · **Unknown** (can't assess yet — needs a spike).

---

## Step 4: Bounded Scope Recommendation

**A slice is an ordering, not an exclusion.** Not always a "POC" either — a bounded subset matters whenever the source is large, whether the actual goal is a proof-of-concept, a phased rollout, or an eventual full migration done in slices. Don't force POC framing onto a project that's committed to a full migration from day one — the underlying decision (which capabilities go first) is the same either way. Whole source is always in scope; recommending a slice decides sequencing, not what gets dropped.

Recommend a first slice from Steps 2–3: capabilities that are **Ready**, business-valuable, and reasonably self-contained (few cross-capability dependencies — check against the wiring graph this feeds into `architecture-blueprint.md` Step 3 later). Two things this recommendation must NOT be based on alone:
- **Extraction cleanliness alone.** A capability that happens to extract cleanly but has low business priority is a bad first slice — ask the user about priority, don't infer it from code tidiness.
- **Silent scope creep in the other direction.** If everything is "Ready," that's not automatically a reason to do it all at once — a large first slice still needs the same dependency/priority reasoning as a small one.

Document as: **capability → verdict → recommended for this slice (yes/no/deferred) → why.**

---

## Step 5: Flag — Does This Need Multiple Mendix Apps, Not Just Modules?

`modularize-domain.md` decides module boundaries **within one Mendix app**, with its own over-/under-split signals (e.g. "one module past ~15–20 persistent entities"). At large enough scale, the real question isn't module count — it's whether this should be **more than one Mendix app**: separate runtimes and databases, integrated via REST/OData/Business Events, the closest Mendix equivalent to a microservices split.

**This skill does not define full multi-app decomposition criteria — that's a bigger architectural question this toolkit hasn't validated against a real large migration yet. Flag it, don't answer it unilaterally.** Raise it explicitly as an open question when:

- The business capability map (Step 2) surfaces capabilities with clearly independent release cadences, ownership, or security/regulatory domains, **and**
- The combined in-scope entity/screen count is large enough that `modularize-domain.md` would still land on many modules (rough signal: it's still recommending 8–10+ modules after applying its own merge criteria) rather than converging toward a handful.

If flagged, resolve "one app or several" as its own open issue **before** `modularize-domain.md` runs — that decision has to come first, not after modules are already being drawn inside a single domain model. If this is the first time your team has hit this question, say so plainly to the user rather than inventing a threshold to sound decisive.

---

## Output Template

```markdown
# Source Triage: [Application Name]

## Extraction Approach
Decision: Reuse existing pipeline (<which>) / Build new pipeline
Reasoning: [stack match, layout-assumption fit, effort tradeoff]

## Business Capability Map
[Step 2 table]

## Coverage Matrix
[Step 3 table]

## Recommended Scope Subset
[Step 4: capability → verdict → in this slice? → why]

## Architecture Scale Flag
[Step 5 — "no concern" OR the open question raised, with the trigger conditions that fired]

## Sign-off
Confirmed by: [user] on [date] — required before Phase 2/3 proceed.
```

---

## Anti-Patterns This Skill Prevents

- **Skipping the extractor because the app "looks small enough to read by hand."** Manual reading missed information even on small, cleanly structured sources — that's exactly why there's no manual-only path anymore. `assess-migration.md` is a complement to extraction, not a substitute for it.
- **The agent picking Reuse vs. Build-new itself and proceeding, instead of presenting the tradeoff and waiting for the user.** Even when the signal looks unambiguous, this is a project-scoping decision, not an implementation detail — the same reasoning as Step 5's "flag, don't answer unilaterally."
- **Assuming an existing pipeline "reuses cleanly" because the stack name matches.** A pipeline's layout assumptions (e.g. `node-express-react`'s regex passes expecting `src/models/*.ts`) may not fit a structurally different source even on the same tech stack — check the pipeline's own README/companion skill before calling it Reuse instead of Build new.
- **Running Phase 3 (BRD scaffolding) the moment Phase 2 produces output, with no scope sign-off.** Produces BRDs for capabilities nobody agreed should come first.
- **Calling every bounded-scope decision a "POC."** Forces artificial throwaway framing onto phased full migrations, and invites treating the first slice's shortcuts as permanent. A slice is an ordering, not an exclusion — capabilities left out of slice 1 are scheduled later, not dropped.
- **Deciding module boundaries (`modularize-domain.md`) before asking whether this should be multiple apps.** The app-count question is upstream of the module-count question — answering them in the wrong order means redrawing module boundaries after discovering they should've been app boundaries.
- **Treating "extracts cleanly" as equivalent to "high priority."** The easiest capability to automate is not automatically the right one to migrate first.
