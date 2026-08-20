# Pattern: every popup that creates/commits an object must close and/or show a result — MDL has no native "show message" toast

**Applies to:** any mxcli project.

**General rule:** any popup page whose primary button creates and commits a domain object (or
triggers a backend flow that will) must leave the user with unambiguous feedback: either the
popup closes and the result is visible on the page behind it, or the popup stays open and shows
the result directly. **Never leave the user staring at an unchanged popup with no visible state
change** — that reads as "did nothing" even when the backend fully succeeded.

This is a standard Mendix UX convention — native Studio Pro has a dedicated "Show message"
microflow activity (a growl/toast) for exactly this case.

## The mxcli/MDL gap

Confirmed (mxcli as of 2026-08-14): there is **no MDL syntax for a "show message"/toast
microflow activity anywhere** — checked `write-microflows.md`'s full supported-statement list
(only `LOG INFO/WARNING/ERROR` for server logs, `VALIDATION FEEDBACK` for NewEdit attribute
errors, nothing generic) and `create-page.md`'s `ACTIONBUTTON` action vocabulary (`save_changes`,
`close_page`, `microflow`, `nanoflow`, `show_page`, `create_object ... then show_page` — no
`show_message`). Any project scripted via mxcli MDL genuinely cannot produce a native toast
notification. This is a tooling gap worth raising as an mxcli feature request once it recurs on
another project — a "Show message" activity is one of the most basic, commonly-used microflow
activities in real Mendix development, and its total absence from the DSL is a significant
practical limitation, not a one-off oversight.

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

## Applying this rule to a new project

Before calling a create-from-popup flow done, check: does the button's target microflow either
(a) `close page;` promptly after the commit, or (b) leave the popup open with a visible
success/failure indicator wired via `DynamicClasses`? If neither, it's not done — flag it
explicitly rather than letting a happy-path e2e test (which only checks the DB row was created,
not what the user actually saw) pass silently over the gap. This is the same underlying
principle as a bug-submission checklist's evidence gate: a passing backend check is not evidence
about what the user experienced.
