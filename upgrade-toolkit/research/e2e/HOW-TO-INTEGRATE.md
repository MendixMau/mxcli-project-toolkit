# How to put journeys into the upgrade SKILL

Paste-ready text for `SKILL.md` steps 2 and 4, in its style. Add one path line to the "Paths used below" list:

```
- `E2E=$TK/research/e2e` (impact_map.py, gen_journeys.py, run_journeys.py; runs the shared journey-runner.js from a copy)
```

## Step 2, Baseline: add after the smoke walk bullet

```
- Journeys on the OLD app (gives the reference for step 4; always-on set only, the upgrade does not exist yet):
  `python3 $E2E/impact_map.py <old.mpr> <old.mpr> --out $W/impact-base.json`
  `python3 $E2E/gen_journeys.py $W/impact-base.json --out-dir $W/journeys-base --roles-with-users <Role,Role,...> [--create $W/create-spec.json]`
  `python3 $E2E/run_journeys.py $W/journeys-base --label before --port <app> --admin-port <admin> --admin-pass <m2ee> --users $W/users.json --work $W/e2e --pause 50`
  exit 0 = every journey PASS on the old app. A journey that FAILs here is a baseline defect or a bad journey:
  fix or drop it now, never carry it into the gate.
  users.json (local, never committed): `{"<Role>": {"user": "...", "pass": "..."}, "_mfa": {"user": "...", "pass": "..."}}`,
  one user per role plus, when an MFA module is present, one user who HAS an MFA type. Set their passwords
  (`{BCrypt}` + `$2a$10$` hash) on the DB copy AFTER the app started: in DTAP mode D the runtime re-syncs demo
  users at start and resets theirs.
  create-spec.json, once per app: `{"role", "nav": {"group", "item"}, "newButton", "fields": [{"widget", "value"}],
  "saveButton", "entity", "ready"}`. Without it create-and-save is TODO in plan.json, never covered.
  Start the app with SessionTimeout 30000 and ClusterManagerActionInterval 15000 (update_configuration): a trial
  runtime allows 6 sessions, guest sessions count, and a full cap shows up as "login form did not render".
  Once per toolkit version: `run_journeys.py ... --positive-control` on the old app. Every ui-landing row must be
  PASS (mutant caught). A FAIL there means the instrument is broken: stop.
```

## Step 4, Gate: add as item 6

```
6. Journeys: map what changed and run the picked set on the NEW app, on a copy of X_frozen:
   `python3 $E2E/impact_map.py <old.mpr> <new.mpr> --out $W/impact.json --md $W/impact.md`
   `python3 $E2E/gen_journeys.py $W/impact.json --out-dir $W/journeys --roles-with-users <same roles> [--create $W/create-spec.json]`
   `python3 $E2E/run_journeys.py $W/journeys --label after --port ... --admin-port ... --admin-pass ... --users $W/users.json --work $W/e2e --pause 50`
   exit 0 = every journey PASS. Run the same `$W/journeys` set on the old app too (`--label before-picked`): a
   picked journey that FAILs on old as well is a baseline defect, list it apart; one that PASSes on old and FAILs
   on new is a regression (FAIL).
   Read `$W/impact.md` top to bottom before the verdict: a high constant "read in the startup tree", or a flow
   "no longer called at startup but still in the model", is a FAIL to explain even when every journey passes.
   `$W/journeys/plan.json` lists `not_browser` checks (start log "active" lines vs the baseline, WARNING included;
   scheduled events; services; screenshots of changed vendor pages old vs new) and `todo` items. Each one is done
   or reported INVALID, never silently dropped. A role in `skipped` (no test user) is INVALID.
```

## Report and done

Add to "5. Report", after the FAIL list: `Journeys: per journey PASS / FAIL / INVALID with the screenshot path, and
the plan.json not_browser and todo items with their outcome.`

Add to "Definition of done": `AND every generated journey PASS on the new app (or each non-PASS explained as a
baseline defect)`.

## Stop rules to add

```
- Stop when an always-on journey (login-<role>, mfa-password-only-refused) FAILs on the new app and PASSed on the
  old one. Do not explain it away with a passing smoke walk: on app A the smoke walk, the data diff and the log
  check all passed while MFA was off.
- Stop when the positive control does not catch the ui-landing mutant. The journeys can no longer fail.
```

## What the gate runtime cannot do (keep in mind when reading results)

- Seeds, data, association and outcome rungs need `mxcli oql --direct`, which answers "Action not found" on a
  runtime started through runapp / m2ee (no live-preview dev flags). Those rungs come out INVALID. Data stays the
  job of `diff.py` (gate item 3); journeys stay UI-only until the gate runtime is started with the dev flags.
- `run_journeys.py` patches its copy of the engine so `fill` reaches Mendix login widgets
  (`input.mx-name-<widget>`). `summary.json` records whether the patch applied; "NOT applied" means the runner
  changed upstream and the patch should be re-checked.
