# Example: Field Service template, Mendix 9.24 to 11.12

A full upgrade of a large public Marketplace template (Field Service, web plus a native phone app) with mxcli and the
upgrade toolkit. Two rungs, every step's evidence kept.

```
9.24.2  ──rung 1──▶  10.24.28  ──rung 2──▶  11.12.7
         triage · plan · upgrade · test (per rung) · gate · cockpit
```

## The app

| | |
|---|---|
| Modules | 58 |
| Pages | 253 |
| Microflows / nanoflows | about 1,900 / 680 |
| Java actions | 162 |
| Clients | web and native (offline sync) |

## Result

| | Rung 1 (9.24 → 10.24) | Rung 2 (10.24 → 11.12) |
|---|---|---|
| Build | clean | clean (38 Java API errors fixed to 0) |
| Mendix 11 findings in triage | | 692, 53 blocking |
| Click paths that pass on old and new | | 277 |
| Click paths that fail the same way on old and new | | 243 (old app defects, evidence per row) |
| Regressions (passes on old, fails on new) | 0 | 0 |
| Database compare | closed | 622 PASS, 9 accepted with a reason |
| Screens compared | closed | 79 pairs, 44 equal, 35 accepted |
| Items closed (cockpit) | | 568 |
| Still open for a person | release notes review, sign-off | 27 topics, listed in the cockpit |

The gate verdict is not a green PASS on purpose: the owner has not signed the proposal, the release-note rows wait for
a person, and two native-only pages are covered by hand on an emulator, not by the web journeys. Read
`steps/test/gate-summary.md` per rung.

The native app: Make It Native cannot run Mendix 11 apps, so the agent followed the Mendix docs for a custom native
build, ran the 11.12 app on an Android emulator, and saved the route as a toolkit skill.

## Folders

| Path | What |
|---|---|
| `rung*/COCKPIT.html` | the one page for the app owner: what is proven, what needs you |
| `rung*/steps/triage/` | what changes and whether it can be tested: release-note impact, local edits, module jumps, test scope |
| `rung*/steps/plan/` | PROPOSAL.md (the plan) and DECISIONS.md (every choice, assumed ones marked) |
| `rung*/steps/upgrade/` | convert and build logs, mx check rounds, CHANGES.md (one line per commit with its reason) |
| `rung*/steps/test/` | smoke, journeys old vs new, data and log diffs, heal report, gate summary |

## App packages (release assets)

| File | Mendix | Source |
|---|---|---|
| `FSM-9.24.2-original-1.1.1.mpk` | 9.24.2 | the Marketplace download, unchanged |
| `FSM-10.24.28-upgraded.mpk` | 10.24.28 | end of rung 1 |
| `FSM-11.12.7-upgraded.mpk` | 11.12.7 | end of rung 2 |

Checksums: `SHA256SUMS`. The upgraded packages carry no data snapshot. `make_mpk.py` builds a package from any commit of
the app repository.

## Run it yourself

```bash
upgrade-pipeline.sh --app-zip FSM-9.24.2-original-1.1.1.mpk --source 9.24.2.6130 \
  --target 10.24.28.129343 --target2 11.12.7 --work ./work
```

The pipeline stops where a person must decide; the cockpit shows what. Paths in the evidence read `<run>` for the run
folder and `<toolkit>` for the toolkit checkout.
