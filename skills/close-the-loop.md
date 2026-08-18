# Close the Loop — filing what a finished task produced

**Applies to:** any agent-driven build session that produces knowledge faster than it
**Requires:** bash and Python 3 — this skill runs toolkit shell scripts. Run `bin/doctor.sh` once on a new machine; it names anything missing and how to get it. Windows: use Git Bash, and see the Prerequisites section of `conversion-runbook.md`.
writes it down. Written 2026-07-30 after a session in which every durable output —
a token audit, five model pins, three hooks, six traps — existed only in the
conversation at the moment compaction was requested.

**Companions:** `tool-output-is-not-ground-truth.md` (why unverified claims must not be
filed as fact), `coverage-ledger.md` (the same append-and-drain shape, applied to scope).

---

## The failure mode

Work finishes. The next thing starts. Nothing is written, because writing feels like
overhead at exactly the moment the knowledge is freshest and therefore feels safest to
carry in your head.

Then one of three things happens: the session is compacted and the summary keeps the
narrative but drops the specifics; the session is cleared and the knowledge goes with it;
or the session survives but at 500k context, where every subsequent tool call re-reads
the whole undigested prefix at cost.

**All three failures are the same failure**: state that should have been a file was left
as conversation. Conversation is the most expensive and least durable storage available.

---

## The routing rule

The instinct is to route by topic — "this is about security, so it goes in the security
doc." That is wrong and it is why filing stalls: most real findings are about three
topics at once.

**Route by lifespan and audience.** Two questions settle almost every case:

1. **Is this still true in a repo that isn't this one?** → yes: toolkit skill. no: project file.
2. **Does it describe the app, or how we work on the app?** → app: build log / build plan /
   `PROJECT.md`. how we work: memory or skill.

### Destinations

| What you have | Goes to | Test that it belongs there |
|---|---|---|
| A script was executed against the `.mpr` | `docs/BUILD-LOG.md` | Append-only. One entry per exec: what it did · exec result · mxbuild result · manual SP work after |
| A build-plan step is now done, blocked, or descoped | `architecture/build-plan.md` (+ the module's own plan) | Someone reading only the plan would otherwise redo it or skip it |
| A decision that constrains future decisions | `PROJECT.md` | Without the *why*, a future session could reasonably decide the opposite |
| A lesson that transfers to another Mendix project | the shared toolkit's `skills/` | Still true with a different client, different module, different .mpr |
| A confirmed, reproducible tool defect | `bug-logs/mxcli-bugs.md` | You could hand the repro to the tool's author |
| How the user wants me to work; project context not derivable from code | memory dir + one line in `MEMORY.md` | It's about the collaboration, not the codebase |
| Where we are, what's next, what's unfiled | `docs/progress/checkpoints.md` | It expires. Nobody will want it in a month |

### The three rules that keep it honest

- **A finding is not filed until it is verified.** An unverified claim written to
  `PROJECT.md` is worse than no claim, because the next session will treat it as settled.
  If it's load-bearing and unchecked, it goes in the checkpoint marked `UNVERIFIED:`, not
  in the register. See `tool-output-is-not-ground-truth.md`.
- **A committed script is not an executed script.** `BUILD-LOG.md` records execs, not
  commits. If the script is in `mdlsource/` but never ran, the log entry is a lie.
- **Nothing goes in two places.** If it's in a skill, `PROJECT.md` links to it. Duplicated
  knowledge diverges, and the stale copy is always the one someone reads.

### When it is genuinely unclear

It goes in the **checkpoint Narrative, prefixed `UNFILED:`**. That is the buffer, and it
already exists.

Do **not** create a `notes/`, `history/`, or `misc/` folder. An unclassified bucket has no
drain — writes accumulate, nobody reads them, and the appearance of having filed something
removes the pressure to actually file it. The checkpoint is a better buffer precisely
because it is *expected* to be drained: the next close-the-loop pass reads the `UNFILED:`
lines and routes them, or deletes them as no longer mattering.

Most `UNFILED:` lines should end up deleted. That is the correct outcome, not a failure.

---

## The trigger — when to run this

Not on a timer, and not only at a token threshold. **At a work boundary**, which is any of:

- a script executed against the `.mpr` and the gate came back
- a gate passed or failed conclusively
- a build-plan step finished, or turned out to be blocked
- the topic changed — the user moved from one part of the app to another
- a commit
- context crossed a threshold and the hook said so

Boundaries are detectable mechanically for the first three. `work-boundary.sh`
(PostToolUse) watches for them and appends to `.claude/.pending-writes`; that ledger is
what `close-task.sh` drains. The point of the ledger is that *owed writes survive being
forgotten* — they are on disk, not in working memory.

---

## The procedure

```sh
./bin/close-task.sh          # what is owed + the routing table (installed by sync-project.sh)
```

1. **Read the ledger.** It lists execs, gates, and commits since the last close, each of
   which owes a specific write.
2. **Route each item** through the table above. Write it. One place only.
3. **Drain the `UNFILED:` lines** from the previous checkpoint — route or delete.
4. **Checkpoint**: `checkpoint.sh --write`, fill the Narrative, including any new
   `UNFILED:` lines. This file is append-only history.
5. **Overwrite `docs/progress/RESUME.md`** — see below. Then **commit**, then
   `close-task.sh --done` to empty the pending-writes file.
6. **`/clear`** — cheaper than `/compact` and leaves reviewable text. Safe only because
   steps 1–5 happened.

Step 5 before step 6 is not optional: `precompact-guard.sh` blocks compaction when the
ledger is non-empty, which is the mechanism that makes this a process rather than a habit.

---

## Resume cost — the hidden half of the bill

Filing state is only half the job. The other half is making it **cheap to pick back up**, and
that half is easy to miss because the cost lands in the *next* session.

Measured 2026-07-31: after a `/clear`, rediscovering project state cost **100k tokens** —
`PROJECT.md` (8k) + `checkpoints.md` (5.9k) + `PROGRESS-LIVE.md` (3.2k) + a handoff (6.4k) +
`build-plan.md` (7.4k), plus exploration on top. The read itself is not the problem. **The
residue is**: everything pulled in at resume sits in the context prefix and is re-read on every
subsequent call — 100k × ~300 calls ≈ 30M tokens ≈ $9–15. You pay for that orientation hundreds
of times.

The cause is a shape mismatch. `checkpoints.md` is append-only, so it grows without bound; a
resume document must stay small and current. **Those are opposite requirements and one file
cannot be both.**

So keep two:

| File | Shape | Read when |
|---|---|---|
| `docs/progress/checkpoints.md` | Append-only, unbounded | Auditing why a past claim was made. **Never to resume** |
| `docs/progress/RESUME.md` | **Overwritten**, hard cap ~60 lines | Always, and first, after `/clear` |

`RESUME.md` holds four things and nothing else: where we are (3–4 lines), the next actions in
order, do-not-lose, and a **pointer table** — "read this larger file only if you are doing that
specific thing." Pointers, not content. The whole value is that it replaces a 31k read with a
1.5k one.

Wire it by putting the instruction in the project's `CLAUDE.md`, which is auto-loaded: *resuming?
read `RESUME.md` and nothing else yet.* A resume convention that lives anywhere else is a
convention nobody follows, for the same reason `gate-agent` never ran.

## Why this is a hook and not just this document

A previous version of this idea was a routing table in a document. Across 21 sessions the
`gate-agent` it routed to was invoked **zero times**, while 243 gate checks ran inline. A
document that is only read when you already remember to read it changes nothing.

What changes behaviour is `additionalContext` from a hook, because it reaches the model at
the moment of the boundary rather than at the moment of good intentions.
`systemMessage` reaches only the user — useful as a nudge, useless as a control.
