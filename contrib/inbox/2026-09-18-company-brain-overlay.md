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
**Proposed target:** `templates/company-overlay/` (new) + `--company <path>` on
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

- `templates/company-overlay/` — skeleton: `README.md` (the wiring recipe), empty
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

## Open

- Does the leak guard run in the overlay? It should, with the company's *own* denylist
  (clients they serve), since the overlay is where client-named learnings are allowed to live.
- Name: "company brain" is the user's term; "overlay" is the mechanism. Pick one for the docs.
