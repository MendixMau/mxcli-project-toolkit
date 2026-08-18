# examples/

Worked reference material for the toolkit's skills. Everything here uses an invented domain (a
purchase-request app with a supplier catalogue) so it can be read and copied without carrying any
project's names.

| Path | For | Guided tour |
|---|---|---|
| `journeys/minimal.journey.json` | the smallest runnable journey — login, land, one assertion | `skills/journey-examples.md` |
| `journeys/full.journey.json` | every field `journey-runner.js` reads; the one to copy | `skills/journey-examples.md` |
| `journeys/no-seed.journey.json` | a REST/mock-fed screen: empty `seeds[]` with the `_seedNote` pattern | `skills/journey-examples.md` |
| `brd/F101-purchase-requests.brd.json` | a trimmed BRD so the requirement pointers resolve | `skills/journey-examples.md` |
| `validate-journeys.js` | static contract checks, no app required | `skills/journey-examples.md` |

```bash
node examples/validate-journeys.js --selftest
node examples/validate-journeys.js --brd examples/brd examples/journeys/*.journey.json
node examples/validate-journeys.js --brd <yourBrdDir> journeys/*.journey.json
```

The journeys are **shape references and have never been executed** — there is no app behind them.
Read `skills/journey-proof.md` for why the five rungs and seven mutants exist, and
`skills/fixture-seeding.md` for how the data a journey's seeds need gets there.
