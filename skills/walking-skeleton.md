# Walking skeleton — prove the whole loop on one thin slice before any module

**Applies to:** every entry mode (migration, requirements-driven, greenfield) — the first thing
Stage 5 does, before the first module of the build plan. À-la-carte work on an existing app skips it.
**Purpose:** one entity, one microflow, one page, one nav item, one demo user, one journey, one
screenshot — proven end to end in the *running* app. It is not a feature. It is the proof that the
build, run, look and test machinery all work on this machine, on this app, before a module depends
on them.

## Why this exists (the failure it prevents)

A real build (2026-07, a workflow PoC) executed 27 scripts and ran **zero** tests. Its build gate
had reported "0 errors" for several commits while pointing at an mxbuild binary that could not run
on that machine, so nothing had been verified at all. The happy path appeared twice as a "next"
item and never as a done one. Every page was later queued for a rewrite because the first look at
a page happened after all pages existed. None of that survives a skeleton: an mxbuild that cannot
execute fails the skeleton's first exec; a page shape that ignores the design system is visible in
the skeleton's one screenshot; a test runner that is not wired fails the skeleton's one journey.
Twenty minutes, once, instead of twenty scripts of blast radius.

The build loop (`iterative-build-loop.md`) is layered — entities, then microflows, then pages — and
gated per module. The skeleton is the vertical cut through those layers that the loop otherwise
never takes until module close.

## The slice

Pick the app's central noun and its one central action (an approval app: `Request` and
`Submit`). Nothing else. Everything below is one script, `mdlsource/00-skeleton.mdl`, unless the
project convention splits security out.

| # | Element | Rule |
|---|---|---|
| 1 | One persistent entity, 2–3 attributes | The real central noun, not `Foo`. Using a throwaway name means the skeleton gets deleted, and with it the evidence. |
| 2 | One microflow that changes state | Must write to the database (create or commit), so the data rung has something to assert. |
| 3 | The smallest screen set that lets the action happen — usually an overview with a "New" button plus the form it opens | Built through `ui-preflight-pages.md`, on the app's owned layout; passes `project-bin/check-page-shell.sh`. This is the first place the design system is tested. |
| 4 | One navigation item + one module role + one user role + one demo user | The journey logs in as the demo user and clicks the nav item. Admin-only reachability is a fail. |
| 5 | One journey | Log in → click nav → fill the form → run the action → assert the row exists (OQL or SQL). Playwright via the project's harness, or `mxcli playwright verify`. |
| 6 | One screenshot of the page, kept | `docs/looks/00-skeleton.png`, judged with the three `ui-loop.md` questions. |

## Completion — all six, with the evidence named

The skeleton is done when the following are pasted in chat, each with its artifact:

1. `exec.sh` gate `pass` for `00-skeleton.mdl` (row in `docs/BUILD-LOG.md`, not `skipped` or
   `unverified`). On a cloud container this is the moment `doctor.sh --install` is proven.
2. The app is up: boot log line, or `curl … /login.html → 200`, after a `snapshot-mpr.sh`.
3. The journey **passes**, and a deliberately broken copy of it **fails** (rename the nav
   item in the journey file and re-run). A journey that cannot fail is not evidence
   (`testing-shape.md` §4).
4. The data assertion names the row: `1 Request where Title = '<value the journey typed>'`.
5. The screenshot exists and the three `ui-loop.md` answers are written under it.
6. The register line in `PROJECT.md`: `Skeleton proven <date>: exec pass, journey pass/fail-control,
   look done` — `gate-check.sh <project> 5` reports `PENDING` on the `skeleton` obligation until
   that line exists.

`NOT RUN` is a legal answer for any row and is written as such. Silence is not.

## Field run — greenfield pilot, 2026-09-04

Cloud container, mxcli v0.20.0, Mendix 11.13.0, `mxcli new --output-dir ./app`. Skeleton done in one
session: exec gate `pass` on the second attempt, app up, journey PASS and its broken control FAIL,
`1 approvals$request where status='Submitted'`, three screenshots judged. What it caught before a
single module existed: every project script refused the two-tree layout (`_common.sh`, fixed);
`exec.sh` printed a CE0117 with no location (fixed); a bare enum value in a CHANGE passes
`check --references` and fails mxbuild; a demo user needs security above Off and a 12-char password
and fails at statement 13 of 14 with 12 already applied; `page-fidelity.js` scores the wireframe's
own annotation class; the form rendered horizontal with truncated labels — the first thing the
first module fixes, known on day one instead of at module close.

## What it is not

- Not the first module. The skeleton entity may be *absorbed* by the first module's script that
  owns that document (`create or modify`), never deleted.
- Not a design review. One page, three questions. `module-review.md` still runs at module close.
- Not optional in greenfield. Greenfield is where the machinery is newest and least proven.

## Related

`iterative-build-loop.md` (the loop this precedes) · `ui-loop.md` (the look) · `testing-shape.md`
(what the journey must be able to do) · `cloud-dev-environment.md` (the container setup the
skeleton proves) · `learned-mdl-preflight.md` (STOP rows apply to the skeleton script too).
