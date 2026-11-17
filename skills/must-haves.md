# Must-haves — the floor every built module owes, whatever the build type

**Applies to:** every module with pages, in every entry mode and build type (full, POC, high-speed, change an existing app). Single source of this list: `skills/poc-build.md` and `skills/module-review.md` point here.
**Purpose:** The checks a user notices in the first minute, owed even when planning was skipped. Skipping stages must never also switch off these.

**When:** at module close, with the module-review report (stage 5). Owed per module by `bin/lib/obligations.tsv` row `must-haves`; with no module brief, the modules that hold built pages owe it.

## The list (every row ticked, or NOT DONE with a reason; never silently left out)

| # | Check | Failure it prevents |
|---|---|---|
| 1 | User name, role and logout visible in the top bar (or the layout's equivalent) | Nobody can tell who is signed in |
| 2 | An empty state on every list | A blank white area reads as broken |
| 3 | Seed data visible to the user who should see it | "My requests" empty: seeded rows had no owner |
| 4 | Every refusal is a friendly in-page message, never the default error dialog | Refusal showed the stock error box |
| 5 | The active navigation item is the current page, checked on first landing after login and on a deep link, not after a menu click | Item bold only after a click; first page seen had none active |
| 6 | No list silently capped: visible pager or count | Gallery stopped at 20 items; journey run 3 failed |
| 7 | Every page checked at 1280 and at 390, and every role reaches each of its pages at 390 | Nav clipped, modal buttons below the fold; menu toggle hidden at phone width, one role lost its second page |
| 8 | Journey re-runnable on a used database: unique data, cleans up or tolerates leftovers | Run 1's test rows broke run 2 |
| 9 | No debug or demo affordance over the designed pages (Mendix's `.mx-demouserswitcher`: hide it in the theme) | Debug button on the finished design |
| 10 | Every cross-page flow has one owner and is run once end to end by a user who starts with NO data | List stayed empty after the first filing; journey passed with a seeded user |
| 11 | Every empty state seen in the browser once (a no-data user, or a filter that returns none); a state no role can reach is marked "not reachable" with the reason | Empty states were built and never seen |
| 12 | Data clean at hand-over: no journey or test leftovers on the main screen | Random-named test rows under the designed screen |
| 13 | Every region the design shows (wireframe, prototype or design-system page) is on the built page: count regions per page, `K of K present`, each missing one named | Field run: dashboard tiles, status tiles and the side navigation absent from screens whose prototypes showed them; 78 pages built, 0 reviewed |

Row 3: `System.owner` cannot be set from a microflow; give the entity an association to `System.User`, filter on it `= '[%CurrentUser%]'`, seed that (`bin/bug-lookup.sh owner` first).
Row 13 with no design supplied: the yardstick is the module brief or the use case; write `13 NOT DONE — no design to count against` only when neither exists.

## The mark

Write `docs/progress/must-haves/<Module>.md`. **First line, the denominator:**

```
<Module> · 13 of 13 rows ticked or NOT DONE with a reason · pages 6 of 6
```

then one line per row: `<#> TICKED — <evidence: screenshot path, journey step or page>` or `<#> NOT DONE — <reason>`. A row with neither is not ticked. `bin/gate-check.sh` reads only that the file exists and states its denominator (`Obligation must-haves`); whether the evidence holds is the reviewer's judgement.

*Failure it prevents:* a module called done with `13 of 13` claimed and row 13 resting on "matches the prototype", no region counted. Name the regions.

## Done when

- `docs/progress/must-haves/<Module>.md` exists for every module that holds a page, first line `13 of 13 rows ticked or NOT DONE with a reason`.
- Every NOT DONE carries its reason, and the module's report or hand-over repeats it.
