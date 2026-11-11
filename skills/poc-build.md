# POC Build — a demo-ready app fast, designed first, continuable afterwards

**Applies to:** any mxcli project where the user asks for a POC, proof of concept, demo, pilot or quick build, or `PROJECT.md` says `Build type: poc`.
**Purpose:** A clickable, good-looking, working app in front of people fast, left in a state a normal build can continue from.

**Status: EXPERIMENTAL.** Proven: a hand-run experiment (3 entities, 5 pages, 2 roles, ~30 min) and one build driven by this text alone (fictional visitor-pass app, 2 persistent + 2 non-persistent entities, 5 pages, 2 roles, no prototype, ~36 min, journey 22/22 four times, 8 of 9 must-haves; grading result pending). One model, one small app; anything larger is unmeasured.

**Who asks, when.** The lead's first question, before anything else: "Normal build or POC build?" — when the request mentions a POC, demo, pilot or quick build, or `PROJECT.md` has no `Build type:` line. Write `Build type: poc` (normal: `full`), `CONFIRMED`, to `PROJECT.md`. `intake.md` has no such question; skip its others. A POC build does **not** run the nine stage gates; `bin/gate-check.sh` reports `PENDING` for the skipped stages. Expected; tell the user; never waive to go green. No answer to a question: wait (`skills/interview-protocol.md` §3); `ASSUMED` only when the user said "you decide", otherwise record "unanswered" and say so in the hand-over.

## Order (nothing else)

Design artifacts (design-system CSS/HTML, wireframes, clickable prototype) → **HUMAN STOP** → only then model work: security and demo users, theme port, walking skeleton, pages, journey, hand-over.

1. **Design questions** (per `skills/interview-protocol.md` §3, ask then stop): "Do you have a prototype or a design?"
   - **Supplied:** reproduce it: `mxcli theme create <name> --from <css>`, `theme apply` (bundled `migrate-design-prototype`).
   - **Otherwise** ask exactly three short questions: who uses it and on what device; look and feel: **calm enterprise** (muted, one accent), **bold modern** (strong colour, large type) or **dense data** (compact, small type); the one screen that must impress. These three replace the longer branding interview in `skills/design-artifacts.md` Step 0b; then build its Steps 0a and 1 (design system first, two files).
2. **Hi-fi wireframes**, one per page, clickable (`bin/assemble-prototype.js`), every state (empty, refusal, success), a 390 variant. Name wireframes after pages or write `design/wireframes/PAGE-MAP.tsv`. Never name a shell class `wf-*`: the assembler hides it (blank prototype).
3. **Buildability check**, `skills/learned-mdl-cannot-express.md` + `bin/mdl-rules.sh page`: each interactive element BUILDABLE or REDESIGNED/DEVIATION. 0 unchecked.
4. **The one human stop**: show the prototype and deviation list; record the answer in `PROJECT.md`.
5. **Security first, aloud.** The scaffold starts with security Off (no demo users, "Login FAILED"). Say in chat, then set the level to Production and create the demo users (STOP-table operation: say it, do not ask; project `CLAUDE.md` "Start here" 3, `skills/learned-mdl-preflight.md`). Add a **second demo user with no data**.
6. **Theme**: port the design system into the theme; look at one page at 1280 and 390; run `bin/check-design-reaches-app.sh design/ds.css` (it needs the argument). *Failure: stock Atlas pages.*
7. **Build** the walking skeleton (`skills/walking-skeleton.md`) as the first slice of the build, not a separate project; then pages. A lead with no subagents does the work itself. Write via `bin/exec.sh --commit-first` (it refuses an uncommitted model). Per page: look at 1280 and 390 beside the wireframe; two polish rounds at most. A `DataView` per list row for editable inputs. A validation message that appears on blur can move the Save button and swallow the click: validate on Save.
8. **Journey**: one script (not the five-rung `journey-proof.md` runner): happy path plus every refusal, each asserted by its message text. **3 cold runs**: stop the app, start it, run the journey, three times in a row, on the same database.
9. **Hand-over**: markdown, not BRD JSON (its schema has no built/not-built, roles matrix or owner fields). One document per use case with: data table; roles-by-page matrix; built vs not built; open questions each with an owner; sized backlog. Continue later per `skills/existing-app-change.md`.

**Mechanical checks vs looks.** Looks are judged from screenshots at 1280 and 390, because `bin/page-fidelity.js` is a text match. *Failure: lowest text-match score, best-looking app.* `check-page-shell.sh` still runs; `page-fidelity.js` never decides.

**Skipped in a POC build, say so in the hand-over:** the StyleGallery page (the design-system HTML is the showcase; so ui-preflight's gallery-reuse rule does not apply), `page-fidelity.js` as a gate, `mxcli test` microflow tests, the five-rung journey-proof, the stage gates.

## Must-have checklist (all 11 rows ticked or listed as NOT DONE with a reason)

| # | Check | Failure it prevents |
|---|---|---|
| 1 | User name, role and logout visible in the top bar | Demo cannot show who is signed in |
| 2 | An empty state on every list | A blank white area reads as broken |
| 3 | Seed data visible to the demo user who should see it | "My requests" empty because seeded rows had no owner |
| 4 | Every refusal is a friendly in-page message, never the default error dialog | Hand-out refusal showed the stock error box |
| 5 | The active navigation item is the current page | "Desk" page highlighted the wrong tab |
| 6 | No list silently capped: visible pager or count | Gallery stopped at 20 items; run 3 of the journey failed |
| 7 | Every page checked at 1280 and at 390 | Nav clipped, modal buttons below the fold at 390 |
| 8 | Journey re-runnable on a used database: unique test data, cleans up or tolerates leftovers | Test rows from run 1 broke run 2 |
| 9 | No demo-user switcher floating over the designed pages (Mendix's own `.mx-demouserswitcher`; hide it in the theme) | A debug button sat on the finished design |
| 10 | Every cross-page flow has one owner and is run once end to end by a user who starts with NO data | After filing the first request the list stayed empty until reload; the journey passed on a user with rows |
| 11 | Every empty state seen in the browser once (the second, no-data demo user) | Empty states were built and never seen |

Row 3: `System.owner` cannot be set from a microflow, so not for "mine" lists. Give the entity an association to `System.User`, filter `[Visit_Host = '[%CurrentUser%]']`, seed that (field-proven once; `bin/bug-lookup.sh owner` first).

## Done when

- The human stop is answered and recorded in `PROJECT.md`.
- Checklist: 11 of 11 ticked or listed under NOT DONE with a reason.
- Journey: 3 of 3 cold runs pass, output pasted, not summarised; one deliberately broken control fails.
- Screenshots exist at 1280 and 390 for every page, and each was compared with its wireframe or the prototype.
- The hand-over documents exist (one per use case, all 5 sections) and the final message lists what is NOT built. Never claim a pass you did not run.
