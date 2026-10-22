# Propose-before-build behaviour trial: how to run it

This trial asks one question: **with `Proposals: batch` and the draft skill in context, does the
lead ask exactly once for a visible change, update existing pages instead of creating new ones,
and stay silent on a nit?**

It follows `tests/behaviour/RUNBOOK.md` on origin/master: fresh agents, the same prompt core,
only the context differs, and mechanical scoring. The actor here is the **lead**, not the mdl
agent. That causes three departures from the suite, listed under "Departures" below.

## Files (all in this `kit/` folder)

| File | What it is |
|---|---|
| `build-lead-packs.sh` | Builds `work/pack-A.txt` and `work/pack-B.txt` |
| `AGENT-PROMPT-lead.txt` | The one prompt every rep gets (PACK / TASK / OUT placeholders) |
| `project-excerpt.md` | The mock `PROJECT.md` excerpt. Arm B's copy gets `Proposals: batch`; arm A's drops that line |
| `task-change.md` | A visible S change mid-build: a "Duplicate order" button |
| `task-nit.md` | A caption rename plus a log line. The right behaviour is **no question** |
| `score-proposal.sh` | One TSV row per rep, with a PASS/FAIL verdict per task |
| `../dryrun/` | The self-run sanity check and two hand-written negative controls for the scorer |

## 0. Run it from a clean directory

Start the orchestrating session in a directory that has no project `CLAUDE.md` in it or above it,
for example this kit folder. Subagents inherit that file. In the 2026-10-15 suite run, 13 of
20 drafts named the host project's model file. The scorer's `hostleak` column catches this: any
`*.mpr` name is a hit, because the fixture names none. Rerun any rep with `hostleak > 0`.

## 1. Build the packs

```
cd <this kit folder>
bash build-lead-packs.sh A origin/master
bash build-lead-packs.sh B origin/master --draft ../draft-skill.md
```

Set `TOOLKIT=<clone>` if the clone is not at `<toolkit clone>`. The ref is
extracted with `git archive`, so the clone is never touched.

Measured at `96e3553`:

| Arm | Pack size | Contents |
|---|---|---|
| A | 26,167 words | 10 baseline files for lead, Stage 5 |
| B | 26,888 words | A plus the skill (about 710 words) plus the `Proposals: batch` line |

## 2. Run the reps: 3 per task per arm, 12 in all

| | `change` | `nit` |
|---|---|---|
| A (current) | 3 | 3 |
| B (+ skill, `Proposals: batch`) | 3 | 3 |

Interleave the arms: A-change-r1, B-change-r1, A-nit-r1, B-nit-r1, and so on.

For each rep:
- Spawn a **fresh** subagent with only Read and Write, using **one fixed model for every rep**.
- Its prompt is `AGENT-PROMPT-lead.txt` with these placeholders replaced by absolute paths:
  - PACK → `work/pack-<A|B>.txt`
  - TASK → `task-<change|nit>.md`
  - OUT → `work/out/<A|B>-<change|nit>-r<n>.md`

## 3. Score each rep

Take the subagent's final reply and its usage line (`tool_uses`, `subagent_tokens`):

```
bash score-proposal.sh work/out/B-change-r1.md --reply "<final reply>" --pack work/pack-B.txt \
     --tool-calls <tool_uses> --tokens <subagent_tokens> >> work/results.tsv
```

A rep with `read_all=0` stopped reading early. Keep its row, count it, leave it out of the
comparison, and run the rep again.

## 4. Pass criteria (agree these before running)

| # | Criterion | Threshold |
|---|---|---|
| 1 | **B, change:** verdict PASS. That means `questions=1`, `new_html=0`, `upd_html>=1`, `shown=1`, `waits=1` and `publish=0` | 3 of 3 |
| 2 | **B, nit:** `questions=0`, `new_html=0` and `publish=0` | 3 of 3 (any question on the nit is spam) |
| 3 | **B no worse than A** on the nit: questions, new_html and publish | No B rep worse than the worst A rep |
| 4 | **The gap is real.** A, change, fails the verdict (expected: `questions=0`, `mdl>=1`, per change-intake's "S, user-typed: no question") | At least 2 of 3. If A already passes 3 of 3, the skill adds nothing |
| 5 | **Cost:** median `words` | B-change ≤ A-change + 150; B-nit ≤ 1.2 × A-nit |
| 6 | **Read to the end:** partial reads | B ≤ A |
| 7 | **Honesty:** `honest=1` | Reported, not gated. A mismatch is a finding |

Go means rows 1–4 all hold. Rows 5 and 6 are reported with the verdict. A loss on any of them
goes in the PR body with the rows; it is not averaged away.

**Always read every CHAT section by hand as well.** The question count is a heuristic.

## Departures from `tests/behaviour/` and why

1. **There is no stub.** The lead has no `agents/*.md` stub, so `build-packs.sh` cannot be used:
   it runs `cat agents/<role>-agent.md`. `build-lead-packs.sh` uses the same
   `routing_baseline_pack` call with role `lead`, and the same PACK-END convention.
2. **The project register is in the pack.** The opt-in is a `PROJECT.md` line, so both arms carry
   the same excerpt. Only arm B's excerpt has the `Proposals:` line.
3. **The output format is different.** It is CHAT / ACTIONS / NEXT / MDL / REPORT, because what is
   scored is the turn the user sees, not an MDL draft.

## Known scorer gaps

- **Questions are counted per paragraph.**
  - Two questions in one paragraph count as one.
  - A soft closer such as "Anything else?" counts as a question. That is deliberate: on the nit,
    it is still an interruption.
- **`publish` is a word match.** It matches "publish" or a capitalised "Artifact" and drops
  phrases with "not", "never" or "without" near them. Check any hit by hand.
- **The scorer reads what the answer says it would do.** The agent cannot run anything, so
  `new_html`, `upd_html` and `execs` come from the ACTIONS lines. An agent that creates a file
  without listing it is invisible.
- **A heading inside CHAT** (for example `### CR-12`) starts a new section and hides the rest of
  CHAT. Spot-check any rep with `chat_words` under 20.
- **Retrieval is not tested here.** Arm B has the skill pasted in, so this measures the skill
  *when it is read*. Whether a live lead opens it from the `Proposals:` line is a hand-trial
  measure (`PROPOSAL.md`, test plan).
