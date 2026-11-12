# Journeys (browser checks of behaviour the data diff cannot see)

Why: on app A (E1) the smoke walk, the data diff and the log check all passed while MFA was off. A journey is a
scripted browser path with an expected outcome; the always-on set catches that class of fault.

Scripts in `$B`: `impact_map.py` (what changed between two MPRs), `gen_journeys.py` (journeys from the impact map),
`run_journeys.py` (runs the shared journey runner from a COPY in `--work`). Needs Playwright:
`PLAYWRIGHT_NODE_PATH` (default `~/mendix-playwright/node_modules`) and the engine dir `TOOLKIT_E2E` (default
`upgrade-toolkit/vendor/e2e`, a pinned copy of mxcli-project-toolkit's `project-tests/e2e`, see its `VENDORED.md`;
read only, copied, never edited). Set `TOOLKIT_E2E` to a live clone to test a newer engine. The record of how this was
built is `research/e2e/`.

## Test users (users.json, local, never committed)

`{"<Role>": {"user": "...", "pass": "..."}, "_mfa": {"user": "...", "pass": "..."}}`: one user per user role, plus
when an MFA module is present one user who HAS an MFA type AND an ordinary user role (without a role a refused
login looks the same as a refused-by-MFA login, and the MFA journey passes for the wrong reason; E2E-6).
Set passwords (`{BCrypt}` plus a `$2a$10$` hash) on the DB copy AFTER the app started: in DTAP mode D the runtime
re-syncs demo users at start. `smoke_users.py <db> --roles <Role,...> --apply` does the per-role users.

Journey databases (the one naming rule; T1-27, T2-15, T6-16): every journey run gets its own `createdb -T X_frozen
<name>` copy. smoke_users.py accepts a copy whose name starts with `fx_` or contains `_copy` / `_smoke`
(`X_smoke_jbase`, `X_smoke_jold`, `X_smoke_jnew`), or any copy the run ledger lists. To keep another name, record it
first and pass the ledger:
`snapshot.py --ledger $W/db-ledger.txt --mark-used X_jold --use journeys`, then
`smoke_users.py X_jold --ledger $W/db-ledger.txt --apply`. A `*_frozen` name is always refused; `--any-db` is not the
way round the rule.

Start every app used for journeys with `UPG_SESSION_TIMEOUT=30000` (runapp.py sets SessionTimeout and
ClusterManagerActionInterval): a trial runtime allows 6 sessions, guest sessions count, and a full cap shows up as
"login form did not render".

**SSO login pages (T2-7, N1-4).** If the deployment `login.html` redirects to an external IdP (Opcenter UMC `./auth/v1/login`),
journeys and smoke walks cannot sign in. `runapp.py` detects this (`--login-override auto`, the default; env
`UPG_LOGIN_OVERRIDE`), replaces `web/login.html` with the app's own `login.old` / `login-stock.html` for old AND new alike (no stock page: left
as it is and sign-in journeys are INVALID; the toolkit never invents a login form),
prints a `HARNESS CONDITION` line and writes `run/<name>/harness-login-override.txt`. Quote that line in the scorecard: the
app's own SSO sign-in is not exercised. A normal Mendix login page is never touched; `--login-override off` disables it,
`--login-override <file>` forces a page. Do not hand-copy login pages over the deployment any more.

**Windows-path harness files (T2R3-5, B4T2-13).** An add-on that builds a Windows path at runtime (EXFN_Authentication
reads `run/<name>\model\metadata.json`) fails with FileNotFoundException on Linux. `runapp.py` creates that file for
old AND new (`--harness-file auto`, the default; env `UPG_HARNESS_FILE`): a copy of the unpacked app's own
`model/metadata.json`, removed and recreated on every start. It prints a `HARNESS FILE` line and writes
`run/<name>/harness-files.txt`; quote it in the scorecard. `--harness-file model\metadata.json,web\x.json` lists other
app-relative files (a file the app lacks stops the start), `--harness-file off` creates none. Do not copy it in a PRE any more.

## At baseline (old app, always-on set)

```
python3 $B/impact_map.py old.mpr old.mpr --out $W/impact-base.json
python3 $B/gen_journeys.py $W/impact-base.json --out-dir $W/journeys-base --roles-with-users <Role,Role,...> [--create $W/create-spec.json]
python3 $B/run_journeys.py $W/journeys-base --label before --port <app> --admin-port <admin> --admin-pass <m2ee> \
    --users $W/users.json --work $W/e2e-base --pause 50
```

The engine signs in on `--login-path` (default `/login.html`, as smokewalk.js), not on `/`: an anonymous home that is
a login PAGE (FSM `General.Login_Web`, a custom Atlas login template) takes the credentials and never signs in (T8-9,
T7-10). A login counts only when no password input is visible, the URL is not a login URL and the role's READY
selector (or `.mx-navigationtree`) is present; the old check (`.mx-page` present) passed on the login page itself.
Pass `--login-path /` only for an app without `login.html` whose anonymous home renders the standard login form.

The always-on set: `login-<role>` per role with a test user, `mfa-password-only-refused` when an MFA module is
present, `sign-out` (generated from the role menu's sign-out item, else from a sign-out item in a menu bar of the home
layout or a layout sign-out button, T2-11; an item under an icon-only menu entry with no caption is opened by clicking
the rendered item names in turn, `menuBar2-1` then `menuBar2-1-1`, T2R3-4; a todo when no tested role has one, E5b-6).
Exit 0 = every journey PASS on the old app. A FAIL here is a baseline defect or a bad journey: fix or drop it now,
never carry it into the gate.

What the generated journeys assert (content, not only "the page rendered"):
- login: a visible element of the home page itself, never a layout widget or a conditionally visible one (E5b-9,
  E5b-23: a hidden layout container FAILed healthy apps). Guards come only from the Name of a widget in the page's own
  widget tree that renders once: never a page parameter or variable (T4-7), a snippet call (T2-10), or anything inside
  a list view, data grid, template grid, gallery or pluggable widget (T1-25: a button in a task list row rendered only
  with tasks), under a conditionally visible widget, under a widget whose Atlas "Hide on" includes Desktop, or on a tab
  page the tab control does not show first (G-3: `dataView2` on the "Forms" tab FAILed the old app). Preference: the
  page title, then the outermost data view, then a distinctive name (B2-2: a data view can be in the DOM with zero
  height, and the engine's ready check is an instant visibility check). An impact.json written before these rules is
  re-checked on the model and the pick replaced (the run prints `note: login-<role>: landing guard X is not a widget
  that renders once ...` or `... is a data view and the page has a title widget ...`).
  Plus the role menu captions when the home layout renders the role's navigation profile; when it renders no menu (a
  popup layout, an MFA QR page) or another menu (a Phone/Tablet layout with its menu document, T6-14), the home page's
  own texts instead (E4-12, E5b-10): only texts that are on screen when the page opens, never a placeholder, tooltip,
  an action's message, or the page Title unless a title widget or a popup header shows it (N1R2-3: "Type search text
  here..." and "Home" FAILed the old app), and none under a hidden widget or tab page. Other roles' captions are asserted absent only when the model proves they cannot
  be on screen: the home layout renders the profile, the caption is no text of the home page, its layout, snippets or
  layout menu documents (any case; T4-6 "Buffer" was a Kanban card label), and every target of the caption has user
  roles the model can read (T2-10: the Administrator's own "Client Configuration" sits in a protected add-on). A
  microflow home never proves it. Dropped captions are listed in `_textAbsent_omitted`: when unsure, no assertion.
- a role home that is a microflow is walked by `login-<role>` (it runs at sign-in): when every page the microflow
  shows has a landing widget (on both models, as menu targets), the journey's ready guard is that widget (a union for
  several pages), it asserts the error texts absent and carries `"closes": ["home:<microflow>"]`; plan.json lists the
  item as `covered` with `closed_by`, and the run reports it with the login journey's verdict (T4-8, T6-14). Without
  such a widget the bare `.mx-page` plus menu captions would also pass on an error or fallback page, so the journey
  does not close it (`_closes_not`) and the home stays a todo.
- menu journeys: the target page's own element and texts. The guard is a widget that the OLD page has too (same name
  and type, never a snippet call; inside the called snippet when the page itself has none), because before-picked
  runs on the old app (E6-18: SAML20 4.x `snippetCallWidget1` never rendered on the old app). No common widget:
  `.mx-page` with a note. A microflow target that shows more than one page (E7-2: a team detail page with a team,
  the overview without) gets a union guard of every branch's widget (`_branches` in the journey); when a branch page
  has no usable widget the item is a `todo` with `_branches`, never a guess at the first page.
- Anonymous roles (Guest): listed in plan.json `skipped` as "anonymous role", so the run prints INVALID instead of
  nothing (E4-11). Walk the anonymous home by hand or accept the INVALID in the report.
- API-only roles (home page = the login page, B2-3: FSMAPIConsumer): listed in `not_browser` as "API-only role" (shown in
  the report, never blocking: no browser journey could ever clear it) and used for no other journey: a signed-in user sees the login page again, so no browser journey can prove it (a
  login journey for it FAILed with a wrong "licence session cap" cause). Prove it through the services it calls.
- plan.json also lists `covered` (a role home that a login journey already walks) and `unreachable` (a page no
  entry point reaches through any chain of callers). The run prints them as INFO: listed, not blocking (E4-31,
  E5b-11, E5b-22). Real `todo` items stay INVALID; a `no-click-path` action you can prove dead in the OLD UI is
  `UNREACHABLE` (PASS*, its own count) with an evidence line, see "Coverage and honesty" (B4T2-14).

Once per toolkit version: add `--positive-control`. Every ui-landing row must be PASS (mutant caught). A miss means
the instrument cannot fail: stop. The run exits 0 when every ui-landing row is PASS and no row FAILs; it prints
`CONTROL MISS` per miss and exits 1. Rungs the journeys declare nothing for (trace, data, outcome without oql) are
counted as INFO UNPROVEN: they stay INVALID in the gate, but they are not control failures (E7-12).

create-spec.json, once per app: `{"role", "nav": {"group", "item"}, "newButton", "fields": [{"widget", "value", "attr"}],
"saveButton", "entity", "ready", "textPresent": [...], "textAbsent": [...]}`. Without it create-and-save stays a todo,
which is INVALID, never covered. `textPresent` is the saved value as the grid shows it, `textAbsent` the validation
messages: a ready selector alone was satisfied by the grid BEHIND a popup whose save was refused (E4-14, E5b-12), and
gen_journeys warns when the spec has no textPresent. Put `${RUN_ID}` in the field value and in textPresent: it is
unique per run, so a reused database cannot satisfy the check with a row from an earlier run (E5b-25). The data rung
(row count +1) is left out unless `--data-rung`: it is asked through the app's Postgres (`run_journeys.py --psql`, see
"Data" below), since no runapp runtime answers `mxcli oql --direct` (E5b-11). Name the attribute each field writes
(`"attr": "Alias"`): with `--data-rung` every such field adds an own-row check, `COUNT(*) FROM <entity> WHERE <attr> =
'<value with ${RUN_ID}>'` = 1, so the row judged is this run's row and not one an earlier run left (E2E-9); without any
`attr` gen_journeys warns that only +1 is checked.

## At the gate (new app, on a copy of X_frozen)

```
python3 $B/impact_map.py old.mpr new.mpr --out $W/impact.json --md $W/impact.md
python3 $B/gen_journeys.py $W/impact.json --out-dir $W/journeys --roles-with-users <same roles> [--create ... --data-rung]
python3 $B/action_inventory.py old.mpr --out $W/actions.json
python3 $B/fixture_check.py $W/journeys --psql "docker exec -i mig-pg psql -U mendix -d <old db>" --out $W/fixture-check.json
python3 $B/run_journeys.py $W/journeys --label before-picked ... --psql "docker exec -i mig-pg psql -U mendix -d <old db>" \
  --actions $W/actions.json
python3 $B/run_journeys.py $W/journeys --label after ... --psql "docker exec -i mig-pg psql -U mendix -d <new db>" \
  --compare $W/e2e-before-picked --shot-accept $W/shot-accept-<rung>.txt [--effect-accept $W/effect-accept-<rung>.txt] \
  --actions $W/actions.json [--baseline-evidence $W/baseline-evidence.txt]
```

Every run prints the coverage line under `journeys:` (see "Coverage and honesty" below); with `--compare` its rules
decide whether rung 8 can be PASS at all.

### Data: the app's Postgres, not mxcli (E2E-9, E5b-11)

`--psql CMD` (or `UPG_PSQL`; gate.sh `JOURNEY_PSQL`) is a command that runs SQL from stdin against the database of the
app under test: the old app's for before-picked, the new app's for after. Any psql that reaches it works
(`psql -h localhost -p 5432 -U mendix -d <db>`, with `PGPASSWORD=` in front when needed; gate.sh masks it).
- run_journeys.py first reads the mapping from `mendixsystem$entity`, `mendixsystem$attribute` and
  `mendixsystem$association` (bin/pgmap.py; never guessed from names: inheritance through the generalization's table,
  association storage as a column or a table, names Postgres cut at 63 bytes) and prints `data psql: pgmap: N entities,
  ...` (summary.json `data_backend`). An entity, attribute or association the mapping does not hold is refused, and its
  check is INVALID. Check it by hand with `python3 $B/pgmap.py sql "<OQL>" --psql "<CMD>"`.
- Without `--psql` the run prints `data INVALID: no --psql / UPG_PSQL ...`; when the database does not answer,
  `data INVALID: the database did not answer the mapping query: <reason>`. Either way the seeds, data, association
  and outcome rungs are INVALID with that reason (per role in summary.json `data_errors`), never PASS.
- The effect record: before and after every step the run counts the rows of every mapped table (runtime housekeeping
  left out: System.Session, TokenInformation, ScheduledEventInformation, the queue tables, SessionLog*, and
  System.XASInstance / TaskQueueToken, re-registered at every start so their count follows how often the copy was
  started, not the journey (B4N1-10); the regex is pgmap.py `NOISE`, overridden with `UPG_EFFECT_IGNORE`, applied again
  at compare time so an older record is judged the same way) and stores what changed (summary.json journeys `effects`: per step
  `{"changed": {"Shop.Item": 1, ...}}`, or `{"invalid": reason}` when a count could not be read). A step that changed
  nothing records `{}`: measured, not missing.
- With `--compare`, a journey that PASSes on both runs must have changed the same rows on both. A difference is
  `EFFECT REVIEW` (a failure, exit 1: a save that wrote nothing, or wrote to another table, is T2-1) until each
  differing `<journey> step<n> <key>` matches a line `pattern # reason` of `--effect-accept` (`PASS*`); an effect not
  measured on either run is `EFFECT INVALID` (exit 3). Every compare prints `effects: N PASS, N PASS*, N REVIEW, N
  INVALID` (summary.json `effects`); cite it at the gate next to the screens line. Run before-picked with `--psql` too,
  or every effect is INVALID.
- A plan row closed by another journey (`todo closed by sign-out-hand`, `covered: closed by create-save`; summary.json
  `closed_by`) was walked as that journey: its effect is judged on the closer's record on both runs, and the detail
  says `(the record of <closer>, which closed it)` (B4T2-15: these rows were EFFECT INVALID "no effect record" although
  the closer had one). The closer without a record is still EFFECT INVALID.
- Scope assertions to the run's own row: `${RUN_ID}` in the typed value and an own-row check on it (create-spec
  `attr`, or a hand-written `data.oql` with `"expect": 1`). Counting the whole table lets a row from an earlier run
  satisfy the check.

Run before-picked on its own fresh copy of X_frozen, as the after run is: a journey that creates rows (create-save
writes a row per run) on a smoke database that already holds earlier runs gives a grid screen that differs for a
reason the upgrade did not cause (E7-15). The old and the new app may be up together for these probes when memory
allows: give the second one another `PORT_OFF` (and its own database), so the probe phase needs no app switches
(E6-21); the heavy lock still serialises the starts.

`--compare` takes the old run's work folder (one label inside), its label folder (`$W/e2e-before-picked/before-picked`)
or that folder's summary.json, and checks the path before anything runs (E4-22). Paths may be relative (E5b-8).
With `--compare` every screenshot is paired with the old run's screenshot of the same step (shotdiff.py): a journey
that PASSes but whose screen changed or lost content is `SCREEN REVIEW` and counts as a failure until the pair is
accepted with a reason in `--shot-accept`; a journey with no screenshot now is `SCREEN INVALID`. Every compare prints
`screens: N PASS, N PASS*, N REVIEW, N INVALID` (also in summary.json `screens`): cite it at the gate. Accept lines
pin the NEW image (`pattern @sha256:<hash> # reason`, the hash is on the pair's line), one accept file per rung
(steps/gate.md 9); a screen with per-run content takes a masked pin (`@mask:x,y,w,h @sha256:<masked hash>`, B4T2-17). To judge the screens
of an existing run again without the browser (after writing accept lines): `run_journeys.py ... --label after --work
<same work> --compare <old> --rejudge`.

Verdicts (printed as `journeys: N PASS, N FAIL, N INVALID[, k PASS* (baseline defect)][, u PASS* (unreachable in the
OLD UI, evidence checked)]`; an evidenced baseline defect is counted as PASS*, not in FAIL, so the headline agrees
with the `defects:` line; a defect without evidence stays in FAIL, B4N1-13):
- PASS on new. FAIL on new tagged `REGRESSION` (PASS on old) is a gate FAIL. `NOT IN BASELINE` means run it on the
  old app too. `BASELINE DEFECT` (did not pass on old) needs checked evidence (E2E-11, below): `BASELINE DEFECT
  FIXTURE|OLD-APP|FLAKY (...)` is PASS* and listed; `BASELINE DEFECT (before FAIL): <why>` has none and is INVALID,
  also when it now passes on new (`, passes on new`: listed for review, the old app is no expected result there).
- SCREEN REVIEW on a PASS journey: open both screenshots; accept with a reason or treat as a regression.
- INVALID: a role in plan.json `skipped` (no test user, anonymous), a `todo` item, a journey that could not be judged.
  INVALID blocks DONE; it is never read as PASS. Not walked is not passed. INFO (`covered`, `unreachable`) does not
  block.
  S (L3): with guest access on, plan.json `anonymous_role` names the anonymous role and one process run as it must PASS:
  the line `anonymous process: P of 1 required (role <Guest>; ...)` prints with P, and 0 blocks under either bar. An
  always-on journey that is INVALID blocks under `--bar processes` as it does under the default bar.
- plan.json `not_browser` checks (start log "active" lines, scheduled events, services, vendor page screenshots
  old vs new) are done by hand or by logdiff and reported with their outcome. A `module-pages` check lists its pages
  in `targets`; a page that no menu item, home page or caller chain reaches is in `no_entry` and the run reports the
  check INVALID ("no entry point: NOT PROVED") until you open it by hand and write the outcome down (E6-20).
- EFFECT REVIEW on a PASS journey: the two runs changed different rows; read the `effect` detail, then fix or accept
  with a reason in `--effect-accept`.
- Exit: 0 all PASS (PASS* when a line says `N PASS*`: evidenced baseline defects, a waived denominator); 1 a FAIL (with --compare: a REGRESSION, NOT IN BASELINE, an open SCREEN REVIEW or EFFECT REVIEW);
  3 INVALID only: nothing FAILed, but a journey, a BASELINE DEFECT without evidence, a SCREEN INVALID pair, an EFFECT
  INVALID journey or a broken coverage rule (`  coverage INVALID: ...`) is INVALID (it prints `verdict: INVALID only` and names the journeys that fail on the OLD app: drop or fix them, then run before-picked again; N1R2-8,
  T2R3-11). Only a journey that did not PASS on the old run is named there: one that PASSed but whose OLD screenshot
  is unusable (STUCK, LOADING, missing) is listed apart under `old screenshot:`: look at both images and accept with
  `--shot-accept`, or repair the wait; do not drop it (B4N1-12); 2 the run could not start (bad `--compare` path,
  arguments, or a journey file that is empty or not a journey: the file is named, nothing runs, B4T2-18). The gate
  shows 3 and 2 as INVALID.

## Action inventory (E2E-8): the denominator, from the old model

```
python3 $B/action_inventory.py old.mpr --out $W/actions.json
```

Lists every button and clickable container (cards included: T2R3 HANDWORK 14, the home-page cards no journey was
generated for) whose action creates, saves, deletes, calls a flow, opens a page, a task or a workflow, or completes a
task outcome. Per action: the click path a role can walk (`as <role>: menu|home ... -> page -> click widget`; a page
or flow that role may not open is not a hop), the roles that may both open the page and run the flow, the kind read from
the flow body (commit, create, delete, workflow-call, status-change, task-outcome, ...), the form fields with their
attribute types, and the todo reasons a generator cannot get past (`combobox`, `page-parameter`, `external-call`,
`no-click-path`, `no-role`, `unknown-action`). The last line is the denominator; cite it:

`actions A found · by kind ... · todo T by reason ... · unknown U · not actions N (cancel, close, link) · excluded docs X`

- Unknown is reported, never dropped: an action type the tool does not know is listed as kind `unknown` with todo
  `unknown-action`; a flow in a protected add-on (or System) makes the kind a lower bound; a page only an unreadable
  module opens gets "the click path is unknown, not absent". A model that cannot be read exits 1, never an empty list.
- `no-click-path` is a finding to look at, not noise: on T1R2's model Vendor_Select is allowed to InvoiceProcessor only
  while its only opener sits on the PurchaseOrderCreator task page.
- Field runs: T2 Opcenter EX Starter Kit 2.1.0 `actions 34 found` (the four HW14 cards with a path; create-spec.json's
  newButton1/actionButton1 found, kind and path unknown behind the EXFN_Authentication add-on); Purchase Request 1.9.0
  (T1R2) `actions 196 found`, every one of the run's 12 todo pages accounted for; customer `actions 21 found`.
- Proof: controls `action-inventory-*` on a golden captured from the real Starter Kit model (controls/lib/capture_units.py),
  and `field-action-inventory-customer-pass`.

## Journey scope: only what is used and reachable

```
python3 $B/journey_scope.py $W/actions.json --model old.mpr --localedits $W/localedits.json --code-root app/ \
    --out $W/journey-scope.json --md $W/journey-scope.md [--usage $W/usage.json] [--vendor MOD,MOD]
python3 $B/gen_journeys.py ... --actions $W/actions.json --scope $W/journey-scope.json
```

The inventory lists every button in the model; most of an app's no-click-path actions are not a testing gap. One class
per action, the first that holds:

| Class | Holds when | Gate |
|---|---|---|
| reachable-with-path | the inventory found a click path | journey generated and run |
| marketplace-module | no path, host in a Marketplace module (FromAppStore flag, localedits.json, `--vendor`) with no domain or logic edit and no UI edit of the host or of a page showing it; an unknown edit state (package not readable) counts, with "edits unknown" in the reason | out of scope, INFO |
| unreachable | no route from a menu item, home page (any profile and role), login page, page with a URL or workflow task page, through page, snippet, layout, microflow and show-page references; Excluded documents break a route (they are not in the app); a name of the host or of any document that leads to it in the app's Java or JavaScript (not the generated `proxies/`) keeps it reachable | out of scope, INFO |
| no-role | no user role may open the page and run the flow | out of scope, INFO |
| reachable-no-path-yet | in the graph, a role may run it, the generator could not build the steps | stays INVALID: record a click path, or test at deploy |
| unused (only with `--usage`) | in scope, but the usage file shows neither its page nor its flow | out of scope, INFO |

With `--scope`, gen_journeys.py writes plan.json `out_of_scope` (id, action, class, why) next to `skipped`: generated +
skipped + override + out_of_scope = actions found (asserted). run_journeys.py lists those rows as INFO (one summary line
per class, the rows are in summary.json), leaves them out of the coverage denominator (`coverage B/(A - out of scope)`),
and adds ` · M out of scope, INFO (class n, ...)` to the coverage line. Out of scope is never INVALID and never PASS.
A marketplace-module action that HAS a path keeps its journey: an updated module can change behaviour.
Without `--scope` nothing changes. usage.json format: `{"period": ..., "source": ..., "pages": {"Module.Page": n},
"microflows": {"Module.Flow": n}}`; see the docstring of journey_scope.py for where the counts come from.
Proof: controls `journey-scope-*`.

**Menu hops (click-paths).** A layout's side bar, a top menu bar or a snippet's menu bar shows a menu document
(`Menus$MenuDocument`); its items open pages and run flows. They are not widgets of a page, so a chain that goes through
"Activities", "Settings" or a profile popup had no click path. action_inventory.py now holds them as hops (not as actions
of their own, so the action count does not move): the BFS climbs through every menu item a host shows, and the path
carries `{"click": <menu bar widget>, "menu_item": <position>, "caption": ...}`. gen_journeys.py turns that hop into
`{"do": "menuitem", "widget": <bar>, "nth": <position>}` (journey-verbs.js: `.mx-name-<bar>-<nth>`, so an icon-only item
with no title works too). Only top-level items; a nested item needs its parent opened first. On the field run this moved
105 of 303 `reachable-no-path-yet` actions to a journey. Proof: controls `menuhop-*`.

`click_causes.py actions.json --model old.mpr --scope journey-scope.json [--out causes.json] [--md causes.md]` says why the
rest still has no path: per host page, what opens it (a flow, a snippet of a page that is itself dynamic, a data-driven
popup). Read only; the work list for a recorded click path.

## Generated action journeys (E2E-10): one per action

```
python3 $B/gen_journeys.py $W/impact.json --actions $W/actions.json --out-dir $W/gen [--create create-spec.json] \
    [--roles-with-users A,B] [--data-rung]
```

Adds to the always-on set (login, menu, sign-out journeys are made exactly as before) one journey `act-<action id>`
per action of `actions.json` that has no todo, walked as the role the inventory found the path for. N3-21 had 7
journeys for a 31-page app; on the Purchase Request 1.9.0 model of T1R2 (N3's Marketplace app, another release: 55 pages) the impact map
alone still gives 7, and `--actions` adds 125.

- Steps: the entry (role home, or the menu item by caption), one step per click of the path, each guarded by the widget
  the next click needs, then the action step: fill the form when the action writes, click, confirm when the action
  asks. Inside a list: `row` clicks the first row (a row on-click, or a classic grid's selection before a control-bar
  button that is not a create); a button repeated in each row is clicked in the first row.
- Values, by attribute type: String `U-${RUN_ID}-n` (unique per run; `U<n>` when the attribute is too short, then no
  own-row check), Integer/Long `n`, Decimal `n.5`, dates 15 January 2026 in the picker's format (en_US order for
  Date and DateTime: the test user's language must be English, stated in `_assumes`), enumeration drop-down its first
  value's caption, reference drop-down its first option. Everything else is not filled and listed in `_unfilled` with
  the reason: hidden (conditional visibility, a later tab page; a confirmed process may fill a conditionally visible field when an earlier step of the same process opens a task, PRF-1), read-only, conditionally editable, check boxes (no
  value is safe: one is System.User.Blocked), radio buttons, reference sets, file uploads, comboboxes, Form-mode
  reference selectors, an attribute type the model does not tell.
- Data: with `--data-rung`, each filled String field with a known attribute adds the E2E-9 own-row check
  (`COUNT(*) ... WHERE <attr> = 'U-${RUN_ID}-n'` = 1) when the action commits, as a create-spec field with `attr` does.
- Guard: the target page's landing widget for open-page and create; for save, the widget that opened the form; for a
  flow `.mx-page` with `_guard` saying it is weak (the own-row check and the old-vs-new comparison carry those).
- Todo actions are `skipped` entries in plan.json, one per action with `reasons` and `why` (INVALID in the gate), and
  so is an action whose role has no test user or whose path starts at the login page, in another navigation profile or
  at an icon-only menu item. Nothing is dropped: generated + skipped + override = actions found, and the plan's
  `actions.line` says so: `actions A found · G generated · O by --create override · S not generated by reason ...`.
- `create-spec.json` is an optional override that wins per action: the actions it walks (its `"action"`/`"actions"`
  ids, else its newButton's create and the saveButton on the page that create opens) get no generated journey; they
  are `covered` with `closed_by: create-save` and the create-save journey `closes` them. On T2 it covers newButton1 and
  actionButton1, two actions the inventory could not reach (their path runs through the protected add-on). A spec that
  matches no action is kept, with a warning. With `--actions`, a missing `--create` is no longer a todo.
- Open: deletes (`_destructive`) remove the first row they are given, so a later journey of the same role can miss it;
  the run order inside a role folder is the file order. A flow that opens a page is guarded by `.mx-page` only. The
  `row` and `select first` verbs have not run on a live app yet.
- Field runs (E2E-10), `actions.json` from action_inventory.py on the real models: T2 Opcenter EX Starter Kit 2.1.0
  34 found, 16 generated, 18 not (no-click-path 18, no-role 4; with T2R3's create-spec 16 + 2 override, 16 not); Purchase
  Request 1.9.0 196 found, 125 generated, 71 not (no-click-path 71, no-role 21); customer 21 found, 5 generated, 16 not
  (combobox 6, external-call 1, no-click-path 14, no-role 5). Every generated file parses and uses only verbs the
  patched engine knows.
- Proof: controls `gen-actions-*` on the captured Starter Kit golden and `field-gen-actions-customer-*`.

## Coverage and honesty (E2E-11): rung 8 counts against the model, not against what survived

Every run of run_journeys.py prints, under `journeys:`, and stores in summary.json `coverage`:

`actions A found · G generated (T todo: <reason> n, ...) · B pass on baseline (D defect) · N pass on new · R regression · coverage B/A (p%)`

- A is the length of `--actions actions.json` (the inventory above, of the OLD model). G counts the actions a journey
  names: a generated journey carries `"action": "<id>"` (gen_journeys.py `--actions`), a hand-written one may list
  `"covers": ["<id>", ...]`. T is every other action, by the first word of its first todo reason (`no journey` when the
  inventory has none). B and D are judged on the baseline (`--compare`; without it, on this run), N and R on the new
  run. An action is PASS only when every journey naming it PASSes. Coverage below 100% is reported, not a verdict.
- No `--actions`: the line reads `actions ? found · G journeys (todo unknown) · ... · coverage ? (no actions.json:
  coverage unknown)` and counts journeys. With `--compare` that makes rung 8 INVALID. When there is honestly no model
  to inventory, `--no-actions "<reason>"` (gate.sh `ACTIONS_WAIVE`) prints `coverage: 1 PASS* (no denominator:
  <reason>)`: never better than PASS*. Decided conservatively: a rung whose size is unknown cannot be green.
- The journey set is pinned: a live run stores `journey_set` (sha256 over every `journeys/*/*.journey.json`, path and
  bytes, and plan.json; plus each journey's action ids) in summary.json. With `--compare`, a baseline without the hash
  (a run of an older toolkit) or a hash that differs from this run's is INVALID: run before-picked again on this set.
  A journey edited after the baseline, or added, or dropped, is a different instrument.
- `--compare` makes these INVALID (each printed as `  coverage INVALID: <why>`, exit 3, the gate row cites them): no
  denominator and no waiver; the hash rules; journeys naming action ids that are not in actions.json (stale inventory);
  G = 0 ("instrument not measuring": no journey names an action); D/G over 30% ("instrument not measuring", evidence or
  not: a set that fails that much on the OLD app measures the fixture, not the upgrade); a baseline defect without
  evidence.
- Evidence (`--baseline-evidence FILE`, gate.sh `JOURNEY_EVIDENCE`), one line per journey (fnmatch), paths relative to
  the file, checked by the tool, never taken on its word:

  | Class | Line | Holds when |
  |---|---|---|
  | FIXTURE | `<journey> FIXTURE fixture-check.json # note` | fixture_check.py lists the journey as EMPTY (a seed that ran and returned nothing; a fault is no evidence) |
  | OLD-APP | `<journey> OLD-APP <log or screenshot>[:line] # note` | the file exists, and the line when given (the old app's error) |
  | FLAKY | `<journey> FLAKY <rerun1> <rerun2> # note` | two reruns of the baseline: the journey PASSed on one and not on the other |

  | UNREACHABLE | `<plan row> UNREACHABLE actions.json [<Module>=<add-on file or folder> ...] [model=<old .mpr>] # note` | for a `skipped`/`todo` plan row only (B4T2-14): the file is the `--actions` file itself; its action has `no-click-path (no entry point reaches it` (a `non-click caller` is reachable: refused); every protected module its `unknown` says "may open it" is given, contains its own name, and names none of the documents on the way to the page: host, via_pages and their whole readable caller chain in the OLD model (`model=`, else actions.json `model`) |

  A line with another class or no evidence exits 2. Evidenced: `BASELINE DEFECT <CLASS> (<detail>)`, PASS*, and
  `defects: n failing on the baseline: k with evidence (FIXTURE a, ...) = k PASS*, m without (INVALID)`.
- UNREACHABLE: the row prints `UNREACHABLE <row> UNREACHABLE: actions.json: no entry point reaches ...`, the headline
  `u PASS* (unreachable in the OLD UI, evidence checked)` and the coverage line ` · u todo unreachable in the OLD UI
  (evidenced, PASS*)`; the denominator does not change (dead is not covered), and it is never PASS. A check that fails
  leaves the row INVALID with `[UNREACHABLE refused, evidence line i: <why>]`. The model alone is no proof when a
  module is protected: on the Opcenter Starter Kit the inventory called ClientConfiguration_NewEdit unreachable while
  the EXFN add-on opens ClientConfiguration_Overview, which leads to it (create-save walks it). Give the add-on's
  .mpk / .mxmodule or unpacked folder; a search that cannot read it (compressed, wrong module) refuses.
- Proof: controls `journeys-coverage-*` (each rule a catch and a pass), `journeys-headline-*`, `journeys-unreachable-*`,
  `gate-journey-actions-*`, `gate-journey-coverage-*`.

## Fixture preflight (E2E-12): why a seed returns nothing, before the run

```
python3 $B/fixture_check.py $W/journeys --psql "<old db psql>" --out $W/fixture-check.json
```

Runs every journey's seeds as the engine does (in order, `{{name}}` filled from the earlier seed, through pgmap.py; a
text starting with `/*sql*/` as it is) and sorts each that answers nothing by its cause. The harness checks the
preconditions and never repairs them: nothing is written. Source: skills/fixture-seeding.md section 3 of the sister
toolkit at 588056a (copied because cloud workers cannot clone it):

| Symptom | Cause | Owner | fixture_check | exit |
|---|---|---|---|---|
| database unreachable | stack down, wrong port | operator | UNREACHABLE | 2 |
| seed SQL errors | malformed query, renamed entity | journey author | QUERY-ERROR | 2 |
| seed SQL runs, 0 rows (or a NULL / empty first value) | fixture absent | seeding | EMPTY | 1 |
| runtime still warming | the mapping or the entity's table is not there yet | operator | WARMING | 2 |

Last line: `fixture: J journeys · S with seeds · OK n · EMPTY n · QUERY-ERROR n · WARMING n · UNREACHABLE n`. EMPTY is a
finding: seed the fixture, or cite the JSON as FIXTURE evidence for the journeys that then fail on the baseline. The
other three are faults: fix the stack or the query and run again, never seed (and never cite) on the strength of one.
Without `--psql` / `UPG_PSQL` every seeded journey is UNREACHABLE, never OK. Run it against the OLD app's database
before before-picked. Proof: controls `fixture-check-*` (each cause on the SQLite psql stand-in).

## Processes (E2E-16): what a user does end to end, on the old app and on the new one

A generated journey per action proves each button works, not that a user can still do their job. A process is that
job ("raise a request, the manager approves it"), in the users' words, with the row that proves it worked. Format:
`templates/processes.example.md`. The order:

1. **Interview + manual.** One 15-minute key-user call per role group with `templates/process-interview.md` (roles, top
   5 daily tasks, the most critical process, what breaking looks like, sample data), and the user manual (md, txt,
   html, pdf) as it is.
2. **Draft.** `python3 $B/draft_processes.py --actions $W/actions.json --out $W/processes.md [--manual guide.pdf ...]
   [--interview notes.md ...]`. Drafts from the model (lifecycle effects per entity, create + save, other writing
   actions: pinned, with an expect), from the manual (sections and tables named process / task / flow / procedure /
   use case / scenario) and from the interview; interview first, then model, then manual, at most `--max` (12) new ones.
   Every block is `status: draft`, never confirmed. A step the model cannot match is written `=> ?` with its
   `candidates:` line. Rerunning keeps the existing blocks byte for byte and only adds new names.
3. **Confirm.** A human walks the drafts with the key user, picks a candidate for every `=> ?`, sets the expect row,
   and writes `status: confirmed` (or `dropped`). Nothing else confirms.
4. **Compile.** `python3 $B/process_journeys.py $W/processes.md --actions $W/actions.json --out-dir $W/gen` after
   gen_journeys.py. Each confirmed process becomes one journey per role leg (`proc-<id>-<nn>`, in that role's folder),
   each step resolved through actions.json to a concrete widget, the expect as the last leg's own-row check (COUNT =
   1, a value with `${RUN_ID}` that a step typed). A step that matches no action or several, an action with a blocking
   todo (combobox, external call, no role, unknown action, page parameter), an expect without `${RUN_ID}`, a role that
   acts again after another one, or an order contradicting another process makes the process INVALID: a
   `process:<id>` row in plan.json `skipped` with the reason, never a dropped step. Drafts are listed, never compiled.
   Exit 3 when any process is INVALID or none is confirmed.
5. **Run old.** before-picked, as for every journey: the proc journeys are in the journey-set hash, role folders run
   in plan.json `role_order` (the requester's leg before the approver's).
6. **Run new.** `--compare` against that baseline, unchanged rules. run_journeys.py prints, after the action line:
   `processes C confirmed · K compiled · I invalid · P pass [· B pass on baseline · R regression] · D draft (not
   compiled)`. A process PASSes only when all its legs PASS; a leg that did not run makes it INVALID; 0 confirmed is
   INVALID, never a quiet pass.

- Limit: a hand-off leg (the approver's) finds the record the way the user does, usually the first row of a list; a
  list that is not sorted newest first can pick an older record. The expect row (own `${RUN_ID}` value) catches that as
  a FAIL, never a false PASS. Write the sort into the process notes when the interview names it.
- Baseline defect (PV-11): when the app's own setup path is broken on the old app too (a save button that counts
  existing rows and refuses, a reset that overwrites the connection), the process does not become INVALID for it. Write a
  `baseline defect:` line in the process notes in processes.md naming the broken path and the helper that does the setup
  instead (a DB helper, an encrypt helper for credentials). The report keeps the defect as a finding of the old app, so a
  later reader does not blame the upgrade, and the journey uses the helper, never the broken page.
- Future option, not built: recording. A key user clicks through the old app once and the recording becomes the
  process steps. Until then the steps are typed from the interview.
- Field run (E2E-16), customer (21 actions) with the customer functional specification as the manual (its §6 flow table)
  and an EXAMPLE interview: model alone drafts 2; together 12 written (interview 3, manual 9; 5 more over `--max`; the
  interview drafts replace the 2 model ones), 24 steps, 7 pinned, 14 `=> ?`. The 3 interview drafts confirmed: 2
  compiled, 1 INVALID (Submit is an external call). All 12 confirmed as they stand: 2 compiled, 10 INVALID, each with
  its first open step; nothing compiled from a guess. The manual describes a routing app the customer model barely has.
- Proof: controls `process-*` (Starter Kit golden) and `field-process-customer-*`.

## Connector pages (TC-1, TC-3)

An app that calls an external system may fall back to mock data when the call fails, so a rendered page proves nothing
(two of five Teamcenter demo apps did). A step on a page that reads the external system is marked and carries a proof:

```
{"do": "open", "page": "Items_Overview", "connector": "Teamcenter", "proof": "<value only the real source returns>",
 "ui": {"textPresent": ["<same value>"]}}
```

`run_journeys.py` refuses the set before anything runs (exit 2, INVALID, "CONNECTOR NO PROOF (TC-1)", gate rung
journeys INVALID, never PASS) when a `connector` step has no `proof` of at least 3 characters, or the proof is not in
that step's `ui.textPresent`. Pick a proof from the old app's real response (an id, a name, a revision), never a
caption, a column header or a value the mock also shows. Controls: `journeys-connector-noproof-catch`,
`journeys-connector-proof-not-asserted-catch`, `journeys-connector-proof-pass`. PV-10: a failed or denied call shows mock rows and sets the connector's connected flag
to false with no error dialog (TeamcenterToolkit 4.0.1: revisions A, B, C), so also assert the connected state: the proof
is the server's own item id (never a revision letter or a card count), and `"connected": "<text only shown while
connected>"` must be in `ui.textPresent` too. `"mockValues": [...]` lists what the mock shows; a proof from that list is
refused. A connector step without `connected` prints a NOTE (PV-10). Controls: `journeys-connector-mock-proof-catch`,
`journeys-connected-not-asserted-catch`, `journeys-connected-pass`, `journeys-connected-note-pass`. The generator does not mark connector
steps yet: triage's `connectors.md` says which pages, and a human adds the fields (backlog #45).

Read-only external systems (TC-3): when the system is shared, journeys drive READ flows only (triage marks each flow).
Never write `create*`, `update*`, `revise*`, `set*`, `delete*`, workflow or BOM window steps, and never click a reset
or default action (TC-2). Direct calls (probes, proof lookups) all go through one allowlist client that refuses
anything not on the READ list. One account runs one session at a time (TC-6): do not run connector journeys in
parallel roles on the same account (use `--pause`, and no parallel gate runs).

## Stop rules

- An always-on journey FAILs on the new app and PASSed on the old one. Do not explain it away with a passing smoke
  walk.
- The positive control does not catch the ui-landing mutant.

## Runner limits (FEEDBACK E2E-1 to E2E-6)

- The data, association and outcome rungs asked `mxcli oql --direct`, which a runapp/m2ee runtime does not answer
  (no dev flags), so they came out INVALID (E5b-11). They now ask the app's Postgres through `--psql` (above, E2E-9);
  without it they are still INVALID. pgmap.py translates the OQL the engine writes (SELECT, COUNT/MAX, WHERE, AND/OR,
  INNER/LEFT JOIN over `a/Module.Assoc/Module.Entity`, ORDER BY, LIMIT); anything else is refused, not guessed. The
  whole-database state at the end is still the job of diff.py.
- The upstream runner's login check could PASS when the anonymous home is itself a Mendix page (T8-9); the engine copy
  is patched (below) and the MFA journey still asserts the refusal text, which the catch control proves.
- run_journeys.py patches its COPY of the engine (bin/journey-verbs.js and bin/settle.js are copied next to it; the
  shared toolkit is never edited; upstream proposal: research/journey-runner-verbs.patch.md):
  - login (helpers.js): signs in on `LOGIN_PATH` (`--login-path`, default `/login.html`) and counts a login only with
    no visible password input, no login URL and the READY selector present (T7-10, T8-9); `navTo` also finds items
    of layout menu bars (`.mx-menubar`, `.mx-simplemenubar`) and an item by its exact text when no title matches (T2-11).
  - `fill` also types into Mendix login widgets (`input.mx-name-<widget>`); values keep every character, ':' included.
  - `click` takes the match inside the topmost open popup first (E6-8: a popup's actionButton1 and the button behind it).
  - new verbs (E5b-21, E7-3): `{"do": "toggle", "widget": "switch1", "value": true}` (alias `switch`),
    `{"do": "select", "widget": "referenceSelector1", "match": "Team A"}` (aliases `reference`, `dropdown`; exact option
    text, then the first option containing it, else an error that lists the options), `{"do": "confirm"}` or
    `{"do": "confirm", "label": "Proceed"}` (the topmost dialog's primary button, waits until it closes). Each reads
    its state back and fails when the page did not take it.
  - for generated journeys (E2E-10): `{"do": "select", "widget": "referenceSelector1", "first": true}` (the first
    non-empty option; an empty list is an error, a fixture gap) and `{"do": "row", "widget": "grid1"}` (clicks the first
    row of a list view, template grid, classic or data grid 2, or gallery; no row is an error). Both are proven on a
    fake page only (controls `journeys-verbs-*`), not yet on a live app: the row selectors are
    `journey-verbs.js` `ROWS`.
  - a hand-written journey may carry `"closes": ["<todo id>", ...]` (the plan.json todo or skipped ids it walks); the
    run then reports those items with that journey's verdict instead of INVALID (E7-3: eight todo items behind one
    wizard).
  - every screenshot waits until the page settled (no Mendix progress bar or loading state, DOM size stable; SETTLE_MS,
    default 15000). A page still loading is saved as `<name>-LOADING.png` and its screen verdict is INVALID (E6-17).
  - data (helpers.js `oql`): with `UPG_PSQL` set the SQL goes through bin/pgdata.js and bin/pgmap.py (copied next to
    the engine) instead of mxcli; every step records its effect (row counts before the actions and at the step's end,
    journey-runner.js, E2E-9).
  `python3 $B/run_journeys.py x --label x --work X --patch-engine <dir>` patches a copy in <dir> and prints which
  patches applied; summary.json records the same. "NOT applied" means the upstream runner changed: re-check it.
- `example.journey.json` upstream uses an older format; use the generated journeys as examples.
- A combobox widget (not a native select): the vendored engine has a `combobox` verb (vendor/e2e/journey-runner.js,
  for the Downshift-backed Atlas combobox); whether it drives the Mendix Combo box widget is unchecked, so such a step is
  still walked by hand, with the screenshots kept for shotdiff, and action_inventory.py gives it the `combobox` todo.

Proof: `controls/journey-control.sh` (part of `make test`) starts the E1 app, runs the MFA journey with MFA on (must
PASS) and with the planted fault `MFAmodule.EnabledMFA=false` (must FAIL as REGRESSION with --compare).

- `assign-to-me-dead` (PRF-2): an action shown only for an unassigned task, in a participant's task list, for a role with one user in `users.json` is a todo, not a defect: its tasks arrive assigned. It is listed in plan.json `skipped` and in the coverage line; give the role a second user to make it reachable.
