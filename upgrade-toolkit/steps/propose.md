# Propose: sign before anything changes

Use after basewalk and before convert, on every run. Nothing in the app model changes before a person signs.

## Run
`python3 $B/proposal.py --work $W --source <full> --target <full> [--app app/ --original $W/original.mpr]`
The pipeline does this as step `propose` (it first writes `$W/actions.json` and `$W/apimock-inventory.json` from
`original.mpr`). It reads the triage outputs by their real names (header of `bin/proposal.py`); a missing one is listed
under "not measured" in section 5, never skipped.

## Sections of `$W/PROPOSAL.md`
1 summary, 2 done by the toolkit (module updates, predicted repairs with repair-row ids), 3 needs your decision,
4 needs a person anyway, 5 human effort, 6 sign-off. A kept module, a stranded module, a RED local edit, Java or theme
edits and a widget with no successor are section 3, never section 2.

## Ask, then stop
Ask one question per section-3 item in chat (options and evidence are in the item; same rules as
[decide.md](decide.md)), write each answer as a `P-n` line in `$W/DECISIONS.md` (decide.md format), then end the turn.
The person writes section 6: `Signed-off: <name> <yyyy-mm-dd>` or `Status: PAUSED <reason>`. An agent never writes it.
Signing an item nobody answered accepts its recommendation (recorded as a P-n line, CONFIRMED, signer named).

## Gate
| state | pipeline exit | next |
|---|---|---|
| unsigned | 14 | NEEDS-JUDGMENT.md points at PROPOSAL.md; sign, rerun the command at its top |
| `Status: PAUSED` | 15 | the resume command is in NEEDS-JUDGMENT.md; remove the line, sign, rerun |
| signed | 0 | carry on to convert |
| plan input changed after the signature | 14 | PROPOSAL.md is rewritten with a "Changed since signed" block and the sign-off is cleared |

`Interview mode: unattended` (env `UPG_INTERVIEW_MODE=unattended` or `$W/interview-mode.txt`) signs nothing: the step
records `ASSUMED (unattended)` P-lines, goes on, and the gate summary and SUMMARY.md say "proposal not signed". A person
who later signs and answers the P-n lines closes them; the ASSUMED lines block the owner sign-off until then.

Section-3 items that fit a pattern in playbooks/rearchitecture.md carry its options, effort and recommendation and cite `[RA-n, status]` (bin/proposal.py); the answer updates that entry (steps/decide.md).

## Step records
`bin/proposal.py` also writes `$W/steps.jsonl` through `bin/steps.py` (plan: STEP-RECORDS-PLAN.md). Every item of sections 2, 3 and 4 gets a step (`S-n`) with what was found and what is proposed, in plain words.
- Routine module updates are one step for the whole section 2 row; they are approved with the sign-off and get no button of their own. Each section-3 choice is one step. A section-3 step keeps its `P-n` as its `alias`; PROPOSAL.md still shows `[P-n]`.
- An unattended run records every step as `assumed` by `agent`. A sign-off records `approved` with the signer for every step nobody answered on its own (an answer a person already gave is kept).
- A rerun opens no second step for the same topic and title and adds no event when nothing changed.

