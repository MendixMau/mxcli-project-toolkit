# Behaviour suite — runbook

Measures whether a change to agent-read text changes what the mdl agent does. Method:
`process/preflight-skill-baseline-2026-08-31.md` (fresh agents, identical prompt core, only the
context differs, mechanical scoring). Paths below are relative to `tests/behaviour/`.

## When to run

| Trigger | Arms | Reps |
|---|---|---|
| A PR that changes baseline-routed text or an agent stub (`docs/RELEASE-PROCESS.md` §4a, Behaviour row) | M = base, T = PR head | 5 × `page`, 5 × `mf`, 3 × each of the 5 probes, per arm (50 reps) |
| Each release cut | N (no pack), and one ablation per baseline skill under review | N: 5 × `page`, 5 × `mf`. Ablation: M vs T-without-skill, same reps as a PR run |

A full PR run is about 50 agent reps at 2–4 agent-minutes each (most of it reading the pack):
roughly 100–200 agent-minutes, 10–20 minutes wall clock at the orchestrator's agent cap.

## Build the packs

```
bash build-packs.sh M origin/master                         # base
bash build-packs.sh T <pr-head-ref>                         # candidate
bash build-packs.sh T origin/master --without skills/<x>.md # ablation: value of <x>
bash build-packs.sh N                                       # no pack: preamble only
```

Each writes `work/pack-<arm>.txt` (`work/` is ignored by git). A candidate and an ablation both
write `work/pack-T.txt`: build one, run its reps, then build the other. The ref is checked out in a
temporary detached worktree and removed again; the caller's tree is never touched. An ablation
pack keeps the stub and its routing row naming the skill; only the skill's text is gone, which is
the "routed but not read" case the skill would face. M vs ablated T is the skill's value; N vs M
is the whole pack's value over plain reasoning.

## One rep

1. Pick arm `A` and task `K` (`page`, `mf`, or `probe-<name>`; task text is `tasks/<K>.md`).
2. Spawn a **fresh** subagent per rep, never reused, with only Read and Write. **One model fixed
   for every rep of every arm.** Its prompt is `AGENT-PROMPT.txt` with PACK, TASK and OUT replaced
   by absolute paths: `work/pack-A.txt`, `tasks/K.md`, `work/out/A-K-rN.md`.
3. Start the orchestrating session in a directory with no project `CLAUDE.md` in it or above
   it: the subagents inherit it. In the 2026-10-15 stub-diet run, 13 of its 20 M/T drafts named
   the host project's model file, which no pack or task contained (0 of the 10 N drafts did, but
   N inherited the same file); it reached every arm alike, so N measured "no toolkit rules", not
   "no guidance".
4. From the subagent's result take its final reply and its usage line (`tool_uses`,
   `subagent_tokens`), then score:
   ```
   bash score.sh work/out/A-K-rN.md --reply "<final reply>" --tool-calls <tool_uses> --tokens <subagent_tokens> >> work/results.tsv
   ```
   `--reply` sets `read_all`: 1 when the reply equals the pack's `PACK-END:` line (the agent read
   to the end), else 0. The scorer reads arm and task from the file name.

Run reps in parallel, up to the orchestrator's agent cap; interleave arms (M1, T1, M2, T2, …)
so drift in the model service hits both.

## Partial reads

A `read_all=0` row stays in the results file: it is counted and reported, never deleted. It is
left out of the metric comparison, and the rep is run again until each cell has its full count.
Report the partial-read count per arm next to the verdict; more partial reads in T than in M is
itself a regression (the pack got harder to read to the end). On 2026-10-15, 3 of 5 agents given
the 4,822-line M pack in one batch stopped early.

## Decision rule (agree it before running)

Arm T is **no worse than arm M on every scored metric**: compare the median and the count of reps
at the good value. Lower is better for `scan`, `check`, `txtcrumb`, `cinloop`, `rinloop`, `pos`;
higher for the rest. Probes: `probe_first` T ≥ M − 1 per probe across its 3 reps. A loss on any
metric is a finding the PR body reports with the rows; it is not averaged away.

`tool_calls` and `tokens` are reported, not judged: here they mostly measure reading the pack,
since the agent cannot run mxcli.

## Known scorer gaps

- `folder` counts `folder '…'` after the name, not the `Folder: '…'` page property.
- `crumbs` counts link/action buttons whose action is `show page`; `Action: PAGE …` and a
  microflow that shows the page are not counted.
- `check` is `mxcli check` with no project, so it is syntax only, and NA without a binary
  (`$MXCLI`, else `mxcli` on PATH).
- `design-spacing.md` §3 shows the breadcrumb as one text widget; expect `txtcrumb` > 0 in every
  arm that carries it.
