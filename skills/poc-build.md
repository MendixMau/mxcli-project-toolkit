# POC Build — a demo-ready app fast, designed first, continuable afterwards

**Applies to:** any mxcli project where the user asks for a POC, proof of concept, demo, pilot or quick build, or `PROJECT.md` says `Build type: poc`.
**Purpose:** A clickable, good-looking, working app in front of people fast, continuable by a normal build.

**Status: EXPERIMENTAL.** Proven: a hand-run experiment (~30 min) and one build driven by this text alone (fictional visitor-pass app, 5 pages, 2 roles, ~36 min, journey 22/22 on repeated runs incl. a cold restart, no failures seen). Independent grade (grader knew no builder claims before scoring; visual scores are one grader's, calibrated on earlier test apps): function 26 pass of 30 testable (3 fail, 1 not testable), every business refusal a friendly in-page message; must-haves 6 pass, 1 partial (active nav), 1 fail (phone navigation for one role), empty states built but not seen; visual design about 4.1 of 5 (earlier design-first apps 3.8 and 4.0; default-look about 2.2); follow-up docs 17 of 24. Verdict: "nearly demo-ready: strong main screen; fix first-load active nav, phone navigation and leftover test data". One model, one small app; anything larger is unmeasured.

**Who asks.** The lead's first question: "Normal build or POC build?" — when the request mentions a POC, demo, pilot or quick build, or `PROJECT.md` has no `Build type:` line. Write `Build type: poc` (normal: `full`), `CONFIRMED`, to `PROJECT.md`. Skip `intake.md`. A POC build does **not** run the nine stage gates; `bin/gate-check.sh` reports `PENDING` for them. Expected; tell the user; never waive. No answer: wait (`skills/interview-protocol.md` §3); `ASSUMED` only on "you decide", else record "unanswered" in the hand-over.

## Order (nothing else)

Design artifacts (design system, wireframes, clickable prototype) → **HUMAN STOP** → only then model work: security, theme, walking skeleton, pages, journey, hand-over.

1. **Design questions** (per `skills/interview-protocol.md` §3, ask then stop): "Do you have a prototype or a design?"
   - **Supplied:** `mxcli theme create <name> --from <css>`, `theme apply` (bundled `migrate-design-prototype`).
   - **Otherwise** ask exactly three short questions: who uses it and on what device; look and feel: **calm enterprise** (muted, one accent), **bold modern** (strong colour, large type) or **dense data** (compact, small type); the one screen to impress. These replace the branding interview (`skills/design-artifacts.md` Step 0b); then build its Steps 0a and 1.
2. **Hi-fi wireframes**, one per page, clickable (`bin/assemble-prototype.js`), every state (empty, refusal, success), a 390 variant. Name wireframes after pages or write `design/wireframes/PAGE-MAP.tsv`. Never name a shell class `wf-*` (the assembler hides it).
3. **Buildability check**, `skills/learned-mdl-cannot-express.md` + `bin/mdl-rules.sh page`: each interactive element BUILDABLE or REDESIGNED/DEVIATION. 0 unchecked.
4. **The one human stop**: show prototype and deviation list; record the answer in `PROJECT.md`.
5. **Security first, aloud.** The scaffold starts with security Off (no demo users, "Login FAILED"). Say in chat, then set Production and create the demo users (STOP-table operation: say it, do not ask; `skills/learned-mdl-preflight.md`). Add a **second demo user with no data**.
6. **Theme**: port the design system into the theme; look at one page at 1280 and 390; run `bin/check-design-reaches-app.sh design/ds.css`. *Failure: stock Atlas pages.*
7. **Build** the walking skeleton (`skills/walking-skeleton.md`) as the first slice, not a separate project; then pages. Write via `bin/exec.sh --commit-first`. Per page: look at 1280 and 390 beside the wireframe; two polish rounds max. A `DataView` per list row for editable inputs. Validate on Save, not blur (a blur message can move Save, swallowing the click). Order lists as a user reads them (date then time, most urgent first); *failure: tomorrow's visit above today's.* Filter choice lists by the rules; *failure: an out-of-service room was selectable, refused only on save.*
8. **Journey**: one script (not the `journey-proof.md` runner): happy path plus every refusal, each asserted by its message text. Every business rule is reachable from the UI and exercised here, or the hand-over lists it "not reachable from the UI" with the reason; *failure: 1 of 6 rules was guarded in the microflow, no screen triggered it, the journey skipped it.* No always-true assertions; *failure: 2 of 22 steps were `ok(true, …)`.* **3 cold runs**: stop the app, start it, run the journey, three times in a row, on the same database. After the last run re-seed the database (or have the journey delete what it creates) and look at the main screen once; *failure: rows like "J2595388 Visitor" under the designed screen.*
9. **Hand-over**: markdown, not BRD JSON (no built/not-built, roles or owner fields). One document per use case: data table; roles-by-page matrix; built vs not built; open questions each with an owner; sized backlog. State, do not fix: a page URL a role may not open lands on the bare sign-in page (messageCode=403). Continue later: `skills/existing-app-change.md`.

**Looks** are judged from screenshots at 1280 and 390; `page-fidelity.js` (text match) never decides; `check-page-shell.sh` still runs.

**Skipped (say so in the hand-over):** the StyleGallery page (the design-system HTML is the showcase), `page-fidelity.js` as a gate, `mxcli test` microflow tests, the five-rung journey-proof, the stage gates.

## Must-have checklist (all 12 rows ticked or listed as NOT DONE with a reason)

| # | Check | Failure it prevents |
|---|---|---|
| 1 | User name, role and logout visible in the top bar | Demo cannot show who is signed in |
| 2 | An empty state on every list | A blank white area reads as broken |
| 3 | Seed data visible to the demo user who should see it | "My requests" empty: seeded rows had no owner |
| 4 | Every refusal is a friendly in-page message, never the default error dialog | Refusal showed the stock error box |
| 5 | The active navigation item is the current page, checked on first landing after login and on a deep link, not after clicking a menu item | Item bold only after a click; first page seen had none active |
| 6 | No list silently capped: visible pager or count | Gallery stopped at 20 items; journey run 3 failed |
| 7 | Every page checked at 1280 and at 390, and every role reaches each of its pages at 390 | Nav clipped, modal buttons below the fold; menu toggle hidden at phone width, one role lost its second page |
| 8 | Journey re-runnable on a used database: unique data, cleans up or tolerates leftovers | Run 1's test rows broke run 2 |
| 9 | No demo-user switcher floating over the designed pages (Mendix's own `.mx-demouserswitcher`; hide it in the theme) | Debug button on the finished design |
| 10 | Every cross-page flow has one owner and is run once end to end by a user who starts with NO data | List stayed empty after the first filing; journey passed with a seeded user |
| 11 | Every empty state seen in the browser once (the second, no-data demo user) | Empty states were built and never seen |
| 12 | Demo data clean at hand-over: no journey leftovers on the main screen | Random-named test rows under the designed screen |

Row 3: `System.owner` cannot be set from a microflow; give the entity an association to `System.User`, filter `[Visit_Host = '[%CurrentUser%]']`, seed that (`bin/bug-lookup.sh owner` first).

## Done when

- The human stop is answered and recorded in `PROJECT.md`.
- Checklist: 12 of 12 ticked or listed under NOT DONE with a reason.
- Journey: 3 of 3 cold runs pass, output pasted, not summarised; one deliberately broken control run fails; every business rule exercised or listed unreachable; demo data clean afterwards.
- Screenshots at 1280 and 390 for every page, each compared with its wireframe or the prototype.
- Hand-over documents exist (one per use case, all 5 sections); the final message lists what is NOT built. Claim no unrun pass.
