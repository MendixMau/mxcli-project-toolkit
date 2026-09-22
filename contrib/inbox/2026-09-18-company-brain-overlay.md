# Idea: a company brain as an overlay repo — template, not automation

**From:** Maurits Visser (MendixMau)
**Date:** 2026-09-18
**Kind:** process
**Field evidence:** there is no layer between the shared toolkit and a project. A company that
adopts the toolkit can put its own material in exactly two places — the shared toolkit (which
the leak guard forbids for anything client-named) or a hand copy inside each project (which
rots; `sync-project.sh` exists because copies rot). Own skills, naming conventions, lint rules,
MDL snippets, design systems and approved MPKs have no home. Related: PR #93's open question
"is a toolkit-owned decision register still justified", PR #88 (mxcli brain adopted per project),
issue #90 (baseline budget saturated).
**Status 2026-09-19:** BUILT on branch `claude/inspiring-darwin-w0p1an` — `templates/company-brain/`, `bin/init-company-brain.sh`, `bin/wire-company-brain.sh`, `init-project.sh --company`, `harvest-learnings.sh --to`, `bin/check-no-private-citations.sh` (CI), `skills/company-brain.md`, fixture `tests/wave2/test-company-brain.sh`, eval `evals/scenarios/company-brain-design-module/`. Triage: promote this file's remaining text into the skill or delete.
**Proposed target:** `templates/company-brain/` (new) + `--company <path>` on
`bin/init-project.sh` / `bin/sync-project.sh` + one ~40-word baseline pointer row in
`bin/lib/skill-routing.tsv`.

---

## Three tiers, same shape

| Tier | Owner | Holds | Mechanism |
|---|---|---|---|
| Toolkit | shared | generic process, stages, gates, learned-* patterns, stock lint rules | clone + `sync-project.sh` (exists) |
| **Company brain** | **the company** | own skills, conventions, lint rules, MDL snippets, design system, MPK catalog, learned patterns that may name clients | **overlay repo — this idea** |
| Project brain | one app | decisions anchored in the model | `mxcli brain` (PR #88, exists) |

The company tier is a second repo with the toolkit's directory shape (`skills/`, `lint-rules/`,
`examples/`, `bin/`, its own `skill-routing.tsv`), so nothing new has to be learned and the
existing render/check tooling applies. A fork is the wrong shape: every toolkit release would be
re-merged by hand. An overlay is `git pull` on both and one sync.

## Decisions taken 2026-09-18 (Maurits)

1. **No new baseline words.** The budget (`render-routing.sh`, 80 000 words, a ratchet) counts
   baseline *documents* only; ondemand rows cost nothing at session start. The company tier
   therefore gets **one baseline pointer row (~40 words)**: "a company overlay is wired at
   `<path>`; its routing table is `<path>/ROUTING.md`, load it when a trigger fires". The
   company's own table is ondemand by construction. This is the toolkit's existing "single source,
   every other mention defers" convention applied one level up. A company may promote its own
   rows to baseline only inside *its* budget, rendered separately — the toolkit's ratchet is not
   theirs to spend.
2. **No mxcli change needed for MPKs.** Brain anchors are `@Module.Element`. An MPK, once
   imported, *is* a module in the model, so a decision "use company widget X on page Y" anchors to
   it with no new capability. A forward anchor to a component not yet imported fails `brain check`
   — which is the correct behaviour (the prerequisite is not met). So: the catalog is a static
   manifest per component (name, version, Mendix version range, namespace, purpose, install
   step); the *use* of a component is a project-brain entry. No upstream bug or feature request.
   Not probed on a binary — this container has none; the claim rests on the anchor grammar
   documented in `close-the-loop.md` and `existing-app-change.md`. Probe before promotion.
3. **The company curates, by hand.** Project content stays in the project: `docs/brain/` for
   model-anchored decisions, plus a project-local `contrib/outbox/` for anything a session thinks
   is reusable. `bin/harvest-learnings.sh` already drafts inbox files from a project's bug logs,
   promotion tables and patched scripts — point its output at the company overlay's `inbox/`
   instead of the toolkit's, and the company decides what to promote. **A template the customer
   wires themselves, not automation:** the toolkit ships the skeleton and the wiring recipe;
   the company owns the repo, the triage, the leak policy and the routing budget.

## What the toolkit ships (v1, small)

- `templates/company-brain/` — skeleton: `README.md` (the wiring recipe), empty
  `skills/ lint-rules/ examples/mdl/ catalog/mpk/ inbox/`, a `skill-routing.tsv` header,
  `catalog/mpk/TEMPLATE.md` (the manifest fields above), `inbox/TEMPLATE.md` (copy of the
  toolkit's).
- `bin/init-project.sh --company <path>` — optional; writes a second root into the wiring block
  and the one pointer row into `CLAUDE.local.md`. Absent flag = today's behaviour.
- `bin/sync-project.sh` — refreshes copies from both roots when the flag was used.
- `bin/harvest-learnings.sh --to <company-overlay>/inbox` — output target, default unchanged.
- Lint: a third hash set beside `lint-rules/STOCK-HASHES.txt` so a company rule is distinguishable
  from a stock rule and from a project-local edit. Same script, one more directory.

## Not in v1

- Company baseline rendering into project surfaces beyond the pointer row.
- Any automatic promotion from project to company or company to toolkit.
- MPK install automation — capability-probe the binary first (the "marketplace is manual"
  misfire is on record in this toolkit).

## Resolved 2026-09-18 (Maurits)

- **Leak guard.** `check-no-client-data.sh` guards the *public toolkit* — that is its stated
  purpose. It has two halves: a gitignored **denylist of names** (optional) and **generic probes**
  for real data (strings copied from a live app, typed GUIDs, local filesystem paths, contact
  details). In the company brain, names — the company's own, its clients', its apps' — are the
  company's call and need no denylist. What the company brain keeps is the **probes half only**:
  no personal data, no credentials, no record contents, no local paths. One reuse of the existing
  script with the denylist off (CI already runs it that way).
- **Name: "company brain".** The overlay is the mechanism; the docs and the template directory say
  company brain (`templates/company-brain/`).

## Prior art found 2026-09-19 — this already exists as a running prototype

- **`personal-toolkit` (private repo) IS the company brain, one person wide.** Its README rule is
  the whole governance model: *"Reviewed weekly — promoted to mxcli-project-toolkit only by explicit
  decision."* It has every directory this idea proposed and two it did not: `skills/`,
  `skills/bugs/`, `skills/agents/`, `proposals/` (patches against the shared toolkit, awaiting a
  go), `widgets/` (own MPKs: RichMarkdown, GraphTraversalViewer), `InputCodeExamples/`,
  `field-runs/`, `handoffs/` (cross-session briefings), `prompts/`, `claude/hooks/` + `install.sh`.
  `skills/PROMOTED.md` (2026-09-14) is the up-direction done right: after promotion the private file
  becomes a pointer stub so project routing rows keep resolving. **v1 of this idea is therefore
  "extract personal-toolkit's shape into `templates/company-brain/`", not a design from scratch.**
- **The failure mode is documented, from the other side.** USI workshop research
  (`ai-presales-notes/customers/USI/workshop/research/gap-repo-truth.md` §5c, 2026-08): five skills
  cited by the *public* toolkit existed only in the *private* one — "a USI engineer following the
  pointer gets nothing." Master still carries three such pointers today (`commands/mobile-dev-loop-
  prompt.md`, two bug-log lines). **Rule for the template: the public tier never cites the company
  tier; the company tier may cite public. Add the grep to `check-scripts`/CI.**
- **At org level the same idea is a leadership ask, unresolved.** `ai-presales-notes/projects/
  AI-Engineering-Leadership.md` recommendation 2: *"Sponsor one central, shared repository for
  skills and MDL templates, RnD and Presales contributing to the same place instead of parallel
  forks."* Open question there and in `TODO.md` (Workstream 9): does the central repo ask point at
  the harness repo or a new org-owned repo — "it's Maurits' personal-toolkit-derived work, not yet an
  org asset." The company-brain template is the answer that makes both true: the toolkit stays the
  public harness, an org-owned company brain is one `templates/company-brain/` instantiation.
- **The deck already teaches the first half.** USI deck slide "A skill in the project folder does
  not survive the project" (ch. 56) — where a skill lives — and "How the next session knows what
  already happened" — the wiring page, now `toolkit-guide.html` §9.
- **Cross-project direction, seeds only.** `personal-toolkit/field-runs/` and `handoffs/` are the
  across-projects material in practice; toolkit issue #64 ("ask 9: cross project open questions
  rollup") is the one formal ask. No index exists; a derived `company-index.sh` over a `projects.tsv`
  registry is still the proposal.
