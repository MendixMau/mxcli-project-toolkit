# POC Build — a demo-ready app fast, designed first, continuable afterwards

**Applies to:** any mxcli project where the user asks for a POC, proof of concept, demo, pilot or quick build, or `PROJECT.md` says `Build type: poc`.
**Purpose:** Get a clickable, good-looking, working app in front of people in the shortest honest time, and leave it in a state a normal build can continue from.

**Status: EXPERIMENTAL.** Proven: one small fictional app ("LoanDesk": 3 entities, 5 pages, 2 roles), one model, ~30 min with the design-first flow; two good builds, visual scores by a non-blind grader. Not proven: any larger app, any other model, a build driven by this text (the experiment briefs were longer and run by hand). Say this in chat once at the start.

**Build type is chosen at intake**, recorded `Build type: poc` in `PROJECT.md` (normal: `Build type: full`), `CONFIRMED`. It is independent of the entry mode (idea, requirements, BRDs, source) and of `Pipeline mode:`. A POC build does **not** run the nine stage gates; `bin/gate-check.sh` reports `PENDING` for every stage it skipped. That is expected, not a failure; tell the user so. Do not waive stages to turn it green.

**Size:** no limit. Tested size is above. Larger is allowed; say once, "anything larger than 3 entities / 5 pages / 2 roles is unmeasured, expect it to take longer", and go on.

## Steps

1. **One design question** (asked per `skills/interview-protocol.md` §3 — ask, then stop): "Do you have a prototype or a design?"
   - **Supplied:** reproduce it. Tokens to theme with `mxcli theme create <name> --from <css>`, then `theme apply` (the bundled `migrate-design-prototype` skill). Compare every page with the prototype's screenshot.
   - **Brand only:** design system first (`skills/design-artifacts.md` Steps 0–1), then hi-fi wireframes.
   - **Nothing:** ask exactly three short questions: who uses it and on what device; look and feel (pick one of three example styles); the one screen that must impress. Then as "Brand only".
2. **Theme before pages.** Ship the design into the theme, build a StyleGallery page (`skills/learned-stylegallery.md`), look at it at 1280 and 390, run `bin/check-design-reaches-app.sh`. *Failure: pages that "worked" but were stock Atlas; the maintainer called them horrible.*
3. **Hi-fi wireframes**, one per page, clickable (`bin/assemble-prototype.js`), with every state (empty, refusal, success) and a 390 variant.
4. **Buildability check**, `skills/learned-mdl-cannot-express.md` + `bin/mdl-rules.sh page`: each interactive element is BUILDABLE or REDESIGNED/DEVIATION. Denominator: 0 unchecked.
5. **The one human stop**: show the clickable prototype / wireframes and the deviation list. Nothing is built before the answer.
6. **Build** per `skills/walking-skeleton.md`, then pages. Dispatch per `skills/dispatching.md` (no-model work in parallel, one writer per `.mpr`, wireframe-built pages one at a time, shared parts one owner). Per page: look at 1280 and 390 beside the wireframe, up to two polish rounds. A `DataView` per list row for editable inputs (`skills/learned-mdl-cannot-express.md`). Never trust `bin/page-fidelity.js` for looks. *Failure: lowest text-match score, best-looking app.*
7. **Journey** (`skills/journey-proof.md`): happy path plus every refusal in the requirements, each asserted by its message text; 3 cold runs in a row.
8. **Hand-over BRDs** (`skills/brd-generation.md`): per use case, a data table, a roles-by-page matrix, built vs not built, open questions each with an owner, a sized backlog. Continue later as `skills/existing-app-change.md`.

## Must-have checklist (all N rows ticked or listed as NOT DONE with a reason)

Both good test builds missed every one of these.

| # | Check | Failure it prevents |
|---|---|---|
| 1 | User name, role and logout visible in the top bar | Demo cannot show who is signed in; sessions pile up |
| 2 | An empty state on every list | A blank white area reads as broken |
| 3 | Seed data visible to the demo user who should see it | "My requests" empty because seeded rows had no owner |
| 4 | Every refusal is a friendly in-page message, never the default error dialog | Hand-out refusal showed the stock Mendix error box |
| 5 | The active navigation item is the current page | "Desk" page highlighted the wrong tab |
| 6 | No list silently capped: visible pager or count | Gallery stopped at 20 items; run 3 of the journey failed |
| 7 | Every page checked at 1280 and at 390 | Nav clipped, modal buttons below the fold at 390 |
| 8 | Journey re-runnable on a used database: unique test data, cleans up or tolerates leftovers | Test rows from run 1 broke run 2 |
| 9 | No demo-user switcher floating over the designed pages | A debug button sat on the finished design |

Row 3: `System.owner` cannot be set from a microflow. Do not rely on it for "mine" lists. Instead give the entity an explicit association to the user (or a user-name attribute), filter on `[Requester = '[%CurrentUser%]']`, and seed that. This is a recommendation, not yet field-proven; run `bin/bug-lookup.sh owner` first and prefer any entry that fixes it.

## Done when

- The human stop is answered and recorded in `PROJECT.md`.
- Checklist: 9 of 9 ticked or listed under NOT DONE with a reason.
- Journey: 3 of 3 cold runs pass, output pasted, not summarised.
- Screenshots exist at 1280 and 390 for every page, and each was compared with its wireframe or the prototype.
- The hand-over BRDs exist and the final message lists what is NOT built. Never claim a pass you did not run.
