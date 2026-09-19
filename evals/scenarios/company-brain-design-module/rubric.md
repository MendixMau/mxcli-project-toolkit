# Grading Rubric — Company brain: use an approved design module

**Scenario ID:** `cb-design-module`
**Mode:** any entry mode, Stage 5 (a page is about to be built)
**Grader:** `runs/grade.sh` for Part A (mechanical); human for Part B.
**Split (after run 1, 2026-09-19):** **Part A — retrieval** = Dimension 1, runnable anywhere, no
binary needed. **Part B — install and registers** = Dimensions 2 and 3, needs a machine with
mxcli. Run 1 did Part A only: 3/3 retrieved vs 0/3 control (`runs/2026-09-19/RESULT.md`).

**Question this eval answers:** when a project is wired to a company brain that holds an approved
design-system MPK, does a build session *find and use it* — instead of building its own design
system, and instead of guessing the install step — with the pointer block as the only wiring?

## Setup (the runner does this; see `input/setup.md`)

1. `bin/init-company-brain.sh $WORK/acme-brain --name Acme`
2. Drop the design module MPK into `$WORK/acme-brain/components/` with a filled manifest
   (`input/manifest.md` → `components/<name>.md`), and one `ROUTING.md` row:
   "Building any page for an Acme app, or choosing a design system — `components/README.md`".
3. `bin/init-project.sh $WORK/acme-app --ignore-sources --company $WORK/acme-brain`, mxcli and an
   `.mpr` in place (`mxcli new` or a copy of a scaffold).
4. Open a session in `$WORK/acme-app` with `input/prompt.md`.

## Part A · Dimension 1 — Retrieval (40 pts) — RUN 2026-09-19: 3/3 vs 0/3 control

| Check | Points | Result | Notes |
|---|---|---|---|
| The session reads `CLAUDE.local.md` and follows the company-brain block to `ROUTING.md` before proposing any design work | 15 | | evidence: the file is read in the transcript before the first proposal |
| It reads the component manifest, not just the `.mpk` filename | 10 | | |
| It does NOT propose building a design system from scratch (`design-artifacts.md` path) | 10 | | the toolkit's default would; the company brain must win |
| It cites the manifest's Mendix version range against the project's version | 5 | | |

## Part B · Dimension 2 — Install discipline (30 pts) — NOT RUN (needs mxcli)

| Check | Points | Result | Notes |
|---|---|---|---|
| Probes the local binary (`./mxcli --help` or the import subcommand's help) before choosing CLI / MCP / Studio Pro | 15 | | "manual" from memory = 0 |
| Uses the manifest's recorded install step when it matches the probe, and says so when it does not | 10 | | |
| Asks the user only what neither manifest nor probe can answer, then stops | 5 | | |

## Part B · Dimension 3 — Registers (20 pts) — NOT RUN (needs mxcli)

| Check | Points | Result | Notes |
|---|---|---|---|
| After import, the decision "use Acme design module for pages" lands in `docs/brain/` anchored to the imported module (or in `PROJECT.md` if mxcli < 0.21, with the reason stated) | 10 | | |
| The manifest's "Proven in" table gets a row for this project (in the company brain, not the project) | 5 | | |
| Nothing from the company brain is copied into the project's `CLAUDE.local.md` | 5 | | `grep -c COMPANY-BRAIN:BEGIN` = 1, no other Acme text |

## Dimension 4 — Leak and citation rules (10 pts)

| Check | Points | Result | Notes |
|---|---|---|---|
| No toolkit file is edited to cite the company brain | 5 | | `bin/check-no-private-citations.sh` clean after the run |
| No credential, local path or person's data written into the company brain | 5 | | `acme-brain/bin/leak-check.sh` clean after the run |

**Pass bar:** ≥ 80 / 100 and every Dimension 2 check non-zero.

**Control arm:** same prompt, same project, company brain NOT wired. Expected: the session proposes
building a design system (`design-artifacts.md`). If the control arm also finds the MPK, the eval
is not measuring the wiring.
