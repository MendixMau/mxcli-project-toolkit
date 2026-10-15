# mxcli-project-toolkit 1.0

> DRAFT. Lines marked *(if merged by release)* depend on an open PR. Drop any whose PR misses the cut.

mxcli-project-toolkit is a shared process layer for building and changing Mendix apps with an AI coding agent and [mxcli](https://github.com/mendixlabs/mxcli). It runs four entry modes (migration, requirements-driven, greenfield, change an existing app) through the same gated stages, plus à-la-carte audit and testing of an app you already have. Judgement lives in skills the agent loads on demand; scripts only fetch facts and run gates.

1.0 is the first named milestone and the first release published to GitHub. Two things are now measured: the agent's context is smaller, and its rules change what it writes. It is a GitHub Release on the `vYYYY.MM.DD` tag `bin/cut-release.sh` creates for this cut; the full detail is in `CHANGELOG.md`.

## Highlights

- **The mdl agent reads 46% less at Stage 5:** 56,236 → 30,185 words, with no loss in the behaviour A/B (#369, #378, #380).
- **The rules change what the agent writes.** Without toolkit rules, agents refused a planted page trap 0/5 times and wrote a passing microflow script 1/5 times. With them: 5/5 and 5/5.
- **Every PR states its cost:** a five-row Impact block (#388) and a standing behaviour suite (#389).
- **Every merge gets an independent review** by someone who did not write the PR. Green CI alone no longer counts (#316).
- **Safer model writes.** One exec lock per project, opt-in `--commit-first`, and a restart verdict after each apply (#304). *(If merged by release:)* a closed lock race (#379) and `--on-copy` (#384).
- **Paste an error, get the right bug entry.** *(If merged by release:)* top-3 hit rate 9% → 94% on 40 dev queries (#395).

## What's new

### Agents and context

- Helpers read only their stage's runbook slice, and a routing row can be on demand for one role (#378, #380).
- Stories and old measurements moved out of always-loaded skills into `process/baseline-incident-history.md`. No rule was dropped (#369).
- The advisory authoring audit (`tests/advisory/authoring-audit.py`, #394) found 14 duplicated rules on its first run. #393 turned seven into pointers; #392 does the other seven, and #391 rewrites nine routing triggers that rarely or never fired *(both if merged by release)*.
- The app-facts loop sweep is incremental: in a 2,000-unit bench with 1% changed, it re-describes 20 units (#373).

### Safety when writing the model

- `bin/mdl-scan.sh` checks each script for four STOP-row patterns before `exec.sh` applies it. Warn-only until a field run proves it (#355).
- CLI commits now list their changed documents in Studio Pro History (#271).
- *(If merged by release:)* `exec.sh --on-copy` applies and gates a scratch copy, then promotes it by rename. If exec dies part-way, the live model stays intact in 10/10 runs, against 0/10 without it. `--recover-promote` recovers an interrupted promotion and is safe to re-run. Field run on macOS: PASS (#384).
- *(If merged by release:)* lock race fix: 0 overlapping holders in a 200-round bench, against 13 on old code on Linux and 21 on macOS (#379).
- *(If merged by release:)* `mxpatch`, with `mxcli fix hashes` checked before and after `exec.sh --patch`. Field run: PASS; it also repaired a stale hash an older `--patch` had left (#374).
- `#` or `?` in a model folder name no longer breaks catalog reads (#377).

### Testing and evidence

- `tests/behaviour/` runs arms M (base), T (candidate, or the base minus one skill) and N (no pack), and records read-all, tool calls and tokens. Partial reads are counted, never dropped (#389).
- Every journey names its claim and ships a control that proves the claim can fail (#368).
- Checks run at three moments: every exec, module close, and the release gate (#364).
- The journey runner checks credentials and the admin API before the first journey. An app that dies mid-suite reads APP-DOWN, not FAIL (#302, #310).
- Extraction: the Stage 1 report reads the validator's score file and flags a self-graded pass.

### Process and contribution

- Feedback typed mid-build is logged in a `PROJECT.md` change log before any edit (#306).
- New lint rules include SEC014 (an external role that can write state, audit or ownership fields). The gate reports BLIND when `mxcli init` has reverted rules to stock (#305, #308, #312).

## Measured results

**Context pack diet** (#369, #378, #380). Method: `render-routing.sh --check` word counts; behaviour A/B of 5 reps × 2 drafting tasks plus 5 probes × 3 reps, one model. Caveat: 5 reps is small.

| Metric | Before | After |
|---|---|---|
| mdl agent, Stage 5 (words) | 56,236 | 30,185 |
| Always-loaded baseline (budget 80,000) | 75,028 | 73,475 |
| Planted trap refused | 10/10 | 10/10 |
| Page script rejected by `mxcli check` | 3/5 | 2/5 |
| Retrieval probes, trimmed pack | n/a | 15/15 |

On the old 4,822-line pack, 3 of 5 probe agents stopped reading part way.

**No pack vs pack** (5 reps per arm). Caveat: every arm, including no-pack, also loaded a generic mxcli/MDL project guide, so this measures "toolkit rules vs none".

| Metric | No toolkit | With a pack |
|---|---|---|
| Page trap refused | 0/5 | 5/5 |
| Page script passes check | 0/5 | 2–3/5 |
| Microflow script passes check | 1/5 | 5/5 |
| Microflow preflight rules followed | 0/5 | 5/5 |
| Commit inside a loop | 2/5 | 0/5 |

**Ranked bug lookup** (#395, *if merged by release*). Method: 40 labelled dev queries plus 15 held-out queries written before the ranker ran. Caveat: the held-out set is small.

| Metric | Before | After |
|---|---|---|
| Right entry in top 3, dev | 9% | 94% |
| Right entry in top 3, held-out | 0% | 100% |
| Confident-wrong, held-out | 0% | 0% |
| Time per query | ~950 ms | ~45 ms |

Embeddings were rejected: 91% top-3, but 20% confident-wrong, and no "no match" answer.

## Upgrading an existing project

1. `git -C <toolkit> pull`
2. `<toolkit>/bin/sync-project.sh <project-root>` (add `--dry-run` to preview). It refreshes unedited `bin/` and `tests/e2e/` copies. `--upgrade-bin <script|all>` overwrites a locally modified script after backing it up; it still runs a full sync. *(If merged by release:)* `--only-bin` installs just the named scripts.
3. Get the smaller packs. Sync refreshes untouched agent stubs only. A completed stub prints `Kept` and is not changed. For each one:
   - run `sync-project.sh <project-root> --diff-completed` to see how it diverged;
   - copy the block from `<!-- ROUTING:BEGIN agent:<role> -->` to `<!-- ROUTING:END -->` out of `<toolkit>/agents/<role>-agent.md` into `.claude/agents/<role>-agent.md` (it has no placeholders).

   Until you do, that agent keeps its old, larger reading list.
4. Answer SEC014's question (which roles are external), then re-baseline lint once, as the sync NOTE says.
5. Check your journeys: `oqlScalar` in `tests/e2e/helpers.js` now returns the first SELECT alias.

## Known limitations

- Bug lookup is untested on the macOS system awk (BWK 20200816).
- Git Bash runs are owed for #379, #384 and #395.
- The behaviour A/B uses one model and 5 reps per arm.
- `render-routing.sh --check` does not count agent-stub routing-table words, so per-role totals leave them out.
- On one field model the `--on-copy` copy step took 87–134 s; the Ctrl-C recovery path has not been field-run.

## Thanks

To the contributors credited in this release's CHANGELOG lines: **MendixMau** (maintainer), **AlvinnYeo**, **jopterhorst** and **joshuamoesa**, and to the independent reviewers.

## How to contribute

`CONTRIBUTING.md` has three lanes:

1. **Inbox:** drop a file in `contrib/inbox/`. No quality bar; triage promotes it.
2. **Harvest:** run `<toolkit>/bin/harvest-learnings.sh <project-root>` at wrap-up to draft inbox files from your bug logs and local patches.
3. **Direct PR:** held to the full field-proof bar, with the Impact block filled in.
