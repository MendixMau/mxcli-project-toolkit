# Skill promotion plan — personal-toolkit → mxcli-project-toolkit (2026-08-20)

**Status: PLAN ONLY. No files have been moved, copied, or edited as part of this plan.**
Per `~/.claude/CLAUDE.md`, promotion into this shared toolkit happens only on explicit
"promote this to the toolkit" instruction, per item. This document is that decision
register — work each row when you're ready, don't bulk-execute it.

## Why this exists

Triggered by a review that found `skills/workflow-patterns.md` was never promoted despite
a dangling `[[workflow-patterns]]` link already sitting in `tool-output-is-not-ground-truth.md`
and two STOP-table entries in `learned-mdl-preflight.md` referencing it implicitly. That
turned out to be one instance of a general problem: `~/Mendix/personal-toolkit/skills/`
has ~30 files with no counterpart here, some genuinely reusable, most wrapped in one
project's client names and file paths.

Five agents each read a batch of source files against this toolkit's own promotion rule
(`CLAUDE.md` → "Writing in this toolkit — generic first": reusable across projects,
judgement lives in `skills/`, no client/project-specific furniture) and the full list of
skills already here (to catch overlap before adding a duplicate). Findings below are
theirs, checked against actual file reads — not re-guessed from memory of "we did this
before."

## How to read the verdicts

- **PROMOTE-AS-IS** — copy in, no edits needed beyond the target path.
- **PROMOTE-WITH-EDIT** — strip client/project names and one-off file paths first; keep the mechanism.
- **MERGE-INTO-EXISTING** — the reusable kernel folds into a named existing shared skill; don't create a new file.
- **LOCAL-ONLY** — stays in personal-toolkit. Either project-specific, personal-preference, or an open/unconfirmed investigation with no reusable conclusion yet.
- **ALREADY-COVERED** — an existing shared skill already says this.

---

## 1. UI / widget skills

| Source file | Verdict | Target | Notes |
|---|---|---|---|
| `dg2-grid-pattern.md` | MERGE (with next row) | `skills/mdl-cookbook-datagrid.md` | **Contradicts `dg2-implementation-guide.md` on native DATAGRID vs DG2 pluggable widget — resolve which is actually safe before merging either.** |
| `dg2-implementation-guide.md` | MERGE (with above) | `skills/mdl-cookbook-datagrid.md` | Real mxcli defects (CE1613 textfilter, BUG-18 customContent crash, BSON corruption on ALTER PAGE) are reusable; strip PROJECT-E branding and the project's enum names. |
| `datagrid-customcontent-text-binding.md` | PROMOTE-WITH-EDIT | `skills/learned-datagrid-customcontent-binding.md` | Already cross-references `tool-output-is-not-ground-truth.md` and `oneshot-page-structure-patterns.md` by their real toolkit paths — light edit only. |
| `stylesheet-classes.md` | LOCAL-ONLY | — | Entirely PROJECT-E brand tokens/classes; no transferable pattern beyond "have a token checklist," which isn't worth a file on its own. |
| `sidebar-nav-icon-only-collapsed.md` | PROMOTE-AS-IS | `skills/learned-sidebar-collapse-icons.md` | Real mxcli grammar gap (`navigation.create` has no icon token), confirmed via `mxcli syntax`. |
| `layout-preference-topbar-mobile.md` | LOCAL-ONLY | — | Explicitly the user's personal design taste, not a Mendix/mxcli technical pattern. |
| `empty-widget-triage.md` | PROMOTE-AS-IS | `skills/empty-widget-triage.md` | Source-agnostic data/security/UI triage protocol with a real mxcli command sequence. |
| `microflow-popup-navigation.md` | PROMOTE-AS-IS | `skills/learned-popup-navigation.md` | Generic close-before-show popup-stacking correctness rule. |
| `popup-create-feedback-rule.md` | PROMOTE-WITH-EDIT | `skills/learned-popup-feedback-pattern.md` | Real DSL gap (no "show message" toast activity) + two-option UX substitute pattern; strip PROJECT-F microflow names. |

## 2. Process / verification / diagnostics skills

| Source file | Verdict | Target | Notes |
|---|---|---|---|
| `security-is-not-a-later-script.md` | MERGE | `skills/learned-mdl-preflight.md` | "Entity access lives with the entity, not a later script" rule; strip the PROJECT-C incident replay to one illustrative line. |
| `scriptable-studio-pro-verification.md` | LOCAL-ONLY | — | Self-flags as an unresolved investigation, not a validated oracle. Revisit once (if) it's proven. |
| `sandbox-ab-tool-defect-probe.md` | PROMOTE-WITH-EDIT | `skills/sandbox-ab-tool-defect-probe.md` | rsync sandbox A/B + negative control method; strip project name/bug ID from the framing. |
| `restart-sp-reopen-and-hang-detection.md` | PROMOTE-WITH-EDIT | `skills/restart-sp-reopen-and-hang-detection.md` | Version Selector Apple-Events bug, port variability, CPU%-can't-detect-hang — all source-agnostic. |
| `context-cost-control.md` | LOCAL-ONLY | — | About personal Claude Code billing/hooks/account config, not Mendix at all — wrong toolkit entirely (belongs in `personal-library` per global CLAUDE.md if anywhere). |
| `corpus-extraction-integrity.md` | PROMOTE-WITH-EDIT | `skills/corpus-extraction-integrity.md` | Scope-filtered extraction, coverage assertions, truncation traps — strip client numbers from prose. |
| `gate-check-file-locations.md` | MERGE | `skills/conversion-runbook.md` (Stage 0/gate section) | A `bin/gate-check.sh` `ANALYSIS_BASE` fallback debugging note — belongs as a note there, not a standalone file. |
| `findings-to-triage-plan.md` | MERGE (partial) | `skills/process-coherence-pass.md` or `skills/skills-over-scripts.md` | Most of it overlaps `report-schema.md`/`e2e-evidence-report.md`; the one new rule worth keeping is "a review that falsifies a triage skill must patch that skill in the same cycle." |

## 3. Data / integration skills

| Source file | Verdict | Target | Notes |
|---|---|---|---|
| `mendix-epics-api.md` | PROMOTE-WITH-EDIT | `skills/mendix-epics-api.md` | No existing shared skill covers the Epics portal API; strip `PROJECT-E-EP-*` example IDs. |
| `mendix-write-modes.md` | **Check overlap first** — likely MERGE | `skills/learned-mdl-preflight.md` and/or `skills/learned-mcp-patterns.md` | CLI-vs-MCP-vs-hand-rolled-MCP decision table; the file's own "Related" section already points at `learned-mdl-preflight.md` as owning this territory. |
| `rest-integration-first-time-right.md` | PROMOTE-WITH-EDIT | `skills/rest-integration-first-time-right.md` | Strongest candidate in this batch — entity/Custom-Name matching, JSON structure bug, reverse-association trap; strip PROJECT-C/PROJECT-A names. |
| `seed-users-and-data.md` | PROMOTE-WITH-EDIT (partial) | `skills/seed-users-hsqldb-local-run.md` | Only Steps 0–4 (HSQLDB lock discovery, trimmed-jar JDBC runner, user-role junction gotcha) generalize; **check against `skills/fixture-seeding.md` first** — likely complementary (HSQLDB-local vs Postgres/Docker), not duplicate. |
| `mxcli-alter-page-observations.md` | Split, not a skill | `bug-logs/mxcli-bugs.md` | OBS-04 corrects existing BUG-18; OBS-05 is a new independent bug (INSERT no-op + orphan duplicates). OBS-01/02/03 already covered by `learned-page-patterns.md` BUG-07 — drop. |

## 4. Workflow + misc

| Source file | Verdict | Target | Notes |
|---|---|---|---|
| `workflow-patterns.md` | MERGE into next row | `skills/learned-workflow-patterns.md` | Same subject as `workflow/SKILL.md` but as a dated append-log; three sections are genuinely newer and must be folded in (see below). |
| `workflow/SKILL.md` | PROMOTE-WITH-EDIT | `skills/learned-workflow-patterns.md` | The cleaner canonical writeup (11 workflow microflow statements, WF task page wiring, common-errors table) — this is the file that should have landed here already. |
| `workflow/example.mdl` | PROMOTE-AS-IS | `skills/build/workflow-example.mdl` | Pure syntax reference (purchase-request approval), no client content. |
| `anonymize-client-app-for-demo.md` | PROMOTE-WITH-EDIT | `skills/anonymize-client-app-for-demo.md` | MPK re-export/rename/verify method is generic; strip the client-app worked example or reduce it to illustration. |
| `field-run.md` | PROMOTE-AS-IS | `skills/field-run.md` | Already written entirely in terms of this toolkit's own skill names — it was drafted about the shared toolkit, just in the wrong repo. |
| `toolkit-distribution-design.md` | LOCAL-ONLY, likely stale | — (if still live, `process/toolkit-worklog.md`) | Design note against specific line numbers in `project-bin/exec.sh` / `sync-project.sh` — git status shows those files already modified, so check whether this is already actioned before doing anything with it. |

**Content to fold from `workflow-patterns.md` into `workflow/SKILL.md` before promoting as one file:**
1. "Divergent outcome branches — reconvergence is not a grammar limit" (nest-the-continuation technique).
2. `WORKFLOW OPERATION ABORT` semantic-scope warning (don't mislabel a normal early-exit as an abort).
3. The `$Type` corruption confirmed-clean-on-v0.18.0 version-check update.

Strip on merge: `PROJECT-E`, `PROJECT-A`, `Engalar`, `PROJECT-E`, and all `~/Mendix/engalar-mxcli/...` / `~/Mendix/personal-toolkit/examples/...` paths.

## 5. Bug-log candidates (`personal-toolkit/skills/bugs/`)

These go to `bug-logs/`, not `skills/` — different mechanism, same review pass.

| Source file | Verdict | Target |
|---|---|---|
| `bug-74-family-callmockapionce-logging-gap.md` | Extends existing BUG-74 | `bug-logs/mxcli-bugs.md` (append to BUG-74) — not submission-ready, still unconfirmed |
| `bug-75-extension-quoted-args.md` | Extends existing BUG-75 | `bug-logs/mxcli-bugs.md` (append to BUG-75) — well-evidenced, ready |
| `bug-82-calculated-attribute-not-wired.md` | New, confirmed | `bug-logs/pending-github-issues/` — file already says "filable draft" |
| `bug-83-loop-var-association-path-in-call-param.md` | New, confirmed | `bug-logs/mxcli-bugs.md` or `pending-github-issues/` — isolated repro, ready |
| `bug-84-import-mapping-array-child-never-populated.md` | On hold | Not ready — two confounds unresolved per its own banner; don't file yet |
| `bug-85-dynamiccellclass-create-time-only.md` | New, confirmed, distinct from existing BUG-42 | `bug-logs/mxcli-bugs.md` — clean isolated repro |
| `bug-submission-checklist.md` | Not a bug — process skill | If promoted, belongs as a contributor-guide skill, not `bug-logs/` |
| `docker-compose-project-name-collision.md` | LOCAL-ONLY / scaffold gap, not a modeling bug | Its own text suggests filing as a toolkit improvement (fix `mxcli docker init` template to set `COMPOSE_PROJECT_NAME`) rather than a bug-log entry |

---

## Wiring plan (once any row above is actually promoted)

This toolkit's README routing tables are **generated**, not hand-edited:
`bin/lib/skill-routing.tsv` → `bin/render-routing.sh` renders both the "When to use which
skill" (situational) and "Baseline routing" tables in `README.md`, plus every consuming
project's agent template and `gate-check.sh`'s stage map, from that one source. **Adding a
row means editing `skill-routing.tsv` and re-running `bin/render-routing.sh`, never
hand-editing the README tables directly** — `bin/render-routing.sh --check` verifies they're
still in sync.

For every file promoted above:

1. **Add a `skill-routing.tsv` row** — task description, skill path, and section bucket
   (Spine / Source / Requirements / Architecture / Design / Build / Build·MDL / Build·Pages
   / Verify / Diagnose), per the "Suggested README section" column each agent gave. None of
   this batch qualifies for **Baseline routing** (loaded on every MDL-writing session
   regardless of task) except possibly `learned-workflow-patterns.md`'s STOP-table
   cross-references, which live inside `learned-mdl-preflight.md` — already baseline — so no
   new baseline row is needed for it.
2. **Run `bin/render-routing.sh`** to regenerate `README.md`, every project agent template,
   and `gate-check.sh`'s stage map together, then `--check` to confirm sync.
3. **Fix the dangling link**: `skills/tool-output-is-not-ground-truth.md:345` — change
   `[[workflow-patterns]]` to `[[learned-workflow-patterns]]` once that file exists.
4. **Add cross-references from STOP #18/#19** in `skills/learned-mdl-preflight.md` (lines
   54–55) to `[[learned-workflow-patterns]]`, since the full detail will now live there —
   don't duplicate it in the STOP table.
5. **`agent-roles.md`**: none of the promoted files need a new subagent role — they're
   skills to load, not new gate/responsibility splits. No change needed there beyond what
   `skill-routing.tsv` already drives into any generated agent templates.
6. **`conversion-runbook.md`**: only `gate-check-file-locations.md`'s merge target
   (Stage 0/gate section) touches this file directly; everything else is reached via the
   README routing table, not the runbook itself.
7. **Bug-log promotions** (§5) don't touch `skill-routing.tsv` at all — `bug-logs/mxcli-bugs.md`
   is already a fixed baseline-routing entry; new entries just extend that file's content.

## What this means for a new project running `bin/init-project.sh`

- **Baseline-routing skills** (the always-loaded table) are referenced directly in the
  `CLAUDE.local.md` that `init-project.sh` writes at scaffold time (via `bootstrap-project.md`'s
  template, copying the Baseline routing table from `README.md`). None of today's promotions
  add a new baseline row, so `init-project.sh` output doesn't change shape — but any future
  promotion that *does* warrant baseline status must be added to `README.md`'s baseline table
  (via `skill-routing.tsv`) as well as `bootstrap-project.md`'s template, or new projects will
  silently miss it, per the existing "why this has to be explicit instead of implicit" warning
  in `README.md`.
- **Situational skills** need no `init-project.sh` change at all — a project clones/references
  this toolkit, not copies of it (per `README.md`'s "Consuming this toolkit"), so a new
  `skills/*.md` file is available to every project the moment it's committed here. The only
  thing that makes it *discoverable* is the routing-table row from step 1 above — without
  that row, the file exists but nothing tells an agent to load it, which is exactly the
  failure mode that produced this review in the first place.
- **Existing projects** pick up newly promoted skills on their next `bin/sync-project.sh`
  run (per its stated purpose: "refreshes artifacts that were *copied* into the project" and
  "flags stale baseline routing") — run that after landing any of the above in a live project.
- **`bug-logs/mxcli-bugs.md` promotions** need no project-side action at all beyond a normal
  `git pull` of this toolkit — it's already baseline-routed.

## Suggested execution order

1. Resolve the DG2 native-vs-pluggable contradiction (§1, rows 1–2) before touching either file.
2. Land the workflow-patterns merge (§4) — it's the one with an existing dangling reference
   waiting for it, and closes out the original feedback that started this review.
3. Batch the clean `PROMOTE-AS-IS` / `PROMOTE-WITH-EDIT` rows (§1, §2, §3) — low-risk, mostly
   find-and-strip-client-names work.
4. Do the two `MERGE-INTO-EXISTING` overlap checks (`mendix-write-modes.md` vs
   `learned-mdl-preflight.md`/`learned-mcp-patterns.md`; `seed-users-and-data.md` vs
   `fixture-seeding.md`) as their own small reviews before merging, since both need a real
   side-by-side read, not just a copy.
5. File the confirmed bugs (§5) into `bug-logs/` — independent of everything else, can run
   in parallel with 1–4.
6. Re-run `bin/render-routing.sh --check` once all routing rows are added, before calling
   the pass done.

Nothing above has been executed. Work it row by row, on explicit instruction, per project convention.
