# Handover (15 Oct 2026)

For the next agent picking up the upgrade toolkit (`upgrade-toolkit/`). Read this, then `SKILL.md`, then the spec named per item.

Standard prompts (backfill the run log, start an upgrade, resume after a container restart, hand over): [templates/prompts.md](templates/prompts.md). Run log: `FIELD-RUNS.md`, written by `bin/runlog.py`.

## Goal and definition of done
- Goal: a toolkit that lets people complete their own Mendix upgrades to the latest LTS (11.12.5), driven to completion with honest reporting.
- Run done (owner, 15 Oct; `SKILL.md` "Run done", spec `research/design-2026-10-15/trust.md`): 0 open items + owner sign-off. Every item ends FIXED (re-measured PASS/PASS*), EVIDENCED, DECIDED, HANDED-OFF or PAUSED. The agent closes only FIXED; it prepares the rest with evidence and a recommendation. Re-architecture (other widget, custom widget, rebuild) is always proposed to the owner, never done silently.
- Reports never say a run "FAILED": progress line `N of M checks closed (P%)`, owner sign-off is the last check (PR 101). Machine codes PASS/PASS*/FAIL/INVALID and exit codes stay for scripts.

## Rules (owner's, keep them)
- Never weaken a gate: DEFECT_MAX 0.30, no `--bar processes`, no hand edits to verdicts.
- Every code change ships a must-catch + must-pass control in `controls/run-controls.sh`, mutation-tested (revert the fix, the control must go red).
- Run scoped controls only (`bash controls/run-controls.sh --only 'REGEX'`), never the full suite unless asked.
- Commit with explicit paths, never `git add -A`. Merge to main through PRs (self-merge allowed). Many sessions push to this repo, including the owner's parallel thread (`night/*` branches): merge main before opening a PR.
- `FEEDBACK.md` is the register (630+ rows, 0 open): append rows, recompute the Counts table by counting rows by status word. Merge conflicts there: keep all rows from both sides.
- No customer data, public apps only, `$MENDIX_PAT` only via env (never on a command line), Python on downloaded files with `-I`, no model names in commits or files.
- Cheap models for mechanical work; stronger reasoning for new failure clusters, gate policy, design.

## State of main (merged this week)
PR 78/79 Academy macOS fixes + register rows; 85/86 seeding research, seed_snapshot HSQLDB fix; 91/92 owner's night branch (7 runs of lessons) + review fixes; 95 F43/F44 (list-row inputs, file upload: live-proved); 96 design research (`research/design-2026-10-14/`, six reports); 98 migration-step rows in release impact, Assign-to-me guard, git proof for unedited theme files; 100 repair rows (CE6779 OQL v2, CE1613 WorkflowCommons 4 comments, CE2729 Atlas_Core roles); 101 progress line + stuck-item step `steps/decide.md`; 103 journey engine (B1 process supersede, `--park-unassigned`, modal check, double-click rows, destructive scope/waves); 104 trust spec; 106 upgrade proposal step `propose` + `bin/proposal.py` (exit 14 unsigned, 15 paused).

## Open work, in order
1. **Merge branch `trust-ledger`** (change ledger: `bin/changelog.py` -> `$W/CHANGES.md`, `bin/appcommit.sh`, commit trailers `Changed-By` / `Upgrade-Change` on every toolkit commit into the app repo, gate `Changes:` line). Main already merged in; 280/280 scoped controls passed. Merge main again, rerun `--only '^(gate|stepupdate|repair|pipeline|changelog|appcommit|proposal|decide)'`, open PR, merge.
2. **Purchase Request to 0 open** (branch `pr-close` was started and stopped; check what it pushed). Last run (RUN-3 on branch `pr-rebuild`, `research/pr-rerun/RUN-3.md`): 49 of 145 old-app failures, limit 43; 1 regression `MyRequests.container6` (attachment on newest request, cause unknown); 12 of 13 processes pass; P10 Unpause fails; P09 draft (policy question: may a confirmed process fill a conditionally visible field?). To do: port the 3 uncontrolled engine fixes from `pr-rebuild` (dab66496, eabf2510) with controls; one-click "Assign to me" picks the UNASSIGNED task; settle wait between pop-up menu steps; P06d Decline at first state; rerun; root-cause the regression; run the gate step; write `research/pr-rerun/PUNCHLIST.md` (every remaining item with proposed state, evidence, recommendation, one-line owner action; "open items the toolkit can still close: 0").
3. **Owner inputs pending**: visual sign-off of the rebuilt Atlas 4 top bar (screenshots in run dir `work/r22/shots/`); Atlas Web Content 3.6.0 -> 4.4.0 or not; "Complete PO(s)" counted as destructive; confirm 11 agent-written processes (key user); OQL v2 and Atlas_Core role mapping (security) acceptance; 5 seeded comments lost at WorkflowCommons 4.
4. **Backlog designs ready** (`research/design-2026-10-14/four-instruments.md`): `update-widgets` reset check (#29), page by URL when the menu is not rendered (#28), design-property scan (#32); seeding (`seeding-parked.md`): visibility condition -> seed requirement; Atlas classes layer (`atlas-topbar.md`). Backlog #81-83: restoreunit, rolecheck DANGLING, planorder.
5. **Seed skill** draft PR 331 in `MendixMau/mxcli-project-toolkit` (base `master`): apply the review in `research/design-2026-10-14/seeding-parked.md` section 4 (wrong `import from` command, cut ~30 lines), then it can merge.
6. Field report (owner's artifact page) was updated 15 Oct; `REPORT.html` in the toolkit still says "FAIL list".

## Where things are
- Toolkit: `upgrade-toolkit/` (`SKILL.md`, `steps/`, `bin/`, `controls/`, `playbooks/`, `FEEDBACK.md`, `BACKLOG.md`, `research/`).
- Pipeline: `bin/cloud/upgrade-pipeline.sh` (steps fetch triage baseline basewalk propose convert update build after afterwalk journeys diff gate).
- Purchase Request run evidence lives on branch `pr-rebuild` under `research/pr-rerun/` (run dirs in cloud containers are lost on restarts; only pushed branches survive).

## The other upgraded apps (per-app run branches)
Twelve apps were upgraded in earlier batches; each run's evidence (SCORECARD, JOURNAL, HANDWORK, TOOLKIT-FEEDBACK, COMPARE) lives on its own branch `runs/<batch>-<app>`, newest batch wins:
- 11.12.5: Checklist (`runs/b6-checklist`), Forms (`runs/b6-forms`), News (`runs/b5-news`), Tasks (`runs/b5-tasks`), Purchase Request (`pr-rebuild`, see above).
- 11.15 (re-run on 11.12.5 still to do): Opcenter EF (`runs/n1r2-opcenter-ef-11`, `runs/b4-opcenter-ef-11`), Opcenter Starter Kit 7.0, Purchase Request 3.3 (`runs/n3-purchase-request-11`, `runs/b4-purchase-request-11`).
- 10.24 (to 11.12.5 still to do): FSM (`runs/t8r2-fsm`, `runs/b4-fsm`), PFEP (`runs/n2-pfep-10`, `runs/b4-pfep`), Visual Inspection (`runs/b6-visual-inspection`, 11.12.5 started), Kanban with Opcenter (`runs/b5-kanban-opcenter`), Quality Inspection (`runs/t7r2-quality-inspection`, `runs/b4-quality-inspection`; one open regression: intermittent Charts 6 error).
- Batch 1 (`runs/t1..t8*`) is the first pass of the same apps; `runs/b6-pattern-mining` is research. Seeding research for Visual Inspection and Checklist (old 9.24 apps): `research/seeding/` on main.
Next for these apps: rerun each on 11.12.5 with the current toolkit (proposal step, progress line, seeding, B1 engine) and give each a punch list.
