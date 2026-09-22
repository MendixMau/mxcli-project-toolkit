# Idea: a prerequisites gate before any "full X" task — readiness and success criteria first, tokens second

**From:** Maurits Visser (MendixMau)
**Date:** 2026-09-18
**Kind:** process
**Field evidence:** recurring pattern, not a single incident — big à-la-carte asks ("full app
analysis", "full e2e test run", "full UI loop", "full assessment") start executing immediately
and discover mid-run that something was never in place: no running app, no login/auth, no seed
data, no baseline to compare against, no agreed definition of done. The tokens spent before the
discovery are lost, and the run either stops half-way or "completes" against a target it never
verified.
**Proposed target:** `skills/task-prerequisites.md` (new skill) + a routing row in
`bin/lib/skill-routing.tsv` that fires on "full …", "complete …", "run the whole …", "e2e",
"analysis of the app", "UI loop"; possibly a `bin/preflight-task.sh` for the mechanical half.

---

## The idea

When a user asks for a **big, self-contained task** — anything expected to take many turns and
a large token budget — the agent does not start the task. It first produces a short
**prerequisites + success-criteria card**, checks what it can mechanically, asks the user only
for what it cannot, and starts the actual work only when the card is green (or the user
explicitly waives a red row).

Two halves:

1. **Prerequisites** — everything the task will need that is *not* the task itself:
   - **Environment**: app running? which URL? mxbuild set up? Docker available? mxcli version
     matches project?
   - **Access**: credentials / demo users / roles for every persona the run will exercise;
     MFA or SSO out of the way; DB connection for assertions.
   - **Data**: seed/demo data present and known; a way to reset it between runs; which records
     the scenarios will touch.
   - **Inputs**: the artifacts the task reads (BRDs, wireframes, page-scope, a baseline
     report, a previous run to diff against) exist and are current.
   - **Scope denominators**: the module list / page list / scenario list the run will cover,
     so "full" has a number attached (ties to the obligation check's "denominators" rule).
   - **Budget & mode**: attended or unattended, expected wall-clock, which snapshot/restore is
     in place.
2. **Success criteria** — what "done" looks like, agreed *before* the run: the artifact it
   emits, the denominator it states, the pass bar (e.g. "all N journeys walked, 0 blockers",
   "report with ≥1 finding per module or explicit NONE"), and what happens on partial failure.

## Why this belongs in the toolkit rather than in each project

- The stage gates already do exactly this for the *pipeline* (`gate-check.sh`, obligations,
  artifact manifest). The à-la-carte lane (`existing-app-assurance.md`) has no equivalent: a
  "full e2e" is a big unguarded task that starts with zero preconditions checked.
- It is the same lesson as "a producer for every consumer" (CLAUDE.md, shipping an instrument):
  a task that consumes a running app + auth + data must have a step that *establishes* them,
  not assume them.
- Cheap where it matters: the card is ~20 lines and one turn; the run it protects is hundreds.

## Product view (what I would and would not build)

**Do:**
- Make it a **skill with a fixed card template** per task family (analysis / e2e / UI loop /
  assessment / migration triage), each family listing its own prerequisite rows and default
  success criteria. The card is posted in chat as the first item of the Live Checklist, so the
  existing ✅/🔄/⬜/❌/⏭ protocol carries it — no new mechanism.
- Split rows into **mechanically checkable** (app answers on the URL, demo users exist via
  `SHOW DEMO USERS`, mxbuild present, BRDs discoverable via `discover-brds.sh`) and
  **ask-the-user** (which persona, which data reset strategy, what pass bar). Auto-check the
  first group; ask only the second — in one `AskUserQuestion` round, then stop and wait.
- Record the answers in `PROJECT.md` (or `docs/brain/` for a no-pipeline app) so the *next*
  "full e2e" on the same project reuses them instead of re-asking. Prerequisites are mostly
  stable per project; success criteria are per run.
- A red row that the user waives is recorded as a waiver with a reason — same convention as
  `--waive`, so a run that fails on the waived item reports "known, waived" not "surprise".

**Don't:**
- Don't build a generic "task planner" — it will drift into re-planning everything. Trigger only
  on the named big-task families, and keep each card under ~15 rows.
- Don't gate small asks. A one-page fix or a single lint question must not pay this tax; the
  routing row's trigger words are the scope fence.
- Don't let the card become prose. Every row is a checkable bound with a denominator (authoring
  rule 4), or it is not a row.

## Open gaps to settle before promoting

1. Which task families get a card in v1? Proposal: **e2e test run**, **UI review loop**,
   **existing-app assurance (audit/lint/regression)**, **full migration assessment**. Others
   later.
2. ~~Where does the "I already checked this on this project" memory live?~~ **Resolved 2026-09-18
   (Maurits): `mxcli brain`.** Rationale: the 2026-09-17 split already sends "what a session
   learned" to brain and only gate answers to `PROJECT.md`; riding the CLI's own concept avoids a
   parallel register that rots; anchors make a prerequisite self-invalidating (`brain check` goes
   red when the demo user's module role is dropped). Three constraints:
   - **Anchor what has a model element** — persona → module role / demo user, seed data → entity,
     journey start → page. **Environment facts** (app URL, Docker, db name, mxbuild path) have no
     anchor and live in `stack.env` via `test-stack-up` — the card reads both, there is no third
     store.
   - **Never a credential in brain** — `docs/brain/` is committed. Demo user name and role only.
   - **Degrade on an older mxcli** — brain is 0.21+; probe first (capability-probe rule), fall back
     to `PROJECT.md` rows rather than block.
3. Does `bin/preflight-task.sh` earn its keep in v1, or is the skill + Live Checklist enough
   until one field run shows which rows are actually re-checked every time?
4. Interaction with unattended mode: in unattended runs a red mechanical row must **stop**, not
   assume — that is the whole point.

Hypothesis, not finding: most of the wasted runs would have been caught by three rows alone —
app reachable, credentials for every persona, data present. Worth measuring on the first two
field runs before growing the card.
