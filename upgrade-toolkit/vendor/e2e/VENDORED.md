# Vendored journey engine

Source: MendixMau/mxcli-project-toolkit, `project-tests/e2e/`, commit `ecfb9d2` (2026-10-06). Files:
`journey-runner.js`, `helpers.js`, `config.js`, `otel.js` (what `bin/run_journeys.py` copies; `ENGINE` there).

Why: cloud workers could not clone the shared toolkit (T5 on 2026-10-06: the clone was refused, journeys rung INVALID).
With this copy no clone is needed. Do not edit these files: `run_journeys.py` patches its own working copy (PATCHES)
and reports any patch that no longer applies.

Files `run_journeys.py` copies next to them (toolkit files, not vendored): `bin/journey-verbs.js`, `bin/settle.js`,
`bin/pgdata.js` and `bin/pgmap.py`. The patches, by area (the full list with reasons: `PATCHES` in run_journeys.py,
`steps/journeys.md` "Runner limits"): login and navTo (helpers.js), fill, click in the topmost popup, toggle / select /
confirm verbs, `closes`, settle before screenshots, and since E2E-9 the data instrument: helpers.js `oql()` sends the
SQL through pgdata.js / pgmap.py to the app's Postgres when `UPG_PSQL` is set (E5b-11: `mxcli oql --direct` does not
answer on a runapp runtime), and journey-runner.js records each step's effect (row counts before and after).

Refresh: copy the four files from a newer mxcli-project-toolkit commit, update the commit above, run
`controls/run-controls.sh` (journeys-engine-* controls).
