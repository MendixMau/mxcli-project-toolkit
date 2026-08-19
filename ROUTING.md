# Skill routing — the whole table, in one place

**Generated. Do not hand-edit the block below.** The source of truth is
[`bin/lib/skill-routing.tsv`](bin/lib/skill-routing.tsv); every routing surface in this repo —
this file, the README's two tables, the runbook's baseline block, each agent template, and
`gate-check.sh`'s protocol stage map — is rendered from it by `bin/render-routing.sh`.

```
edit bin/lib/skill-routing.tsv   →   bin/render-routing.sh   →   review the diff
bin/render-routing.sh --check    →   exit 2 if any surface drifted   (wired into gate-check.sh)
```

**Why this exists.** Routing one skill used to take six coordinated edits, plus a seventh copy
inside every project's `CLAUDE.local.md` that no script could reach. Measured on 2026-08-18,
before this table: **17 of 43 skills were routed by nothing a project agent reads**,
`bin/facts-lock.sh` reached 1 of 6 wired projects, and `agent-roles.md` and `source-triage.md`
reached 1 each. Adding a skill without adding it here does not fail loudly — it just quietly
never reaches anyone, which is why the table is the artifact and the surfaces are output.

**Tiers.** `baseline` = always-on; it is written into every project's `CLAUDE.local.md`
(by `bin/init-project.sh` at scaffold, refreshed in place by `bin/sync-project.sh`).
`ondemand` = situational; load it when the task calls for it. Keep `baseline` short — its cost
is paid on every session in every project.

**Adding a skill:** add the file under `skills/`, add one row here, run the renderer, review the
diff, and run `bin/sync-project.sh <project>` on each live project so its `CLAUDE.local.md`
picks the row up. That is the whole procedure — there is no second list to remember.

<!-- ROUTING:BEGIN full -->
| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Any pipeline work at all — every session, before producing any stage artifact (not just "when unsure"); READMEs and the guide are orientation only | `skills/conversion-runbook.md` | all | P,0,1,2,3,4,5,6,7 | baseline |
| Any question before asking the user or writing anything — query the model, then read the source, then ask the human, in that order | `skills/query-the-model.md` | all | P,0,1,2,3,4,5,6,7 | baseline |
| Before writing any .js or .sh for a check, gate or report — and before adding a rule to an existing one: judgement goes in a skill, code only fetches facts a reader cannot | `skills/skills-over-scripts.md` | all | - | baseline |
| Putting a question TO the user — any gate, any stage: ask in chat not in a file, two named options plus your recommendation, one batch per gate then end the turn | `skills/interview-protocol.md` | ba,architect | P,0,1,2,3,4,5,6,7 | baseline |
| Setting up or completing a project's dev-process subagents — once, at project start, not "on demand" | `skills/agent-roles.md` | all | P,4,5 | baseline |
| Deciding whether to extract at all, before any BRD gets generated | `skills/source-triage.md` | ba | 0 | baseline |
| Taking in a new source — before generating anything from it. Grades what the source can support; nothing else in this toolkit reads a source | `bin/source-sufficiency.sh` | ba | 0,1 | baseline |
| Deciding who answers a question — before putting any batch to the user. gap/conflict/choice is what keeps a gate batch at four questions instead of 127 | `bin/question-kinds.sh` | ba | 1,2,3 | baseline |
| Writing BRDs, especially several in parallel — "build" before the fan-out, "check" before any BRD is called done | `bin/facts-lock.sh` | ba | 2 | baseline |
| Building any module — before the first script. The mdl-agent's single per-module input | `skills/module-brief.md` | ba,mdl | 4,5 | baseline |
| Writing ANY MDL script — before the first line. Step 0 picks the write mode, then the STOP table overrides it for corrupting operations | `skills/learned-mdl-preflight.md` | mdl | 5 | baseline |
| Placing any document in a module — before the first `create`. Feature group, then Pages/Microflows/Services/Resources; the path comes from the brief's folder plan, and the table says which types mxcli can actually place | `skills/module-folder-convention.md` | architect,mdl | 4,5 | baseline |
| Writing or fixing any microflow — MDL gotchas plus annotation discipline | `skills/learned-microflow-patterns.md` | mdl | 5 | baseline |
| Building any page or snippet — before the first widget. Wireframe, tokens, gallery reuse, cross-check; no wireframe means STOP | `skills/ui-preflight-pages.md` | mdl | 5 | baseline |
| Building or using the in-app design gallery | `skills/learned-stylegallery.md` | mdl | 5 | baseline |
| Choosing CLI vs MCP+MDL vs hand-rolled MCP, or any MCP write session — three co-equal write modes, not CLI-only | `skills/learned-mcp-patterns.md` | mdl | 5 | baseline |
| Reviewing any module before calling it done — the ONE pass: build, gate, prove, LOOK (is it logical, does it look right, does it match our design, over every page not just the tested ones), confirm with the denominator stated | `skills/module-review.md` | mdl,review,test | 5,6 | baseline |
| Before calling any module tested — what testing a module means, and the false-green register of confirmed ways a test reports green over a broken feature | `skills/testing-shape.md` | test,gate,review | 5,6 | baseline |
| Finishing any module — before calling it done. One command that runs every instrument and keeps "instrument faulted" apart from "feature failed"; in a wired project run the installed copy at bin/verify-module.sh | `project-bin/verify-module.sh` | mdl,gate,test,review | 5,6 | baseline |
| A CE error or behavior that looks like a known mxcli quirk rather than a modeling mistake | `bug-logs/mxcli-bugs.md` | mdl,gate | 5,6 | baseline |
| Generating a new project's CLAUDE.md — baseline routing plus project-specific facts | `skills/bootstrap-project.md` | ba | P | ondemand |
| Auditing or regression/e2e-testing an EXISTING app — no intake, no stages, no gates | `skills/existing-app-assurance.md` | test,review | 6 | ondemand |
| Assessing or planning a migration up front, before any pipeline is chosen | `skills/assess-migration.md` | ba | 0 | ondemand |
| Running the extraction pipeline | `skills/migration-pipeline.md` | ba | 0,1 | ondemand |
| Migrating from a stack that has no dedicated pipeline | `skills/migrate-general.md` | ba | 0 | ondemand |
| Migrating an OutSystems app | `skills/migrate-outsystems.md` | ba | 0 | ondemand |
| Understanding OutSystems 11 source | `skills/source-os11.md` | ba | 0,1 | ondemand |
| Reading the OutSystems XML export schema | `skills/os-xml-schema.md` | ba | 0,1 | ondemand |
| Understanding Node/Express+React source, its layout assumptions and its gaps | `skills/source-node-express-react.md` | ba | 0,1 | ondemand |
| Scanning or classifying an unstructured document folder | `skills/document-discovery.md` | ba | 0,1 | ondemand |
| Validating an extractor's output before its BRDs are trusted | `skills/extractor-quality-loop.md` | ba | 0,1 | ondemand |
| Validating a new stack pipeline's extraction quality | `skills/qa-loop-goal-pattern.md` | ba | 0,6 | ondemand |
| Extracting Excel/Word/PDF specs into a knowledge base | `skills/kb-generation.md` | ba | 1,2 | ondemand |
| Writing or enriching a BRD JSON | `skills/brd-generation.md` | ba | 2 | ondemand |
| Validating BRDs against the code and document KB | `skills/brd-validation.md` | ba | 2 | ondemand |
| Diagramming target architecture — module defs, wiring, fit-gap, marketplace, security, NFRs, integrations | `skills/architecture-blueprint.md` | architect | 3 | ondemand |
| Deciding module boundaries before "create module" | `skills/modularize-domain.md` | architect | 3 | ondemand |
| Designing the brand and ONE ANNOTATED WIREFRAME PER SCREEN before building pages — the design system alone is half the deliverable | `skills/design-artifacts.md` | architect | 3 | ondemand |
| Turning BRDs plus architecture into a numbered, dependency-ordered build plan | `skills/brd-to-build-plan.md` | architect | 3,4 | ondemand |
| Building the Stage 4 coverage ledger — every requirement either claimed by a build-plan row or catalogued with a reason, never invisible | `skills/coverage-ledger.md` | architect,gate | 4 | ondemand |
| Checking a coverage ledger against its BRD — every scalar leaf CLAIMED, LEDGERED, UNCLAIMED, PHANTOM or DOUBLE-CLAIMED, so coverage is measured rather than remembered | `bin/coverage-check.sh` | architect,gate | 4 | ondemand |
| Building a module with mxcli — verified, iterative, coverage-checklist gated | `skills/iterative-build-loop.md` | mdl,gate | 5 | ondemand |
| Writing MDL microflow scripts — worked recipes | `skills/mdl-cookbook-microflows.md` | mdl | 5 | ondemand |
| Building and auditing Mendix pages — widget patterns, datasource shapes | `skills/learned-page-patterns.md` | mdl | 5 | ondemand |
| Generating a whole page tree in one script — the structure patterns that survive it | `skills/oneshot-page-structure-patterns.md` | mdl | 5 | ondemand |
| Running the ledger rung alone — recompute every stored ledger status against the live model and catch the STALE rows that claim built for something the model no longer has | `project-bin/conformance-check.sh` | gate,review | 5,6 | ondemand |
| Running the wiring rung alone — a module imported but never reached, an element built but wired to nothing, a boundary crossed; mxbuild and e2e are blind to all three | `project-bin/graph-sweep.sh` | review,gate | 5,6 | ondemand |
| Before any runtime test — brings the stack up unattended and PROVES the thing that answered is this project's app; --check makes it report-only | `project-bin/test-stack-up.sh` | test,gate | 5,6 | ondemand |
| Standing up or extending the Playwright e2e harness | `skills/e2e-harness-base.md` | test | 6 | ondemand |
| Writing DB assertion tests that cross-check UI state against the database | `skills/learned-db-assertions.md` | test | 6 | ondemand |
| Establishing the data and identities a journey run needs — BEFORE it runs. Derive and measure with project-bin/fixture-manifest.sh first; interview only the residue, and never seed from inside the harness | `skills/fixture-seeding.md` | test,review | 5,6 | ondemand |
| Proving a module's user journey end-to-end — the deep form of step 3 PROVE; use whenever an instrument reports green and you cannot say what would have made it red | `skills/journey-proof.md` | test,review | 5,6 | ondemand |
| Running the fuzz/crash net on a module whose journeys are already green — and reading the result, which is NOT evidence the module works | `skills/monkey-test.md` | test,review | 5,6 | ondemand |
| UX audit and screenshot-loop discipline | `skills/learned-skill-ux-audit.md` | review | 6 | ondemand |
| Tracking scope delta between the BRD and the built state | `skills/learned-skill-scope-delta.md` | review | 6 | ondemand |
| Cutover and retrospective — promoting proven patterns back into the toolkit | `skills/close-the-loop.md` | all | 7 | ondemand |
| Writing or reading docs/report.json — the append-only contract every instrument writes to and every renderer reads; open BEFORE building a new instrument or a second renderer | `skills/report-schema.md` | test,review,gate | 5,6 | ondemand |
| Installing, extending, debugging or porting the verification harness — which part owns what, which parts run standalone, and what a missing part must report | `skills/harness-architecture.md` | test,review | 5,6 | ondemand |
| Before citing ANY behavioural claim about the harness, the Mendix runtime or a test tool as evidence — a claim not in the register may not be cited | `skills/measured-claims.md` | all | - | ondemand |
| Any time an exit code, a tool's output or a subagent's report is about to become a stated finding — verify before you conclude | `skills/tool-output-is-not-ground-truth.md` | all | - | baseline |
| Checking whether the whole journey hangs together rather than each piece — finds correctly-built components nothing reaches, which per-element conformance and UI tests both miss | `skills/process-coherence-pass.md` | review | 5,6 | ondemand |
| Turning an already-rigorous run into a narrated proof a stakeholder can trust without running anything | `skills/e2e-evidence-report.md` | test,review | 6 | ondemand |
| Studio Pro will not load the project, or the .mpr looks gutted — recover before relaunching SP, never git checkout | `skills/mpr-corruption-and-sp-load-errors.md` | mdl,gate | - | ondemand |
| Running lint as a gate rather than a report — per-rule ratchet against a committed baseline, plus the crash and collapse guards that stop a blind rule passing | `project-bin/lint-gate.sh` | mdl,gate | 5,6 | ondemand |
| Reading a lint result, or writing/repairing any .star rule — lint's failure mode is a confident clean pass, so 0 findings is a claim needing evidence | `skills/lint-that-actually-runs.md` | gate,review | 5,6 | ondemand |
| Authoring the cross-module user journey ONCE at design time as a source artifact, bound L0→L3, that the module brief, coherence pass and journey-proof read instead of each re-deriving it | `skills/journey-map.md` | ba,architect,test | 2,3,4 | experimental |
<!-- ROUTING:END -->
