# Behaviour suite

A standing A/B for agent-read text: three arms (M = base ref, T = candidate ref or an ablation,
N = no pack), two drafting tasks and five retrieval probes for the mdl agent at Stage 5, scored
by `score.sh`. How and when to run it, and the decision rule: `RUNBOOK.md`.

| File | What |
|---|---|
| `build-packs.sh` | builds `work/pack-<arm>.txt` from any ref; `--without` for an ablation |
| `AGENT-PROMPT.txt` | the one prompt every rep gets |
| `tasks/` | `page.md`, `mf.md` (each with a planted STOP-row request) and five `probe-*.md` |
| `score.sh` | mechanical scorer, one TSV row per rep |
| `results/` | committed field runs |
| `fixtures/` | four real agent outputs, golden input for `tests/wave2/test-behaviour-score.sh` |

## Field runs

Each results file's `#` header carries its run's refs, rep counts, partial reads, tool-call and
token ranges, and findings.

- **2026-10-15, stub diet** (#369/#378/#380): `results/2026-10-15-stub-diet.tsv`, 42 reps.
- **2026-10-15, first N-arm run**: `results/2026-10-15-no-pack.tsv`, 10 reps. The page trap was
  refused 0/5 without a pack against 5/5 with either pack; `mf` passed `mxcli check` 1/5 against
  5/5. Caveat: every arm, N included, also inherited the host session's project CLAUDE.md (a generic mxcli/MDL guide), so N measures 'no toolkit rules', not 'no guidance'.

## Future work

In this kit `tool_calls` mostly measures reading the pack, because the agent cannot run mxcli.
It becomes meaningful as a count of DESCRIBE and exec calls in a variant where the agent drives
a live mxcli against a throwaway model.
