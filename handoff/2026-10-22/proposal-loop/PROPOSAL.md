# Propose before build: alignment (#507, with #506 and #508)

Research only. Toolkit read at origin/master `96e3553`. Nothing in the repo was changed.

## Outcome first

- **Recommendation:** ship #507 as one opt-in, experimental, lead-only skill. A project turns it on
  with `Proposals: batch` in `PROJECT.md`.
  - **What it changes:** it draws a visible change into the screen's **existing wireframe** and
    shows it in the **existing** `design/prototype.html`.
  - **How it asks:** the proposal rides the question `change-intake.md` already asks. The one
    exception is a user-typed visible S change, which today gets no question at all.
  - **Cost:** 0 new HTML files, 0 always-loaded words, 0 mxcli/mxbuild calls.
- **First step:** run it by hand on one real project tomorrow, then the 12-rep trial in `kit/`.
- **#506:** comes in as a three-row "show it where the user is" table inside the skill. Its sentinel
  bug should be fixed now, separately.
- **#508 stays parked.** The hand trial carries one question that decides whether it is unparked.

## Why

| Idea | The problem today (evidence) | If we don't |
|---|---|---|
| #507 propose → confirm → build → verify | The user approves wireframes **once**, at Stage 3. After that, nobody is asked about a change before it is built:<br>• `change-intake.md`: an S change the user typed gets "No question. Reply with a one-line receipt".<br>• A drift-sync re-render is never shown to anyone (runbook §3b).<br>• A greenfield wireframe is drawn to clear `ui-preflight-pages.md`'s STOP, and nobody approves it.<br>#232: the LOOK never happened during the build, the owed list reached 106, and the user found the UX defects by hand. #291: defects designed in, then built faithfully. | The user's first view of a change is the running app. Rework comes after the build, and the fidelity score keeps measuring against a design nobody re-approved. |
| #506 show it where the user is | `init-project.sh` L699–714 writes `.guide-shown` even when neither `open` nor `xdg-open` exists. Observed in a cloud session; Git Bash has neither binary either. `build-plan-status.sh --open` works only on macOS. `learned-skill-ux-audit.md:290` runs a bare `open`. | Cloud and Windows users never see the guide, and a proposal page has no defined way to reach them. |
| #508 model change view | Studio Pro already shows the model. The value would be a picture of *what changed* in non-UI work. Maintainer decision on 2026-10-21: park it until the #507 trial shows the picture is wanted. | Nothing breaks. Non-UI changes keep the BRD's as-is/to-be text. |

## How: the loop in 6 steps

| # | Step | Uses (exists today) | Asks? |
|---|---|---|---|
| 1 | **Gate on the switch.** Read `Proposals: off \| batch \| each`. Absent means off. | The `Context packs:` / `Lint gate:` pattern | — |
| 2 | **Classify** the CR: nit, non-visible, visible S, visible M/L, Stage-3-approved first build, greenfield, or more than 5 screens. | change-intake class/size; drift-sync "visually observable" | Silent for nits, non-visible changes and first builds |
| 3 | **Propose in place.** Edit `design/wireframes/<Screen>.html`: `data-changed` outlines plus one `wf-proposal` block. Re-run `assemble-prototype.js`. "Before" is the last LOOK screenshot or the wireframe at HEAD. | `wf-` is already annotation: `page-fidelity.js` drops any `div.wf-*` (L214–227), and the prototype hides it behind "Show bindings" | — |
| 4 | **Show it where the user is.**<br>• `Display: artifact` set by the user: publish a private Artifact.<br>• Local desktop with an opener: open the page once.<br>• Anything else: give the path and route. | #506 detection, reduced to `CLAUDE_CODE_REMOTE`, the opener and `$DISPLAY` | No question about display. The user types the line. |
| 5 | **Ask once, then stop.**<br>• Approve / Change / Drop / Something else.<br>• `batch`: one question per round, before the first page script that builds any of the changes.<br>• M/L: rides change-intake's existing question.<br>• Greenfield: rides the module-start coverage-checklist confirmation. | `interview-protocol.md` §3 | **At most 1 per CR or round** |
| 6 | **Record, build, verify.**<br>• The CR status *is* the status strip: `refined` → `agreed` → `applied` → `proven`.<br>• Approval is pinned as `<Screen>.html@sha`.<br>• The proof is the ui-loop LOOK and the `page-fidelity.js` row against the approved wireframe.<br>• Once proven, the block is removed. | change-intake statuses; the dashboard's existing `Change log:` row; ui-loop; PAGE-FIDELITY.tsv | — |

**Pages updated, not created.**

| Page | Status | Role in the loop |
|---|---|---|
| `design/wireframes/<Screen>.html` | Exists | Carries the "after" |
| `design/prototype.html` | Exists, regenerated | The one page the user opens |
| `PROJECT.md` Change log | Exists | The approval record |
| `index.html` dashboard | Exists | Already shows the `Change log:` line |
| Module-review `design/ui-reviews/ui-review-<date>.html` | Exists, one per pass | Already holds approved-vs-built through its `vs wireframe` divergences |

`design/proposals/` and any `proposal.html` are **not** created. The #507 issue text proposed
both; this design drops them.

**#508:** stays parked. A non-visible change gets no picture and no question. The hand trial
asks one thing: did you want a picture for the non-visible change? If yes on real changes, build
the narrow change view.

## Where

| File | Change | Always loaded? | A/B needed |
|---|---|---|---|
| `skills/propose-before-build.md` (new) | The draft skill (`draft-skill.md`, about 710 words) | No: on demand, lead only | No while experimental; yes to promote |
| `bin/lib/skill-routing.tsv` | One row: `lead`, stages `3,5`, `experimental`, `design` | No: experimental rows render into no stub and no baseline view | No. Run `render-routing.sh --check` |
| README.md / ROUTING.md | Re-rendered by the script | No | No |
| `skills/change-intake-detail.md` (ondemand) | One line under Size → ask: "`Proposals:` on → propose-before-build" | No | No |
| `skills/design-artifacts.md` (ondemand) | One line: a wireframe edited after Stage 3 approval → the skill | No | No |
| `skills/existing-app-change.md` (ondemand) | Stage 3 row: "as-is = last screenshot or the Path D describe; no new call" | No | No |
| The project's `PROJECT.md` | `Proposals: batch  (skills/propose-before-build.md)`. **The switch names its skill**, so retrieval needs no baseline text. | Read at session start | — |
| `CHANGELOG.md` | One line | No | No |
| **Separate PR, not gated by this trial (#506 bug):** `bin/init-project.sh` L699–714, `skills/learned-skill-ux-audit.md:290` | • Write the sentinel only when something was opened<br>• Add `cmd //c start ""` for Git Bash<br>• No `open` on Linux | No | No; a field-proof under CLAUDE.md "Shipping an instrument" |

Deliberately **not** touched in v1 (all baseline, so each would need an A/B):

- `change-intake.md`
- `conversion-runbook.md`
- `interview-protocol.md`
- `ui-preflight-pages.md`
- every agent stub

## Cost

| Item | Value | Basis |
|---|---|---|
| Always-loaded words added | **0** | Experimental, lead-only row; the switch line is in the project |
| Per session, first visible change | About 1.1k tokens (reading the skill once) | 4,460 characters ÷ 4 |
| Per visible change | About 3–6k tokens: read the wireframe (2–4k), edit it (0.5–1.5k), question turn (about 0.4k) | Estimate. The dry-run question turn was 240 words, about 410 tokens. **Measure in the trial.** |
| Per nit or non-visible change | **About 0 added** (change-intake's receipt is unchanged) | Dry run: 0 questions |
| New HTML files | **0 per change, 0 per project** | The wireframe and prototype are updated |
| mxcli / mxbuild calls added | **0** | "Before" is an existing screenshot or the wireframe at HEAD. `assemble-prototype.js` already runs after every wireframe edit (design-artifacts Step 3). |
| Questions added | **+1 only for a user-typed visible S change**. M/L and greenfield ride existing questions. | §How, step 5 |

## Options

| | Option | What ships | Risk | A/B |
|---|---|---|---|---|
| 1 | **Hand trial only** | Nothing. The draft skill is used by hand on one project. | None | No |
| 2 | **Experimental skill, switch-routed** *(recommended after a "go" on 1)* | The skill, its routing row, 3 one-line hooks in on-demand skills, the `Proposals:` line. The #506 bug fix ships separately. | Retrieval: a lead may not open the skill. The trial measures this. | No, but run `kit/` first (12 reps) |
| 3 | **Promoted, with instruments** | Option 2, plus:<br>• a change-intake.md line;<br>• a `status.sh` watch "proposals waiting: CR-12";<br>• a progress-report "Proposed changes" card from `refined` visual CR rows;<br>• a gate-check WARN for a built page whose wireframe still says `data-status="proposed"`;<br>• #506 `show.sh`;<br>• the #508 change view. | Baseline text, plus 3 instruments to field-prove | Yes: full suite, 50 reps, plus the field-proof bar |

**Recommendation:** run Option 1 tomorrow. On a "go", ship Option 2. Consider Option 3 only after
two projects have run Option 2.

## Test plan before any build

**Hand steps, on one real project you own (about 45 minutes):**

1. **Turn it on.** In `PROJECT.md`, add `Proposals: batch  (<path-to>/draft-skill.md)`. If you work
   in a cloud session and accept a private publish, also add `Display: artifact`.
2. **Type four changes, one at a time, as you normally would:**
   - (a) a visible S, such as a new button on a built page;
   - (b) a visible M: one field on two screens;
   - (c) a nit: a caption;
   - (d) a non-visible change: a log line or a validation rule.
3. **Answer each proposal honestly.** Use "Change" once if anything is off.
4. **After each change, note the row below.** Use `git status --porcelain` for files, and the token
   counter (`/cost` or the progress report's token section).
5. **Let one approved change build,** then compare the LOOK and fidelity row against the approved
   wireframe.

| Change | Questions | Lead opened the skill unprompted? | Tokens | Time to approval | You changed the proposal? | Files new / updated | Built vs approved drift | Wanted a picture (non-UI)? |
|---|---|---|---|---|---|---|---|---|
| a | | | | | | | | — |
| b | | | | | | | | — |
| c | | — | | — | — | | — | — |
| d | | — | | — | — | | — | |

**Go / no-go.**

| Go when all of these hold | No-go when any of these happens |
|---|---|
| ≤ 1 question on each of (a) and (b) | Any question on (c) or (d) |
| 0 questions on (c) and (d) | Any new HTML file or `proposals/` folder |
| 0 new HTML files | MDL drafted before your "yes" |
| ≤ 8k extra tokens per visible change | Neither proposal was changed **and** no drift was found. Value unproven: keep it parked. |
| You would keep it on | |
| The skill was opened unprompted at least once. If not, Option 2 needs the `status.sh` pointer from Option 3. | |

Then run `kit/` with 12 fresh agents (`kit/HOW-TO-RUN.md`). Go needs rows 1–4 there.

**#508:** unpark only if you answered "yes" in the last column.

**Dry run (self-run sanity check, not the trial).** I followed the draft skill on each task once.

| Run | Questions | New / updated HTML | Waited | MDL | Words | Verdict |
|---|---|---|---|---|---|---|
| change | 1 | 0 / 1 | yes | 0 | 240 | PASS |
| nit | 0 | 0 / 1 | no | 1 | 227 | PASS |

Two hand-written negative controls both scored FAIL, which shows the scorer catches each fault:

- The change control created a proposal folder, published without the `Display:` line, asked 2
  questions and drafted MDL.
- The nit control asked "Shall I go ahead?".

Rows: `dryrun/dryrun-scores.tsv`.

## Open questions: the three to decide tomorrow

1. **Should a user-typed visible S change be asked at all?** This is the one place the loop adds a
   question. It overrides change-intake's "S, typed by the user: no question" for projects that
   opt in.
   - Related: the switch values. Keep `off | batch | each`, or just `off | on`, with `on` meaning
     `batch`?
2. **Display consent for #506: a user-typed `Display: artifact` line (no question ever), or asked
   once at CAC-1?** I recommend the typed line, so the loop adds no question. The answer also
   decides how #506's `show.sh` consumes it.
3. **Built pages: revive the wireframe?** Today change-intake says a built page's visual change
   gets a before/after screenshot pair, and the wireframe a "BUILT" stamp instead of upkeep. Under
   `Proposals:`, the wireframe becomes the "after" again. Accept that upkeep while opted in?

Smaller questions, with a default if you don't decide:

| Question | Default |
|---|---|
| Ship the #506 sentinel fix now, separately? | Yes |
| Under `Interview mode: auto`: queue proposals as a Ruling, or block page scripts for those screens? | Ruling |
| A v2 gate-check WARN for a built page with a still-`proposed` wireframe? | Later, Option 3 |
| Batch timing: ask before the first page script, or at the module gate? | Before the first page script |

---

## Trial results (2026-10-21, 12 fresh sonnet reps, 3 per task per arm)

A = current toolkit pack. B = same pack + draft skill + `Proposals: batch`.

| | A change | B change | A nit | B nit |
|---|---|---|---|---|
| Verdict PASS | 0/3 | **3/3** | 1/3 | **3/3** (scorer says 2/3, see note) |
| Questions to user | 0, 0, 0 | 1, 1, 1 | 0, 1, 0 | 0, 0, 0 |
| Proposal shown before build | 0/3 | 3/3 | — | — |
| Stopped and waited | 0/3 | 3/3 | — | — |
| New HTML files | 0 | 0 | 1 (one rep) | 0 |
| Existing pages updated | 2 each | 2 each | 2 each | 1 each |
| Published without consent | 0 | 0 | 0 | 0 |
| Answer length (words) | 885–929 | 530–662 | 850–1500 | 611–658 |
| Tokens per rep | 151–155k | 146–148k | 148–160k | 148–152k |

- **Change task:** without the skill the agent never showed or asked; it just planned the build. With it, all 3 reps proposed once, updated the existing wireframe + prototype, and stopped.
- **Nit task:** with the skill all 3 stayed silent. The scorer counted one B rep as asking, but its chat says "no question for you" — a scorer false positive (to fix in `score-proposal.sh`). Without the skill, one A rep asked and one created a new HTML file.
- **Cost:** answers were ~35% shorter with the skill; tokens per rep the same (pack reading dominates; the skill adds ~720 words to the pack only when routed).
- **Caveat:** the reps inherited the orchestrating session's project `CLAUDE.md`, and 8 of 12 named that project's model file (`hostleak`), spread across both arms. Rerun from a clean directory before treating numbers as final.
