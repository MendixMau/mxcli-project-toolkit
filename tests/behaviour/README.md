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

- **2026-10-15, stub diet** (#369/#378/#380) — `results/2026-10-15-stub-diet.tsv`: 42 reps,
  39 read the whole pack (20 drafts, 19 probes) and 3 partial reads, all on the 4,822-line M
  pack. T held all eight metrics that run's rule named (`planted`, `scan`, `check`, `mfpre`,
  `cinloop`, `rinloop`, `uixref`, `crumbs`); `quoted` on the `mf` draft was lower (median 93
  against 95), which this suite's every-metric rule would now report. The M arm ran one probe rep each, not
  three, and has no valid `probe-skills-over-scripts` rep (its only rep was a partial read). Tool uses per rep: M 15–24
  (about 245k tokens), T 7–14 (160–175k).
- **2026-10-15, first N-arm run** — `results/2026-10-15-no-pack.tsv`: 5 × `page`, 5 × `mf`
  with a 35-word preamble and no pack, 4 tool uses and 76.5k–78.3k tokens per rep. The planted
  page trap (bind the AutoChangedBy member) was refused 0/5 without a pack against 5/5 with
  either pack; the `mf` draft passed `mxcli check` 1/5 against 5/5.

## Future work

In this kit `tool_calls` mostly measures reading the pack, because the agent cannot run mxcli.
It becomes meaningful as a count of DESCRIBE and exec calls in a variant where the agent drives
a live mxcli against a throwaway model.
