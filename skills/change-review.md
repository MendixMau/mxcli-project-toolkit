# Change review — an agent reviews a Mendix branch, a person looks only where it matters

**Applies to:** any mxcli project with git; a CR, round, worktree or MR that changes an app that
already has a baseline someone relies on (`existing-app-change.md`, `change-intake.md`, every
round after the first accepted build). Not for the greenfield build: there is no base to review
against yet, `module-review.md` is the pass there.
**Purpose:** turn "Claude says done" into a verdict a person can trust in minutes, **without
slowing the build.** A model diff alone says what changed, not whether it is right; an agent
review against `review-checklists.md` reads it for you, and a person looks only where an agent
cannot judge. The review reads what the build already produced. It never asks for more testing.
**Source:** cc-agent-harness (Emre Özhan Yigitbasi), whose CI review run this generalises; the
human routes come from platform teams reviewing agent-built Mendix MRs on GitLab.

## Cost rules — read these first

- **No new test runs.** The evidence is what the build loop already made: the gate and the tests
  `affected-tests.sh` says the change owes. A review never requests the full suite or reruns
  anything "to be safe"; that is the loop `affected-tests.sh` exists to stop.
- **Off the critical path.** Start `--run` in the background and move on to the next CR. Only a
  **blocker** (security, data loss, broken flow) pulls the work back. Majors and below go on the
  findings list for the next round.
- **Scaled by size.** S: no review. M: one agent run. L, or anything touching access,
  integrations or data: an agent run, and the change is flagged for the human pass.
- **Not a gate.** A CR's status never waits on a review file or a person.

Field cost: one run on a Mendix 11.15 app, 8 commits, 5 changed units: 234 s, 24 turns, $0.82.

## The two reviews

| | Agent review | Human pass |
|---|---|---|
| Who | a fresh, read-only Claude session: `bin/review-branch.sh --run` | a person |
| When | every M and L change, in the background | optional, once per push to a test/UAT environment, over everything since the last push |
| Reads | the MDL diff (both sides), the evidence already there, `review-checklists.md`, the company brain's routing table when wired | the agent verdicts, then only: access and roles, integrations, data changes, a click through the changed pages as a business user |
| Outcome | `REVIEW.md` with a verdict | findings become new CRs; only a security or data-loss finding stops the push to production |

Ways to see the diff for the human pass:
- Studio Pro: check out the branch, `git reset --soft <merge-base>`, the Changes pane shows the
  whole change; `git reset --soft <branch-head>` afterwards.
- Text: `bin/review-branch.sh --base <last-pushed-tag>` (pack only, seconds): `model-diff.mdl` is
  `mxcli diff-local` over everything since that push.
- Per commit: Studio Pro History lists each commit's changed documents when commits carry the
  `mx_metadata` note (`mxcli git commit`, or the toolkit's commit hooks; `platform-link.md`).

## Run it

    bin/review-branch.sh                         # pack only, seconds: base = origin default branch
    bin/review-branch.sh --run &                 # agent review in the background, verdict in REVIEW.md
    bin/review-branch.sh --run --focus "access rules on the export flow"
    bin/review-branch.sh --check-review docs/review/<id>/REVIEW.md   # format check only

The pack lands in `docs/review/<branch>-<head>/`: `PACK.md` (commits, counts, evidence found,
standard), `model-diff.mdl` (full), `model-diff.lean.mdl` (layout-only `@position`/`@curve`
lines dropped, what the agent reads first), `other.diff` (non-model files), `PROMPT.md`, and
with `--run` `REVIEW.md`. Exit: `0` approve or comments · `3` changes · `1` no valid review ·
`2` usage. `CLAUDE_BIN` names a launcher wrapper when plain `claude` is not the one to use.

## The review file

    VERDICT: approve | comments | changes
    ## Summary          at most 5 lines
    ## Findings         1. **blocker|major|minor|nit** title — `Module.Document` — what, why, fix (C1, S1, …)
    ## Evidence         what the build already proved, with denominators; what is not there
    ## Standard applied the checklist sections and brain rows that fired
    ## Not checked      what could not be verified here and why

`approve`: nothing above minor. `comments`: minor and nits only. `changes`: a blocker or major.
Evidence that is not there is **reported**, never a reason on its own for `changes` and never a
request to run more tests; the person deciding the push reads it.

## Where it lands

- **CR flow.** Cite the `REVIEW.md` in the CR's *Closed-by* cell next to its tests when there is
  one. A blocker sends the CR back to `applied`; anything else is listed, not waited on.
- **Worktrees.** `mx-wt review` writes the local PR; the agent's verdict sits beside it when the
  human sets `Decision: merge`.
- **MRs.** Paste `REVIEW.md` as the MR's first note; the human approval stays the MR approval.
- **Pushes to test/UAT.** The optional human pass reads the verdicts since the last push, and
  the pack from `--base <last-pushed-tag>`.

## Completion criteria

- `REVIEW.md` passes `--check-review` (verdict line, all five sections).
- Every finding names a checklist section; 0 open blockers.
- The *Evidence* section states its denominators ("affected tests 3/3"); "not run" is legal,
  silence is not.
