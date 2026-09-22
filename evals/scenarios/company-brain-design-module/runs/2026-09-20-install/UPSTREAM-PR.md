# From "could we change the CLI?" to a tested PR — 2026-09-20

The fork-or-PR note said the seams were in the right place. This proves it: the change was
built on a shallow clone of `mendixlabs/mxcli`, tested at three layers, and field-run against
real packages with the built binary. **Not submitted** — this session cannot reach that repo; the
two patches, the PR body and a submission recipe are staged in the private repo under
`gh-issues-ready/mxcli-pr-local-mpk-install/`.

## The approach, and why this order

1. **Read the repo's own rules first** (`CONTRIBUTING.md`, `CLAUDE.md`'s PR checklist): issue
   before code, test written first, verify at the layer the symptom lives in, prove a fix by
   revert, record a finding. The PR follows all of them, so a maintainer reviews the change and
   not the process.
2. **Baseline before touching anything**: grammar generated, clean tree built, vetted, tested.
   Without that, a failure later cannot be attributed.
3. **Smallest honest change.** A file input through the existing writer. The 10.6.4 case stays
   refused by `mx`'s window and is documented with the remedy, not worked around.
4. **Field run with real packages, not fixtures**, using a module exported by `mx` itself from one
   app and installed into another, plus a real widget, plus the real 10.6.4 theme package for the
   refusal path.

## What the field run found that no unit test would have

- **A pre-existing bug in the install writer**: with a relative `-p app.mpr` every bundled file was
  refused as a path-traversal attempt, *after* the module had been transplanted — a half install
  reporting failure. The traversal tests only ever used absolute temp dirs, so the root was
  canonical by accident. Fixed as its own commit, test shown failing first, finding recorded in
  the repo's log.
- **Two bugs in my own integration test**, both mine: a temp `HOME` (copied from the unit-test
  helper) hid the mxbuild cache; and `return out.String(), cmd.Execute()` reads the buffer before
  the command runs. Both were misread as product failures for one round each. The lesson is the
  toolkit's own: an instrument's first run tests the instrument.

## Final state

| Check | Result |
|---|---|
| 8 unit tests, new | pass; client factory fatal-if-called proves no PAT |
| 1 unit test for the fix | fails on unpatched code with the reported message, passes on patched |
| integration test, real package | pass: module in model, no marketplace stamp, MPR v2 preserved, 5 bundled files verified, second run reports |
| `make lint-go`, `go test ./...`, `make check-findings`, `make sync-all` | all green / nothing generated |
| field run, relative `-p` | 4 units, 6 files, `mx check` 0 errors, Source column empty |
| 10.6.4 theme package | refused with `mx`'s message, app untouched |

The company-brain component manifest's install field can now say exactly what works: `mxcli
marketplace install --file <pkg>.mpk -p app.mpr` on this branch, or the hand procedure recorded
in `CLI-CAN-DO-IT.md` until it merges.
