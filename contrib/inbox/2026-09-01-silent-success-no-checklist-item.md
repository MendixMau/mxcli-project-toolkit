# Checklist has "silent failure" but no "silent success" rule — a real defect slipped through

**From:** a React/Express-to-Mendix dashboard-publishing migration project
**Date:** 2026-09-01
**Kind:** learning
**Field evidence:** confirmed finding, reported by the user from the running app: "after
clicking new dashboard I don't see anything happening." Logged as B-7 in the project's own
`docs/improvement-plan.md`.
**Proposed target:** `skills/ui-preflight-pages.md` (the mandatory cross-check table) and/or
`skills/testing-shape.md` (false-green register)

---

**What happened.** A create-dashboard microflow committed the object and returned `true`, and
that was the whole microflow. The create form was an inline data view on the same page,
still showing the same (now-saved) object with the same text in its fields; the gallery below
it was a *separate* data view over a microflow data source, which does not re-run because a
sibling committed. Net effect for a human: click "Create dashboard," and nothing on screen
changes at all. The object existed — a reload proved it — but nothing said so.

**Why the checklist didn't catch it — checked, not assumed.** I grepped this toolkit's own
skills before writing this up, expecting to find the rule already existed and the session had
just skipped it. It doesn't exist:

- `ui-preflight-pages.md`'s mandatory cross-check table has "Validation feedback: every form
  with a required/unique field surfaces a visible validation message on failed save... a save
  that fails silently... is a P1, not a pass." That is the FAILURE case only. There is no
  paired line for "every commit that succeeds produces a visible response (navigation, a
  message, or a refreshing data source) — a success that leaves the screen unchanged is a P1,
  not a pass."
- `testing-shape.md`'s false-green register has an entry for a *test* that reloads to "get
  unstuck" after a navigation the test itself was supposed to trigger and verify. That's a
  related but different shape: here, the journey never modeled "click Create" as a navigation
  at all — it modeled the click purely as a DB write, verified by reloading the overview and
  finding the new card. That's a legitimate way to prove the write happened, and it is exactly
  why the test could never see that the button itself produces no response: the reload is a
  correct assertion about persistence and a total blind spot for user-visible feedback.
- `patterns-crud.md` shows `show page` after a create in its own worked example, but nothing
  enforces the pattern — it's something to imitate, not a checked rule.

**Proposed fix (untested against the toolkit, this is a suggestion not a diff).** Add one row
to `ui-preflight-pages.md`'s cross-check table, symmetric to the existing validation-feedback
one: every commit-and-return action button (create, update, delete, bulk action) resolves to
one of: a navigation (`show page`/`close page`), a validation-feedback message, or a data
source that is provably re-scanned after the commit (e.g., the committing object is the
gallery's own selection, or the gallery's data source is refreshed via the same microflow). A
commit with none of the three is a P1. Optionally add a matching false-green register entry to
`testing-shape.md`: "a journey step that asserts state via reload-then-check cannot detect
that the UI gave the user no feedback for the action it just performed — pair every
commit-and-return assertion with a same-page, no-reload check that *something* on screen
changed."
