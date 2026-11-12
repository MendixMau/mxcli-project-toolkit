# Step 5: gate (all must hold)

Same database, same checks, two binaries. The new app starts on a fresh copy of X_frozen.

**Cost line per layer (QJ item 4):** after each layer (L0, L1, L1b, L2, L3, L4, L5, L6, C) record its wall minutes, tokens and
human review minutes with `python3 $B/cost_ledger.py add --work $W --layer <L..> --step "<what ran>" --wall <min> --tokens <n or -> --review <min or ->`;
`gate.sh` prints `cost_ledger.py report` at the end when `$W/cost-ledger.tsv` exists. It is measurement only and never changes a verdict.

**Driver (N1-13):** `bash $B/gate.sh --config $W/gate.conf` runs rungs 1 to 10 below, then the external-API rung
(item 12, row 11 of the summary), in order through these same instruments, checks every input path before anything runs (a missing one stops it, exit 2, the path named), records
each rung's rc and a one-line verdict, and writes `gate-summary.md` with every rung as PASS, PASS*, FAIL, INVALID or
NOT RUN (with the reason). Exit 0 only when every required rung is PASS or PASS*; 1 on a FAIL; 2 on INVALID or NOT
RUN. `--dry-run` prints the commands. Do not hand-write a gate.sh: the copies drifted (N1: a journeys folder that did
not exist, rc=2 never reported). The numbered steps stay as the reference for what each rung means and which exit it
reads; the driver only runs them. Starting the new app on its fresh copy and taking the snapshot (rung 4 and the app
for rungs 7 and 8) stay yours: give them as `PRE_data=...`, `PRE_smoke=...`, `PRE_journeys=...`, and `POST_CMD=...`
to stop the app. A key a PRE command produces (AFTER_JSON, NEW_LOG) may come from any earlier rung's PRE (NEW_LOG
written by `PRE_data` serves logdiff). PRE commands and POST_CMD see `$G` (the gate folder), `$WORK`, `$RUN` and every
key as environment variables: write `--out $G/after.json` as is (single-quote it on a command line). `{RUN}` in any value is the
invocation id (UTC time, or `RUN=...`): `createdb -T X_frozen X_after_{RUN}` gives every invocation its own database.
The `CONST_OVERRIDES` key is a path and is exported as such; runapp.py reads a path or JSON text, so a PRE that starts
the app needs no `CONST_OVERRIDES="$(cat ...)"` (B4T2-12). Without the key, a CONST_OVERRIDES you exported yourself
reaches the PRE commands unchanged. `OLD_LOG=logs/runtime-old.<baseline db>.log` is the old app's start log of the
baseline as runapp.py saves it (B4N1-16).
`--only journeys,screens` re-runs those rungs and merges them into the existing `gate-summary.md` (the others keep
their row, marked "earlier run"). Journeys exit 3 (INVALID only, for example a journey that fails on the OLD app too)
is INVALID with the instrument's advice, never FAIL (N1R2-8, N1R2-9, T2R3-10, T2R3-11). A new gate folder (a remedy trial's own LABEL) has no summary to merge into: `--seed-from <original gate folder>` copies that summary in first, so the untouched rungs keep their rows instead of NOT RUN (RT-11; remedy_apply.sh passes it). A rung that hits `GATE_TIMEOUT` is INVALID and its line says "raise GATE_TIMEOUT". The two screen rungs take separate accept files, `SMOKE_SHOT_ACCEPT` and `JOURNEY_SHOT_ACCEPT`
(one accept file per rung, see rung 9). The build rung needs "BUILD SUCCEEDED" and no "ERROR at" line. With
`APIMOCK=<state>` and `EXCLUDE_SYSTEMS=Teamcenter` (item 12) the driver can end in `PASS (except Teamcenter: N items)`,
exit 4, with every NOT CHECKED item listed by name in `gate-summary.md`; it never prints plain PASS then. With
`APIMOCK` set and any endpoint on the stand-in it ends in `PASS (on stand-in APIs: <systems>)`, exit 4, the stand-in
endpoints listed by name (E2E-15); both together: `PASS (on stand-in APIs: Opcenter; except Teamcenter: 3 items)`. Run
`gate.sh --help` for the keys.

1. Build: mx check 0 errors and BUILD SUCCEEDED (step 4).
2. Identity: `python3 $B/idcheck.py old.mda new.mda --md $W/idcheck.md`. Exit 0, or every REVIEW line (removed, made
   non-persistent) accepted in writing. GUID_CHANGED on a data-bearing element is FAIL. MPR vs MDA: System is excluded
   on the MPR side, so counts differ; the verdict does not.
3. Constants: `python3 $B/constcheck.py old.mda new.mda --overrides <env values.json> --allow $W/const-allow.txt --md $W/constants.md`.
   CHANGED is FAIL unless allow-listed with a reason (a module update resets constants to package defaults; E1 lost
   MFA this way). An ADDED behaviour switch (Boolean, or a name like Show*, Enable*, Disable*) is REVIEW: its
   default decides what the app does (E4, E5b: TaskQueueHelpers 3.1.0 ShowSystemQueuesInCharts=False emptied the
   dashboard charts while this line said INFO). Accept it in const-allow.txt with a reason, or set it in
   --overrides; the row then shows the effective value. Secret-looking values are never printed. To put a reset
   value back without seeing it: `--restore-to $W/const-restore.mdl` writes a 0600 MDL script (old values of every
   open CHANGED constant); run it with `mxcli exec`, then delete it (E4-25).
4. Data: new app on `createdb -T X_frozen X_after` (its own fresh copy), `snapshot.py --label after --ledger $W/db-ledger.txt`
   (snapshot.py writes the ledger line itself; never add one by hand, a hand note reads as "already used" and the
   refusal names that line, E6-16, E7-8; record a walk or probe with `--mark-used DB --use walk`), then
   `python3 $B/diff.py $W/before.json $W/after.json --allow $W/allow.txt --log-allow $W/log-allow.txt --md $W/diff.md`:
   0 FAIL, 0 INVALID, 0 open REVIEW, 0 NEW_ENDPOINT open. allow.txt: `<check pattern> [detail pattern] # reason`; it
   accepts FAIL, INVALID, REVIEW and NEW_ENDPOINT lines (for example `http./rest-doc/*/openapi.json` on 9 to 10). An
   accepted line prints as PASS*, with its reason, and the report lists it (E4-23). `--log-allow` applies the logdiff
   allow file to the `log.start` rows.
5. REST contract: part of diff.py (lost operation, response code or parameter, or a new required parameter is FAIL).
   For saved documents: `python3 $B/restcontract.py before/ after/`.
6. Start log: `python3 $B/logdiff.py old.log new.log --allow $W/log-allow.txt --md $W/logdiff.md`. START_FAILED and
   NEW_ERROR are FAIL; changed INFO/WARNING lines of the after-startup section are REVIEW (E1: "MFA module login NOT
   active" was a WARNING). An ERROR that is new in the start window but appears later in the OLD log is
   `REVIEW MOVED` (logged earlier now, E4-24): check it is the same failure, then accept it. diff.py also carries this
   as `log.start` (the snapshot stores the old log's ERROR signatures for MOVED).
7. Smoke walk: plan regenerated from the NEW project, then
   `node $B/smokewalk.js --plan ... --url ... --user ... --compare $W/smoke-before.json --out $W/smoke-after.json --shots $W/smoke-after-shots`;
   exit 0 = no PASS step regressed. A step already FAIL in the baseline is a baseline defect, listed apart.
   T6R-9: the old runs of the baseline (3 walks by default, and every `--compare` file) are pooled per step. An error
   the old walks never showed is a REGRESSION, `REGRESSION (intermittent: n of m)` when only some new walks show it
   (`UPG_SMOKE_REPEAT=2` walks the new app twice). The old app's own intermittent error on the new side is
   `FLAKY on both`: not a regression and not a pass (exit 2); walk again, or pin it per playbooks/widgets.md section 2.
   `node $B/smokewalk.js --rejudge new.json [--rejudge new2.json] --compare old.json ...` judges saved walks again.
7b. Layout (optional rung `layout`, LAY-1, runs BEFORE journeys, LAY-9): a page can show every value and still be squeezed or stretched, which no journey and
   no smoke shot sees. Walk the same page list on the old and the new app, then compare widget by widget:
   `node $B/layoutwalk.js --plan layout-plan.json --url http://localhost:8080 --user Role=name:pass --out $W/layout-old`
   (again with `--out $W/layout-new` on the new app), then gate keys `LAYOUT_OLD=$W/layout-old LAYOUT_NEW=$W/layout-new
   [LAYOUT_ACCEPT=file]` or `python3 $B/layoutdiff.py OLD NEW --accept file --md $W/layoutdiff.md`. Findings: WIDTH (a widget
   changed width by more than 24 px and 20%), CUT (text that fitted is cut off), IMAGE (an image grew more than 3 times).
   A page saved on the old app and absent on the new is MISSING and fails the rung. Without the two folders the rung says NOT
   RUN; it is never a PASS. Order matters: journeys change data (pager counts, edited or deleted rows), so walk the layout on both apps
   first. A layout compare run after the journeys fails against a baseline walked on fresh data. In the gate the rung sits before `journeys`. Accept lines: `pair pattern # what you saw`, the reason is required.

8. Journeys: [journeys.md](journeys.md) "At the gate". `GATE_TIMEOUT` (seconds per instrument, default 900) is too
   short for a big set: 247 journeys at `--pause 50` take about 65 minutes per side. Set it to journeys times pause
   times 1.3 plus the app start, e.g. `GATE_TIMEOUT=6000`, in gate.conf next to the journeys rung (NR1-29). A REGRESSION is FAIL; INVALID (no test user, todo) blocks DONE.
   Cite the coverage line (`actions A found · G generated ... · coverage B/A`, journeys.md "Coverage and honesty").
   gate.sh keys: `ACTIONS` (the OLD model's actions.json, run_journeys `--actions`), else `ACTIONS_WAIVE=<reason>`
   (at best PASS*: no denominator); without either the rung is INVALID. `JOURNEY_EVIDENCE` (`--baseline-evidence`)
   names why each baseline defect fails on the old app (FIXTURE from fixture_check.py, OLD-APP, FLAKY); a defect
   without it, a journey set whose hash differs from the baseline's, or more than 30% of the set failing on the old app
   is INVALID (E2E-11), and the row quotes each `coverage INVALID` line.
   Processes (E2E-16, journeys.md "Processes"): with a `processes.md`, run `process_journeys.py processes.md --actions
   actions.json --out-dir $GEN` after gen_journeys.py and before before-picked, inside `PRE_journeys`. Exit 3 means a
   process is INVALID: cite it in the row, never drop it; any INVALID process keeps rung 8 INVALID. Quote the
   `processes ...` line. A processes.md with 0 confirmed processes adds nothing: say so, never count drafts as tests.
   PASS bar (B5-3, the user's decision 2026-10-07): `JOURNEY_BAR=processes` (`run_journeys --bar processes`) makes
   the confirmed key-user processes the bar: PASS = every confirmed process passes on old and new, 0 REGRESSION / FAIL
   / SCREEN or EFFECT REVIEW from any journey, the other rungs green. Action coverage and the other journeys' INVALID
   count are quoted from the `bar: key processes ...` line, never blocking, never hidden. No confirmed process is
   INVALID and names the drafts a key user must confirm; a worker never confirms one.
   Critical set (S, quality-judgement L3): every role logs in, anonymous included when guest access is on. With guest
   access on, the journeys line needs `anonymous process: P of 1 required` with P at least 1 (a process run as the
   anonymous role PASSes), else rung 8 is INVALID under either bar; an always-on journey (`login-<role>`, `sign-out`,
   `mfa-password-only-refused`, `create-save`, `anonymous-<role>`) that is INVALID blocks under `JOURNEY_BAR=processes` too.
9. Screens (required, E4 and E5b): a page that renders but shows less than before passes every rung above. Compare
   the old and new screenshots pair by pair:
   `python3 $B/shotdiff.py $W/smoke-before-shots $W/smoke-after-shots --accept $W/shot-accept-<rung>.txt --md $W/shotdiff-smoke.md`
   and the journeys' own screens through `run_journeys.py --compare` (SCREEN REVIEW, accepted with `--shot-accept`);
   cite its `screens: N PASS, N PASS*, N REVIEW, N INVALID` line, printed on every compare (T1-26).
   PASS, or PASS* with a reason per accepted pair; REVIEW means open both images and decide: an expected change
   (new styling, a moved widget) goes into shot-accept.txt with the reason, anything else (an empty chart, missing
   rows, a lost widget) is a regression to repair. "indicator on both sides, images equal" is a REVIEW too: the
   progress-bar detector hit page content (a file-upload field, a card line) at the same place on two equal images
   (T5-18, T6-15). INVALID (a screenshot on one side only, a NEW step not reached, a -LOADING shot, a one-sided
   progress bar) blocks DONE and cannot be accepted: take the shot again. Two INVALIDs can be closed after a look:
   STUCK (the indicator never left a page that stood still: an empty 10.6 Data grid 2, an error page, T7-22) and
   BASELINE DEFECT (the OLD step was not reached; list it with the baseline defects, T1-24).
   Accept lines: `pattern @sha256:<12 hex> # what you saw`, the hash being the NEW image's, printed on the pair's
   line. A pinned line closes only that image; without the hash it matches every image of that name and shotdiff
   prints "unpinned accept". Keep **one accept file per rung** (`$W/shot-accept-<rung>.txt`): the pair names are the
   same on every rung, and an accept written for rung 1 silently accepted a broken rung-2 image (T7-28).
   A page with per-run content (the row a create-save journey made, its id, rows earlier journeys added) gets a new
   hash every run, so a plain pin never holds twice: pin it with a mask over the volatile cells,
   `pattern @mask:x,y,w,h @sha256:<masked hash> # what you saw` (`shotdiff.py --hash NEW.png --mask x,y,w,h` prints the
   line; at most 25% of the image, the PASS* says "masked accept: n% not pinned" and the count line "N masked
   accepts", B4T2-17). Do not fall back to an unpinned line.
   A STUCK line prints "ink OLD a% NEW b%": near 0 is a blank page (B4N1-14). settle.js ignores a thin bar at the
   top edge (at most 10 px, the only indicator, DOM still, page text present; the step says "top bar ignored"), so a
   rendered page under a persistent session-renew bar is no longer named -STUCK; a blank page under it still is.
   Never accept a pair you did not look at.

10. Release impact (required, V31-RI): `python3 $B/release_impact.py --check $W/release-impact.md` exits 0: every
   row of the triage file says `handled: <evidence path or commit>` or `not relevant: <reason>`. Exit 1 (rows open) or
   no file is INVALID, whatever the other rungs say. A row "handled" points at evidence that exists (a commit, a log, a
   diff row); "not relevant" says why the app does not use what changed. `not relevant (auto): <rule>: <fact>` entries
   from `--auto --facts` count as handled; the check prints `auto: N, human: N, open: N`, and the report gives that
   line and the facts file. An auto entry is only as good as its fact: a fact you did not check is a wrong entry.
   The facts file is made by `release_impact.py --facts-from-mpr <original>.mpr --db-vendor <v> --db-version <n> --runtime-os linux
   --facts-out $W/facts.json` (steps/triage.md item 10); rerun the report with `--auto` to see "auto would also decide N rows
   that carry a human entry" and the ones that differ in kind (T2F-3).
   A breaking, removal or runtime row about a feature the app uses cites a scan or a journey, not the build alone.

11. Convert mappings (9 to 10 only, T2-1): `python3 $B/convertcheck.py --mappings <pre-convert app dir> app/`. Exit 0, or
   every REVIEW line fixed (re-run to 0) or answered in the report. Exit 1 is FAIL: build, start, data diff and the
   smoke walk all pass on this defect and only a create-and-save journey sees it. The line "N call sites got an explicit
   mapping" goes into the report; no pre-convert copy is INVALID, not PASS.
11b. Connector pages (TC-1): a journey step on a page that reads an external system needs a proof value, or the
   journeys rung is INVALID (run_journeys refuses the set, exit 2). A connector page that only rendered is not a PASS:
   the app may be showing its mock fallback. Also read the connector config rows after the run against baseline (TC-2):
   a changed host means a reset action ran. Details: [journeys.md](journeys.md) "Connector pages".

12. External APIs (E2E-13, E2E-14, E2E-15; driver rung `apis`, optional): no gate run calls a production system. Order
   of preference per API: (a) the vendor's test or sandbox system (point its constants there with `CONST_OVERRIDES`,
   no `APIMOCK`); (b) responses recorded from a real system (`apimock.py serve --recorded DIR`); (c) the stand-in, only
   when no test system is reachable. The stand-in is a stopgap, not the standard: whenever `APIMOCK` is set and the
   stand-in answers for any endpoint (b or c), the gate is at best `PASS (on stand-in APIs: <systems>)`, exit 4, the
   endpoints listed in `gate-summary.md` with "real-system behaviour was NOT checked". That is a conditional PASS for
   the report: run the gate again against the real test systems before go-live. Plain PASS needs real (test) systems.
   To use the stand-in, before PRE_smoke starts the apps, start one for both:
   `python3 $B/apimock.py serve old.mpr new.mpr --state $G/apimock --public-host <docker gateway> --background`. With
   `--public-host` it listens on 0.0.0.0 (an app in a container cannot reach 127.0.0.1 on the host; B4T2-5); without it,
   on 127.0.0.1 only; `--bind` overrides either. It reads
   every consumed REST call, OData service, web service and URL constant from the models, prints
   `apis E found · mocked M · excluded X (names) · unknown U` and writes `overrides.json`: pass it to both apps as
   `CONST_OVERRIDES` (runapp.py), and set the `/a/<Entity.Attr>` URLs it prints in the seed data where a location comes
   from data. Gate keys: `APIMOCK=$G/apimock`, and `EXCLUDE_SYSTEMS=Teamcenter` when a system cannot be stood in.
   `apimock.py check` is the rung: every endpoint MOCKED and every request answered is PASS; an UNKNOWN endpoint (a
   location from data, a hard-coded URL, a URL constant no modelled call reads), or a request the stand-in could not
   match, is INVALID until it is classified (`--classify` lines with a reason) or its data points at the stand-in.
   Add-on modules (`modules/*.mxmodule`, B4T2-6 / B4N1-9) are packed and protected: their calls cannot be read, and a
   location their microflows build at runtime from entity data (Opcenter `EXFN_ServiceLayer`: ServiceUrl from
   `ClientConfiguration.OpcenterEXFNUrl`) is invisible. Each add-on is one UNKNOWN endpoint `addon:<Module>` naming its
   URL constants and URL attributes, so "unknown 0" is never shown beside an add-on. Point such a location at the
   stand-in with a LOCATION line, then classify it: `<pattern> LOCATION const:<Module.Constant> # reason` (serve
   overrides that constant, it is in `overrides.json`) or `<pattern> LOCATION data:<Module.Entity.Attribute> # reason`
   (serve prints the `/a/<Module.Entity.Attribute>` URL: put it in that attribute in the seed data, or override the
   constant the data is filled from), followed by `<pattern> MOCKED # reason`. MOCKED on an endpoint with no constant
   or data location is refused: it stays UNKNOWN, and the rung INVALID, never MOCKED. An endpoint that cannot be
   redirected is UNKNOWN or EXCLUDED by name, nothing else.
   Direct API test (`steps/apis.md`, step `apidirect`, gate key `APIDIRECT=$G/apidirect`): when `direct.json` exists the
   rung measures each consumed REST call on the old and the new app against the stand-in: PASS, FAIL (the requests,
   the parsed result or the error path of a stand-in 500 or a malformed body differ: exit 1, a candidate regression),
   INVALID (could not be measured, with the reason: exit 3) or INFO (excluded system). The endpoints it measured need no
   journey hit; the journey hits stay as extra evidence. A system with a `--classify ... EXCLUDED <System> # reason` line
   is INFO ("check at deploy", exit 0), not INVALID, with no `EXCLUDE_SYSTEMS` needed.
   The rung's row carries `requests seen: N` (B4N1-11). A MOCKED endpoint no request reached is `NOT EXERCISED`
   and INVALID: nothing showed that the app reaches the stand-in for it. Waive one only when no journey can reach it,
   with `<pattern> UNEXERCISED # reason`; the waiver is listed. MOCKED endpoints with 0 requests in all are INVALID
   with or without waivers: the stand-in was never shown reachable (check `CONST_OVERRIDES`, the bind address, the
   seeded `/a/` URLs). A PASS on the stand-in with `requests seen: 0` does not exist.
   Exclude ONLY a system no stand-in can replace (Teamcenter: SOA login, FMS tickets, server-side viewer rendering),
   by name. A journey or smoke step whose every failing step called that system inside the step's time window, with no
   UNKNOWN call, is `NOT CHECKED (excluded: Teamcenter)`; every other failure stays FAIL. The overall verdict is then
   `PASS (except Teamcenter: N items)`, exit 4, and the report lists the N items: they are not tested, not passed.
   A smoke screenshot of a NOT CHECKED step still differs on the screens rung: accept it in that rung's accept file
   with the reason "excluded: Teamcenter" after looking at it, or it stays REVIEW.

13. Vendor Java (NS-5): `python3 $B/vendorjava.py app/ --base <original commit> --md $W/vendorjava.md`. Exit 0, or every
   COMMENTED-OUT / EMPTIED line fixed (update the module, or port the code to the new API) or answered in the report as
   an accepted loss. Build, start, data diff and smoke all pass on this defect: notification-service 076dca76 commented
   out DatadogConnector's metric bodies to get past javac on 11 and every Datadog metric was dropped silently. Not a
   gate.sh rung; run it by hand before the verdict.

14. Widgets no walk renders (MC-19; driver rung `widgets`, optional, row 13 of the summary): `python3 $B/widgetcover.py app/
   --smoke $G/smoke-after.json --journeys $W/e2e-gen` lists every widgets/*.mpk that a page uses and that no smoke step and
   no journey renders (a snippet or layout of a rendered page renders with it). Exit 0 = every used package is rendered or
   waived (`--waive FILE`, "package or widget id # reason"), exit 3 = at least one UNRENDERED: the driver reports INVALID, never
   PASS. Why: Asset Console's 3D viewer widget (2024 build, its own React 18) crashed on the 11.12.6 client with React
   error #525 and "Could not render widget"; the gate exited 0 because the frozen data had no configuration for the panel,
   so no walked page held the widget. Close it by a journey or hand-written walk that opens one page with the widget
   (`--rendered FILE` names the pages a hand-written walk covers) or by a waiver with the reason. Gate key: `WIDGETS_APP=app/`.
   Triage finds the same widget earlier: replacement_check row R36 (steps/triage.md step 10).

15. Step records complete (STEP-RECORDS-PLAN.md slice 9; driver rung `trail`, optional, row 13 of the summary): `python3 $B/steps.py
   trail --work $W` asks, for every step in `$W/steps.jsonl`: a proposal; an approval (`assumed` counts, and is listed as waiting
   for the owner's OK); a change in the app, or a written gap "no change needed"; a test result for each rung it closes by, or a
   written gap; and that every D row of AGENT-DECISIONS.md names a step (a step that lists the D id counts). It answers in
   plain words, one GAP line each, and a last line that becomes the summary row. The gate's own gaps ("did not run", "no check
   is linked") do not count as written: they are what the rung shows. The rung runs after all others, once `steps.py tested
   --gate` has linked the rows to the steps.
   Optional for now. It runs only when `$W/steps.jsonl` exists (otherwise NOT RUN, "no step records in this run"). A complete
   record is PASS. A miss is a NOT RUN row that starts with `WARNING:` and names the first gap; it never changes the verdict or
   the exit code. The switch for slice 10 is the gate key `TRAIL_REQUIRED=1`: then a miss is INVALID and a run without
   step records is a required NOT RUN, so the verdict cannot be PASS. Older runs get their records from
   `python3 $B/steps.py import-legacy --work $W [--app app/]` (every event has source `legacy`; what it cannot link is a gap,
   "not linked in this run"; a rerun adds nothing). `changelog.py` shows the toolkit's own `config` commits for the rung start and
   regenerated stubs as `housekeeping`, not as a commit with no step.

Read `$W/impact.md` (from the journeys step) before the verdict: a high constant "read in the startup tree", or a flow
"no longer called at startup but still in the model", needs an explanation even when every check passes.

# Step 6: report

One table per rung: rung (full versions from `mxversion.py`), verdict, evidence path per gate item above.
Directly under the verdict, always (also on PASS): the decision cards from `$W/remedy-cards.md` (steps/remedy.md), one
per FAIL blocker, kept module and open release-impact row, with the option tried and its result, the options left and
who decides, and the instrument gaps. A FAIL or kept module with no card is not reported as a dead end: run remedy.py.
Then, in this order:
0. Progress line (`Progress: N of M checks closed`), then the open items in `DECISIONS.md` ([decide.md](decide.md)).
   Next line: `Changes: N (toolkit a, agent b, person c, unlabelled d)` from `bin/changelog.py` (gate.sh runs it when `$W/app` or `APP_REPO` is a git repo); the full list is `$W/CHANGES.md`. An unlabelled commit (no `Changed-By` / `Upgrade-Change` trailers) is a decision item: say who made it and why, or label the next one with `bin/appcommit.sh` (repair.md).
1. REGRESSION list (FAIL): cause, owner (module update, own code, platform), evidence file.
2. INVALID list: what is needed to judge it (a test user for role X, a todo journey, a scanner with no coverage).
3. Kept modules (unattended stop rule): "upgrade complete except kept modules: <list>", with the localedits line or
   step idcheck finding that kept each one. A kept module is never reported as upgraded.
4. Accepted changes: every allow-list, accept and approved line (diff, constants, logdiff, idcheck, shotdiff) with its
   reason, and the `.stepupdate/no-baseline.txt` and `saved-edits/` modules with what was replayed.
5. Release impact: the `release_impact.py --check` line, and the rows marked handled with their evidence.
6. Journeys: per journey PASS / FAIL / INVALID with the screenshot path, and the plan.json not_browser and todo
   items with their outcome.
7. Baseline defects (smoke walk or journey steps that already failed on the old app), apart.
8. Carried debt (NS-12): what the upgrade moved to the new version without fixing, listed even when every gate item
   passes. Run `python3 $B/replacement_check.py app/ --to <target ver>` and `python3 $B/dojo_report.py app/ --to
   <target ver>` on the NEW app and list every row that still hits (deprecated modules, removed widgets, behaviour
   changes) with its row id, plus widget packages in widgets/ that no module ships and deprecated widgets still in
   use, with their count. The notification-service team went to 11.12.4 carrying R3, R7, R9, R11, R25 and R26, an
   AnyChart.mpk with no module behind it and Data grid 1 back to 15 uses (5447bbf3), and nothing written said so. Each row gets an owner and "before 12" or "later".
9. Lessons: brain note candidates (through the brain gate, never straight into the brain); toolkit defects into
   this toolkit's FEEDBACK.md with status open.
Verdict codes: PASS only under the SKILL definition of done, otherwise FAIL or INVALID. "Not run" is said as such. Report words and the progress line: READING-THE-VERDICT.md section 2; a FAIL with any REGRESSION line is said "REGRESSION to fix", never "pending".
`PASS (except <systems>: N items)` (gate exit 4) is said that way, with the N NOT CHECKED items listed: never shortened
to PASS (E2E-14). `PASS (on stand-in APIs: <systems>)` is said that way too, as a conditional PASS with the stand-in
endpoints listed and "to be run again against the real test systems before go-live" (E2E-15).

## Heal and notes (L55, L56)

The diff step also gives the gate `SMOKE_REJUDGE=1` (the smoke rung judges the stored `smoke-after.json` against `smoke-before.json`; before this the smoke rung was left out of the summary), `APIMOCK` (the apis rung when the stand-in's inventory exists), `GATE_NOTES=work/gate-notes.txt` (one line per open decision, each listed as "needs a decision") and `HEAL_JSON` (see `steps/heal.md`).
