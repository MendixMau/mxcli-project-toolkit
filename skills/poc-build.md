# POC Build — a demo-ready app fast, designed first, continuable afterwards

**Applies to:** a project whose kickoff answer (intake Q16) is the POC build, or whose user explicitly asks for one past kickoff; `PROJECT.md` says `Build type: poc`.
**Purpose:** A clickable, good-looking, working app in front of people fast, continuable by a normal build.

**Status: EXPERIMENTAL.** Two builds driven by this text, one model, small apps. First (fictional visitor-pass app, ~36 min): "nearly demo-ready", function 26 of 29, design ~4.1 of 5 (not blind), journey 22/22. Second (kickoff question asked first, answered POC; ~64 min): a blind grader compared it with the same requirements built in plain plan mode with no toolkit: function 25 of 25 against 24 of 24 testable; refusals in-page 7 of 7 against 2 of 6; must-haves 10 of 10 against 5 of 10; visual mean 3.8 against 3.6; hand-over 22 of 24 against 12 of 24; time ~64 against ~27 min (both ran in parallel, inflated). The gain is the must-have list and the hand-over, not the look, and it costs time. NOT proven: a real person answering (answers and approval came from a prepared file).

**Who asks.** The kickoff interview asks the build type first, at project birth (intake Q16; rendering per `skills/interview-protocol.md` §3). On a POC answer `Build type: poc` is recorded `CONFIRMED` in `PROJECT.md`, and this skill is the flow; the other intake questions are not asked. A missing `Build type:` line means `full`; `Interview mode: auto` never picks `poc`. A project past kickoff whose user only says "we need a demo this week" does NOT switch: the lead says in one line that the build type is chosen at the start and offers to continue the normal build (optionally `Pipeline mode: high-speed`). Switching such a project needs the user to say so explicitly, confirmed once, and is recorded in `PROJECT.md` as a decision. *Failure: a Stage 5 project whose user mentioned a demo dropped its gates.* A POC build does **not** run the nine stage gates. Stage P still checks that every `intake.md` question carries an answer marker, so write them: Q16 `Answered (CONFIRMED): POC build`, and under each of Q1–Q15 exactly `Unverified — how to verify: not asked, POC build (Build type: poc, skills/poc-build.md); ask it if the build continues as a full build`. Then `bin/gate-check.sh` shows Stage P `PASS` (markers present; it says nothing about those answers), Stages 0–4, 6, 7 `PENDING`, Stage 5 `MANUAL`. *Failure: unmarked questions kept Stage P at `FAIL` for the whole build.* No answer: end the turn and wait (`skills/interview-protocol.md` §3); `ASSUMED` only when the user said "you decide" (= `full`).

**Size:** more than 3 entities, 5 pages or 2 roles is unmeasured. Say so once, then continue: a warning, not a refusal (*failure: an agent that refuses, or proceeds without a word*).

**Not a speed setting.** `Pipeline mode: high-speed` is the existing way to make a NORMAL build faster; a POC build is a different shape of build.

**Question moments:** after the build-type answer, ONE message with the prototype question AND the three design questions (step 1; the three apply only if the prototype answer is Nothing), and wait for the reply; then exactly one more stop, the approval (step 4), which ends the turn. The build type was asked at kickoff.

## Order (nothing else)

Design artifacts (design system, wireframes, clickable prototype) → one **APPROVAL STOP** → only then model work: security, theme, walking skeleton, pages, journey, hand-over.

1. **Design questions** (per `skills/interview-protocol.md` §3; ONE message, then end the turn and wait for the reply): "Do you have a prototype or a design?" plus, for the Nothing case, the three questions below, so the answer can be a single reply.
   - **Prototype or design supplied:** reproduce it (`mxcli theme create <name> --from <css>`, `theme apply`; bundled `migrate-design-prototype`). Steps 2 and 3 still run in reduced form: the prototype IS the wireframe set; run the buildability pass on it; the stop (step 4) is on the prototype plus the list of deviations Mendix forces.
   - **Brand guide only:** tokens from the brand → design system → hi-fi wireframes (step 2) → buildability (step 3) → stop (step 4).
   - **Nothing:** the three short questions already asked in that same message (one reply answers them), then continue as the brand-guide path: who uses it and on what device; look and feel: **calm enterprise** (muted, one accent), **bold modern** (strong colour, large type) or **dense data** (compact, small type); the one screen to impress. These replace the branding interview (`skills/design-artifacts.md` Step 0b); then build its Steps 0a and 1.
2. **Hi-fi wireframes**, one per page, clickable (`bin/assemble-prototype.js`), every state (empty, refusal, success), a 390 variant. Name wireframes after pages or write `design/wireframes/PAGE-MAP.tsv`. Never name a shell class `wf-*` (the assembler hides it).
3. **Buildability check**, `skills/learned-mdl-cannot-express.md` + `bin/mdl-rules.sh page`: each interactive element BUILDABLE or REDESIGNED/DEVIATION. 0 unchecked.
4. **The approval stop**: show prototype and deviation list; record the answer in `PROJECT.md`. End your turn here and wait for the answer.
5. **Security first, aloud.** The scaffold starts with security Off (no demo users, "Login FAILED"). Say in chat, then set Production and create the demo users (say it, do not ask: the project wiring's exec-approval item, `bin/lib/wiring-item3.sh` item 3, names security level changes among the things to SAY in chat even on `auto`). Add a **second demo user with no data**. Then run `bin/demo-login-tiles.sh` (sign-in tiles on localhost, one per demo user).
6. **Theme**: port the design system into the theme; look at one page at 1280 and 390; run `bin/check-design-reaches-app.sh design/ds.css`. Name the design tokens as the theme names them (`--mxt-*`), or the check sees none (*failure: `FAIL 0 of 10 tokens` on a visibly styled app*); component classes in `ds.css` never ship, the theme does (`ui-preflight-pages.md`). *Failure: stock Atlas pages.*
7. **Build** the walking skeleton (`skills/walking-skeleton.md`) as the first slice, not a separate project; then pages. Write via `bin/exec.sh --commit-first`. Per page: look at 1280 and 390 beside the wireframe; two polish rounds max. A `DataView` per list row for editable inputs. Validate on Save, not blur (a blur message can move Save, swallowing the click): show the message in a gap reserved above Save, so it moves nothing. Order lists as a user reads them (date then time, most urgent first); *failure: tomorrow's visit above today's.* Filter choice lists by the rules; *failure: an out-of-service room was selectable, refused only on save.*
8. **Journey**: one script (not the `journey-proof.md` runner): happy path plus every refusal, each asserted by its message text. Add one deliberately broken control (change one expected message; the run must FAIL; restore it). Every business rule is reachable from the UI and exercised here, or the hand-over lists it "not reachable from the UI" with the reason; *failure: 1 of 6 rules was guarded in the microflow, no screen triggered it, the journey skipped it.* No always-true assertions; *failure: 2 of 22 steps were `ok(true, …)`.* **3 cold runs**: stop the app, start it, run the journey, three times in a row, on the same database. No documented command resets the database (`mxcli run` has none; the hsqldb files sit in `deployment/data/database/hsqldb/` and a harness may refuse deleting them): make the journey delete what it creates, or add a demo-reset microflow and list it in the hand-over under "remove before real use". After the last run look at the main screen once; *failure: rows like "J2595388 Visitor" under the designed screen.*
9. **Hand-over**: markdown, not BRD JSON (no built/not-built, roles or owner fields). One document per use case: data table; roles-by-page matrix; built vs not built; open questions each with an owner; sized backlog. State, do not fix: a page URL a role may not open lands on the bare sign-in page (messageCode=403). Before the app leaves the machine, before any package or deploy: `bin/demo-login-tiles.sh --remove`, then `bin/demo-login-tiles.sh --check --strict` must exit 0; say so in the hand-over. Continue later: `skills/existing-app-change.md`.

**Looks** are judged from screenshots at 1280 and 390; `page-fidelity.js` (text match) never decides; `check-page-shell.sh` still runs.

**Skipped (say so in the hand-over):** `intake.md` (the project intake interview), the StyleGallery page (the design-system HTML is the showcase), `page-fidelity.js` as a gate, `mxcli test` microflow tests, the five-rung journey-proof, the stage gates.

**Precedence.** Only in a project whose `PROJECT.md` says `Build type: poc`, and for the items under Skipped ONLY, this skill wins over the project's `CLAUDE.local.md` "Before any page MDL" rule, the stage gates and the per-page checks, whatever `Pipeline mode:` says. The gate output (Who asks) is expected for `Build type: poc`: tell the user once, and never waive to turn it green. The approval stop on the prototype replaces the numbered change-list approval of the project's `CLAUDE.md`.

**Page pre-flight.** `CLAUDE.local.md` says to read `skills/ui-preflight-pages.md` in full before page MDL: do, for its page-shell and class rules (Steps 1, 2, 4, 5), but skip "Step 0 — enumerate what already reaches this capability" and "Step 3 — Find the closest StyleGallery example" (no gallery exists in a POC build), and still run `bin/check-page-shell.sh` (Step 5). Warning: `check-page-shell.sh` reads a phone bottom bar `<nav class="tabs">` as a top bar; name that class otherwise.

STILL BINDING in a POC build: access rules and grants in the same script that creates the entity or microflow (`skills/security-is-not-a-later-script.md`), every model write through `bin/exec.sh` (`--commit-first`), exec approval mode, the Production security level, ask-then-stop for every question, explicit-path commits (never `git add -A` or `git add .`; commit with `git commit -- <paths>`), and saying in chat before a destructive or security-level change.

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
| 11 | Every empty state seen in the browser once (the no-data demo user, or a filter that returns none); a state no role can reach is marked "not reachable" in the hand-over | Empty states were built and never seen |
| 12 | Demo data clean at hand-over: no journey leftovers on the main screen | Random-named test rows under the designed screen |

Before hand-over, run `bin/security-check.sh`: show the person its security findings and `docs/security/access-snapshot.txt`, and record their approval (`--approve --reason`, `--accept` per finding; an agent never approves). Every role gets at least one "must be refused" journey step that reads or writes another user's data, not only a forbidden page; *failure: the journey caught a role reaching forbidden pages, not a role reading every other user's rows.*

Row 3: `System.owner` cannot be set from a microflow; give the entity an association to `System.User`, filter on that association `= '[%CurrentUser%]'`, seed that (`bin/bug-lookup.sh owner` first).

## Done when

- The approval stop is answered and recorded in `PROJECT.md`.
- Checklist: 12 of 12 ticked or listed under NOT DONE with a reason.
- Journey: 3 of 3 cold runs pass, output pasted, not summarised; one deliberately broken control run fails; every business rule exercised or listed unreachable; demo data clean afterwards.
- Screenshots at 1280 and 390 for every page, each compared with its wireframe or the prototype.
- Hand-over documents exist (one per use case, all 5 sections); the final message lists what is NOT built. Claim no unrun pass.
