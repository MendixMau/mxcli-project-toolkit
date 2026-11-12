# Journey runner: proposed upstream changes (v3.1)

The upgrade toolkit never edits the shared journey engine (`project-tests/e2e/journey-runner.js`). `run_journeys.py`
copies the engine into `<work>/engine`, copies `journey-verbs.js` and `settle.js` next to it, and applies the text
patches in `PATCHES` (bin/run_journeys.py). A patch whose old text is gone is reported "NOT applied" in summary.json
and by `--patch-engine`, so an upstream change cannot drop one silently. This file is the proposal to make the
patches unnecessary. Promote it only on explicit instruction.

## What each patch fixes, with the run that showed it

| Patch | Field evidence | Change proposed upstream |
|---|---|---|
| fill: also `input.mx-name-<widget>` | E1: Mendix login widgets render the input itself with the class | add `input.mx-name-${w}` to the fill locator |
| shoot: settle first, mark `-LOADING` | E6-17: a smoke shot of the Home page with the progress bar, compared with a finished page | wait for `settle()` (no visible loading indicator, DOM size stable for 750 ms, bounded by SETTLE_MS) before `page.screenshot`; name the file `<name>-LOADING.png` when it did not settle |
| click: topmost popup first | E6-8: a popup's Save (`actionButton1`) shared its name with a button behind it; `.first()` clicked the wrong one | resolve a widget inside the last visible `.modal-dialog, .mx-dialog, .mx-window` before the page-wide `.first()` |
| verbs toggle, select, confirm | E5b-21, E7-3: every todo item of one app sat behind a wizard with switches and native reference selectors; walked with a hand Playwright script | add the three cases to `act()` (see below) |
| describe: verbs as sentences | readable findings | add the describe lines for the new verbs |

## Verbs

```
{"do": "toggle", "widget": "switch1", "value": true}        alias "switch"; without value it flips; reads aria-checked
                                                            or checked back and fails when the page did not take it
{"do": "select", "widget": "referenceSelector1", "match": "Team A"}
                                                            aliases "reference", "dropdown"; native <select> inside
                                                            .mx-name-<widget>; exact option text first, then the first
                                                            option containing it; no match = error listing the options
{"do": "confirm"} / {"do": "confirm", "label": "Proceed"}   topmost dialog: primary button or the button with that
                                                            text; waits until the dialog is hidden
```

Values keep every character, ':' included (E7-3: a URL value); only `{{var}}` placeholders are substituted.
Not covered yet: combobox widgets (Combo box from Data Widgets), which render no native select.

## Implementation

`bin/journey-verbs.js` (topmost, toggle, select, confirm) and `bin/settle.js` (settle, pageSettled, BUSY) are the
reference implementation and can move into the engine unchanged. Controls that prove them without a browser:
`controls/journey_verbs_control.js` and `controls/settle_control.js` (in `make test`); the Docker journey controls
run the patched engine end to end.

## Related runner change in run_journeys.py (no engine change needed)

- `--positive-control` exits 0 when every ui-landing row is PASS; UNPROVEN rungs print as INFO (E7-12).
- A hand-written journey's `"closes": [<todo id>]` gives the todo that journey's verdict (E7-3).
