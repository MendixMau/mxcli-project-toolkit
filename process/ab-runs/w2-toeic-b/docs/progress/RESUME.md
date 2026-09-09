# RESUME.md

**Overwritten, never appended. Hard cap ~60 lines.** The one file a session reads first, and for
a while the only one. Append-only history lives in `checkpoints.md` next to this file — read
that to audit a past claim, never to resume.

## Where we are

**No session has closed the loop in this project yet** — this file is the toolkit's starter
scaffold (`bin/init-project.sh`, or `bin/sync-project.sh` backfilling a project that predates
it). The first session to finish work overwrites it wholesale per
`/home/user/mxcli-project-toolkit/skills/close-the-loop.md`.

**So the stage is not stated here, on purpose.** A scaffold that guessed "Stage P" would be
confidently wrong on any project that was already mid-flight when this file appeared, and a wrong
resume doc is worse than none. Step 1 below is how to find out.

## Next actions, in order

1. Run `/home/user/mxcli-project-toolkit/bin/gate-check.sh .` — it reports the current stage from the files on disk.
   That verdict, not this file, is the answer to "where are we".
2. **If it reports Stage P:** run the kickoff interview against `intake.md`. Question 1 is the
   entry mode (migration / requirements-driven / greenfield) and it decides everything after.
   Every question is asked in chat and the turn then ENDS and waits —
   `/home/user/mxcli-project-toolkit/skills/interview-protocol.md` §3. Record each answer in `PROJECT.md` as
   `CONFIRMED` or `ASSUMED`.
   **If it reports anything later:** the stage's owning skill lists what that stage owes — find it
   in `CLAUDE.local.md`'s baseline routing, or in the runbook's stage matrix.
3. Overwrite this file before the session ends (`bin/close-task.sh` prints the checklist), so
   the next one does not have to repeat step 1.

## Do not lose

Nothing recorded yet. This section is where a closing session puts the thing that would be
expensive to rediscover — not a summary, only what would otherwise be lost.

## Read this larger file only if you are doing that specific thing

| Doing | Read |
|---|---|
| Anything at all in the pipeline | `CLAUDE.local.md` — wiring, session-start ritual, baseline routing |
| Working out what stage anything is in | `/home/user/mxcli-project-toolkit/skills/conversion-runbook.md` |
| The kickoff interview | `intake.md`, then `PROJECT.md` |
| Auditing why a past decision was made | `PROJECT.md` (decision register — not an orientation doc) |
| Rewriting this file at the end of a session | `/home/user/mxcli-project-toolkit/skills/close-the-loop.md` |
