# Pattern: every popup that creates/commits an object must close and/or show a result

**Applies to:** any mxcli project.

**General rule:** any popup page whose primary button creates and commits a domain object (or
triggers a backend flow that will) must leave the user with unambiguous feedback: either the
popup closes and the result is visible on the page behind it, or the popup stays open and shows
the result directly. **Never leave the user staring at an unchanged popup with no visible state
change** — that reads as "did nothing" even when the backend fully succeeded.

This is a standard Mendix UX convention — native Studio Pro has a dedicated "Show message"
microflow activity (a growl/toast) for exactly this case.

## RETIRED 2026-09-04 — MDL *does* have `show message`

**This file previously stated: "Confirmed (mxcli as of 2026-08-14): there is no MDL syntax for a
'show message'/toast microflow activity anywhere."** That is wrong, and it was wrong by method:
it was concluded from reading two *skill files*' supported-statement lists, not from probing the
binary. `mxcli syntax` documents the activity nowhere, so a documentation sweep will always
return "absent" — the grammar has to be probed.

**Retested 2026-09-04 on mxcli `4b58b89` (2026-08-26) / Mendix 11.13.0**, on a live workflow
project, by `mxcli check` plus an executed probe microflow gated by a real mxbuild:

| Form | Verdict |
|---|---|
| `show message 'literal text';` | parses, execs, **mxbuild 0 errors** |
| `show message 'a ' + $Obj/Attr + ' b';` | parses, execs, mxbuild 0 errors |
| `show message 'text' type Information \| Warning \| Error;` | all three parse and exec |
| `show message 'text' type Success;` | parses — but see [[learned-microflow-patterns]] §"show message": silently stored as `Information` |
| `SHOW MESSAGE WARNING 'text';` (level BEFORE the text) | **does not parse**, in microflows *or* nanoflows |
| `show message 'text' type Warning blocking;` | **does not parse** — no blocking form |

Two traps worth carrying, because both actively mislead:

1. **The binary embeds examples of a grammar it rejects.** `strings ./mxcli` yields
   `SHOW MESSAGE ERROR 'Incorrect username or password.'` and friends, and mxcli's own bundled
   `.ai-context/skills/write-nanoflows.md` uses that level-first form **seven times**. Every one
   of them fails `mxcli check` on the shipped binary. An agent that finds the skill and follows
   it gets a parse error and concludes the activity does not exist — which is very nearly how
   this file came to say what it said.
2. **The severity keyword goes AFTER the text**, as `type <Level>`, matching how mxcli
   round-trips it: `show message '{1}' type Warning objects ['...'];`.

The toast is therefore **Option C** below, not a gap. The rest of this file — when a popup must
close, when it should stay open and show detail — is unchanged and still governs; a toast alone
is not a substitute for the popup doing the right thing.

## The two working substitutes (both proven live)

**Option A — Close + let the result speak via the page behind it.** Add `close page;` to the
create/commit microflow (immediately after the object is created/committed, not at the very end,
so the popup closes promptly even if downstream steps take longer). The user lands back on the
overview page and sees the new/changed row appear in its grid. Good when:
- The result doesn't need explaining beyond "it happened" (the row itself, and any status
  badge/color it carries, tells the story — e.g. badge-styling that makes a case's `BusState`
  visible at a glance in the grid).
- There's no meaningful intermediate state worth showing before the user moves on.

**Option B — Stay open, surface the result inline.** Keep the popup open; add a `dataview`
(sourced from a summary microflow) with a result banner using `DynamicClasses` to switch
success/warning/danger styling, directly in the same popup. Good when:
- The result has detail worth showing immediately (counts, a status breakdown, a raw call log)
  before the user decides what to do next.
- Proven pattern: `CheckStatus_Trigger` — stays open after "Run check", shows a
  `ctnResultBanner` (info/success/warning via `DynamicClasses` off a summary DTO) plus a
  live grid and raw call log, all in the same dialog.

**Do not silently do neither** — that was this exact defect, found live in `SomeAction_Trigger`:
the button called a microflow that did all the real work but never closed and never showed
anything, so a user clicking "Start run" had zero indication whether anything happened. A past
debugging session found this and — instead of building the missing feedback — wrote it into the
e2e test as `"Known UX substitution ... intentional, not a bug"`, which buried a real, deferred
gap under language implying it was a deliberate final decision.
**Watch for this failure mode generally**: a bug-log/BUILD-LOG entry that says "no working
pattern found, deferred" is an open item, not a decision — don't let a later test-script comment
or checkpoint restate it as intentional without re-confirming that with the user first.

**Option C — a toast, now that MDL has one.** `show message 'text' type Warning;` inside the
microflow the button calls. Use it for the case Options A and B do not cover: a flow that
**refuses** and returns without navigating anywhere. Proven live 2026-09-04 on a task-ownership
guard — the guard logged a warning and returned, so the button appeared to do nothing; the toast
is what turns "broken button" into "refused, and here is why". A toast is *not* a substitute for
closing the popup (A) or showing the result inline (B) when the flow actually succeeded.

## Applying this rule to a new project

Before calling a create-from-popup flow done, check: does the button's target microflow either
(a) `close page;` promptly after the commit, or (b) leave the popup open with a visible
success/failure indicator wired via `DynamicClasses`? If neither, it's not done — flag it
explicitly rather than letting a happy-path e2e test (which only checks the DB row was created,
not what the user actually saw) pass silently over the gap. This is the same underlying
principle as a bug-submission checklist's evidence gate: a passing backend check is not evidence
about what the user experienced.
