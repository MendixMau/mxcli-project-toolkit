# Reading the verdict

One page: what the toolkit prints at the end of a run, what each word means, and what you do next. The rules
themselves live in [steps/gate.md](steps/gate.md) and [steps/journeys.md](steps/journeys.md); this page only routes.

## 1. Where to look, in this order

| file | what it tells you |
|---|---|
| the pipeline log (`upgrade-pipeline.sh`) | one line per step: `done`, `skipped (done <time>)`, or `STOP <step>: needs judgment (exit N)`, codes in section 4 |
| `$WORK/PROPOSAL.md` | what the toolkit will do, what you must decide, what needs a person anyway; signed before anything changes (unattended run: the gate summary says `proposal not signed`) |
| `$WORK/NEEDS-JUDGMENT.md` | when the pipeline stopped, the exact items a person must decide, each with the file to write the decision in |
| `$WORK/gate-summary.md` (the pipeline runs the gate with `GATE_DIR=$WORK`) | one row per rung (build, identity, constants, data, logs, smoke, journeys, screens, API) and the overall verdict |
| `$WORK/e2e-<label>/summary.json` and the `journeys:` lines in the log | per journey: verdict, failing step, screenshot, and `shown_if` |

## 2. The overall verdict

| verdict | exit | report says | means | you do |
|---|---|---|---|---|
| `PASS` | 0 | verified | every required rung is PASS or PASS* | ship; read every PASS* reason once |
| `PASS (except Teamcenter: N items)` / `PASS (on stand-in APIs: ...)` | 4 | verified on stand-in, real system pending | green, except for named back-end systems that were not reachable, or that a stand-in answered | test those items against the real system before go-live |
| `FAIL` | 1 | REGRESSION to fix, or needs a decision | at least one rung found a real difference between the old and the new app | open that rung's evidence and fix the upgrade, not the instrument |
| `INVALID` / `NOT RUN` | 2 or 3 | not measured yet | an instrument could not measure: missing input, unseeded data, a journey failing on the OLD app without evidence | fix the measurement; INVALID is never a pass and never a fail of the app |

In the report a `PASS*` rung reads "verified with accepted differences". A `FAIL` rung reads `REGRESSION to fix` when its own
output has any REGRESSION, FAIL, START_FAILED, NEW_ERROR or GUID_CHANGED count above zero, or when the gate cannot tell;
it reads `needs a decision` only when every open line is a REVIEW (an accept file closes those). An `INVALID` rung reads
`needs a decision` when a human item is open (release rows, widgets not rendered), otherwise `not measured yet`. The word
REGRESSION is never softened and is always listed first.

`PASS*` means PASS with a written, tool-checked reason: an accepted screenshot difference, an evidenced baseline
defect, or an allow-listed constant. Each reason is in the rung's evidence file.

## 2b. The progress line

```
Progress: 6 of 11 checks closed (54%). 1 with REGRESSIONS to fix, 3 need a decision, 0 not measured yet, owner sign-off pending.
```

It is printed right after the `Overall:` line (which keeps its form and exit code) and at the end of the run.
- **A check** is one gate rung in scope (every required rung, plus an optional rung that was configured) plus one fixed
  item, **owner sign-off**. The rung list is fixed by the gate, so the denominator cannot grow by adding easy journeys or
  shrink by dropping a hard one. Item counts (journeys 99/101, pairs, release rows) are the second level, per rung;
  action coverage stays a separate number.
- **Closed** is PASS or PASS* only. Everything else is in the denominator and never in the numerator. A written decision
  (`DECISIONS.md`) never closes a check; only the gate measuring PASS/PASS* again does.
- Sign-off is never closed by a machine, so the gate alone never prints 100%. Floor division, the fraction is always shown.
- With a REGRESSION open the overall stays FAIL (exit 1) and the line names the regression count before anything else.

## 3. The journeys line

```
actions 280 found · 146 generated (...) · 101 pass on baseline (45 defect) · 99 pass on new · 2 regression · coverage 101/280 (36%)
```

- **regression** is what matters: it PASSed on the old app and fails on the new one. Every regression is FAIL.
- **defect** fails on the OLD app too, so it says nothing about the upgrade. Each defect needs a line of evidence
  (FIXTURE, OLD-APP or FLAKY, [steps/journeys.md](steps/journeys.md) "Coverage and honesty"). Without one it is INVALID.
- **defect over 30% of generated** means `instrument not measuring`, and evidence does not lift it. When most journeys
  fail on the old app, the problem is the fixture or the generator, not the upgrade. Fix those first.
- **`[shown only if ...]`** after a FAIL names the condition the app sets for that button, for example
  `container1: $Workflow/System.Workflow_ParentWorkflow != empty`. If the test data never reaches that state, the
  FAIL is an OLD-APP defect: cite the baseline screenshot as evidence, or seed the state and run again.

## 4. When the pipeline stops

| exit | means | read |
|---|---|---|
| 0 | gate PASS, nothing left for a person | `gate-summary.md` |
| 2 / 3 / 4 | usage error / missing tool (run `bin/cloud/setup.sh`) / a fixed step failed | the log the message names |
| 10 | mx check, mxbuild or quick start errors after the update | [steps/repair.md](steps/repair.md) |
| 11 | journeys INVALID or FAIL on the old or the new app: fix the journey or the fixture, or give evidence | [steps/journeys.md](steps/journeys.md) |
| 12 | REVIEW, FAIL or INVALID items that need a person to compare | [steps/gate.md](steps/gate.md) |
| 13 | a module plan or a data-bearing finding needs a decision | [steps/upgrade.md](steps/upgrade.md) |
| 14 | the upgrade proposal awaits sign-off (or a plan input changed after it was signed); nothing in the app has changed yet | [steps/propose.md](steps/propose.md) |
| 15 | the owner paused the run on purpose; `NEEDS-JUDGMENT.md` has the resume command | [steps/propose.md](steps/propose.md) |

Fix or decide, then start the pipeline again with `--from <step>`; finished steps are skipped.

### The judgments a person makes

| item in NEEDS-JUDGMENT.md | decide | write it in |
|---|---|---|
| SCREEN REVIEW | the old and new screenshots differ: is it the expected look of the new version (styling, widget update) or a broken page? | `shot-accept-<rung>.txt`, one `pattern # reason` line, then run the step again with `--rejudge` |
| EFFECT REVIEW | a step changed different rows on old and new: is it expected? | `effect-accept-<rung>.txt` |
| BASELINE DEFECT without evidence | why does this fail on the OLD app? | `baseline-evidence.txt` |
| the upgrade proposal (`PROPOSAL.md`) | section 3 items: which option; section 6: sign it or pause | section 3 answers in `DECISIONS.md` (P-n lines), section 6 in `PROPOSAL.md` by a person |
| stuck item (a module, widget or Java action that cannot be upgraded as it is) | which option, asked in chat ([steps/decide.md](steps/decide.md)) | `DECISIONS.md` |
| constants, identity REVIEW | is the reset or the removal intended? | `const-allow.txt` / the idcheck accept list |

A reason is a sentence a reviewer can check. "ok" is not a reason. A screenshot of a progress bar or an empty page
cannot be accepted: take it again.

## 5. What is never a verdict

Coverage below 100% is reported, not judged. Time and cost lines (`cost_ledger.py`) are measurement only. A rung
marked `earlier run` in `gate-summary.md` was not re-run this time.

## 6. The completion grade

The verdict word says whether the instruments found a difference. The grade says how much of the run is done. It is printed
next to the verdict (`GRADE 89% (8 of 9 required rungs done): ... | verdict INVALID`), stamped into `gate-summary.md` by
`gate.sh`, and recorded per run in [runs/HISTORY.md](runs/HISTORY.md) by `bin/grade.py` ([steps/report.md](steps/report.md)).

**Required rungs: 9.** build, idcheck, const, data, logdiff, smoke, journeys, screens, release. `widgets` is a 10th when
the gate ran it. `rest` and `apis` are optional: listed, never graded.

Every required rung lands in exactly one bucket:

| bucket | the rung said | means | counts as done |
|---|---|---|---|
| proven | PASS | the instrument judged and found no difference | yes |
| accepted | PASS* | the same, with a written reason a reviewer can check | yes |
| waiting on a person | INVALID or NOT RUN because of a human input | guest or sign-out process to confirm, release rows open, screens to look at, a rung to run | no |
| not testable here | INVALID, NOT RUN or EXCEPT that needs customer systems, keys or a licence | the check needs something this environment does not have | no |
| open regression | FAIL | a real difference, or a failing rung | no, never |

`grade = (proven + accepted) / required rungs`, as a percent with the bucket counts. Examples: 8 of 9 is 89%, 7 of 9 is 78%.
A FAIL is never counted as done. A 100% grade with verdict PASS and a 100% grade with verdict `PASS (except ...)` differ
in the verdict word, so always read both.

**What puts an INVALID in which bucket.** The rung's one-line reason is searched for licence, key, credential, NOT CHECKED,
excluded, AWS, VPN: those are "not testable here". Everything else is "waiting on a person". The owner is `toolkit` when the
reason says the instrument did not measure (timed out, instrument not measuring); otherwise `person` or `customer`.

**What the gate did not see.** `grade-notes.tsv` next to the summary (`rung, bucket, owner, text`, tab separated) records a
finding made by hand, for example a crash in a vendor widget after a clean gate. A note can lower a rung (PASS to waiting,
not testable or open) or move an INVALID between waiting and not testable. It can never raise a rung and never turn a FAIL
into anything else. The Material Cockpit run is the example: the gate read PASS (100%), the 3D Viewer crash on 11.12.6 needs
a licensed 7.1.2, so the run reads 89% with that item open (`runs/notes/MC.tsv`).

**Open and pending work.** Below the grade line `grade.py` lists each rung that is not done with an owner: `person`,
`customer` or `toolkit`.
