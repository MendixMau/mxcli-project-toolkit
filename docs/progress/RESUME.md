# RESUME — handle 2026-08-25-2245

## Where we are
a customer training round day 1 failed. Diagnosed from artifacts; 3 toolkit fixes shipped and tested;
a replan prompt for day 2 is written and ready to paste. Nothing is half-done.

## Do first, before anything else
1. **PUSH `4f75473`** — Windows mxbuild fix + gate-check perf fix, committed LOCAL-ONLY. Until it
   lands, the workshop room runs with no mxbuild verification (it silently never ran on Windows).
   This clone is ~27 commits behind origin; peers share the tree (14 dirty files). Coordinate.
2. Tell attendees: `MXTK_NO_FETCH=1` in their env. Never `MXTK_SKIP_GATES=1`.
3. Verify each machine: `git -C <toolkit> rev-parse --short HEAD` == PROJECT.md `Toolkit commit:`.
   The workshop project still records `40ffa85` — 33 commits / 29 skills stale.

## The day-2 prompt
`~/Mendix/<workshop-project>/docs/local/replan-prompt.md` — **local only, gitignored**
(`.gitignore:33`), because that repo's remote is the shared Mendix Team Server. Do not move it.

## What changed in the toolkit (committed)
| File | Change |
|---|---|
| `project-bin/exec.sh` | guard 5 — *warns* when a script writes to a module with no brief (build-plan projects only); never refuses. The `BRIEF` row in the build plan is the enforcement |
| `skills/brd-to-build-plan.md` | Step 5 row schema: BUILD/PROVE/RUN/HARNESS, Skills column, "every phase ends in a verification row", brief = row 0 |
| `skills/module-brief.md` | "Build skills to read first" widened past Workflow/Agent to every build group; now a roll-up of the rows |
| `skills/iterative-build-loop.md` | the "enforced manually" claim, made false by the guard |

Tested: 12/12 scratch matrix + 28-script replay of day 1 (first refusal at script 1 of 28).
No wave2 fixture was run — standing rule. `test-bug07-08.sh` was verified by inspection and the
guard was changed so its `CREATE MODULE "Nope";` fixture still passes.

## Agreed, not done
Content-triggered skill routing (`triggers` column on `skill-routing.tsv`, greped by exec.sh as a
backstop) and project-profile baseline routing. **77 of 101 skills are `ondemand`** — invisible
unless something names them. That is the root routing bug; the two fixes above only narrow it.

## Read for detail
`docs/progress/checkpoints.md` → handle 2026-08-25-2245 (full narrative, evidence, traps).
