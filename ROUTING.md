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

#### Spine — what am I doing, who decides, how do I ask

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Any pipeline work at all — every session, before producing any stage artifact (not just "when unsure"); READMEs and the guide are orientation only | `skills/conversion-runbook.md` | all | P,0,1,2,3,4,5,6,7 | baseline |
| Any question before asking the user or writing anything — query the model, then read the source, then ask the human, in that order | `skills/query-the-model.md` | all | P,0,1,2,3,4,5,6,7 | baseline |
| Before writing any .js or .sh for a check, gate or report — and before adding a rule to an existing one: judgement goes in a skill, code only fetches facts a reader cannot | `skills/skills-over-scripts.md` | all | - | baseline |
| Any pass whose input is missing, stale or unresolvable — before recording UNMEASURED, N/A or a silent skip: name what was missing, say what you assessed against instead, still deliver a verdict | `skills/degrade-to-judgement.md` | all | - | baseline |
| Putting a question TO the user — any gate, any stage: ask in chat not in a file, two named options plus your recommendation, one batch per gate then end the turn | `skills/interview-protocol.md` | ba,architect | P,0,1,2,3,4,5,6,7 | baseline |
| Deep, adaptive interview on one topic, on demand, when a checkpoint's 2+1 or a single question batch isn't enough | `skills/grill-mode.md` | ba,architect | P,0,1,2,3,4,5,6,7 | ondemand |
| Any stage transition — the 2+1 format every CAC uses, and the one-register rule (answers land in PROJECT.md, never in a separate state file). The seven CACs themselves are routed per stage in the situational table | `skills/checkpoints/checkpoint-template.md` | all | 0,1,2,3,4,6,7 | baseline |
| CAC-1, closing Stage 0 in EVERY entry mode — scope IN: full scope or a slice, and in what order. Opens with a brainstorm, not options | `skills/checkpoints/checkpoint-scope.md` | ba,architect | 0 | ondemand |
| CAC-1b, after Stage 1 — scope OUT: is what extraction produced what you meant. No gate stops you; run it late against the BRDs if it was skipped | `skills/checkpoints/checkpoint-extraction.md` | ba | 1 | ondemand |
| CAC-2, after BRD scaffolding and before enrichment — capability grouping and enrichment order | `skills/checkpoints/checkpoint-brd.md` | ba | 2 | ondemand |
| CAC-3, after BRD validation and before architecture locks — the hidden business rules that are expensive to discover later | `skills/checkpoints/checkpoint-architecture.md` | ba,architect | 2 | ondemand |
| CAC-4, after rearchitect sign-off and before any design artifact — branding and UI direction. Opens with a brainstorm | `skills/checkpoints/checkpoint-design.md` | architect | 3 | ondemand |
| CAC-5, after design sign-off and before the build plan — build order and slice boundaries. Opens with a brainstorm | `skills/checkpoints/checkpoint-build.md` | architect,mdl | 4 | ondemand |
| CAC-6, after Stage 6 passes and before any cutover step — migration mode only, and a hard gate: every answer lands CONFIRMED, no ASSUMED defaults | `skills/checkpoints/checkpoint-cutover.md` | gate,test | 6,7 | ondemand |
| Setting up or completing a project's dev-process subagents — once, at project start, not "on demand" | `skills/agent-roles.md` | all | P,4,5 | baseline |
| Deciding who answers a question — before putting any batch to the user. gap/conflict/choice/user-only is what keeps a gate batch at four questions instead of 127 | `bin/question-kinds.sh` | ba | 1,2,3 | baseline |
| Generating a new project's CLAUDE.md — baseline routing plus project-specific facts | `skills/bootstrap-project.md` | ba | P | ondemand |
| Setting up or resuming an mxcli project in a cloud/ephemeral container — the one-time setup order (mxcli download → mxcli init → init-project.sh → sources decision → push) and the commit-and-push loop that survives container reclaim | `skills/cloud-dev-environment.md` | all | P | ondemand |
| Cutover and retrospective — promoting proven patterns back into the toolkit | `skills/close-the-loop.md` | all | 7 | ondemand |
| Before citing ANY behavioural claim about the harness, the Mendix runtime or a test tool as evidence — a claim not in the register may not be cited | `skills/measured-claims.md` | all | - | ondemand |
| Any review pass that runs more than once — module-review, coherence, monkey, wiring-sweep: findings accumulate across runs, a per-run report cannot show a trend | `skills/improvement-register.md` | mdl,gate,test,review | 5,6 | ondemand |

#### Source — reading a legacy system (migration entry mode)

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Deciding whether to extract at all, before any BRD gets generated | `skills/source-triage.md` | ba | 0 | baseline |
| Taking in a new source — before generating anything from it. Grades what the source can support; nothing else in this toolkit reads a source | `bin/source-sufficiency.sh` | ba | 0,1 | baseline |
| Rendering a filled triage.md for review — the triage.html surface Stage 0 names. Renders only; the Stage 0 verdict stays with gate-check and the judgement with source-triage.md | `bin/triage-report.sh` | ba | 0 | ondemand |
| Reviewing what the extraction actually produced — the Stage 1 surface, and the file the Stage 1 gate looks for. Renders a code-extracted and a document knowledge base alike, so a requirements-driven project gets the surface too; prints no zero that a second record does not agree with | `bin/extraction-report.sh` | ba | 1 | ondemand |
| Assessing or planning a migration up front, before any pipeline is chosen | `skills/assess-migration.md` | ba | 0 | ondemand |
| Running the extraction pipeline | `skills/migration-pipeline.md` | ba | 0,1 | ondemand |
| Migrating from a stack that has no dedicated pipeline | `skills/migrate-general.md` | ba | 0 | ondemand |
| Migrating an OutSystems app | `skills/migrate-outsystems.md` | ba | 0 | ondemand |
| Understanding OutSystems 11 source | `skills/source-os11.md` | ba | 0,1 | ondemand |
| Reading the OutSystems XML export schema | `skills/os-xml-schema.md` | ba | 0,1 | ondemand |
| Understanding Node/Express+React source, its layout assumptions and its gaps | `skills/source-node-express-react.md` | ba | 0,1 | ondemand |
| Scanning or classifying an unstructured document folder | `skills/document-discovery.md` | ba | 0,1 | ondemand |
| Validating an extractor's output before its BRDs are trusted | `skills/extractor-quality-loop.md` | ba | 0,1 | ondemand |
| Extracting Excel/Word/PDF specs into a knowledge base | `skills/kb-generation.md` | ba | 1,2 | ondemand |

#### Requirements — what must be built

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Writing BRDs, especially several in parallel — "build" before the fan-out, "check" before any BRD is called done | `bin/facts-lock.sh` | ba | 2 | baseline |
| Reviewing what the BRDs actually say — the Stage 2 surface, for BRDs from any source. Reads every knowledge base at once, and keeps a section that is absent-because-not-applicable apart from one that is absent-because-expected | `bin/brd-report.sh` | ba | 2 | ondemand |
| Building any module — before the first script. The mdl-agent's single per-module input | `skills/module-brief.md` | ba,mdl | 4,5 | baseline |
| Validating a new stack pipeline's extraction quality | `skills/qa-loop-goal-pattern.md` | ba | 0,6 | ondemand |
| Writing or enriching a BRD JSON | `skills/brd-generation.md` | ba | 2 | ondemand |
| Validating BRDs against the code and document KB | `skills/brd-validation.md` | ba | 2 | ondemand |
| Turning BRDs plus architecture into a numbered, dependency-ordered build plan | `skills/brd-to-build-plan.md` | architect | 3,4 | ondemand |
| Building the Stage 4 coverage ledger — every requirement either claimed by a build-plan row or catalogued with a reason, never invisible | `skills/coverage-ledger.md` | architect,gate | 4 | ondemand |
| Checking a coverage ledger against its BRD — every scalar leaf CLAIMED, LEDGERED, UNCLAIMED, PHANTOM or DOUBLE-CLAIMED, so coverage is measured rather than remembered | `bin/coverage-check.sh` | architect,gate | 4 | ondemand |
| Writing an actual .journey.json — the worked field-by-field reference for the contract journey-proof.md argues for | `skills/journey-examples.md` | test,review | 5,6 | ondemand |
| Extracting structured requirements from a large delivered document corpus into per-scope knowledge-base files | `skills/corpus-extraction-integrity.md` | ba | P,0,1 | ondemand |

#### Architecture — how it is shaped

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Placing any document in a module — before the first `create`. Feature group, then Pages/Microflows/Services/Resources; the path comes from the brief's folder plan, and the table says which types mxcli can actually place | `skills/module-folder-convention.md` | architect,mdl | 4,5 | baseline |
| Diagramming target architecture — module defs, wiring, fit-gap, marketplace, security, NFRs, integrations | `skills/architecture-blueprint.md` | architect | 3 | ondemand |
| Deciding module boundaries before "create module" | `skills/modularize-domain.md` | architect | 3 | ondemand |

#### Design — how it looks, before any MDL

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Building any page or snippet — before the first widget. Wireframe, tokens, gallery reuse, cross-check; no wireframe means STOP | `skills/ui-preflight-pages.md` | mdl | 5 | baseline |
| Writing or reviewing any page or snippet — the spacing scale (8/16/24/32/48), section rhythm, and the page-header scaffold every full page starts with; sections at 0px apart and pages with no H1 are the defects it retires | `skills/design-spacing.md` | mdl,review | 5 | baseline |
| After every page-building script, and any time the UI looks wrong — the cheap repeatable look during the build: one page, one screenshot, three questions. Feeds Gate: UI, never replaces it | `skills/ui-loop.md` | mdl,review | 5 | baseline |
| Building or using the in-app design gallery | `skills/learned-stylegallery.md` | mdl | 5 | baseline |
| Before porting ds.css into SCSS, and at the Stage-3 gate — greps the stylesheet for rules that cannot match the HTML Mendix emits (rem against the real root, table/th/td selectors, positional row selectors). mx check, mxcli check and mxcli lint are all blind to CSS | `project-bin/check-design-portability.sh` | architect,mdl,gate | 3,5 | ondemand |
| Before exec'ing ANY page script — compares the drafted MDL's shell against the wireframe's: page column, layout/nav shell, one H1. Measured 0/10 pages on a real first build, repaired wholesale 47 scripts later | `project-bin/check-page-shell.sh` | mdl,gate,review | 5 | baseline |
| After drafting and again after exec'ing any page script — scores the page MDL (or `mxcli describe` output on stdin) against its wireframe: headings/actions/content/classes, weighted. The scored companion to check-page-shell's binary gate; 32% median measured without it, 90% first-draft with it. Every run is appended to the project's docs/PAGE-FIDELITY.tsv — first non-stub row per page = first-build score of record vs the ≥80% target (forward-reference stubs score with --stub, exempt) | `project-bin/page-fidelity.js` | mdl,gate,review | 5 | baseline |
| Designing the brand and ONE ANNOTATED WIREFRAME PER SCREEN before building pages — the design system alone is half the deliverable | `skills/design-artifacts.md` | architect | 3 | ondemand |
| Before a wireframe or a design commits to a WIDGET — and when a page script hits a parse error that looks like a syntax mistake: the short list of things MDL cannot write at all, and the four-minute probe that answers it at Stage 3 instead of at build time | `skills/learned-mdl-cannot-express.md` | architect,design,mdl | 3,5 | ondemand |

#### Build — the loop itself

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Reviewing any module before calling it done — the ONE pass: build, gate, prove, LOOK (is it logical, does it look right, does it match our design, over every page not just the tested ones), confirm with the denominator stated | `skills/module-review.md` | mdl,review,test | 5,6 | baseline |
| Building a module with mxcli — verified, iterative, coverage-checklist gated | `skills/iterative-build-loop.md` | mdl,gate | 5 | ondemand |
| After marking a module done, or any time "how much is built vs proven" is asked — renders build-plan.html from done- prefixes and verify-module.sh/improvement-register.md, kept as two honestly separate views | `project-bin/build-plan-status.sh` | architect,gate,review | 4,5,6 | ondemand |
| Turning a client-derived Mendix app into a clean, shareable demo with zero client fingerprint — branding, data, custom widgets | `skills/anonymize-client-app-for-demo.md` | mdl,review | 6 | ondemand |
| Handing a headless-built model to a person — opening it in Studio Pro, a free sandbox, or a colleague's machine: the model travels, the demo data and runtime config (keys, an agent's bound model) do not, and each needs its own re-establish step | `skills/handoff-to-studio-pro.md` | test,review | 6,7 | ondemand |
| Sharing the project with a colleague on Mendix Team Server while the build loop stays on GitHub — content-transplant snapshots between the two clones (status/push/pull); UNPROVEN against a real Team Server, first field run owed | `project-bin/ts-sync.sh` | mdl,gate | 6,7 | experimental |

#### Build · MDL — the language and tool reference

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Writing ANY MDL script — before the first line. Step 0 picks the write mode, then the STOP table overrides it for corrupting operations | `skills/learned-mdl-preflight.md` | mdl | 5 | baseline |
| Writing or fixing any microflow — MDL gotchas plus annotation discipline | `skills/learned-microflow-patterns.md` | mdl | 5 | baseline |
| Choosing CLI vs MCP+MDL vs hand-rolled MCP, or any MCP write session — three co-equal write modes, not CLI-only | `skills/learned-mcp-patterns.md` | mdl | 5 | baseline |
| Writing MDL microflow scripts — worked recipes | `skills/mdl-cookbook-microflows.md` | mdl | 5 | ondemand |
| Writing a single MDL script that takes a project from nothing to a working vertical slice — execution order, why it is deliberately non-idempotent, the instrument hierarchy, and the silent failures that pass every check | `skills/build/mdl/oneshot-mdl-method.md` | mdl | 5 | ondemand |
| Writing a popup page's microflow with a retry/validation-failure branch that re-shows the same popup — missing close page stacks duplicate dialogs | `skills/learned-popup-navigation.md` | mdl | 5 | ondemand |
| Writing MDL for a datagrid column with ShowContentAs customContent that needs to display a bound value | `skills/learned-datagrid-customcontent-binding.md` | mdl | 5 | ondemand |
| Writing a popup whose primary button creates/commits an object or triggers a backend flow — MDL has no native toast, so feedback must be explicit | `skills/learned-popup-feedback-pattern.md` | mdl | 5 | ondemand |

#### Build · Pages — page-building patterns

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Building and auditing Mendix pages — widget patterns, datasource shapes | `skills/learned-page-patterns.md` | mdl | 5 | ondemand |
| Generating a whole page tree in one script — the structure patterns that survive it | `skills/oneshot-page-structure-patterns.md` | mdl | 5 | ondemand |
| Building or auditing a collapsible sidebar nav — Atlas Core's collapsed state needs icons assigned per menu item or it silently clips label text | `skills/learned-sidebar-collapse-icons.md` | mdl | 5 | ondemand |
| Building or altering any data grid — native DATAGRID vs pluggable DG2 decision rule, the ALTER PAGE INSERT corruption, sort-by and filter-binding traps | `skills/learned-dg2-patterns.md` | mdl | 5 | ondemand |

#### Build · Agents — Mendix AI agents, tools, knowledge bases, chat UI

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Building a Mendix AI agent — the agent is runtime data not a model document, so JSON import, tool microflows, knowledge base chunk loading and the runtime wiring all sit outside MDL, and mxbuild stays green when they are wrong | `skills/mendix-agents.md` | mdl,architect | 5 | ondemand |
| Embedding a copilot chat panel — the frame is yours, ConversationalUI owns the conversation; wireframe to tokens to snippet to page placement | `skills/mendix-agent-ui.md` | mdl | 5 | ondemand |
| Standing up a project's GenAI agents in any environment — MxCloud key import, model-to-agent binding, KB indexing and the agent-answers-a-question proof are all UI-only (no MDL/SQL path), driven with Playwright; you need the resource keys handed to you as env vars first | `skills/mendix-agent-setup.md` | mdl,test | 5,6 | ondemand |

#### Build · Workflow

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Writing or debugging a Mendix native Workflow (CREATE WORKFLOW/USER TASK/OUTCOMES) — syntax, the 11 workflow microflow statements, DECISION vs CALL MICROFLOW, and the two corruption classes (binary-version $Type, and create-before-reference) | `skills/learned-workflow-patterns.md` | mdl | 5 | ondemand |
| Designing or reviewing a Workflow's SHAPE before or after the MDL — where a path may end, boundary event vs event sub-process, parallel-split limits, outcome minimums, targeting from the sentence, multi-user decision methods, which edits break running instances; and any CE6689/CE1844/CE1845/MW0012 after a clean mxcli check | `skills/workflow-structure-rules.md` | architect,mdl,review | 3,4,5,6 | ondemand |

#### Build · Integration

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Building a REST integration (consumed or published) for the first time on a project — the checks that avoid a rebuild after the first live call | `skills/rest-integration-first-time-right.md` | mdl | 4,5 | ondemand |

#### Build · Security

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Creating any entity, or calling a module security-ready — entity and grants land in one script, and ready means SHOW SECURITY MATRIX proves it | `skills/security-is-not-a-later-script.md` | mdl,gate,review | 5 | baseline |

#### Verify — does it work

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Before calling any module tested — what testing a module means, and the false-green register of confirmed ways a test reports green over a broken feature | `skills/testing-shape.md` | test,gate,review | 5,6 | baseline |
| Finishing any module — before calling it done. One command that runs every instrument and keeps "instrument faulted" apart from "feature failed"; in a wired project run the installed copy at bin/verify-module.sh | `project-bin/verify-module.sh` | mdl,gate,test,review | 5,6 | baseline |
| Auditing or regression/e2e-testing an EXISTING app — no intake, no stages, no gates | `skills/existing-app-assurance.md` | test,review | 6 | ondemand |
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
| Writing or reading docs/report.json — the append-only contract every instrument writes to and every renderer reads; open BEFORE building a new instrument or a second renderer | `skills/report-schema.md` | test,review,gate | 5,6 | ondemand |
| Installing, extending, debugging or porting the verification harness — which part owns what, which parts run standalone, and what a missing part must report | `skills/harness-architecture.md` | test,review | 5,6 | ondemand |
| Checking whether the whole journey hangs together rather than each piece — finds correctly-built components nothing reaches, which per-element conformance and UI tests both miss | `skills/process-coherence-pass.md` | review | 5,6 | ondemand |
| After every module's CONFIRM stage — counts proven modules since the last cluster/full coherence pass and exits DUE once the threshold is reached, so the cadence isn't left to memory | `project-bin/coherence-cadence.sh` | mdl,gate,review | 5,6 | ondemand |
| Turning an already-rigorous run into a narrated proof a stakeholder can trust without running anything | `skills/e2e-evidence-report.md` | test,review | 6 | ondemand |
| Recording a narrated screen-capture demo of a running app for a human to watch — opening on the app instead of a blank frame, and keeping captions synced to the pixels | `skills/record-demo-video.md` | test | 6 | ondemand |
| Running lint as a gate rather than a report — per-rule ratchet against a committed baseline, plus the crash and collapse guards that stop a blind rule passing | `project-bin/lint-gate.sh` | mdl,gate | 5,6 | ondemand |
| Reading a lint result, or writing/repairing any .star rule — lint's failure mode is a confident clean pass, so 0 findings is a claim needing evidence | `skills/lint-that-actually-runs.md` | gate,review | 5,6 | ondemand |
| Every module before it is called done — does every clickable thing actually do something; run AFTER the happy-path journey is green, never before | `skills/wiring-sweep.md` | mdl,test,review | 5,6 | ondemand |
| The user asks for a full end-to-end test, a click-through proof, or does-everything-actually-work — or you are unsure which harness skill applies; this one routes you | `skills/full-harness-audit.md` | test,review | 5,6 | ondemand |
| End of any build+test cycle that wrote docs/report.json — did the testing itself hold up, not just get filed; one level up from finding-disposition | `skills/test-result-audit.md` | test,review | 5,6 | ondemand |
| Any report from a test/review run is about to be published — no report ends without a disposition for every finding | `skills/finding-disposition.md` | test,review,gate | 5,6 | ondemand |
| Handing the human a batch of steps only they can perform (Stage 7 cutover, browser-only GitHub settings) — generate a paced confirm-and-verify walkthrough script instead of a prose checklist; hypothesis under trial, no field run yet | `skills/wizard-walkthrough.md` | gate,review | P,7 | experimental |
| Exposing a container-run app at a public URL (mxcli run --hub) — demo/stakeholder preview: the db-name default trap, the runtime REST client ignoring JVM proxy settings (GenAI 403 "Host not in allowlist" that is really a proxy bypass), and stale-app detection | `skills/preview-over-hub-tunnel.md` | test,review | 5,6 | ondemand |
| Starting a hub-tunnelled preview with the flags outbound calls actually need — wraps mxcli run --hub with db-name and the runtime proxy settings from preview-over-hub-tunnel.md | `bin/run-hub.sh` | test | 5,6 | ondemand |

#### Diagnose — something is broken and it may be the tooling

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| A CE error or behavior that looks like a known mxcli quirk rather than a modeling mistake | `bug-logs/mxcli-bugs.md` | mdl,gate | 5,6 | baseline |
| Any time an exit code, a tool's output or a subagent's report is about to become a stated finding — verify before you conclude | `skills/tool-output-is-not-ground-truth.md` | all | - | baseline |
| Studio Pro will not load the project, or the .mpr looks gutted — recover before relaunching SP, never git checkout | `skills/mpr-corruption-and-sp-load-errors.md` | mdl,gate | - | ondemand |
| Preparing an mxcli/Studio Pro bug for submission — scope pinning, read-back-vs-write-path verification, gate-sensitivity negative controls, severity scoping, before it's called filable | `skills/bug-submission-checklist.md` | mdl,gate,review | 5,6 | ondemand |
| A page/grid/combobox renders empty (blank cells, zero rows, zero options) during UI review or an e2e run — before assuming a single cause | `skills/empty-widget-triage.md` | mdl,test,review | 5,6 | ondemand |
| Suspecting an mxcli/mxbuild tool defect and deciding whether to swap a binary — proving it's version-specific without risking the real model | `skills/sandbox-ab-tool-defect-probe.md` | mdl,gate | - | ondemand |
| Restarting Studio Pro on macOS — the reopen bug, the port bug, and detecting a real hang vs a slow load | `skills/restart-sp-reopen-and-hang-detection.md` | mdl,gate | - | ondemand |
| Driving the whole toolkit pipeline on a real source to find what the written skills don't say — the toolkit is the subject, not the app it builds | `skills/field-run.md` | all | - | ondemand |
| Before trusting a green check/exec/DESCRIBE result as proof, or when a runtime symptom appears over a fully green model — the register of constructs that pass early rungs and fail later ones | `skills/learned-detection-gaps.md` | mdl,gate,review | 5,6 | baseline |
| Needing Studio Pro load evidence without a human at the GUI — direct-binary launch and log capture; a capture technique, NOT a validated pass/fail oracle | `skills/scriptable-sp-verification.md` | mdl,gate | - | ondemand |
| A runtime test reads/writes data that then is not there, or vice versa — three local Postgres instances can answer on this box; resolve the real port from the project's own compose file first | `skills/learned-local-db-confusion.md` | mdl,test,gate | 5,6 | ondemand |
| gate-check.sh reports a Stage 0 file not found that plainly exists — ANALYSIS_BASE falls back to project root until Stage 1; move the file, do not debug the script | `skills/gate-check-file-locations.md` | ba,gate | 0 | ondemand |

#### Reference — lookup tables, not method

| Always relevant for | Load this | Agent(s) | Stage(s) | Tier |
|---|---|---|---|---|
| Working with the Mendix Epics board programmatically — creating/reading stories and epics, updating workflow state, or integrating BRDs with the portal | `skills/mendix-epics-api.md` | ba,architect | P,0 | ondemand |
<!-- ROUTING:END -->
