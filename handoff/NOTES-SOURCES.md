# Sources for RELEASE-NOTES-1.0.md

All paths are on `origin/master` at `1512b09` unless a PR or issue is named. "CL L<n>" means a line of `CHANGELOG.md` at that commit (all under `## Unreleased`). PRs #355, #364, #368, #369, #370, #373, #377, #378 and #380 show as *closed, not merged* on GitHub. They landed through the night batch #385 (`868b3cb`), the same pattern `docs/releases/v1.0.md` notes for #329.

## Header

| Claim | Source |
|---|---|
| Four entry modes plus à-la-carte, gated stages, skills on demand | `README.md` "What it is", "How it works", "Ways to use it"; `skills/skills-over-scripts.md` routing row |
| First named milestone; GitHub Release on the train tag; the `vYYYY.MM.DD` tag comes from `bin/cut-release.sh` | `docs/RELEASE-PROCESS.md` §8; `bin/cut-release.sh` header; `docs/releases/v1.0.md` ("first release-train tag published to GitHub") |

## Context pack diet

| Number | Source |
|---|---|
| mdl Stage 5: 56,236 words before | CL L43 (#378: "56,236 → 43,599"); PR #369/#378/#380 bodies |
| mdl Stage 5: 30,185 words after | `render-routing.sh --check` output quoted in PR #393 (base side), #389 Impact row and #391 Context-cost row; also the example in `docs/RELEASE-PROCESS.md` L122. **Note:** #393's head output, which is current master, gives **30,160** (−25 words; agent stubs are excluded from that count). |
| −46% | Computed: (56,236 − 30,185) / 56,236 = 46.3% |
| Baseline 75,028 → 73,475 of 80,000 | 75,028: CL L37, L39, L43. 73,475: CL L25 (#393, "73,522 → 73,475") |
| Planted trap refused 10/10 both arms | `tests/behaviour/results/2026-10-15-stub-diet.tsv` (`planted=1` on all 10 M and 10 T drafts); CL L42/L43 |
| Page check rejected 3/5 old vs 2/5 new | same TSV: M-page `check=PARSE` r2, r4, r5; T-page `check=PARSE` r2, r3; CL L42/L43 ("page 2/5 vs 3/5") |
| Probes 15/15 | same TSV: 15 T-probe rows, all `probe_first=1`. The old arm ran one rep per probe, so the 15/15 is for the trimmed pack only. |
| 5 reps × 2 tasks + 5 probes × 3 reps, one model | CL L42/L43 ("sonnet"); TSV header ("One model fixed for every rep"); `tests/behaviour/RUNBOOK.md` per CL L23 |
| 4,822-line pack; 3 of 5 probe agents stopped part way | CL L23; TSV header and its 3 `-partial` rows; PR #385 body ("3 of 5 M-arm probe agents skipped most of the 4,822-line pack") |

## No pack vs pack

| Number | Source |
|---|---|
| Page trap refused 0/5 vs 5/5 | `tests/behaviour/results/2026-10-15-no-pack.tsv` (N-page `planted=0` ×5) against the stub-diet TSV (M and T page `planted=1`); CL L23 |
| Page passes check 0/5 vs 2–3/5 | no-pack TSV: no N-page row has `check=0`. Stub-diet TSV: M has 2 rows with `check=0`, T has 3. |
| Microflow passes check 1/5 vs 5/5 | no-pack TSV: N-mf-r3 is the only `check=0`. Stub-diet TSV: all 10 M/T mf rows have `check=0`. CL L23 |
| Preflight followed 0/5 vs 5/5 | `mfpre=0` on every N-mf row; `mfpre=1` on every M/T mf row |
| Commit-in-loop 2/5 vs 0/5 | `cinloop=1` on N-mf-r1 and N-mf-r3; `cinloop=0` on every M/T row |
| Caveat: generic project guide inherited | no-pack TSV header; CL L23 |

## Bug lookup (#395, open)

| Number | Source |
|---|---|
| Top-3: 9% → 94% dev (40 = 35 positive + 5 no-match) | PR #395 body, results table |
| Top-3: 0% → 100% held-out (15 = 12 + 3) | same |
| Confident-wrong 0% held-out | same. Dev confident-wrong is **8%**; this is not stated in the notes. |
| ~45 ms vs ~950 ms | PR #395 Runtime row (45 ms is mawk; gawk 79 ms, BWK about 300 ms) |
| Embeddings: 91% top-3, 20% confident-wrong, cannot say "no match" | PR #395 results table, arm C |
| macOS awk BWK 20200816 untested | PR #395 "awk variants" paragraph |

## Other numbers and claims

| Claim | Source |
|---|---|
| Impact block: five rows; "none"/"NOT RUN" legal, blank not | CL L24; PR #388 |
| Behaviour suite arms M/T/N, ablation, read_all/tool_calls/tokens, partial reads kept | CL L23; PR #389 |
| Independent review before merge | CL L57; `docs/releases/v1.0.md` cites #316 |
| exec lock, `--commit-first`, restart verdict | CL L95 (#304) |
| Audit found 14 duplicated rules | PR #392 (pairs 1–5, 10, 14) + PR #393 (pairs 6–9, 11–13) = 14 pairs. PR #394 body gives "19 true duplicates in its top 40" for the TF-IDF ranking. #393 is merged; **#392 is open**. |
| #391: nine triggers rewritten | PR #391 (open). Seven phrasings "missed with every method", two tightened from rank 2 to 1. Top-3: 46 → 55 of 55 on the full trigger, 39 → 47 on stub text; in-sample. |
| App-facts: 20 of 2,000 units at 1% changed | CL L40 (`tests/wave2/bench-app-sweep.sh`) |
| mdl-scan: four STOP-row patterns, warn-only | CL L29 |
| Studio Pro History lists changed documents | CL L45 (#271, commit `36c5a85`) |
| `--on-copy` 10/10 vs 0/10 | PR #384 body, bench table and "The gain" (stub bench) |
| `--recover-promote` safe to re-run | PR #384 commit `1aef3d3` ("idempotent --recover-promote"); issue #390 (no-op run twice) |
| #384 macOS field PASS | issue #390 (a and b PASS; the Ctrl-C half of c NOT RUN). PR #384's own body still says "Field evidence: none… Not run on macOS". |
| Copy step 87–134 s | issue #390, finding 2 |
| #379: 0 vs 13 overlaps (Linux), 0 vs 21 (macOS), 200 rounds | PR #379 Runtime row and Field-runs table; issue #390 `RESULT` lines |
| #379 Git Bash run owed | PR #379 checklist |
| #374 field PASS; repaired a stale hash from an old `--patch` | issue #390, #374 section and finding 7. PR #374's body still says "no field project yet". |
| `--upgrade-bin` runs a full sync | issue #390, finding 1; `bin/sync-project.sh` usage text |
| `--only-bin` | issue #390, finding 1 asks for it. **No PR or branch found.** |
| Completed stubs print `Kept`, with the `--diff-completed` hint; only pure stubs are refreshed | `bin/sync-project.sh` L21–23, L552 |
| ROUTING block in agent templates holds no placeholders | `agents/mdl-agent.md` L32–117 (0 `{{` inside the markers) |
| Stub routing words not counted by `render-routing.sh --check` | PR #393 Context-cost row ("per-role figures exclude the agent stubs") |
| `oqlScalar` returns the first SELECT alias | CL L72 |
| SEC014 question and re-baseline | CL L50; `docs/releases/v1.0.md` Upgrading |
| Journey preflight, APP-DOWN | CL L96 (#302), CL L73 (#310 per `docs/releases/v1.0.md`) |
| Lint rules, BLIND on stock revert | CL L50, L51, L93 (#305, #308, #312) |
| Named controls, three check moments, escaped URI | CL L31 (#368), L32 (#364), L41 (#377) |
| Stage 1 extraction-quality report | CL L69 (#151) |
| Change log for mid-build feedback | CL L94 (#306) |
| Three contribution lanes | `CONTRIBUTING.md` "Three lanes, by friction" |
| Contributors | CHANGELOG credit lines in `## Unreleased`: MendixMau, AlvinnYeo, jopterhorst, joshuamoesa |
