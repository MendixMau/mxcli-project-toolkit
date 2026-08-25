# Skill: test-result-audit — did the testing itself hold up, not just get filed

**Applies to:** the end of any build+test cycle that produces `docs/report.json` —
`module-review.md` Stage 4/5, `existing-app-assurance.md` Track B, a `verify-module.sh` run, or
any future instrument that writes into the same structured report.

**Status:** a judgement pass, run automatically at the end of each build+test cycle, one level up
from `finding-disposition.md`. Read `report-schema.md` first — this skill reads the same
`docs/report.json` that skill's mechanical backstop reads, but asks a different question of it.

---

## The gap this closes, and the one it does not

`finding-disposition.md` (+ its mechanical backstop, `project-bin/report-disposition-check.sh`)
answers exactly one question: **did the findings a report already surfaced get filed to
`docs/improvement-register.md`?** It is a paper-trail check. It cannot tell you whether the report
was worth trusting in the first place — a run that tested three of nine pages and reported "0
findings" passes `report-disposition-check.sh` cleanly (`nextSteps` is empty, nothing owed filing),
and that clean exit is exactly where the false confidence lives.

**This skill answers a different question: was the testing itself logically complete and internally
consistent, against whatever the project's requirements artifacts say it should cover?** It re-reads
a *finished* report the way a skeptical second reviewer would — not to re-run anything, but to
notice what the report's own numbers imply and what they don't.

Two failure modes this catches that `finding-disposition.md` structurally cannot:

1. **Missing coverage that never became a FAULT/FAIL row.** A page nobody wrote a journey for
   doesn't fault — it's simply absent from every instrument's denominator, and an absence is
   silent by construction. `report-disposition-check.sh` only reads what a report *says*; it has
   no notion of what a report *should* have said.
2. **Logically suspicious passing results.** Every check row it reads passed its own local
   assertion and still adds up to something a human would call implausible: every row in a grid
   carrying the identical value, an empty-state message rendering next to a populated table, a
   "12 total" header sitting over 8 visible rows with no stated denominator gap, a persona whose
   entire journey is one page shorter than every sibling persona's for no stated reason. None of
   these individually fail an instrument's assertion. Together they are exactly the pattern a
   distracted human reviewer would catch and an unattended sweep would not.

## Why this is a toolkit skill, not a project-local one

Filed here rather than under this project's own `.ai-context/`, for the same reason
`finding-disposition.md` and `module-review.md` are toolkit skills and not project-local ones:
**the judgement transfers.** Nothing about "does the report's own arithmetic hold together" is
specific to the originating project's domain, its modules, or its Track-B-vs-pipeline entry mode — every project
that runs `report-normalize.js` produces the same `checks[]`/`instruments[]`/`nextSteps[]` shape
this skill reads, and the same four suspicious-pattern checks below apply unchanged. Per
`close-the-loop.md`'s own routing test ("is this still true in a repo that isn't this one?" — yes),
it belongs alongside its sibling `finding-disposition.md`, not duplicated per-project. A
project-local copy would also drift the moment `report-schema.md` gains a field, exactly the
failure `close-the-loop.md`'s "nothing in two places" rule exists to prevent.

## When to run it

**At the same boundary `finding-disposition.md` fires at** — the end of a build+test cycle, right
after (not instead of) that skill's own disposition pass. Order matters: `finding-disposition.md`
first files what the report already knows it found; this skill then re-reads the same finished
report for what it *didn't* say. Running this skill does not replace `report-disposition-check.sh`
— both run, in that order, and this skill's own findings are filed through the identical path
(below), so a session that skips `finding-disposition.md`'s mechanical backstop doesn't get to
skip this either.

Do not run this mid-cycle, against a report that is still being written — it audits a *finished*
report's own claims, not a live instrument run.

---

## The procedure

### 1. Gather the three inputs — read them, don't guess

```bash
# The structured contract — ground truth for what ran, what passed, what the run itself flagged
cat docs/report.json | python3 -m json.tool | head -100   # orient; then read checks[]/instruments[]/nextSteps[] in full

# Every finding already on record, so this pass builds on it instead of re-discovering it
cat docs/improvement-register.md

# Requirements artifacts — read whichever of these actually exist, and say so either way
ls architecture/modules/*/module-brief.md 2>/dev/null
ls analysis/*/knowledge-base/brd/*.brd.json 2>/dev/null
```

**Name what you have before judging anything.** This project (the worked example here) is Track B
(`existing-app-assurance.md`) — no BRD, no module-brief pipeline was ever run against it, so both
`ls` calls above legitimately return nothing. **That is not a reason to skip this skill; it changes
what "coverage" means to judge against.** With no BRD/module-brief to check test scope against,
judge coverage against the model itself instead: `SHOW PAGES IN <Module>` / `SHOW MICROFLOWS IN
<Module>` (the same per-action inventory `existing-app-assurance.md` Track B step 2 already
requires) is the closest thing to a requirements artifact this entry mode has, and the audit should
say exactly that — "no BRD/module-brief exists (Track B); coverage judged against
`SHOW PAGES`/`SHOW MICROFLOWS` output instead" — rather than silently treating "no requirements
artifact" as "nothing to check against." A project that *does* have BRDs/module-briefs judges
coverage against those directly: does the report's page/action list actually match what the BRD's
acceptance criteria describe, not just what the harness happened to walk.

### 2. Four checks against the report's own numbers — this is the judgement, not a script

None of these are mechanically checkable the way `report-disposition-check.sh`'s grep is — that is
exactly why this is a skill and not a new script, per `skills-over-scripts.md`. A script can compute
"12 rows in this table" from a screenshot's DOM dump; it cannot decide whether "12 total · 2
available" next to 8 visible rows is a pagination artifact or a wrong count, or whether an empty
Product-number column is real data or a rendering bug — those need a reader who can hold the report
next to the model and to each other.

**a. Missing coverage.** Cross-reference the report's own page/module list (`checks[].page`,
`instruments[]`) against the fuller inventory from step 1 — `SHOW PAGES IN <Module>` /
`SHOW MICROFLOWS IN <Module>`, or the BRD's acceptance criteria where one exists. Every page or
action present in the inventory but absent from every check row is a coverage gap — name it, don't
just note the aggregate count. `report.json`'s own `nextSteps[]` often already contains
`page-never-walked-*` entries for exactly this; read them as data, but don't stop there — a
`nextSteps` entry only exists for pages the harness *knows* it has a journey file for and didn't
reach. A page with **no journey file at all** for its module may not generate a `nextSteps` row
the same way; the inventory cross-reference catches that class too.

**b. Logically suspicious passing results.** Read every `checks[]` row with `verdict: "pass"`
(not just the fails/faults — a suspicious pass is the entire point) and ask, for each:
- **Identical values across rows** — every row of a grid carrying the same status/date/name where
  variety would be expected (a strong tell for seed data that was never varied, or a binding that
  resolved to a constant instead of the row's own attribute).
- **An empty-state message rendering alongside real, populated content** — the exact class already
  found and logged this session on `Approval.Approval_Archive` (`ctnEmptyHint` with no `Visible:`
  condition, rendering under 3 real rows). A structure/a11y check can pass while this sits right
  next to it, because neither check's assertion covers "does the empty-state hint contradict the
  grid it sits under."
- **Counts that don't add up** — a header stating "N total" that doesn't match the visible row
  count without a stated pagination reason; a persona's journey landing on fewer stations/pages
  than a sibling persona's equivalent journey with no `descoped`/access-control reason given.
- **A page reached only via a fallback identity, with no explanation of why the primary identity
  couldn't reach it** — read the `detail` string; if a check says "reached only via fallback
  identity X" without naming *why* (role gate vs. harness bug), that is itself worth flagging as
  underspecified, not just accepted at face value.

**c. Unreached personas.** Cross-reference every user role the model defines
(`DESCRIBE USER ROLE <Role>`, or `SHOW USER ROLES`) against which personas the report's `run.target`
/ `checks[].detail` actually exercised. A role with a materially different module-role bundle from
every persona a journey covers is untested surface, not a redundant duplicate — the same rule
`existing-app-assurance.md` Track B step 2 already states for actions, applied here to personas.

**d. Unreached modules/pages, restated with their own denominator.** Don't just cite the report's
top-line pass/fail/fault tally — state, in the audit's own words, "N of M pages reviewed, N of M
journeys run, N of M personas exercised," per `module-review.md`'s own denominator discipline. A
report that never states its denominator is itself a finding under this check, independent of what
it did or didn't find.

### 3. Produce a written critique — not a rubber stamp

The deliverable is prose, not a checklist of ✅s. State plainly:
- What was actually covered, with the denominator from 2d.
- Every gap found under 2a–2c, each with what page/persona/module it names and why it counts as a
  gap (missing journey file vs. role-gated-and-undocumented vs. genuinely out of scope).
- Every suspicious-but-passing result found under 2b, with the evidence line from the report that
  triggered the suspicion and what would need to be checked live to confirm or dismiss it (do not
  claim it as a confirmed defect from report-reading alone — that is this skill's own limit; if the
  suspicion is confirmable in a few minutes via `mxcli oql`/`DESCRIBE PAGE`, confirm it before
  filing, same as this session did for the `ArticleDiscontinuation_Overview` blank-render finding).
- If nothing suspicious was found: say so, and say what you checked to reach that conclusion — an
  empty critique with no stated method reads exactly like the rubber stamp this skill exists to
  prevent.

### 4. File findings — through the SAME path, never a parallel one

Every real finding from step 2 — confirmed or still-suspected — is filed to
`docs/improvement-register.md` via `close-the-loop.md`'s routing table, using
`finding-disposition.md`'s "detailed enough for a cold pickup" bar (module/source pass, reproducible
description, suspected fix class, disposition). **This skill produces zero new report artifacts.**
Its output is: register rows for what it found, plus the written critique from step 3 posted in
chat (or appended to whatever HTML surface the triggering skill already produces — `test-report.html`
for `existing-app-assurance.md` Track B, the module-review report for Stage 4/5) — never a second
JSON/HTML file that competes with `docs/report.json` as a second source of truth.

A suspected-but-unconfirmed finding (2b's "would need to be checked live") still gets a register row
— mark its Disposition `open (unconfirmed by this audit pass — needs live check)` rather than
omitting it because it isn't proven yet. An unfiled suspicion is exactly the kind of thing that
evaporates at the next `/clear`, per `close-the-loop.md`'s own argument for why filing beats memory.

### 5. Closing question — same shape as `finding-disposition.md`'s

> **"Test-result audit: N coverage gaps, M suspicious-passing results (K confirmed live, J still
> unconfirmed) logged to the improvement register. Which should I investigate further now versus
> leave logged?"**

Then stop and wait, per `interview-protocol.md`. Do not silently confirm or dismiss an unconfirmed
suspicion just because investigating it would be quick — that decision is the user's, same as any
other "should I keep going" moment this toolkit gates.

---

## What this skill is not

- **Not a re-run of the tests.** It reads the finished report; it does not re-execute journeys,
  `design-audit.js`, or `verify-module.sh`. If the report itself looks stale (older than the code
  it claims to describe), that staleness is itself a finding under 2b/2d, not a reason to silently
  re-run anything.
- **Not a replacement for `finding-disposition.md`.** That skill's job (did the report's *own*
  findings get filed) still has to happen, in the same cycle, before this one adds its layer on top.
- **Not a second report format.** See step 4 — everything this skill produces lands in the existing
  register and the existing HTML surface, never a new file.

## Related

- `skills/finding-disposition.md` — the sibling this skill runs after, and whose filing bar (module/
  source-pass/reproducible/fix-class/disposition) this skill reuses rather than inventing its own
- `skills/report-schema.md` — the `docs/report.json` contract this skill reads (`checks[]`,
  `instruments[]`, `nextSteps[]`) — read it first if the shape of any field above is unclear
- `skills/close-the-loop.md` — the routing table every finding from this pass goes through
- `skills/existing-app-assurance.md` — Track B, where "no BRD/module-brief exists" is the normal
  case this skill's step 1 has to handle explicitly rather than skip
- `skills/module-review.md` — the denominator discipline (2d) this skill borrows rather than
  reinventing
- `project-bin/report-disposition-check.sh` — the mechanical backstop for the *sibling* skill
  (filing presence); this skill has no mechanical backstop of its own by design — the judgement in
  §2 cannot be reduced to a grep without losing the thing that makes it worth doing (see
  `skills-over-scripts.md`)
