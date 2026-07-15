# Toolkit Worklog — hardening campaign

Running log of toolkit development sessions: what shipped, which live incident drove it, what's open.
**Keep this current**: every toolkit work session appends a dated entry (newest first). This file is
the re-entry point for continuing the work — read it plus `git log --oneline -30` before touching anything.

---

## 2026-07-15 — Demo user passwords + navigation wiring + StyleGallery seed data

Three incidents from live KT-POC builds surfaced in a single session:

**Incident 1 — CLI wiping/setting MxAdmin password.**
Generated security MDL was touching MxAdmin (reset or wipe). MxAdmin ships with password `1` in
every project — it is pre-existing infrastructure, not something the build creates. Demo users
need no password set at all; the in-app user-switch from MxAdmin is the correct workflow.

**Incident 2 — Pages left unwired from navigation.**
StyleGallery home and other generated pages were left unreachable — not wired to any toolbar
nav item. "Navigation shell" in the build plan was vague enough that the wiring step was
consistently deferred and then skipped.

**Incident 3 — StyleGallery rendered NPE/hardcoded containers instead of real widgets + data.**
DataGrid2 and ListView gallery components backed by NPE entities appeared empty on every page
reload. Static `div` containers were used where real Mendix widgets were needed. The "Default to
static" guidance in `learned-stylegallery.md` was the root cause — it sent the wrong signal.

**Rules now:**

| Incident | Rule | Where enforced |
|----------|------|----------------|
| MxAdmin password reset | Never touch MxAdmin; demo users created name+role only, no password block | `learned-mdl-preflight.md` gotchas (fires at draft time); `brd-to-build-plan.md` Step 6 |
| Pages unwired | Every page has a designated nav wire point decided at plan time; `Config` toolbar item for gallery/admin pages; wire at creation not cleanup | `brd-to-build-plan.md` Step 7 (new); Handoff checklist updated |
| NPE/static for data widgets | DataGrid2/ListView must use persistent entity + seeded records; NPE only for object-context-only DataViews; static only for decorative non-widget elements | `learned-stylegallery.md` Static vs Real-Widget section rewritten; 3 new anti-patterns added |

No mechanical gate added — these are author-time rules caught at `mxcli check` + mxbuild.

---

## 2026-07-15 — MDL phasing made explicit: plan fully, generate incrementally

Incident: a WMS build-plan session initially appeared to generate all MDL upfront (turned out
benign — only the plan doc was being written), but the review showed the rule was implicit:
`iterative-build-loop.md` said "replaces bulk MDL generation" without ever stating *when* MDL
gets drafted, and CAC-5 Q1 option A actively offered "full generation in one session".

Rule now (user-confirmed): **the build plan contains no MDL; MDL for phase N is drafted only after
phase N−1 has passed its full gate** (exec.sh mxbuild + SP reopen + happy-path). Enforced in:

- `skills/brd-to-build-plan.md` — ⛔ block after "Output of This Skill" + new anti-pattern
  ("Generating all MDL upfront, even WITH a build plan")
- `skills/checkpoints/checkpoint-build.md` — Q1 reframed as *drafting unit within a phase*;
  option A is now phase-by-phase (default); hard rule stated above the options; Decision
  Recording value updated
- `skills/iterative-build-loop.md` — Core Principle corollary: "MDL is drafted just-in-time,
  never stockpiled"

No mechanical check yet — gate-check Stage 5 is manual by design; if a session is ever caught
stockpiling scripts, add a check for unexecuted `.mdl` files more than one phase ahead.

---

## 2026-07-15 — architecture render is a first-class Stage-3 surface

**Incident:** in an arch test run, the wiring & architecture doc got no HTML while wireframes +
design system did. Root cause was a spec contradiction, not agent error: the runbook's Stage-3
Surface row promised `architecture.html`, but the owning skill (`architecture-blueprint.md`) called
HTML "optional, for stakeholder decks only" — and per "rows are routing, not specs" the agent
followed the skill. gate-check never checked for it either.

**Rule now:** markdown/Mermaid stays the source of truth; `architecture/blueprint.html` is a
**generated checkpoint render** (never hand-edited) that the architecture track must bring to the
Stage-3 ✋ gate, same as the design track's HTML surfaces.

**Shipped:**
- `architecture-blueprint.md` Step 7: render `blueprint.html` from `blueprint.md` (shared CSS shell
  tokens, generated-banner, Mermaid via `<pre class="mermaid">`+mermaid.js or inline SVG for
  offline); new anti-pattern: hand-editing the render.
- `bin/gate-check.sh` Stage 3: FAIL if `blueprint.html` missing **or older than**
  `blueprint.md`/`fit-gap.md`/`open-issues.md` (mtime check). Verified: missing→FAIL,
  stale→FAIL, fresh→PASS.
- Naming aligned: runbook Stage-3 rows + `toolkit-guide.html` now say `architecture/blueprint.html`
  (was `architecture.html`). `module-design.html` unchanged — that surface already existed.

---

## 2026-07-14 — the big hardening day (~20 commits, be26d7c → d242c19)

Context: full toolkit review + live validation on three projects (WMS-App-main, TFC-TCXGraphPOC-main
"TCX", KT-POC). Every incident below produced a named rule + where possible a mechanical check.

### Shipped

| Area | What |
|---|---|
| Spine | conversion-runbook.md finalized: entry modes (migration / requirements-driven / greenfield / à-la-carte), interview protocol, stage matrix, done-checklist |
| Front door | CONVERSION-RUNBOOK.md (root pointer), toolkit-guide.html (visual onboarding + shared CSS shell; auto-opens at install; §4 = CLI vs MCP+MDL vs hand-rolled MCP) |
| Install | **One command**: `bin/init-project.sh <project-root>` → intake, PROJECT.md, CLAUDE.local.md (runbook wiring + baseline routing + session-start ritual), all 5 agent stubs, dashboard. Also `/toolkit-init` slash command (`commands/toolkit-init.md`, copied to `~/.claude/commands/`) |
| Agents | `agents/` stub templates (5) + `bin/init-agents.sh`. Stubs are **inert until completed** (refuse-to-run while `{{PLACEHOLDER}}`s remain). Domain-context block in ba/architect/mdl (customer language + pointers, never memorized facts). Complete ba/architect at Stage P, mdl/gate/test at Stage 5 |
| Gates | `bin/gate-check.sh`: mechanical checks P–7 incl. wireframes (Stage 3), CONFIRMED-decision rows for ✋ stages 3/4/7, test-report (6), intake completeness (P), **protocol-freshness Sync check** (blocks ALL gates if PROJECT.md's `Toolkit commit:` ≠ toolkit HEAD) |
| Sync | `bin/sync-project.sh`: after toolkit pull, refresh copied artifacts (intake questions, untouched stubs, ritual, commit line); flags unwired projects |
| Checkpoints | CAC reconciled with interview protocol — PROJECT.md is the ONE register (no pipeline-state.md). CAC-6 cutover added. Brainstorm-first blocks in CAC-1 (scope), CAC-4 (design), CAC-5 (build); open-floor question closes every checkpoint |
| Pipelines | Capability grouping (`generators/lib/capability-grouper.js`, java-angular + node-express-react): per-item path-evidence rollup of technical-layer packages → business-capability BRDs; `brd/grouping-proposal.md` confirmed at CAC-2 Q0; `config.json brdGrouping` overrides. Verified on real WMS KB (19 pkg → 17 capability BRDs, `impl`'s 113 items fanned out correctly). Enrichment-summary report ported to outsystems (function-centric schema) + node-express-react; config-driven hero (`config.json "project"`); hardened vs missing arrays. `npm run reports` in all three |
| Layout | **analysis/ lives INSIDE the project folder** (never a sibling); flat `analysis/knowledge-base` accepted; split-workspace demoted to licence-constrained variant |
| Build WOW | brd-to-build-plan.md canonical phase shape (user-confirmed WOW): **Phase 1 full scaffolding + domain models across all modules → Phase 2 StyleGallery/UI module (theme CSS, example classes) → microflows → pages → security/demo users** |
| Docs | README rewritten (agent banner: "orientation, not the spec"), toolkit CLAUDE.md rewritten, pipeline READMEs refreshed, assess-migration de-duplicated to a pointer (bundled skill is canonical), Stockpilot name stripped |

### Incident → rule map (all cited inline in the runbook)

| Incident | Rule/mechanism now |
|---|---|
| Sibling `analysis/<project>/` scaffolded | In-repo layout is the default everywhere; docs say "never a sibling" |
| TCX misrouted to greenfield despite specs+source | Entry mode = confirmed Stage-P decision; classification rules (source→analyze, specs→requirements-driven, greenfield only from a conversation) |
| Stages 1–3 ran with zero questions asked | **ASSUMED is earned by asking** (user said "you decide"); ask via AskUserQuestion then END TURN; unattended mode opt-in only (intake Q9); gate-check requires CONFIRMED rows |
| Stage 3 done with design system but no wireframes | Stage 3 gate fails without `design/wireframes/*.html`; "rows are routing, not specs" — open the owning skill |
| Stage 4 skipped citing Stage-3 "decisions" nobody made | Anti-laundering: skips must quote the prior user-answered decision back in chat |
| Stage 3+4 agents launched in parallel, self-declared done | Stages sequential; gates paste-proven (gate-check output in chat); parallelism only within a stage |
| "Let's ideate" answered with generated artifacts | "Let's ideate" halts production until the conversation converges; CAC-1/4/5 open with brainstorms |
| Sessions obey stale rules | Session-start ritual + protocol-freshness Sync gate (PROJECT.md `Toolkit commit:` must match HEAD) |
| No interview anywhere / only closed Q&A | Brainstorm mode: scope (CAC-1), design (CAC-4), build (CAC-5) open-floor conversations |

### Open items

- [ ] **Run one full source end-to-end under the new protocol** — the real validation; then delete `TOOLKIT-IMPROVEMENT-PROPOSAL.md` (kept until then)
- [ ] WMS: redo build plan via CAC-5 (brainstorm first, no pre-fill); re-validate existing MDL against the new plan; commit its wiring files (uncommitted in that repo)
- [ ] TCX: retro CAC-3/CAC-4 pass (artifacts = proposals), move `reports/*` wireframes/design to `design/` convention paths, merge `architecture/PROJECT.md` into root `PROJECT.md`, commit wiring
- [ ] `pipelines/java-angular/pipeline/config.json` is committed with real WMS paths — deliberate ("PROJECT-OWNED" comment) but violates the repo's own rule; decide keep-exception vs move out
- [ ] Stage 5 gate-check stays MANUAL by design (per-module checklists live in iterative-build-loop); revisit if needed
- [ ] Possible CAC for Stage 1 (analysis paths done/declared-unavailable attribution) — deliberately skipped so far
- [ ] Naming decided: stays "mxcli-project-toolkit" (MCP is a write mode, not the brand)

### Standing conventions for future toolkit sessions

- Commit per work item in this repo (user pre-approved); push after each batch; never commit other repos without asking.
- Every improvised decision in a consuming project = runbook defect → fix the template here, log it in this file.
- Incident entries name the failure, the rule, and the mechanical check — prose alone doesn't count as fixed.
