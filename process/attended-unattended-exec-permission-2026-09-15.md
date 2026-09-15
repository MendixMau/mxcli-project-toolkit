# Proposal — Attended / Unattended session mode, and a build window, for EXEC permission

**Status:** PROPOSAL. Nothing here is implemented. No toolkit rule changes until this is accepted.
**Date:** 2026-09-15
**Kind:** process
**From:** a live Mendix conversion project running the toolkit pipeline unattended
**Field evidence:** an overnight build/fix/test/review run on Mendix 11.13.0 / mxcli v0.21.0,
interrupted repeatedly by permission prompts and denials on routine, already-authorised work.
The operator's summary of the damage: *"It stopt good auto build & tests."*

---

## 1. The rule this proposes to make conditional

The toolkit's standing instruction, restated in every consuming project's `CLAUDE.md`:

> Never run `mxcli exec`, `bin/exec.sh`, `mxcli test`, `mxcli docker check`, or any `--mcp`
> write against the real `.mpr` without asking the user first — **every time**.

The rule is correct and this proposal does not delete it. It is unconditional, and that is the
problem: it is written as if a human is always sitting at the terminal. Increasingly one is not.
An unattended run hits the same gate a hundred times and stalls on every one of them, so the
rule that exists to protect the model ends up preventing the work the model was opened for.

## 2. The proposal

Declare a **session mode** once, explicitly, at session start, and let it govern whether
EXEC-class operations prompt.

### 2.1 Two modes

| Mode | Who is present | EXEC-class operations |
|---|---|---|
| **Attended** | an operator is at the terminal and will answer | **prompt every time** — today's behaviour, unchanged |
| **Unattended** | nobody is watching; the session must run to completion or stop | **pre-authorised**, under the preconditions in §2.3 |

Neither mode is the default by inference. The mode is **declared in chat at session start and
recorded**, the same way the toolkit commit is declared by the session-start ritual. A session
that has not declared a mode is Attended — failing closed.

An agent must never select or change its own mode. In practice an agent *cannot*: writing the
harness's own permission settings is refused as self-modification (§3.3). That refusal is a
feature and the design should lean on it — the mode is set by the person who opens the session,
in the same act as opening it.

### 2.2 A build window inside an Attended session

The operator's second ask, and the more useful half: *during a build it can also be turned off.*

An Attended session should be able to open a bounded **build window** — "I am about to run
scripts 40 through 76, do not ask me again until they are done" — and close it when the build
finishes. This is not a mode change; it is a scoped suspension of prompting with:

- an explicit **start** (the operator says so, in chat) and an explicit **end** (the agent
  announces the window closed when the numbered build completes, errors, or is abandoned);
- a **declared scope** — which scripts, against which `.mpr`;
- **automatic closure on the first gate failure.** A red `mx check` or a failed
  `gate-check.sh` closes the window and returns to prompting. A build window suspends the
  *asking*, never the *checking*.

Without the window, an Attended session running a 30-script build is Attended in name only:
the operator clicks approve 30 times without reading, which is worse than not asking.

### 2.3 What Unattended still may not do

Pre-authorisation is not a blanket. These stay ask-always in **both** modes, because their
blast radius is not recoverable by a `git checkout`:

1. **Dropping model elements** — `DROP ENTITY / MICROFLOW / PAGE / WORKFLOW / MODULE`.
   Every consuming project already carries this carve-out; it survives the mode.
2. **Any write while another writer may hold the `.mpr`.** The ONE WRITER rule is a data-
   integrity invariant, not a permission preference. On the source project it has corrupted the
   model five times. Unattended mode must *verify* no concurrent writer, not assume one.
3. **A dirty git tree.** Pre-authorised exec is only safe because the rollback is one command.
   No clean tree, no pre-authorisation.
4. **Anything pushed outward** — a PR, a deploy, a message to a third party.

And the post-conditions do not relax: script validated before exec, native `mx check` after,
`gate-check.sh` before any stage is called done. Unattended mode removes the *question*, not
the *evidence*.

## 3. Why this is worth changing — three findings from the field run

### 3.1 The allow-list named a binary that cannot execute

The project's checked-in allow-rules read `Bash(./mxcli:*)` and `Bash(./mxcli *)`. That is the
invocation the toolkit documents, and it is correct on the operator's own machine. The session
was running in a Linux container, where:

```
$ ./mxcli -p <project>.mpr -c "SHOW MODULES"
bash: ./mxcli: cannot execute binary file: Exec format error
```

The working binary was a platform-specific one under `bin/`. So **every single mxcli call fell
through the allow-list to the classifier**, all night. The rule wasn't wrong; it was written
against one platform and silently stopped matching on another.

This is the part a mode selection alone does not fix, and it is worth stating plainly: a
permission allow-list keyed to an exact command string is a brittle instrument. It fails
*open-looking and closed-acting* — nothing reports that a rule stopped matching.

### 3.2 A read-only query on the local dev database was refused

Clearing stale sessions from the local, ephemeral, just-created dev database was refused as a
mass-delete. The follow-up **`select count(*)`** on the same table — a read — was refused too.

Minutes later the e2e suite produced **one blocker and two majors** on a page that was in fact
correct. The runtime log showed the cause:

```
INFO - Client_Auth: ... status code 419. Removing session.
```

A dropped session, not a defect. Every finding evaporated on a clean re-run. The diagnosis cost
a substantial part of the run, and the session debris that plausibly caused it was exactly what
the refused cleanup would have removed. **A denial on a routine local-dev operation did not
prevent damage; it manufactured a false blocker.** An unattended session with no operator would
have filed all three as real.

### 3.3 The agent cannot fix any of this itself, by design

Asked to widen its own allow-list, the session was refused — writing the harness's own settings
is classified as self-modification. Correct, and the reason the mode must be an operator-set
input rather than something an agent can negotiate its way into. It also means **the
misconfiguration in §3.1 was unfixable from inside the run**: the only party who could repair
it was asleep, which is the definition of an unattended session.

## 4. What lands in the toolkit if this is accepted

Deliberately small — this is a process change, not an instrument:

1. **`skills/conversion-runbook.md` §1** — the session-start ritual gains one line: declare the
   mode in chat alongside the toolkit commit.
2. **The exec rule** (in `CLAUDE.md` and in the project `CLAUDE.md` template) — restated as
   mode-conditional, carrying the §2.3 carve-outs verbatim so nothing that is ask-always today
   becomes pre-authorised by omission.
3. **A short skill, `skills/session-mode.md`** — the two modes, the build window, the
   carve-outs, and the failure modes in §3 as the motivating evidence.
4. **A preflight line** — before the first exec of an Unattended session, verify the mxcli
   invocation actually runs on *this* platform, rather than trusting that a documented
   invocation matched. One `--version` call, once, catches §3.1 in full.

Item 4 is worth having regardless of whether the rest of this proposal is accepted.

## 5. Open questions for review

1. **Where is the mode recorded** so a gate can read it — `PROJECT.md`, or chat-only? A gate
   that can see the mode can also refuse to pass a stage that ran Unattended without a clean
   tree, which is attractive. Chat-only is cheaper and unverifiable.
2. **Does an Unattended session get to open a build window at all**, or is that redundant? The
   author's view: redundant, and allowing it invites the window to become the mode.
3. **Should a build window carry a wall-clock cap** as a second closure condition alongside the
   gate failure?
4. **Is the ONE WRITER check mechanisable** — a lock file next to the `.mpr` that both this
   toolkit and a GUI session would respect — or does it stay a human promise?

## 6. What was not run

No code was written or executed for this proposal. No toolkit script, skill or rule was
modified. No test suite, CI pipeline or eval was run. This is a document.

The evidence in §3 was collected incidentally during normal project work on Mendix 11.13.0 with
mxcli v0.21.0, not from a designed probe; §3.1 and §3.3 are reproduced verbatim from that run's
terminal output, and §3.2's runtime-log line likewise. The causal link in §3.2 between session
debris and the 419 is the one **hypothesis** in this document, labelled as such: what is
established is that the 419 occurred, that all three findings vanished on re-run, and that the
cleanup that would have removed the debris was refused.
