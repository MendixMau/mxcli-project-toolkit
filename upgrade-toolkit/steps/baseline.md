# Step 2: baseline (old app, frozen data)

Goal: the reference every gate check compares against. Same database, same checks, two binaries.

Order matters (E1 1, E1 23): anything that logs in or starts an app WRITES to its database (sessions, login fields,
FileDocuments, demo-user resync). So the data snapshot is taken from the frozen state, and walks run on copies.

Test data: pick the route before seeding anything. Take the first that applies:
(a) a copy of a real environment's database, or the publisher's demo data (`data-snapshot.zip`, item 1);
(b) otherwise `seed_pg.py` for bulk rows in every entity (item 1); the same channel as mxcli's bundled
`.ai-context/skills/demo-data.md`, which explains the Mendix id and association scheme behind it;
(c) for state that SQL cannot build validly (a workflow with a task waiting at each step, a comment, an
attachment), seed through the app's own UI: confirmed processes with `park: n after leg k` in `processes.md`
(steps/journeys.md), walked before the data pass on both apps.
Order of work, from mxcli-project-toolkit `skills/fixture-seeding.md` (recommended reading, not required): derive what
the journeys need, measure what the frozen database holds, seed only the gap, then verify by re-running the journeys.
Traps from that skill: a user inserted without a proper password hash and role links exists but cannot log in, so
test users come from `smoke_users.py` (bcrypt hash, one user per role), never a hand-written INSERT; failed logins set
`Blocked`, so check it before a rerun; and confirm which database the runtime is attached to before the first insert.

Old build fails at javac on a missing jar (MC-1): an MPK exported without `vendorlib/` (bouncycastle, commons-io and the
like) cannot build on its own version, and the toolkit has no sync route for 10.x. Known case "MPK without vendorlib":
make a THROWAWAY copy of the app, run the newest `mx` that has `sync-java-dependencies` on it (`mx<major>.sh` with that
mx; the project version stays unchanged), and commit only the resulting `vendorlib/` to the app. Never commit the
copy's converted model.

1. Database with realistic data. If it has none: `seed_pg.py --psql "docker exec -i mig-pg psql -U mendix -d X" --mpr app/<app>.mpr`
   with the app STOPPED (values are unique per entity, so two System.User specializations no longer collide). `--mpr`
   gives every enum column its enumeration's first value; the summary names any enum left NULL. FileDocument and Image
   specializations are not seeded (a row without a file throws FileNotFoundInStorageException on the page that shows
   it); `--with-filedocuments` seeds them anyway (T6R-13). Set key
   values by hand for every RED element from localedits. A Marketplace template that ships `data-snapshot.zip` (the
   publisher's demo data, HSQLDB) is loaded with `seed_snapshot.py` instead, never a hand-written loader (T5-10, T3-11):
   start the app ONCE on the empty X (it creates the schema), stop it, then
   `python3 $B/seed_snapshot.py <data-snapshot.zip> --dry-run` (counts per table), then the same with
   `--psql "docker exec -i mig-pg psql -U mendix -d X"` (add `--dry-run` first to check the mapping against X). It replays
   the script and log in order, remaps ids by entity GUID, matches System.User / UserRole by name, and lists every table
   or column it cannot map under UNMAPPED with exit 1 (`--skip TABLE` waives one, reported). Start the app again, then
   freeze. File contents (`data/files/*` in the zip) are copied into the app's `data/files` after EVERY start (runapp.py
   wipes `run/<name>/`, T5-5). Open: autonumber counters are not advanced.
2. Start the OLD app on X: `WORKDIR=$W UPG_TOOLS=<run>/tools python3 $B/runapp.py start old <old.mda> <full ver> X`
   (Java image by major: 9 to temurin 11, 10 and every 11.x to temurin 21, also for an 11.x to 11.y run, N1-14; `CONST_OVERRIDES` = the environment's values, the
   SAME for old and new: JSON text or the path of a JSON file, B4T2-12). Slow start (E5b-13): a start above a few minutes is usually a module calling home at
   start with a backoff; runapp.py sets `MendixSSOClient.PushAppDeploymentEnabled=false` (LaMa push) itself when the app has
   that constant and CONST_OVERRIDES does not name it (HARNESS CONDITION line, T9), the same for both apps. The old app needs an mxbuild first; mx9.sh / mx10.sh refuse an incomplete toolset (no
   `modeler/runtemplates/deployment` or `modeler/tools/node/node_modules`): the symptom is "dojo-web
   DirectoryNotFoundException" (9.x, 10.12) or "copyDeploymentArtifacts NoSuchFileException" (10.24), and the fix is a
   fresh extraction of `mxbuild-<full ver>.tar.gz` (E4-20, E5b-1). Stop it, then freeze: `createdb -T X X_frozen`. Never drop or start anything on X_frozen.
3. Restart-neutral data baseline: start the OLD app again on a fresh copy `createdb -T X_frozen X_base`, then
   `python3 $B/snapshot.py --label before --ledger $W/db-ledger.txt --psql "... -d X_base" ... --out $W/before.json`
   (db, http with swagger.json or openapi.json contracts, start log window, admin). This snapshot already contains
   what any start changes, so the gate does not report the start's own writes as FAIL. Endpoints are judged on status,
   JSON shape and contract, never on the body md5: an endpoint whose body carries a random id (a urn:uuid in a 400
   answer) can stay in the list (E7-17). Checking the endpoint list against the running app is itself a probe: do it
   on a separate copy (`createdb -T X_frozen X_probe`), never on X_base before the snapshot, or X_base counts as used
   and you snapshot a second copy (NR1-7). `--endpoints` writes the operation path without the service location
   (backlog #21): read each path against the service's published Path, and treat a listed endpoint that answers 404
   on the old app as not probed, because a 404 on both sides compares equal (NR1-5).
   Fresh copy per snapshot (E4-21): a snapshot, an endpoint probe, a walk or a journey writes to its database. In E4
   a second snapshot on the same X_base after an endpoint probe gave 15 FAIL against the first. So every snapshot
   (before, after, controls) gets its own `createdb -T X_frozen <name>` copy, and every database a probe or walk used
   is recorded: `snapshot.py --ledger $W/db-ledger.txt --mark-used <db> --use probe`. With `--ledger` the snapshot
   refuses (exit 2) a database already in the ledger, and it always refuses a `*_frozen` database. Without
   `--ledger` it warns.
4. Controls: `diff.py before.json before.json` 0 FAIL. The restart control (PV-7): a start can change data by itself
   (Product View 360 deletes and re-imports its demo data in an after-startup microflow: 14 rows differ between two
   starts of the SAME old binary, and the gate would have blamed the upgrade). Fresh copy `createdb -T X_frozen
   X_restart`, start the OLD app on it once more, `snapshot.py --label restart --ledger $W/db-ledger.txt ... --out
   $W/restart.json`, then `python3 $B/diff.py $W/before.json $W/restart.json --emit-allow $W/start-noise.txt`. Every
   FAIL or REVIEW row it shows is start noise: read the list, append it to `$W/allow.txt` (each line carries the reason
   "start noise ...") and name it in ASSUMPTIONS.md. Rows it does not show are what the upgrade alone may change. The
   mutant control must FAIL: copy X_frozen
   (`createdb -T X_frozen X_mutant`; `-T X_base` fails while the app holds X_base), change one value of a
   data-bearing attribute (`update <table> set <col> = 'mutant' where id = (select min(id) from <table>)`), take a
   db-only snapshot (`snapshot.py --label mutant --psql "... -d X_mutant" --ledger ...`) and expect
   `diff.py before.json mutant.json --db-only` exit 1 with that attribute as FAIL (`--db-only` leaves out the http
   and log rows a db-only snapshot cannot have; System.User.Password and changedDate of the local admin also differ,
   because runapp.py set that password on the started side: expected, E6-11, E7-18). Keep the old start log
   (`runapp.py logs old`) for logdiff at the gate: every save also writes `logs/runtime-old.X.log` (named by the
   start's database), so the gate's `OLD_LOG=logs/runtime-old.X.log` needs no hand copy (B4N1-16).
5. Logins per role on ANOTHER copy (`X_smoke`, never X_frozen), after the app started on it once:
   `python3 $B/smoke_users.py X_smoke --apply` (user `smoke_<role>` per user role, persisted sessions cleared; it
   refuses databases not named fx_*, *_copy* or *_smoke* unless `--ledger $W/db-ledger.txt` lists them; the naming
   rule for journey copies is in steps/journeys.md). Demo users are re-synced at start in DTAP mode D, so set
   passwords after the start, and use smoke_ users rather than demo users.
   The users are created as the entity the home microflow retrieves (`--entity Module.Entity`; default: the one
   specialization of `Administration.Account` that has rows, several -> exit 2 and the candidates, T3-6); a plain
   Account user lands on the login page. The smoke walk FAILs a step whose page still shows the login form or an
   "An error occurred" dialog, whatever the Mendix client says.
6. Smoke walk on the old app on X_smoke (the plan comes from the OLD model: the pre-convert worktree, or `app/` at
   the baseline commit; in a parallel run `app/` is owned by triage and is converted later, NR1-6):
   `python3 $B/smokewalk_gen.py <old model folder> -o $W/plan.json`
   `node $B/smokewalk.js --plan $W/plan.json --url http://localhost:<port> --user <Role>=smoke_<role>:<pw> ... --out $W/smoke-before.json`
   The runner skips microflow steps unless it gets `--microflows`. When smokewalk_gen prints `WARN <role>: ...` (the
   home is a microflow, or over half the menu items are; PV-6: every page of Product View 360 was one), add
   `--microflows` to the baseline AND the gate walk, on the X_smoke copy only: they run for real.
   Add `--shots $W/smoke-before-shots` (and `--shots $W/smoke-after-shots` after the upgrade) so the gate can compare
   the walked pages with shotdiff.py. The baseline walk repeats every role 3 times (`--repeat N`, T6R-9: a client
   teardown error that shows in 2 of 3 walks is a coin flip for a one-walk baseline); each step keeps its runs, and a
   step that failed in some walks is listed `[not PASS in n of m walks]`. Roles without credentials are INVALID. A trial runtime allows 6 sessions and guest sessions count: start with
   `UPG_SESSION_TIMEOUT=30000`. With `--shots`, smokewalk also saves the page's visible text beside each shot
   (`<shot>.txt`); shotdiff compares those words, so a lost caption or a doubled paging text is a REVIEW whatever the
   pixel share (NR1-25). Keep the .txt files with the png files when you copy or archive a shots folder.
7. Journeys, always-on set: [journeys.md](journeys.md) "At baseline". Plan the whole old-app side here, not at the
   gate: run `gen_journeys.py --actions` and the old-app before-picked pass now, on their own database and stand-in
   (NR1-30: left to the gate this was an extra 68 minute old-app run). After the journeys run
   `python3 $B/apimock.py check` on the stand-in's record; 0 requests means the gate's apis rung is INVALID by
   construction (NR1-10): plan a journey that reaches an API call, or write UNEXERCISED waivers, before the gate.
8. Connector apps (TC-2, TC-6, TC-4; only when triage wrote `connectors.md`):
   - Record the connector config rows (host, user, default flag, whatever the config entity holds) BEFORE and AFTER
     seeding and after each journey that could touch them. A changed host is a baseline defect (TC-2): seeding, a
     "Reset to default" button or a demo-data reset microflow overwrote the connection with another host. Journeys never
     click reset or default actions.
   - Serialize connector checks (TC-6): one account allows one session at a time, and parallel sessions on it collided
     (HTTP 500). Never run two connector checks, or the smoke walk and a journey, against the same external account at once.
   - A claimed API failure (TC-4) is not evidence until it is replayed with the connector's own request body (read it from
     the connector's Java), not a hand-built one. Two services reported as failing worked once the body matched.
9. Readiness re-check (RD-1): run triage item 13 again, `python3 $B/readiness.py $W --app app/`. Now it also reads
   before.json, users.json and the old-app journeys summary. Journeys failing on the OLD app above the gate's 30% bar
   (run_journeys.DEFECT_MAX) make the journeys rung CANNOT JUDGE: the instrument is not measuring, and the gate will
   say INVALID however the upgrade goes (notif R2: 233 of 406, 57%). So does an empty frozen database for the data
   rung. Fix it here (confirmed key-user processes with JOURNEY_BAR=processes, demo data the old app passes on), or
   tell the customer before step 2 which verdict the run can reach at best.

Output: X_frozen, `$W/before.json`, the old start log, `$W/smoke-before.json`, `$W/journeys-base/` summary, `$W/readiness.md` (re-checked).
