# Heal (classify every failing row, heal the test, rerun only what is affected)

Why: a first run of the pipeline on a 10.24 to 11.12 app ended with 4 data FAIL rows, 54 journey FAILs and 513 INVALIDs.
Most of them were not the upgrade: the start of any app changes timestamps, a button exists only for a selected row, a
runner wrote no findings. A person had to read every row to find the two that were real. The heal step does that reading
and heals what belongs to the TEST. It never edits the app.

Pipeline step `heal`, between `journeys` and `diff` (`--from heal` resumes here, `UPG_HEAL=0` turns it off and the old
exit-11/12 stop of the journeys step returns). Script: `bin/heal.py`. Output: `work/heal.json` (every row, class,
evidence, heal, result), `work/heal.md` (short table), `heal-allow.txt` and `heal-log-allow.txt` (what was accepted,
each line carries its reason), `allow-effective.txt` and `log-allow-effective.txt` (your file plus the heal file; the
diff step passes these to the gate).

## The classes (every failing row gets exactly one)

| class | the evidence | the heal |
|---|---|---|
| startup-noise | the same check also differs between two starts of the SAME old app (`twin-old.md`, written by the step: a fresh copy of the frozen DB, old app started, snapshot, compared with `before.json`) | an allow line, printed as accepted, whose reason is that evidence |
| no-test-data | the page of a failing journey shows an empty list on the screenshot text | seed the same rows (3) into the old and the new database (`seed_pg.py`), rerun that journey on both |
| no-click-path | the generator found no path or role to the action | none: needs a hand-written journey. Counted, listed in heal.json |
| outside-call | the only reason the journey was not generated is an external call | `apimock.py` answers for the system on the old and the new app (same answers), `gen_journeys.py --standin` generates it, the apis rung checks the traffic |
| test-setup | the harness: a runner that wrote no findings (rerun on both apps), a button shown only for a selected row (a row-select step is inserted right before the click), a known harness log line (accepted with its written reason), a failure the old app has too | as named; a failure on both apps is listed, not healed |
| test-setup, seedname | the old app passes, the new one fails on an error dialog, and the new app's journey log names a SEEDED value as a missing entity (`Entity does not exist: s294x2`: `seed_pg.py` filled a String attribute that holds a model name with junk) | `bin/seedname_fix.py` makes the entity-name attribute a real entity (`System.User`) and its member attribute a real String attribute (`Name`) in the base of BOTH reruns; `work/seedname-set.txt` (lines `table.column = value  # reason`) overrides. The row is never silent: `heal-gate-notes.txt` / `gate-notes-effective.txt` carry an owner-facing line (below) |
| real-regression | the old app passes and the new one fails, rows or columns of the old data are gone, a new ERROR in the start log | none |
| likely-real | nothing above explains it, or a heal ran and the row stays | none |

## Seeded model names (behaviour change, owner-facing)

A Data widgets Combo box in the newer version loads its options when the page opens (it must show the caption of the
stored value); the older one loaded them when the dropdown opened. A configuration object whose String attribute names an
entity (an option source that calls `Core.getMetaObject(name)`) therefore fails on page open now. With seeded junk the
journey shows an error dialog whose backdrop (`.mx-underlay`) also blocks later clicks. That is a test-data cause exposed
by a real behaviour change. The heal fixes the data on both sides and writes the behaviour change to `heal-gate-notes.txt`;
the diff step passes `gate-notes-effective.txt` (the person's `gate-notes.txt` plus the heal's lines) to the gate, so it is
listed as "needs a decision": check production configurations with an empty or wrong entity name before go-live.

## Rules

- Heal the test, never the app. A row that may be a real defect is never accepted: it becomes one NEEDS-JUDGMENT item
  (exit 12 from the diff step) with options and a recommendation (`heal.py nj`).
- At most 2 rounds. Round 2 only runs when round 1 changed something; a row whose heal already ran is not healed again
  (it becomes likely-real if it still fails). A round that changes nothing stops the loop.
- No-test-data seeds both databases or neither: a seed on one side would be a difference of its own.
- A pass on the stand-in is never a plain PASS (gate exit 4, "PASS (on stand-in APIs)").
- The merge keeps the stored summaries as `summary.pre-heal.json` and lists the healed ids under `healed`.
- `heal-pre-diff.md` is the data diff the classifier reads (the heal step runs `diff.py` itself, before the gate).

## What the gate reads from it

`gate.sh` keys `HEAL_JSON` (prints the one-line `heal:` summary), `GATE_NOTES` (L56: every non-empty line that is not a
comment in `work/gate-notes.txt` is listed as "needs a decision" and counted in Progress), `SMOKE_BEFORE` plus
`SMOKE_REJUDGE=1` (L55: the smoke rung judges the stored `smoke-after.json`, no app) and `APIMOCK` (the apis rung).
The diff step sets all of them when the files exist.

## Build loop

`step_build` already loops on its own rows: every fixed repair row runs through `try_fix` (fixer, mx check again, kept
only when `checkdiff.py` says not worse, else undone), and an unfixed error ends in the exit-10 hand-off. What was
missing was a repeat: a fixed row can expose the code another row handles (L42). After the rows, the rows whose code is
still open (update-widgets for CE0463, design properties for CE6087) run again, at most `UPG_BUILD_ROUNDS` (default 2)
more rounds, and the loop stops at the first round that lowers no error count.

## Reshoot mode

`UPG_HEAL_RESHOOT=1 ... --only heal` reruns only the journeys the heal already closed (plus the likely-real rows) on the
old and the new app, with the stand-in running, and merges the fresh step shots into the compared `shots-<role>` folders.
Use it when the journeys screen pairs are INVALID because a healed row's shots only live in the heal folders (the heal
reruns `rm -rf e2e-heal-old/new` on every call). `heal.py reshoot-plan --work <dir>` prints the plan (plain ids and the
seedname ids). The smoke walker clears the same step's shots under the other suffixes before it writes a new one.

## Controls

`controls/lib/mkheal.py` builds a synthetic work folder with one failing row per class; the `heal-*`, `gate-heal-*` and
`proposal-testing-plan-*` controls run offline (no docker). Resume with the pipeline option `--from heal`.

## Test fixtures: stand-in broker and auth, test-setup rows, browser storage

Label every result that rests on these in the report: **"stand-in broker and auth; real broker and IdP to be checked at deploy"**.
They make pages testable that no pipeline run could open before. They never prove the real broker, the real identity
provider or real user data.

### NATS broker (a connector that dials out at startup or on save)

An app with the Mendix NATS connector shows a "NATS server connection error" dialog on pages that connect, on the old app and on the new
one. Without a broker those journeys fail on both sides and can only be classed BASELINE DEFECT (evidence lines in
`baseline-evidence.txt`). Two switches turn the fixture on: `UPG_HEAL_NATS=1 ... --only heal` (only the journeys with an evidence
line, a probe) and `UPG_NATS=1` (the journeys step and the heal step, every journey and every rerun, both apps):

- `bin/natsfixture.py up` generates everything under `<work>/natsfixture` (one test password; a self-signed server identity, a JKS trust
  store and key store, an NKey user from the app's own jnats jar) and starts container `<UPG_NAME>-nats` (official `nats:2`, TLS, NKey auth)
  on the runapp network. Nothing comes from or goes to a customer system.
- **Server side** (Java connector): the broker admits the NKey user on port 4222. The log of the app shows "connected to nats://...".
- **Browser side** (the connector's WebSocket client dials `wss://<WebsocketHostName>:<WebSocketPort>` with the signed in user's IdP token):
  the broker has a second listener, websocket with TLS, published on `127.0.0.1:18443` (`--ws-port` or `UPG_NATS_WS_PORT`). The
  certificate is self-signed for `localhost`; the test browser trusts exactly that key through `UPG_BROWSER_SPKI` (`natsfixture.py spki`,
  passed to Chromium by `vendor/e2e/helpers.js` as `--ignore-certificate-errors-spki-list`), nothing else. The broker runs with
  `debug: true`, so `docker logs <UPG_NAME>-nats` shows each browser client ("Client connection created", the websocket one).
- **Stand-in auth**: the websocket listener maps a client without a token to a test user (`no_auth_user`). The test browser signs in
  with a local password, so the app sends no IdP token. A real token is never validated; an app whose browser always sends a token
  needs an auth callout stub, which this fixture does not have.
- `natsfixture.py seed` points the default `ConnectionData` rows of a database copy at the broker (server host and port, websocket host
  `localhost` and port). `fixture_db` calls it for every journeys and heal copy, the same on the old and the new side.
- the three constants (`NATS_CertificateStorePath`, `NATS_CertificateAlgorithm`, `NATS_AUTHCalloutAccount`) are merged into the constant
  overrides of those runs only, never into `env-values.json`, so the constants rung is untouched.
- `heal.py nats-plan` picks the journeys of the `UPG_HEAL_NATS` mode: every one with a baseline-evidence line, plus the seedname rows.
- `natsfixture.py down` removes the container.

### Test-setup rows (`work/test-setup.sql`)

Some pages need a row the app writes itself in real use, for example a per-user settings row created at the first sign-in through the
identity provider. The test users come from `smoke_users.py`, so the page raises an error ("Change object ... should not be null")
on the old app too. Put the row in `work/test-setup.sql` (plain SQL, one transaction, ids as `max(id)+n` of the same table, a comment
for each row). `bin/setup_sql.py` applies it to the database copy of every journeys and heal run, the same file for old and new, never
to the frozen baseline. Read the app's own microflow first (what does the page retrieve, which key does it match on) and name the
reason in the file.

### Stored sign-in token (`work/test-setup-users.sql`, `UPG_NATS_WS_TOKEN`)

An app that calls its own back end with a sign-in token it stored at the first real login (OIDC token row linked to the user) never makes
the call for a test user: no token, so the list stays empty and the NATS client falls into an "Authentification error" dialog. Put
rows for the test users in `work/test-setup-users.sql`; the pipeline applies it right after `smoke_users.py` made the users (the
`fixture_users_db` hook, old and new alike). A browser client then sends that token to the websocket, which a broker with NKey users
cannot check: with `UPG_NATS_WS_TOKEN=<same value>` `natsfixture.py up` starts a second container `<prefix>-natsws` that owns the
websocket listener and accepts exactly that token. Stand-in only; nothing validates a real token.

### Recorded stand-in bodies (`work/apimock-recorded/`)

The stand-in answers with a generated body. When a page needs real-looking content (a valid time zone, a mapping that is not null),
put a recorded body in `work/apimock-recorded/<endpoint id, non [A-Za-z0-9._-] as _>.json`; the pipeline passes the folder to
`apimock.py serve --recorded` when it exists. Answers are static per endpoint.

A sample captured from a real system can carry fixed-width padding (`"Wkcenter": "START "`). When the app copies such a value into
a URL query (a REST call built from a stored work centre), the Mendix runtime stops before sending with
`Illegal character in query at index N` and the microflow's error handler logs only a null message. Symptom: the call never reaches the
stand-in. Find it by setting the `ConnectionBus`, `REST Consume` and `MicroflowEngine` log nodes to TRACE (admin API `set_log_level`;
`Microflows` is not a node) and reading the exception; fix it with a recorded body whose value is trimmed (same body on both apps).

### Browser storage (`UPG_BROWSER_STORAGE`)

State a person's browser keeps (a stored station id, a chosen site) is missing in a fresh test browser, and a dialog asks for it. Set
`UPG_BROWSER_STORAGE='{"Key":"value"}'`: `vendor/e2e/helpers.js` seeds those localStorage items when the app has not set them. Same
value on both apps; match it with the row in `test-setup.sql`.

Limit found on a field app (run2): with the broker, the websocket listener, the setup row and the stored id, the NATS dialog, the
workstation dialog and the setup error are gone on both apps and the Task List page opens. Lists that the app fills from a message feed
or from an external system stay empty (no stand-in data), so journeys that need a row in such a list still fail on both sides.

### Parallel runs, browser size, file check (test-gap work)

- Two runs on one machine need their own names and ports: `UPG_NAME` and `PORT_OFF` for the apps, `UPG_NATS_NAME` (default `UPG_NAME`) and `UPG_NATS_WS_PORT` for the broker, `UPG_APIMOCK_PORT` (default 9290) for the stand-in REST server. Check a run's `env.sh` before a second run starts: a copied work folder keeps the first run's ports.
- `smokewalk.js` and `filecheck.js` open the browser at 1440x900 with that screen size, like `run_journeys.py`. At the Playwright default of 1280x720 an app that redirects narrow screens to its tablet profile (`screen.width <= 1280`) lands on the tablet page and the walk judges the wrong page. `UPG_BROWSER_STORAGE` (a JSON object) seeds localStorage before the first page, for apps that read a workstation id there.
- `filecheck.js` uploads one file as a role user (`mx.data.saveDocument`), reads it back through `getDocumentUrl` (a Promise on the new client) and compares sha256. Run it on the old and the new app, then `node filecheck.js --compare old.json new.json`. A role without create right on the entity cannot upload; use a role that has it.
- The REST stand-in answers from recorded bodies in `apimock-recorded/<call id>.json`. A wrong length for a String attribute or an empty format setting in a recorded body fails the import quietly (a 200 with null content); read the app log for the mapping error before judging the call.
