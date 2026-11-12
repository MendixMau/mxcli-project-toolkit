#!/usr/bin/env python3
"""Run generated journeys with the shared journey-runner.js, once per role, and summarise per journey.

    run_journeys.py <gen-dir> --label NAME --port 8680 --admin-port 8690 --admin-pass PASS \
                    --users users.json --work DIR [--pause 50] [--only id,id] [--compare BEFORE]
                    [--shot-accept accept.txt] [--psql CMD] [--effect-accept accept.txt] [--positive-control]
                    [--actions actions.json | --no-actions REASON] [--baseline-evidence evidence.txt]

users.json (local, never committed): {"<Role>": {"user": "...", "pass": "..."}, "_mfa": {"user": "...", "pass": "..."}}

The engine (journey-runner.js and what it requires) is COPIED from TOOLKIT_E2E (default ../vendor/e2e, a pinned copy
of the shared toolkit's project-tests/e2e, so cloud workers need no clone) into <work>/engine; it is only read. A small
project.config.js is written next to it. journey-runner.js logs in once per invocation as TEST_USER, so each role
folder is one invocation. FALLBACK_USER is set empty: a run that cannot log in as the role is a FAIL/INVALID, never an
admin run. Needs node and Playwright (PLAYWRIGHT_NODE_PATH, default ~/mendix-playwright/node_modules).

Not walked is not passed: without --only, every plan.json `skipped` entry (a role with no test user) and every `todo`
entry (for example create-save without a --create spec) is added to the summary as INVALID.

--compare (gate): the SAME journey set on the old app: its work folder (<work>, one label inside), its label folder
(<work>/<label>) or its summary.json. The path is checked before anything runs. A journey that PASSed before and does
not PASS now FAILs is a REGRESSION; one that did not PASS before is a BASELINE DEFECT, listed apart (fix the journey or
the baseline).
Screens (E4 / E5b: a dashboard that rendered with empty charts PASSed its menu journey): with --compare every
screenshot of this run is paired with the old run's screenshot of the same journey step (shotdiff.py). A journey that
PASSes but whose screen changed or lost content gets compare "SCREEN REVIEW" and counts as a failure until the pair is
accepted with a reason in --shot-accept (shotdiff.py accept format: "fnmatch-pattern-on-the-pair [@sha256:<hash>] #
reason"; pin the hash, one accept file per rung, T7-28). A journey that PASSed before and has no screenshot now is
SCREEN INVALID: missing evidence, exit 2 (N1R2-8), never a FAIL. --compare always prints "screens: N PASS, N PASS*,
N REVIEW, N INVALID" (T1-26, T4-17: it was silent when every pair passed, so the gate had nothing to cite) and stores it as summary.json "screens" (a --rejudge prints
it and writes nothing). An open pair no journey owns still keeps the exit non-zero; no pairs at all is INVALID.
Paths (gen dir, work, users, compare) may be relative.

Exit: 0 = every journey PASS; 1 = a FAIL (with --compare: a REGRESSION, NOT IN BASELINE, an open SCREEN or EFFECT REVIEW),
or the positive control missed a mutant (a ui-landing mutant not caught, or a FAIL row; UNPROVEN rungs are INFO, E7-12);
3 = judged, nothing FAILed, but something is INVALID: a journey not walked, a BASELINE DEFECT without evidence, a broken
coverage rule (E2E-11), a SCREEN INVALID pair or
no screen pairs, an EFFECT INVALID journey or none compared (N1R2-8, T2R3-11: SCREEN INVALID used to exit 1 and gate.sh showed FAIL with 0 journeys failed); the
run prints "verdict: INVALID only" and, when the OLD side is what failed, advises dropping or fixing those journeys and
running before-picked again (only journeys that did not PASS on the old run; one that PASSed there with an unusable OLD
screenshot is listed apart, "old screenshot:": accept or repair the wait, never drop, B4N1-12); 2 = the run could not
start (bad --compare path, arguments, an empty or broken journey file, named, B4T2-18); 4 = nothing FAILed or is
INVALID, but journeys are NOT CHECKED because they only failed on an excluded system (below). gate.sh maps 3 and 2 to
INVALID, never FAIL or PASS, and 4 to "PASS (except <system>: N items)" only when EXCLUDE_SYSTEMS is set. Output: <work>/<label>/summary.json and one findings file per role.

Known runner issues (FEEDBACK.md E2E-1..6): the engine reports a false login PASS when the anonymous home is a Mendix
page (T8-9: patched, a login counts only with no visible password input, no login URL and the role's READY selector;
the engine signs in on --login-path, default /login.html as smokewalk.js, not on '/', T7-10); `fill` cannot type into Mendix login widgets
(patched in the engine COPY, summary.json says whether the patch applied); the trial runtime's 6 sessions include
guest sessions (start the app with UPG_SESSION_TIMEOUT=30000 and use --pause 50); demo-user passwords are reset at
startup in DTAP mode D (set test passwords after the start); the shared example.journey.json uses an old format.

Data (E2E-9, E5b-11): the engine's seeds, data, association and outcome rungs ask OQL through `mxcli oql --direct`, which
no runapp runtime answers, so every one of them was INVALID. The engine copy now asks the app's Postgres instead:
--psql CMD (default env UPG_PSQL, e.g. "docker exec -i mig-pg psql -U mendix -d opc_after_<run>") is checked first
(pgmap.py map: entity/attribute/association -> table/column from mendixsystem$*, written to <work>/engine/pgmap.json),
then the engine runs each OQL as SQL through bin/pgdata.js + pgmap.py. Without --psql, or when the database does not
answer, summary.json "data_backend" says INVALID with the reason and every data rung is INVALID, never PASS.
Effect record: per journey step, the rows each mapped table (and association) gained or lost between before the
step's actions and the end of its checks (summary.json journeys.<id>.effects; runtime noise such as System.Session and
System.XASInstance is left out, pgmap.NOISE / UPG_EFFECT_IGNORE, also when two records are compared, B4N1-10). A plan
row closed by another journey is judged on the closer's record (B4T2-15). With --compare, a journey that PASSes on both runs must have the SAME effects on both:
a difference is EFFECT REVIEW (counts as a failure, exit 1) until each differing "<journey> step<n> <key>" matches a
line of --effect-accept ("fnmatch-pattern # reason", reason required) -> PASS*; an effect not measured on either run is
EFFECT INVALID (exit 3). --compare prints "effects: N PASS, N PASS*, N REVIEW, N INVALID" (no journey PASSing on both
runs: INVALID) and stores it as summary.json "effects". The old app is the expected result: nobody writes the
expected row counts by hand.

Coverage (E2E-11, plan section 3; T2R3 HW14: 4 home cards had no journey and nothing said so): every run prints and
stores (summary.json "coverage") "actions A found · G generated (T todo: reason n, ...) · B pass on baseline (D defect) ·
N pass on new · R regression · coverage B/A (p%)". A = --actions (bin/action_inventory.py on the OLD model); G = the
actions a journey names ("action": id, generated; "covers": [ids], hand-written); an action is PASS when every journey
naming it PASSes. A live run stores "journey_set" (sha256 of the journey files and plan.json, plus the links). With
--compare the rung is INVALID (exit 3, one "  coverage INVALID: ..." line each) when: there is no --actions and no
--no-actions REASON (the waiver prints "coverage: 1 PASS* (no denominator: REASON)": never better than PASS*); the
baseline has no set hash or another one; a journey names an action id actions.json lacks; G is 0 or D/G > 30%
("instrument not measuring"); a journey that did not pass on the baseline has no evidence. --baseline-evidence lines
"<journey fnmatch> FIXTURE|OLD-APP|FLAKY <evidence> # note" are checked, never trusted: FIXTURE = a fixture_check.py
JSON (E2E-12) listing it EMPTY, OLD-APP = a log/screenshot (path[:line]) that exists, FLAKY = two baseline reruns, one
PASS and one not. Evidenced defects are PASS* ("BASELINE DEFECT <CLASS> (...)"; one passing on new is listed for
review); unevidenced ones are INVALID, also when they now pass (before E2E-11 those were silently PASS). The journeys
line counts evidenced defects as "k PASS* (baseline defect)", not in FAIL (B4N1-13). "<plan row> UNREACHABLE
actions.json [Module=addon ...] [model=old.mpr]" makes a no-click-path skipped/todo row UNREACHABLE (PASS*, counted
apart, the denominator unchanged) when check_unreachable() holds; otherwise it stays INVALID with the refusal (B4T2-14).
"sign-out NO-SIGNOUT old.mpr" does the same for the sign-out todo of an app with no sign-out UI at all, when the
OLD model has no sign-out item or button anywhere (check_no_signout, BT-4); "create-save NO-CREATE actions.json" does it
for the create-save todo when every create action in the --actions inventory is dead in the UI or needs an existing row
(check_no_create, BT-12).

Processes (E2E-16, bin/process_journeys.py): when plan.json carries a "processes" set, the run prints and stores
(summary.json "processes") "processes C confirmed · K compiled · I invalid · P pass [· B pass on baseline · R regression]
· D draft (not compiled)" under the coverage line. A process PASSes only when all its legs (proc-<id>-<nn>) PASS; an
INVALID process is a plan "skipped" row (INVALID). A set with no confirmed process exits 3, never 0. Role folders run
in plan.json "role_order" (then by name), and ${RUN_ID} is one value per run, so a process's legs share it.
Two passes (PR-F25): every role first walks its journeys that need no data on the way, then every role (same order)
walks those whose path needs data (gen_journeys.py "_path_needs": a row in a list, a workflow instance, an open user
task), so rows the first pass creates exist for them. The second pass logs as <role>~data (run, log, shots folders);
the destructive ones among them run in a third pass, <role>~last, after every role's second (PR-F35).
Destructive tier (PR-P4): a journey whose action wipes or reseeds shared data (action_inventory.py scope identity /
delete-all / reimport, "_scope" and "resetsData" in the journey) runs after all of those, each alone as
<role>~destructive<k>, on the shared database (a copy per journey needs the app restarted on it: not done, and said).
They are reported on their own line, "destructive: P/F of N (...)", outside the coverage ratio; a login that FAILs after
one of them is CONTAMINATED, never FAIL.

Engine copy patches (v3.1, PATCHES below; `--patch-engine DIR` applies them to a scratch copy and reports): every
screenshot waits until the page has settled (settle.js; a page still loading is saved as -LOADING.png and shotdiff
marks it INVALID, E6-17; an indicator that stays on a DOM that stood still is saved as -STUCK.png, T7-22); a click goes to the widget in the topmost popup first (E6-8); new verbs toggle/switch,
select/reference/dropdown and confirm (journey-verbs.js, E7-3 / E5b-21). Fill values keep every character (':' too).
OQL through UPG_PSQL (pgdata.js, E2E-9) in helpers.js oql(); the effect record (row counts before and after each step);
each step's start and end time (leg.t0 / leg.t1, E2E-14).

External APIs (E2E-13, E2E-14): with --apimock-log <state>/requests.jsonl (apimock.py serve) and --exclude-systems
Teamcenter[,...], a FAIL journey whose every failing step called an EXCLUDED system inside that step's time window,
and no step of which called an UNKNOWN or UNMATCHED endpoint, becomes "NOT CHECKED" and is listed as
"NOT CHECKED (excluded: <System>) journey <id>: <calls>". Every other FAIL stays FAIL. Its screen pairs no longer
decide the exit; the journeys line counts it apart.
"""
import argparse, collections, json, os, re, shutil, subprocess, sys, time
from pathlib import Path

TOOLKIT_E2E = Path(os.environ.get("TOOLKIT_E2E", Path(__file__).resolve().parent.parent / "vendor" / "e2e")).expanduser()
ENGINE = ["journey-runner.js", "helpers.js", "config.js", "otel.js"]
NODE_PATH = os.environ.get("PLAYWRIGHT_NODE_PATH", str(Path("~/mendix-playwright/node_modules").expanduser()))

PROJECT_CONFIG = """'use strict';
// Written by run_journeys.py: the minimum journey-runner.js needs. Credentials come from env per role.
const path = require('path');
module.exports = {
  root: %(root)s,
  mpr: null,
  mxcli: process.env.MXCLI || 'mxcli',
  dsCss: null,
  defaultPort: %(port)s,
  // helpers.loginOnce waits for one of these after submitting. They must NOT match the login page or the
  // guest home: on E1 the anonymous home is a Mendix page, so '.mx-page' resolved before the login request
  // finished, the runner reported "login PASS" and the next page.goto aborted the login (measured).
  readySelectors: (process.env.READY_SELECTORS || '.mx-navigationtree,.mx-navbar').split(','),
  NAV: {},
  TARGETS: { 'full-app': [] },
  credentials: () => ({ user: process.env.TEST_USER, pass: process.env.TEST_PASS,
                        fallbackUser: process.env.FALLBACK_USER ?? '', fallbackPass: process.env.FALLBACK_PASS ?? '' }),
};
"""


# ENGINE PATCHES (the shared toolkit is never edited; research/journey-runner-verbs.patch.md is the upstream proposal).
# Each: (name, old text, new text). A patch whose old text is gone is reported NOT applied in summary.json and by
# --patch-engine, so an upstream change cannot silently drop it.
PATCHES = [
    # E1: `fill` looks for an input INSIDE .mx-name-<w>; Mendix login widgets render the <input> itself with that class.
    # PR-F41: and it took .first(): a hidden tab page's same-name field earlier in the DOM FAILed every comment fill;
    # V.field returns the first shown match (the topmost dialog's first), input.mx-name-<w> included
    ("fill: the first shown field, also input.mx-name-<widget> (login widgets, PR-F41)",
     "      const el = page.locator(`.mx-name-${a.widget} input, .mx-name-${a.widget} textarea`).first();\n"
     "      if (!(await el.isVisible({ timeout: 6000 }).catch(() => false)))\n"
     "        throw new Error(`.mx-name-${a.widget} input not visible`);",
     "      const el = await V.field(page, a.widget, 6000);\n"
     "      if (!el && a.optional) { console.log(`    fill: ${a.widget} not shown, optional (an input in a list with no items, FN-7)`); break; }\n"
     "      if (!el)\n"
     "        throw new Error(`.mx-name-${a.widget} input not visible (no shown match)`);"),
    ("verbs: require journey-verbs.js and settle.js",
     "const H = require(__dirname + '/helpers.js');",
     "const H = require(__dirname + '/helpers.js');\nconst V = require(__dirname + '/journey-verbs.js');\n"
     "const SETTLE = require(__dirname + '/settle.js');"),
    # PR-F27: a generated date is typed in the date picker's own format (its placeholder): 11.12.5 shows "dd mmm yyyy"
    ("fill: a generated date in the picker's placeholder format (PR-F27)",
     "      await el.fill(String(subst(a.value, vars)));",
     "      const fv = V.dateAs(await el.getAttribute('placeholder').catch(() => null), String(subst(a.value, vars)));\n"
     "      if (fv.note) console.log(`    fill: ${fv.note}`);\n"
     "      await el.fill(fv.value);"),
    # PR-F43: a fill of a list's input ("rows": true, process_journeys.py row_fields) types into every shown row
    ("fill: every shown row of a list's input (PR-F43)",
     "      await el.fill(fv.value);",
     "      await el.fill(fv.value);\n"
     "      if (a.rows) for (const o of await V.fields(page, a.widget))\n"
     "        await o.fill(V.dateAs(await o.getAttribute('placeholder').catch(() => null), String(subst(a.value, vars))).value);"),
    # E6-17: wait until the page has settled before every screenshot; a page still loading is saved as -LOADING.png
    ("shoot: wait for the page to settle, mark -LOADING or -STUCK (E6-17, T7-22)",
     "    const file = path.join(cfg.artifactsDir, `${name}.png`);\n    await page.screenshot({ path: file });",
     "    const st = /-(NOT-REACHED|ACTION-FAILED)$/.test(name) ? { ok: true } : await SETTLE.settle(page);\n"
     "    const file = path.join(cfg.artifactsDir, `${name}${st.ok ? '' : st.stuck ? '-STUCK' : '-LOADING'}.png`);\n"
     "    await page.screenshot({ path: file });\n"
     "    // NR1-25: the visible text beside the shot, so shotdiff sees a lost caption the pixels hide\n"
     "    try { require('fs').writeFileSync(file.replace(/\\.png$/, '.txt'), await page.evaluate(() => document.body.innerText)); } catch (e) { /* pixels only */ }"),
    # T8R B2-2: the landing guard waits (isVisible ignores its timeout) and a 0-height wrapper with drawn content counts;
    # PR-F39: any match of the guard counts, a hidden same-name widget earlier in the DOM no longer hides a shown one
    ("ready: wait for the landing guard, a 0-height wrapper with drawn content counts (T8R B2-2)",
     "      onPage = await page.locator(step.ui.ready).first()\n"
     "                         .isVisible({ timeout: 12000 }).catch(() => false);",
     "      onPage = await V.reached(page, page.locator(step.ui.ready), 12000);"),
    # E6-8: a popup's button can share its widget name with a button on the page behind it; click the topmost one
    # PR-F42: a.near (a process leg's ${RUN_ID}) picks the list item that names the walk's own record
    # PR-C1: a.unassigned ({"unassigned": true, "has": "Assign to me"}) picks the list item that states no assignee
    ("click: the widget in the topmost popup first (E6-8), in the own record's list item (PR-F42), the unassigned one (PR-C1)",
     "      const el = w(a.widget);\n      await el.waitFor(",
     "      const el = await V.topmost(page, a.widget, a.near, a.unassigned ? { has: a.has } : null);\n      await el.waitFor("),
    # PR-F42: an information or warning message box over the widget is answered with OK, as its user would; the
    # message is logged. Anything else still covering it stays the finding
    ("click: OK on a message box that covers the widget (PR-F42)",
     "      if (cover)\n        throw new Error(`.mx-name-${a.widget} is covered by",
     "      for (let k = 0; cover && k < 3; k++) {\n"
     "        const said = await V.ack(page);\n"
     "        if (!said) break;\n"
     "        console.log(`    ack: OK on the message \"${said.slice(0, 100)}\" over .mx-name-${a.widget}, as its user would`);\n"
     "        cover = await V.cover(el);\n"
     "      }\n"
     "      if (cover)\n        throw new Error(`.mx-name-${a.widget} is covered by"),
    # E5b-21 / E7-3: switches, native drop-downs and reference selectors, confirmation dialogs
    ("act: toggle/switch, select/reference/dropdown, row, menu, confirm (E7-3, E2E-10, PR-F35)",
     "    case 'dismissModal': await H.dismissModal(page); break;",
     "    case 'toggle': case 'switch': {\n"
     "      const got = await V.toggle(page, a, a.value === undefined ? undefined : subst(a.value, vars));\n"
     "      note('ui', `switch ${a.widget} is ${got}`, 'PASS', String(got)); break;\n    }\n"
     "    case 'select': case 'reference': case 'dropdown': {\n"
     "      const got = await V.select(page, a, String(subst(a.match ?? a.value, vars)));\n"
     "      note('ui', `select ${a.widget} committed the asked option`, 'PASS', got); break;\n    }\n"
     "    case 'combo': {\n"
     "      const got = await V.combo(page, a, String(subst(a.match ?? a.value ?? '', vars)));\n"
     "      note('ui', `combo box ${a.widget} committed ${a.first ? 'its first option' : 'the asked option'}`, 'PASS', got); break;\n    }\n"
     "    case 'row': {\n"
     "      const got = await V.row(page, a);\n"
     "      note('ui', `row: ${a.dblclick ? 'double-clicked' : 'clicked'} ${a.nth ? 'row ' + (a.nth + 1) : 'the first row'} of ${a.widget}`, 'PASS', got); break;\n    }\n"
     "    case 'item': {\n"
     "      const got = await V.item(page, a);\n"
     "      note('ui', `item: clicked navigation list item ${a.nth + 1} of ${a.widget}`, 'PASS', got); break;\n    }\n"
     "    case 'menuitem': {\n"
     "      const got = await V.menuitem(page, a);\n"
     "      note('ui', `menu item: clicked item ${a.nth + 1} of menu bar ${a.widget}`, 'PASS', got); break;\n    }\n"
     "    case 'menu': {\n"
     "      const got = await V.menu(page, a);\n"
     "      note('ui', `menu: opened pop-up menu ${a.widget}`, 'PASS', got); break;\n    }\n"
     "    case 'confirm': {\n"
     "      const got = await V.confirm(page, a);\n"
     "      note('ui', `confirm dialog closed with ${got}`, 'PASS', got); break;\n    }\n"
     "    case 'dismissModal': await H.dismissModal(page); break;"),
    ("describe: the new verbs read as sentences",
     "    case 'wait':     return { verb: 'Wait'",
     "    case 'toggle': case 'switch': return { verb: 'Switch', target: `${a.label || a.widget}${a.value === undefined ? '' : ' to ' + v(a.value)}`, selector: `.mx-name-${a.widget}` };\n"
     "    case 'select': case 'reference': case 'dropdown': return { verb: 'Choose', target: `${a.first ? 'the first option' : '\"' + v(a.match ?? a.value) + '\"'} in ${a.label || a.widget}`, selector: `.mx-name-${a.widget} select` };\n"
     "    case 'combo': return { verb: 'Choose', target: `${a.first ? 'the first option' : '\"' + v(a.match ?? a.value) + '\"'} in ${a.label || a.widget}`, selector: `.mx-name-${a.widget}` };\n"
     "    case 'row': return { verb: a.dblclick ? 'Double-click' : 'Click', target: `${a.nth ? 'row ' + (a.nth + 1) : 'the first row'} of ${a.label || a.widget}`, selector: `.mx-name-${a.widget}` };\n"
     "    case 'item': return { verb: 'Click', target: `item ${a.nth + 1} of ${a.label || a.widget}`, selector: `.mx-name-${a.widget}` };\n"
     "    case 'menuitem': return { verb: 'Click', target: `menu item ${a.nth + 1} of ${a.label || a.widget}`, selector: `.mx-name-${a.widget}-${a.nth}` };\n"
     "    case 'menu': return { verb: 'Open', target: `the menu ${a.label || a.widget}`, selector: `.mx-name-${a.widget} .popupmenu-trigger` };\n"
     "    case 'confirm': return { verb: 'Confirm', target: a.label || 'the open dialog', selector: '.modal-dialog .btn-primary' };\n"
     "    case 'wait':     return { verb: 'Wait'"),
    # PR-F44: a file input (File manager) gets a small generated file: Purchase Request's 32 workflow-admin baseline
    # defects include the attachment views, which need an attachment nobody had a verb to add
    ("act: upload a generated file into a file input (PR-F44)",
     "    case 'dismissModal': await H.dismissModal(page); break;",
     "    case 'upload': {\n"
     "      const got = await V.upload(page, a, String(subst(a.file ?? '', vars)));\n"
     "      note('ui', `upload: ${got} into ${a.widget}`, 'PASS', got); break;\n    }\n"
     "    case 'dismissModal': await H.dismissModal(page); break;"),
    ("describe: upload reads as a sentence (PR-F44)",
     "    case 'wait':     return { verb: 'Wait'",
     "    case 'upload': return { verb: 'Upload', target: `${v(a.file || V.SEED_FILE)} into ${a.label || a.widget}`, selector: `.mx-name-${a.widget}` };\n"
     "    case 'wait':     return { verb: 'Wait'"),
    # PR-P2: a step with ui.noDialog (a process step that completes a task: Received, Approve, Complete) FAILs while a
    # dialog is open after its click. The old app answers "Received" before the product line is completed with a Warning
    # box; the step's `.mx-page` guard passed ("a page is shown") and the park reported "8/8 walked" for walks that stopped.
    ("ui: a step that asserts noDialog FAILs when a dialog is open after the click (PR-P2)",
     "             body.includes(bad) ? 'rendered \u2014 the screen contradicts the data' : '', req);\n    }\n",
     "             body.includes(bad) ? 'rendered \u2014 the screen contradicts the data' : '', req);\n    }\n"
     "    if (step.ui && step.ui.noDialog) {\n"
     "      const said = await V.openDialog(page);\n"
     "      record('ui', `${step.name}: no dialog open`, said === null ? 'PASS' : 'FAIL',\n"
     "             said === null ? '' : `a dialog is open after the click, the step did not complete: ${said}`, req);\n"
     "    }\n"),
    # PR-F26: a journey that ends the session (a Discard, a sign-out, a runtime that drops it) left every later journey
    # of the role on the login form: Purchase Request pipe-19, 1 Requester journey ended it and the next 21 FAILed at
    # "role home". Signing in again here is the reset between independent journeys, not a mid-walk recovery; it is
    # said in the log, and a role whose sign-in fails again stops the walk at the next journey's first step as before.
    ("reset: sign in again when the previous journey ended the session (PR-F26)",
     "async function resetToStart(page) {\n  await page.goto(cfg.baseUrl, { waitUntil: 'domcontentloaded' });\n"
     "  await page.waitForTimeout(2500);\n}",
     "async function resetToStart(page) {\n  await page.goto(cfg.baseUrl, { waitUntil: 'domcontentloaded' });\n"
     "  await page.waitForTimeout(2500);\n"
     "  const out = await page.locator('#loginButton, .mx-name-loginButton, input[type=password]').first()\n"
     "    .isVisible().catch(() => false);\n"
     "  if (out) {\n"
     "    const li = await H.login(page);\n"
     "    console.log(`    reset: the previous journey ended the session; signed in again: ${li.ok ? 'ok' : 'FAILED ' + li.reason}`);\n"
     "  }\n}"),
    # T7-10, T8-9: login on --login-path (default /login.html, as smokewalk.js), not on '/': an anonymous home that is
    # a Mendix page with a login widget or a custom Atlas login page took the credentials and never signed in
    ("login: open LOGIN_PATH (--login-path), not / (T7-10, T8-9)",
     "  await page.goto(cfg.baseUrl + '/', { waitUntil: 'domcontentloaded' });",
     "  await page.goto(cfg.baseUrl + (process.env.LOGIN_PATH || '/'), { waitUntil: 'domcontentloaded' });",
     "helpers.js"),
    # T8-9: "signed in" = no visible password input AND not a login URL AND the role's READY selector present. The
    # engine took '.mx-page present and URL not /login', which the anonymous login PAGE already satisfies: login PASS
    # while still on the login page, then every journey FAILed on a healthy app.
    ("login: signed in only without a visible password input and with READY (T8-9)",
     "      const inApp = await page.waitForFunction(() => {\n"
     "        const onLogin = /login\\.html|\\/login(\\b|\\/|$)/.test(location.href);\n"
     "        return !onLogin && !!document.querySelector('.mx-navigationtree, .mx-page');\n"
     "      }, { timeout: 12000 }).then(() => true).catch(() => false);",
     "      const inApp = await page.waitForFunction((sel) => {\n"
     "        const onLogin = /login\\.html|\\/login(\\b|\\/|$)/.test(location.href);\n"
     "        const pw = [...document.querySelectorAll('#passwordInput, input[type=password]')].some((e) => e.getClientRects().length > 0);\n"
     "        return !onLogin && !pw && !!document.querySelector(sel);\n"
     "      }, cfg.readySelectors.concat('.mx-navigationtree').join(', '), { timeout: 12000 }).then(() => true).catch(() => false);",
     "helpers.js"),
    ("loginOnce: 'already in the app' needs READY, not .mx-page (T8-9)",
     "      && await page.locator('.mx-page').first().isVisible({ timeout: 1000 }).catch(() => false)) {",
     "      && !/login\\.html|\\/login(\\b|\\/|$)/.test(page.url())\n"
     "      && await page.locator(cfg.readySelectors.join(', ')).evaluateAll((els) => els.some((e) => e.getClientRects().length > 0)).catch(() => false)) {",
     "helpers.js"),
    ("loginOnce: wait until no password input is visible (T8-9)",
     "    const ready = document.querySelector(sel);\n    return !onLogin && !!ready;",
     "    const ready = document.querySelector(sel);\n"
     "    const pw = [...document.querySelectorAll('#passwordInput, input[type=password]')].some((e) => e.getClientRects().length > 0);\n"
     "    return !onLogin && !pw && !!ready;",
     "helpers.js"),
    # T2-11: a sign-out item in a layout menu bar renders as .mx-menubar / .mx-simplemenubar, not in the tree or navbar;
    # and an item without a title attribute is found by its exact text
    ("navTo: also menu bars, and exact text when no title matches (T2-11)",
     "    const a = [...document.querySelectorAll('.mx-navigationtree a, .mx-navbar a')]\n"
     "      .find((x) => x.getAttribute('title') === title);",
     "    const all = [...document.querySelectorAll('.mx-navigationtree a, .mx-navbar a, .mx-menubar a, .mx-simplemenubar a')];\n"
     "    const a = all.find((x) => x.getAttribute('title') === title)\n"
     "      || all.find((x) => (x.innerText || '').trim() === title);",
     "helpers.js"),
    # E2E-9 / E5b-11: `mxcli oql --direct` does not answer on a runapp runtime; ask the app's Postgres (pgdata.js)
    ("oql: SQL through UPG_PSQL (pgdata.js + pgmap.py), not mxcli oql --direct (E2E-9, E5b-11)",
     "function oql(sql) {\n  try {\n    const out = execFileSync(cfg.mxcli, [",
     "function oql(sql) {\n  if (process.env.UPG_PSQL || process.env.UPG_PGDATA_DOWN) return require(__dirname + '/pgdata.js').oql(sql);\n"
     "  try {\n    const out = execFileSync(cfg.mxcli, [",
     "helpers.js"),
    # E2E-9: the effect record: row counts of every mapped table before the step's actions and when the step ends
    ("effect: require pgdata.js (E2E-9)",
     "const O = require(__dirname + '/otel.js');",
     "const O = require(__dirname + '/otel.js');\nconst PG = require(__dirname + '/pgdata.js');"),
    ("effect: each step's leg.effect = row counts after minus before (E2E-9)",
     "    const seal = () => {\n      leg.checks = results.slice(from)",
     "    let fx0;   // E2E-9: row counts before this step's actions (null: not read, the effect is INVALID)\n"
     "    const seal = () => {\n      if (fx0 !== undefined) leg.effect = PG.effect(fx0, PG.snap());\n"
     "      leg.checks = results.slice(from)"),
    ("effect: counts taken before the actions (E2E-9)",
     "    try {\n      for (const a of step.actions || []) await act(page, a, vars, note);",
     "    fx0 = PG.snap();\n    try {\n      for (const a of step.actions || []) await act(page, a, vars, note);"),
    # E2E-14: each step's time window, so a failure can be matched to the stand-in's request log (apimock.py)
    ("step window: leg.t0 / leg.t1 (E2E-14)",
     "      leg.ms = Date.now() - t0;\n",
     "      leg.ms = Date.now() - t0;\n      leg.t0 = new Date(t0).toISOString(); leg.t1 = new Date().toISOString();\n"),
]
HERE = Path(__file__).resolve().parent


def copy_engine(eng):
    """Copy the shared engine into eng, add settle.js, journey-verbs.js, pgdata.js and pgmap.py, apply PATCHES (journey-runner.js unless the
    patch names another engine file); returns the patch report."""
    eng.mkdir(parents=True, exist_ok=True)
    for f in ENGINE:
        shutil.copy2(TOOLKIT_E2E / f, eng / f)
    for f in ("settle.js", "journey-verbs.js", "pgdata.js", "pgmap.py"):
        shutil.copy2(HERE / f, eng / f)
    texts = {}
    report = []
    for name, old, new, *where in PATCHES:
        f = where[0] if where else "journey-runner.js"
        t = texts.setdefault(f, (eng / f).read_text())
        if t.count(old) == 1:
            texts[f] = t.replace(old, new)
            report.append(name)
        else:
            report.append(f"NOT applied: {name} ({f} text changed upstream; check whether it is still needed)")
    for f, t in texts.items():
        (eng / f).write_text(t)
    return report


def run_copy_text(t, mfa, run_id):
    """The run copy of a journey file: MFA and RUN_ID placeholders filled in, everything else byte for byte (a fill
    value with ':' such as a URL stays whole, E7-3)."""
    return t.replace("${MFA_USER}", mfa.get("user", "")).replace("${MFA_PASS}", mfa.get("pass", "")).replace("${RUN_ID}", run_id)


def resolve_compare(p):
    """Work folder, label folder or summary.json of the old run -> (summary.json, label folder). Exits 2 when absent."""
    q = Path(p).expanduser().resolve()
    if q.is_dir() and not (q / "summary.json").exists():
        labels = [d for d in sorted(q.iterdir()) if d.is_dir() and (d / "summary.json").exists()]
        if len(labels) == 1:
            q = labels[0]
        elif len(labels) > 1:
            print(f"run_journeys: --compare {p}: several run labels {[d.name for d in labels]}; name one", file=sys.stderr)
            sys.exit(2)
    if q.is_dir():
        q = q / "summary.json"
    if not q.is_file():
        print(f"run_journeys: --compare {p}: no summary.json there (run_journeys writes <work>/<label>/summary.json); "
              "checked before running, nothing was run", file=sys.stderr)
        sys.exit(2)
    return q, q.parent


SHOT = __import__("re").compile(r"^shots-[^/]+/(.+?)-step\d+(?:-CTL.*)?(?:-LOADING|-STUCK)?\.png$")


def screen_compare(before_dir, out_dir, journeys, accept_file=None):
    """Pair the screenshots of both runs (shotdiff.run) and attach the worst pair verdict to each journey."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import shotdiff
    accept = shotdiff.read_accept(accept_file) if accept_file else []
    rows = shotdiff.run(str(before_dir), str(out_dir), accept=accept)
    worst = {"INVALID": 0, "REVIEW": 1, "PASS*": 2, "PASS": 3}
    per = {}
    for r in rows:
        m = SHOT.match(r["pair"])
        if not m:
            continue
        jid = m.group(1)
        if jid not in per or worst[r["verdict"]] < worst[per[jid]["verdict"]]:
            per[jid] = r
    for jid, s in journeys.items():
        r = per.get(jid)
        if r:
            s["screen"] = f"{r['verdict']} {r['detail']}"
            if s["verdict"] == "PASS" and r["verdict"] in ("REVIEW", "INVALID") and not s.get("compare"):
                s["compare"] = f"SCREEN {r['verdict']}"
    return rows


def login_preflight(port, login_path):
    """HARNESS CONDITION text when the app's login page redirects off-app (SSO / IdP, T2-7, N1-4), else None.
    No journey can sign in there: every role's journeys are INVALID (not walked), never a login FAIL of the app."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from runapp import login_redirects_off_app
    import urllib.request
    url = f"http://localhost:{port}{login_path}"
    try:
        text = urllib.request.urlopen(url, timeout=15).read().decode("utf-8", "replace")
    except Exception:
        return None   # unreachable: the runner reports that itself
    if login_redirects_off_app(text):
        return (f"HARNESS CONDITION: {url} redirects off-app (SSO): no journey can sign in; restart the app with "
                f"runapp.py --login-override (auto or a login page file), see steps/journeys.md")
    return None


def runner_env(a, role, cred, role_dir, pgenv, pglog):
    """The journey-runner.js environment for one role's login (one role folder, or a parked leg, PR-F33)."""
    ready = ".mx-navigationtree,.mx-navbar"
    lj = role_dir / f"login-{role}.journey.json"
    if lj.exists():
        ready = read_journey(lj)["steps"][0]["ui"].get("ready") or ready
    env = dict(os.environ, READY_SELECTORS=ready, LOGIN_PATH=a.login_path, APP_PORT=str(a.port), M2EE_ADMIN_PORT=str(a.admin_port), M2EE_ADMIN_PASS=a.admin_pass,
               TEST_USER=cred["user"], TEST_PASS=cred["pass"], FALLBACK_USER="", NODE_PATH=NODE_PATH,
               MXCLI=os.environ.get("MXCLI", str(Path("~/.local/bin/mxcli").expanduser())))
    for k in ("UPG_PSQL", "UPG_PGMAP", "UPG_PGDATA_DOWN"):
        env.pop(k, None)
    env.update(pgenv, UPG_PGDATA_LOG=str(pglog))
    Path(pglog).unlink(missing_ok=True)
    return env


def park(a, jdir, users, eng, pgenv, out, run_id):
    """PR-F33: walk legs 1..k of each parked process n times (plan.json processes.park), each walk with its own
    ${RUN_ID}, so workflow instances wait at the step after leg k when the second-pass journeys run. A fixture: its
    walks are logged (park.log) and counted, never verdicts. {"walks": "W of N walked", "specs": [...]}."""
    specs, done, total, logs = park_specs(a.gen_dir), 0, 0, []
    mfa = users.get("_mfa", {})
    rows = []
    for si, sp in enumerate(specs):
        ok = 0
        for i in range(sp["n"]):
            total += 1
            rid = f"{run_id}k{si}{i:02d}"
            good = True
            for leg in sp["legs"]:
                f = next(iter(sorted(jdir.glob(f"*/{leg}.journey.json"))), None)
                role = f.parent.name if f else None
                cred = users.get(role) if role else None
                if not f or not cred:
                    logs.append(f"{leg}: {'no journey file' if not f else 'no test user for role ' + role}")
                    good = False
                    break
                run = out / "run-park"
                if run.exists():
                    shutil.rmtree(run)
                run.mkdir()
                (run / f.name).write_text(run_copy_text(f.read_text(), mfa, rid))
                env = runner_env(a, role, cred, f.parent, pgenv, out / "park-pgdata.log")
                if (eng / "artifacts").exists():
                    shutil.rmtree(eng / "artifacts")
                p = subprocess.run(["node", str(eng / "journey-runner.js"), str(run / f.name)], env=env, cwd=str(eng),
                                   capture_output=True, text=True)
                logs.append(f"=== park {sp['process']} #{i + 1} {leg} as {role} (RUN_ID {rid}) exit {p.returncode}\n{p.stdout}")
                fj = eng / "artifacts" / "journey-findings.json"
                walk = next((w for w in (json.load(open(fj)).get("walks", []) if fj.exists() else [])
                             if w.get("journey") == leg), None)
                checks = [c["verdict"] for st in (walk or {}).get("steps", []) for c in st["checks"]]
                if not walk or len(walk["steps"]) != len(read_journey(f)["steps"]) or any(v != "PASS" for v in checks):
                    good = False
                    break
            ok += good
        done += ok
        rows.append({"process": sp["process"], "after": sp["after"], "n": sp["n"], "walked": ok})
        print(f"park: {sp['process']} after leg {sp['after']}: {ok} of {sp['n']} walked", file=sys.stderr)
    (out / "park.log").write_text("\n".join(logs) + "\n")
    return {"walks": f"{done} of {total} walked", "specs": rows}


def data_backend(psql, eng):
    """(line, env) for the engine's data instrument (E2E-9). The line starts with INVALID when there is no database to
    ask; the psql command itself is never printed (it may carry a password)."""
    if not psql:
        return ("INVALID: no --psql / UPG_PSQL: seeds, data, association and outcome rungs and the effect record are not "
                "measured (E5b-11: mxcli oql --direct does not answer on a runapp runtime)"), {}
    p = subprocess.run([sys.executable, str(eng / "pgmap.py"), "map", "--psql", psql, "--out", str(eng / "pgmap.json")],
                       capture_output=True, text=True)
    if p.returncode or not (eng / "pgmap.json").exists():
        why = (p.stderr or p.stdout).strip().splitlines()[-1:] or [f"pgmap exit {p.returncode}"]
        line = f"INVALID: the database did not answer the mapping query: {why[0][:300]}"
        return line, {"UPG_PSQL": psql, "UPG_PGDATA_DOWN": line}
    return f"psql: {p.stdout.strip().splitlines()[0]}", {"UPG_PSQL": psql, "UPG_PGMAP": str(eng / "pgmap.json")}


def effects_of(walk):
    """The effect record of a walked journey: one entry per step the engine walked (E2E-9)."""
    out = []
    for st in walk.get("steps", []):
        e = st.get("effect")
        if e is None:
            e = {"invalid": "no effect record (an engine copy without the E2E-9 effect patch)"}
        out.append(dict(e, n=st.get("n")))
    return out


def read_effect_accept(path):
    """'fnmatch-pattern # reason' lines; a line without a reason is refused (exit 2), as shotdiff's accepts."""
    pats = []
    for i, l in enumerate(Path(path).expanduser().read_text().splitlines(), 1):
        l = l.strip()
        if not l or l.startswith("#"):
            continue
        pat, _, why = l.partition(" #")
        if not why.strip():
            print(f"run_journeys: --effect-accept {path}:{i}: no '# reason': {l}", file=sys.stderr)
            sys.exit(2)
        pats.append((pat.strip(), why.strip()))
    return pats


CLOSED_BY = re.compile(r"\bclosed by (\S+)")


def closer_of(s):
    """The journey that closed this plan row ("closes", E7-3; covered by create-save), or None. Read from "closed_by", or
    from the row's why for a summary written before that field existed (B4T2-15)."""
    if s.get("closed_by"):
        return s["closed_by"]
    m = CLOSED_BY.search(str(s.get("why", ""))) if not s.get("effects") else None
    return m.group(1) if m else None


def effect_noise():
    """The runtime-housekeeping pattern of pgmap.py (UPG_EFFECT_IGNORE): applied again when two records are compared,
    so a record taken before a table joined the list (B4N1-10: System.XASInstance) is judged as a new one would be."""
    sys.path.insert(0, str(HERE))
    import pgmap
    return re.compile(pgmap.NOISE)


def effect_compare(journeys, before, accept=()):
    """Effect records of the journeys that PASS on both runs, old against new: per journey PASS / PASS* (every
    difference accepted) / REVIEW / INVALID (an effect not measured on either side). Returns the rows.
    A plan row closed by another journey (sign-out closed by sign-out-hand, actions covered by create-save) was walked
    as that journey: it is judged on the closer's record, on both runs, and says so (B4T2-15: it was EFFECT INVALID,
    "no effect record", although the closing journey had one). Runtime-housekeeping keys are left out (effect_noise)."""
    import fnmatch
    noise = effect_noise()
    rows = []
    for j, s in journeys.items():
        b = before.get(j, {})
        if s.get("verdict") != "PASS" or b.get("verdict") != "PASS":
            continue   # a FAIL is judged by its checks; a baseline that did not pass is no expected result
        src = closer_of(s)
        bsrc = closer_of(b) or src
        old = (before.get(bsrc, {}) if bsrc else b).get("effects")
        new = (journeys.get(src, {}) if src else s).get("effects")
        bad = [f"{side} run has no effect record" for side, e in (("old", old), ("new", new)) if not e]
        steps = {}
        for side, e in (("old", old or []), ("new", new or [])):
            for st in e:
                steps.setdefault(st.get("n"), {})[side] = st
        diffs, acc = [], []
        for n, both in sorted(steps.items(), key=lambda x: (not isinstance(x[0], int), x[0] if isinstance(x[0], int) else 0, str(x[0]))):
            if old and new and len(both) < 2:
                bad.append(f"step{n} measured on one run only")
                continue
            if len(both) < 2:
                continue
            inv = [f"{side} step{n}: {st['invalid']}" for side, st in both.items() if "invalid" in st]
            if inv:
                bad += inv
                continue
            o, w = both["old"].get("changed", {}), both["new"].get("changed", {})
            for k in sorted(k for k in set(o) | set(w) if not noise.search(k)):
                if o.get(k, 0) != w.get(k, 0):
                    d = f"step{n} {k}: old {o.get(k, 0):+d}, new {w.get(k, 0):+d}"
                    hit = next((why for pat, why in accept if fnmatch.fnmatch(f"{j} step{n} {k}", pat)), None)
                    (acc if hit else diffs).append(d + (f" (accepted: {hit})" if hit else ""))
        if bad:
            v, detail = "INVALID", "; ".join(bad)
        elif diffs:
            v, detail = "REVIEW", "; ".join(diffs + acc)
        elif acc:
            v, detail = "PASS*", "; ".join(acc)
        else:
            v = "PASS"
            moved = sorted({f"{k} {d:+d}" for st in new for k, d in st.get("changed", {}).items() if not noise.search(k)})
            detail = "same rows changed on both runs" + (f": {', '.join(moved)[:200]}" if moved else " (none)")
        if src:
            detail += f" (the record of {src}, which closed it)"
        s["effect"] = f"{v} {detail}"
        if v in ("REVIEW", "INVALID") and not s.get("compare"):
            s["compare"] = f"EFFECT {v}"
        rows.append({"journey": j, "verdict": v, "detail": detail})
    return rows


class BadJourney(ValueError):
    """A journey file that cannot be read: an empty file, not JSON, or no "id" (B4T2-18)."""


def read_journey(f):
    """One journey file -> its dict. BadJourney names the file: an empty (0 byte) journey file gave a raw traceback in
    journey_set(), the run died before any line said which file (B4T2-18)."""
    try:
        t = Path(f).read_text()
    except OSError as e:
        raise BadJourney(f"{f}: not readable ({e})")
    if not t.strip():
        raise BadJourney(f"{f}: empty file ({len(t.encode())} bytes)")
    try:
        d = json.loads(t)
    except ValueError as e:
        raise BadJourney(f"{f}: not JSON ({e})")
    if not isinstance(d, dict) or not isinstance(d.get("id"), str) or not d["id"] or not isinstance(d.get("steps"), list):
        raise BadJourney(f"{f}: no \"id\" or no \"steps\" list (a journey file is {{\"id\": ..., \"steps\": [...]}})")
    return d


def proof_problems(d):
    """TC-1: a step on a page that reads an external system ("connector": true or the system's name) must carry a "proof"
    value that only the real source returns, and the step must assert it (it is in that step's ui.textPresent). Apps
    fall back to mock data when the external call fails, so a rendered page proves nothing. Returns [problem, ...]."""
    out = []
    for i, st in enumerate(d.get("steps", []), 1):
        if not isinstance(st, dict) or not st.get("connector"):
            continue
        proof = st.get("proof")
        if not isinstance(proof, str) or len(proof.strip()) < 3:
            out.append(f"step {i} reads {st['connector'] if isinstance(st['connector'], str) else 'an external system'} "
                       "but has no \"proof\" value (a text only the real source returns, at least 3 characters)")
        elif proof not in ((st.get("ui") or {}).get("textPresent") or []):
            out.append(f"step {i}: proof {proof!r} is not asserted (put it in the step's ui.textPresent)")
        # PV-10: a denied or failed call shows mock rows (revisions A, B, C) and flips the connector's connected flag
        # to false WITHOUT an error dialog. "mockValues" lists what the mock shows: the proof must not be one of them.
        # "connected" is the text the page shows only while the connector reports connected: asserted when given.
        mocks = st.get("mockValues") or []
        if isinstance(proof, str) and proof.strip() and proof in [m for m in mocks if isinstance(m, str)]:
            out.append(f"step {i}: proof {proof!r} is also what the mock shows (mockValues): use the server's own item id")
        if "connected" in st:
            c = st["connected"]
            if not isinstance(c, str) or not c.strip():
                out.append(f"step {i}: \"connected\" must be the text the page shows while the connector is connected")
            elif c not in ((st.get("ui") or {}).get("textPresent") or []):
                out.append(f"step {i}: connected {c!r} is not asserted (put it in the step's ui.textPresent)")
    return out


def connected_notes(d):
    """PV-10: connector steps that assert a proof but no connected state. A note, not a refusal: not every connector page
    shows its state."""
    return [f"step {i} reads an external system and asserts no connected state (\"connected\": text shown only while "
            "connected; the item id alone passes while the connector is disconnected)"
            for i, st in enumerate(d.get("steps", []), 1)
            if isinstance(st, dict) and st.get("connector") and "connected" not in st]


def journey_set(gen_dir):
    """The journey set as the gate pins it (E2E-11): sha256 over every generated journey file (its path relative to the
    gen dir, then its bytes, placeholders unfilled) and plan.json, plus each journey's action ids ("action": id, or a
    hand-written journey's "covers": [id, ...]). None when the gen dir holds no journey file."""
    import hashlib
    g = Path(gen_dir)
    files = sorted((g / "journeys").glob("*/*.journey.json")) if (g / "journeys").is_dir() else []
    if not files:
        return None
    h, links, destr = hashlib.sha256(), {}, []
    for f in files + ([g / "plan.json"] if (g / "plan.json").is_file() else []):
        h.update(str(f.relative_to(g)).encode() + b"\0" + f.read_bytes() + b"\0")
    for f in files:
        d = read_journey(f)
        ids = ([d["action"]] if isinstance(d.get("action"), str) else []) + [x for x in d.get("covers") or [] if isinstance(x, str)]
        links[d["id"]] = sorted(set(ids))
        if destructive_scope(d):
            destr.append(d["id"])   # PR-P4: counted apart from the main ratio
    return {"sha256": h.hexdigest(), "files": len(files), "plan": (g / "plan.json").is_file(), "links": links,
            **({"destructive": sorted(destr)} if destr else {})}


def read_actions(path):
    """actions.json of bin/action_inventory.py (E2E-8) -> {action id: entry}. Exit 2 when it is not one."""
    try:
        acts = json.load(open(Path(path).expanduser())).get("actions")
    except (OSError, ValueError, AttributeError) as e:
        print(f"run_journeys: --actions {path}: not readable as actions.json: {e}", file=sys.stderr); sys.exit(2)
    if not isinstance(acts, list) or not all(isinstance(x, dict) and x.get("id") for x in acts):
        print(f"run_journeys: --actions {path}: no \"actions\" list of {{id, ...}} (write it with bin/action_inventory.py)",
              file=sys.stderr); sys.exit(2)
    return {x["id"]: x for x in acts}


EVIDENCE = ("FIXTURE", "OLD-APP", "FLAKY")   # why a walked journey fails on the baseline (E2E-11)
CLASSES = EVIDENCE + ("UNREACHABLE", "NO-SIGNOUT", "NO-CREATE")   # B4T2-14: why a no-click-path action is never walked (check_unreachable); BT-4: an app with no sign-out UI (check_no_signout); BT-12: no free-standing create (check_no_create)


def read_evidence(path):
    """--baseline-evidence lines '<journey fnmatch> FIXTURE|OLD-APP|FLAKY <evidence> [<evidence>] # note' (E2E-11), and
    '<journey fnmatch> UNREACHABLE <actions.json> [<Module>=<file or folder> ...] # note' (B4T2-14).
    Evidence paths are relative to the file. A line without a class or evidence is refused (exit 2)."""
    p = Path(path).expanduser().resolve()
    rows = []
    for i, l in enumerate(p.read_text().splitlines(), 1):
        l = l.strip()
        if not l or l.startswith("#"):
            continue
        body, _, note = l.partition(" #")
        parts = body.split()
        if len(parts) < 3 or parts[1] not in CLASSES:
            print(f"run_journeys: --baseline-evidence {path}:{i}: want '<journey> {'|'.join(EVIDENCE)} <evidence> # note' or "
                  f"'<journey> UNREACHABLE <actions.json> [<Module>=<file>] [model=<old .mpr>] # note': {l}",
                  file=sys.stderr); sys.exit(2)
        rel = lambda x: str(p.parent / x) if not os.path.isabs(x) else x
        refs = [rel(x) if k == 0 or parts[1] != "UNREACHABLE" or "=" not in x
                else x.partition("=")[0] + "=" + rel(x.partition("=")[2]) for k, x in enumerate(parts[2:])]
        rows.append((parts[0], parts[1], refs, note.strip(), i))
    return rows


def summary_at(p):
    """A run's summary.json from its work folder, label folder or the file itself; None when there is none."""
    q = Path(p)
    if q.is_dir() and not (q / "summary.json").exists():
        labels = [d for d in sorted(q.iterdir()) if d.is_dir() and (d / "summary.json").exists()]
        q = labels[0] if len(labels) == 1 else q
    q = q / "summary.json" if q.is_dir() else q
    try:
        return json.load(open(q))
    except (OSError, ValueError):
        return None


def check_evidence(j, cls, refs):
    """(True, detail) when the evidence holds for journey j, else (False, why). Mechanical, never trusted on its word:
    FIXTURE: a fixture_check.py JSON that lists j as EMPTY (a seed that ran and returned nothing, E2E-12);
    OLD-APP: an error screenshot or log that exists (path[:line], the line must exist);
    FLAKY: two rerun summaries of the baseline, j PASSed on one and not on the other."""
    if cls == "FIXTURE":
        try:
            r = json.load(open(refs[0])).get("journeys", {}).get(j)
        except (OSError, ValueError, AttributeError) as e:
            return False, f"FIXTURE {refs[0]}: not a fixture_check.py JSON ({e})"
        if not r:
            return False, f"FIXTURE {os.path.basename(refs[0])}: {j} not in it"
        if r.get("status") != "EMPTY":
            return False, f"FIXTURE {os.path.basename(refs[0])}: {j} is {r.get('status')}, not EMPTY (only an empty seed is a fixture gap)"
        return True, f"FIXTURE: seed {r.get('seed')} returned nothing ({os.path.basename(refs[0])})"
    if cls == "OLD-APP":
        f, _, n = refs[0].rpartition(":")
        if not (f and n.isdigit()):
            f, n = refs[0], ""
        if not os.path.isfile(f):
            return False, f"OLD-APP {refs[0]}: no such file"
        if n:
            lines = Path(f).read_text(errors="replace").splitlines()
            if not 1 <= int(n) <= len(lines):
                return False, f"OLD-APP {refs[0]}: the file has {len(lines)} lines"
            return True, f"OLD-APP: {os.path.basename(f)}:{n} {lines[int(n) - 1].strip()[:80]}"
        return True, f"OLD-APP: {os.path.basename(f)}"
    if len(refs) < 2:
        return False, "FLAKY needs two rerun summaries of the baseline"
    vs = []
    for r in refs[:2]:
        s = summary_at(r)
        if s is None:
            return False, f"FLAKY {r}: no summary.json"
        vs.append(s.get("journeys", {}).get(j, {}).get("verdict", "absent"))
    if "PASS" in vs and any(v != "PASS" for v in vs):
        return True, f"FLAKY: reruns {' / '.join(vs)}"
    return False, f"FLAKY: reruns {' / '.join(vs)} (needs one PASS and one not)"


UNREADABLE = re.compile(r"unreadable module\(s\) (.+?) may open it")


def _blobs(path):
    """(name, bytes) of every file under path: a folder recursively, a zip (an .mxmodule / .mpk) member by member, one
    level of zip inside it too; anything else as it is."""
    import io, zipfile
    def unzip(name, data, depth):
        if depth < 2 and data[:4] == b"PK\x03\x04":
            try:
                z = zipfile.ZipFile(io.BytesIO(data))
            except zipfile.BadZipFile:
                yield name, data
                return
            for m in z.namelist():
                if not m.endswith("/"):
                    yield from unzip(f"{name}!{m}", z.read(m), depth + 1)
        else:
            yield name, data
    q = Path(path)
    for f in (sorted(x for x in q.rglob("*") if x.is_file()) if q.is_dir() else [q]):
        yield from unzip(str(f), f.read_bytes(), 0)


def check_no_signout(j, entry, refs):
    """(True, detail) when the app has no sign-out UI to walk, else (False, why) (BT-4). `sign-out NO-SIGNOUT <old.mpr>`.
    Never on its word: the plan row must be the generator's own "no tested role has a sign-out item" todo with no
    unreadable menu in its reasons (an add-on menu may hold the item), and a scan of every page, layout, snippet, menu
    document and navigation profile of the OLD model (impact_map.any_sign_out) must find no item or button that signs
    out (platform action, a flow named like sign-out, or a Sign out / Log out caption). One hit refuses it."""
    if j != "sign-out":
        return False, f"NO-SIGNOUT is for the sign-out plan row only, not {j}"
    why = str(entry.get("why") or "")
    if not why.startswith("no tested role has a sign-out item"):
        return False, "NO-SIGNOUT: the plan row is not the generator's 'no tested role has a sign-out item' todo"
    if "not in the model" in why or "no items read" in why or "no layout in the model" in why:
        return False, "NO-SIGNOUT: the todo lists a menu the model cannot read (add-on module?): it may hold the item"
    mp = refs[0] if refs else ""
    if not mp or not os.path.exists(mp):
        return False, f"NO-SIGNOUT: the OLD model {mp or '(none given)'} is not readable: give <the OLD .mpr>"
    try:
        sys.path.insert(0, str(HERE))
        from mprmodel import Model
        import impact_map
        hits = impact_map.any_sign_out(Model.load(mp))
    except Exception as e:
        return False, f"NO-SIGNOUT: model {mp} not readable ({e})"
    if hits:
        w, by, d = hits[0]
        return False, f"NO-SIGNOUT: {w} signs out ({by}: {d}): write the sign-out journey, the app has one"
    return True, f"NO-SIGNOUT: no page, layout, snippet, menu or navigation profile of {os.path.basename(mp)} has a sign-out item"


def check_no_create(j, entry, refs, acts_file, acts):
    """(True, detail) when the app has no free-standing create to walk as the core create-and-save, else (False, why)
    (BT-12). `create-save NO-CREATE <actions.json> # note`. Never on its word: the plan row is the generator's own
    "no --create spec" todo, refs[0] is the --actions inventory itself (as UNREACHABLE), and every action of kind create
    in it is either dead in the UI (a no-click-path todo) or reached only on a list row / inside a row container / under
    a data-dependent condition (a click step with row, within or shown_if: it needs a record that is already there, so
    it is no first create). One create with a plain click path refuses it: write its create-spec."""
    if j != "create-save":
        return False, f"NO-CREATE is for the create-save plan row only, not {j}"
    if not str(entry.get("why") or "").startswith("no --create spec"):
        return False, "NO-CREATE: the plan row is not the generator's 'no --create spec' todo"
    if acts is None or not acts_file:
        return False, "NO-CREATE is checked against --actions (the OLD model's actions.json): none given"
    try:
        same = refs[0] and Path(refs[0]).read_bytes() == Path(acts_file).expanduser().read_bytes()
    except OSError as e:
        return False, f"NO-CREATE {refs[0]}: not readable ({e})"
    if not same:
        return False, f"NO-CREATE {os.path.basename(refs[0])}: not the --actions file (the inventory the denominator comes from)"
    creates = [x for x in acts.values() if x.get("kind") == "create"]
    dead = dep = 0
    for x in creates:
        if any(str(t).startswith("no-click-path") for t in x.get("todo") or []):
            dead += 1
            continue
        steps = [st for st in x.get("path") or [] if isinstance(st, dict) and "click" in st]
        if any(st.get("row") or st.get("row_only") or st.get("within") or st.get("shown_if") for st in steps) or not steps:
            dep += 1
            continue
        return False, f"NO-CREATE: {x['id']} is a create with a plain click path (menu to button): write its create-spec"
    return True, (f"NO-CREATE: actions.json has {len(creates)} create action(s): {dead} dead in the UI, {dep} only on an existing "
                  "row / under a data condition; none is a free-standing first create")


def check_unreachable(j, entry, refs, acts_file, acts):
    """(True, detail) when the action behind plan row j is proven dead in the OLD UI, else (False, why) (B4T2-14).
    Never taken on its word, and never from the run (a negative cannot be walked):
    - refs[0] is the --actions inventory itself (bin/action_inventory.py on the OLD model; the denominator's file);
    - its entry for the action says "no-click-path (no entry point reaches it"; "a non-click caller reaches it" is
      reachable (a microflow opens the page) and is refused;
    - every unreadable module the entry says "may open it" (a protected add-on) is given as <Module>=<file or folder>,
      the file looks like that module (its name is in it) and names none of the documents that lead to the page: the
      host, via_pages and their whole readable caller chain in the OLD model (model=<.mpr>, else actions.json "model");
      a readable microflow only the add-on calls is a way in too, so the model is required whenever an add-on is.
      On the Opcenter Starter Kit the inventory said "unreachable" for ClientConfiguration_NewEdit while the EXFN add-on
      opens it (create-save walks it): the model alone is no proof when a module cannot be read."""
    if acts is None or not acts_file:
        return False, "UNREACHABLE is checked against --actions (the OLD model's actions.json): none given"
    try:
        same = refs[0] and Path(refs[0]).read_bytes() == Path(acts_file).expanduser().read_bytes()
    except OSError as e:
        return False, f"UNREACHABLE {refs[0]}: not readable ({e})"
    if not same:
        return False, f"UNREACHABLE {os.path.basename(refs[0])}: not the --actions file (the inventory the denominator comes from)"
    aid = entry.get("action") or (j[4:] if j.startswith("act-") else j)
    x = acts.get(aid)
    if not x:
        return False, f"UNREACHABLE: {aid} is not in actions.json"
    todo = [t for t in x.get("todo") or [] if str(t).startswith("no-click-path")]
    if not todo:
        return False, f"UNREACHABLE: actions.json gives {aid} a click path (no no-click-path todo): walk it"
    if "no entry point reaches it" not in todo[0]:
        return False, f"UNREACHABLE: actions.json says {todo[0]}: reachable, not dead in the UI"
    pages = [p for p in dict.fromkeys([x.get("host")] + list(x.get("via_pages") or [])) if p]
    mods = []
    for u in x.get("unknown") or []:
        m = UNREADABLE.search(str(u))
        if m:
            mods += [s.strip() for s in m.group(1).split(",") if s.strip()]
    given = dict(r.partition("=")[::2] for r in refs[1:] if "=" in r)
    mods = list(dict.fromkeys(mods))
    for m in mods:   # what is missing is said first: the add-on file, then the model
        if not given.get(m):
            return False, (f"UNREACHABLE: unreadable module {m} may open {pages[-1] if pages else aid} (actions.json): give "
                           f"{m}=<its project.mpr, .mxmodule or folder> and the tool checks it never names the page")
        if not os.path.exists(given[m]):
            return False, f"UNREACHABLE: {m}={given[m]}: no such file"
    chain = list(pages)
    if mods:   # the add-on may open any readable document on the way to the page, not only the page itself
        mp = given.pop("model", None)
        if not mp:
            try:
                mp = json.loads(Path(acts_file).expanduser().read_text()).get("model")
            except (OSError, ValueError, AttributeError):
                mp = None
        if not mp or not os.path.exists(mp):
            return False, (f"UNREACHABLE: the OLD model is needed to list what calls {pages[-1] if pages else aid} "
                           f"({mp or 'actions.json names none'}: not found): give model=<the OLD .mpr>")
        try:
            sys.path.insert(0, str(HERE))
            from mprmodel import Model
            mm = Model.load(mp)
            callers = mm.callers_index()
        except Exception as e:
            return False, f"UNREACHABLE: model={mp}: not readable ({e})"
        seen_d, todo_d = [], list(x.get("via_pages") or [x.get("host")])
        while todo_d and len(seen_d) < 2000:   # the readable caller chain, walked as action_inventory.py orphans() does
            q = todo_d.pop()
            if not q or q in seen_d:
                continue
            seen_d.append(q)
            todo_d.extend(c for c in callers.get(q, ()) if not mm.excluded(c) and c != q)
        chain = list(dict.fromkeys(chain + seen_d))
    seen = []
    for m in mods:
        f = given[m]
        blobs = list(_blobs(f))
        if not any(m.encode() + b"." in d for _, d in blobs):
            return False, f"UNREACHABLE: {m}={os.path.basename(f)}: the name {m} is not in it (not that module, or compressed)"
        for pg in chain:
            hit = next((n for n, d in blobs if pg.encode() in d), None)
            if hit:
                return False, (f"UNREACHABLE: {m} names {pg} ({os.path.basename(hit)})"
                               f"{'' if pg in pages else ', which leads to ' + (pages[-1] if pages else aid)}: "
                               "it may open it, not dead in the UI")
        seen.append(f"{m} ({len(blobs)} files)")
    return True, (f"UNREACHABLE: actions.json: no entry point reaches {', '.join(pages) or aid}"
                  + (f"; none of {len(chain)} document(s) on the way named in {', '.join(seen)}" if seen else ""))


DEFECT_MAX = 0.30   # E2E-11: more than 30% of the generated set failing on the OLD app = the instrument is not measuring


def coverage(js, before, cur_set, base_set, acts, waive, evidence, compare, skip_reasons=None, oos=None):
    """The coverage line and the honesty rules of rung 8 (E2E-11, plan section 3). Returns a dict: line, the counts,
    defects {journey: (class or None, detail)}, invalid [reasons] (only with compare: they make the rung INVALID)."""
    links = (cur_set or {}).get("links")
    if links is None:   # an older summary: the walked journeys are the ones that are not plan rows
        links = {j: s.get("actions", []) for j, s in js.items()
                 if s.get("verdict") != "INFO" and not str(s.get("why", "")).startswith(("skipped:", "todo:"))}
    invalid = []
    # PR-P4: a journey whose action wipes or reseeds shared data is reported on its own line ("destructive: P/F of N"), so
    # it neither lifts nor sinks the main ratio, whichever side has the reset (DEFECT_MAX stays comparable)
    dest = set((cur_set or {}).get("destructive") or [])
    apart = {i for j in dest for i in links.get(j, [])}
    links = {j: ids for j, ids in links.items() if j not in dest}
    if acts is not None:
        units, stale = {}, []
        for j, ids in links.items():
            for i in ids:
                (units.setdefault(i, []) if i in acts else stale).append(j if i in acts else f"{j} -> {i}")
        if stale:
            invalid.append(f"{len(stale)} journey action ids not in actions.json (stale inventory?): {', '.join(stale[:5])}")
    else:
        units = {j: [j] for j in links}   # no denominator: count journeys, stated as such
    base = before if compare else js
    ok = lambda side, jids: all(side.get(j, {}).get("verdict") == "PASS" for j in jids)
    G = len(units)
    B = sum(1 for u in units.values() if ok(base, u))
    D = G - B
    N = sum(1 for u in units.values() if ok(js, u)) if compare else None
    R = sum(1 for u in units.values() if any(js.get(j, {}).get("compare") == "REGRESSION" for j in u)) if compare else None
    nr = lambda x: "-" if x is None else x
    if acts is not None:
        A = len(acts)
        todo = {}
        oos = {i: c for i, c in (oos or {}).items() if i in acts and i not in units}   # out of scope, not walked: not in the denominator
        for i, x in acts.items():
            if i not in units and i not in apart and i not in oos:
                t = (x.get("todo") or [""])[0]   # the inventory's reason: its first word ("combobox: ...")
                if not t and (skip_reasons or {}).get(i):   # PRF-2: a reason the generator gave (assign-to-me-dead), not a defect
                    t = skip_reasons[i]
                k = re.split(r"[ :(]", str(t).strip(), maxsplit=1)[0] or "no journey"
                todo[k] = todo.get(k, 0) + 1
        T = sum(todo.values())
        tt = f"{T} todo" + (": " + ", ".join(f"{k} {n}" for k, n in sorted(todo.items(), key=lambda x: (-x[1], x[0]))) if todo else "")
        Am = A - len(apart & set(acts)) - len(set(oos) - apart)   # PR-P4: the destructive actions are counted on their own line
        cov = f"{B}/{Am}" + (f" ({100 * B // Am}%)" if Am else "")
        line = (f"actions {A} found · {G} generated ({tt}) · {B} pass on baseline ({D} defect) · {nr(N)} pass on new · "
                f"{nr(R)} regression · coverage {cov}")
        if apart:
            line += f" · {len(apart)} destructive run apart (own line)"
        if oos:   # journey_scope.py: INFO with a reason, never INVALID, not counted in the coverage denominator
            bc = collections.Counter(oos.values())
            line += f" · {len(oos)} out of scope, INFO (" + ", ".join(f"{k} {n}" for k, n in sorted(bc.items())) + ")"
        U = sum(1 for s in js.values() if s.get("verdict") == "UNREACHABLE")
        if U:   # B4T2-14: listed apart, the denominator unchanged: proven dead in the OLD UI is not covered
            line += f" · {U} todo unreachable in the OLD UI (evidenced, PASS*)"
    else:
        A = T = None
        why = f"no denominator: {waive}" if waive else "no actions.json: coverage unknown"
        line = (f"actions ? found · {G} journeys (todo unknown) · {B} pass on baseline ({D} defect) · {nr(N)} pass on new · "
                f"{nr(R)} regression · coverage ? ({why})")
    out = {"line": line, "A": A, "G": G, "T": T, "B": B, "D": D, "N": N, "R": R, "defects": {}, "invalid": invalid,
           "out_of_scope": len(oos) if acts is not None and oos else 0}
    if not compare:
        return out
    if acts is None and not waive:
        invalid.append("coverage unknown: no --actions (actions.json, bin/action_inventory.py) and no --no-actions REASON")
    if not (base_set or {}).get("sha256"):
        invalid.append("the baseline recorded no journey-set hash: run before-picked again with this toolkit on this set")
    elif not (cur_set or {}).get("sha256"):
        invalid.append("this run's journey set is not hashed (no generated journey files)")
    elif base_set["sha256"] != cur_set["sha256"]:
        invalid.append(f"journey set changed since the baseline (sha256 {base_set['sha256'][:12]} then, {cur_set['sha256'][:12]} now): "
                       "run before-picked again on this set")
    if G == 0:
        invalid.append("instrument not measuring: no journey " + ("names an action of actions.json (generate with gen_journeys.py "
                       "--actions, or link a hand-written journey with \"covers\")" if acts is not None else "was walked"))
    elif D / G > DEFECT_MAX:
        invalid.append(f"instrument not measuring: {D} of {G} {'actions' if acts is not None else 'journeys'} fail on the "
                       f"baseline ({100 * D // G}% > {int(DEFECT_MAX * 100)}%)")
    import fnmatch
    # every walked journey, linked to an action or not. The destructive tier (PR-P4) is counted apart but is judged the
    # same way: a destructive journey that did not PASS on the old app needs the same checked evidence, else it kept the
    # tag "BASELINE DEFECT (before FAIL)" with no evidence and sat in FAIL although the old app failed it too.
    for j in sorted(set(links) | {d for d in dest if d in base}):
        if base.get(j, {}).get("verdict") == "PASS":
            continue
        hit = next((r for r in evidence if r[1] in EVIDENCE and fnmatch.fnmatch(j, r[0])), None)
        if hit is None:
            out["defects"][j] = (None, "no evidence")
            continue
        good, detail = check_evidence(j, hit[1], hit[2])
        out["defects"][j] = (hit[1] if good else None, detail if good else f"evidence line {hit[4]}: {detail}")
    bad = [j for j, (c, _) in out["defects"].items() if c is None]
    if bad:
        invalid.append(f"{len(bad)} baseline defects without evidence (FIXTURE / OLD-APP / FLAKY, --baseline-evidence): "
                       + ", ".join(bad[:5]))
    return out


def session_cap_refused(findings_path):
    """BT-7: True when the engine's findings say the runtime refused the login for its session limit (the engine's own text
    for a faulted login, vendor/e2e/journey-runner.js: 'trial-licence concurrent-session cap'), not for the credentials."""
    try:
        F = json.load(open(findings_path))
    except (OSError, ValueError):
        return False
    login = next((r for r in F.get("results", []) if r.get("rung") == "ui" and r.get("name") == "login"), None)
    return bool(login and login.get("verdict") == "INVALID" and "concurrent-session cap" in (login.get("detail") or ""))


def session_wait(a):
    """Seconds to wait before a retry: the pause between roles (the app runs with UPG_SESSION_TIMEOUT=30000 and the cluster
    manager frees expired sessions every 15 s) plus a margin; --session-wait overrides."""
    return a.session_wait if a.session_wait else max(a.pause, 50) + 15


def login_outcome(login, prior_dirty):
    """PR-P4: (role login word, journey verdict, why prefix) for a role whose sign-in did not PASS. A login that FAILs after
    a destructive journey ran on this same database is CONTAMINATED, not a failure of this role: the journey may have
    deleted its account (identity), its data or the seed. A harness problem (INVALID) stays INVALID. ("PASS", None, "")
    when the sign-in passed."""
    if login and login["verdict"] == "PASS":
        return "PASS", None, ""
    if login and login["verdict"] == "FAIL" and prior_dirty:
        return ("CONTAMINATED", "CONTAMINATED",
                f"CONTAMINATED: login FAIL after {prior_dirty} ran on the same database, not a failure of this role: ")
    v = login["verdict"] if login else "INVALID"
    return v, "INVALID" if v == "INVALID" else "FAIL", ""


def destructive_summary(journeys):
    """PR-P4: the destructive journeys (scope identity / delete-all / reimport) counted apart from the main ratio:
    ({"n", "pass", "fail", "contaminated", "invalid", "by_scope", "line"}, line), or None when there is none. The line is
    "destructive: P/F of N (...)": P pass, F fail, of N journeys; CONTAMINATED (a login that failed after one of them ran
    on the same database) is listed apart, never counted as a fail. They share the database with the rest and run last:
    a copy per journey needs the app restarted on it, which this runner does not do, and the line says so."""
    dj = {j: s for j, s in journeys.items() if s.get("destructive")}
    if not dj:
        return None
    n = lambda v: sum(1 for s in dj.values() if s["verdict"] == v)
    by = {k: sum(1 for s in dj.values() if s["destructive"] == k) for k in DESTRUCTIVE_SCOPES}
    d = {"n": len(dj), "pass": n("PASS"), "fail": n("FAIL"), "contaminated": n("CONTAMINATED"), "invalid": n("INVALID"),
         "by_scope": {k: v for k, v in by.items() if v}, "isolation": "shared database"}
    d["line"] = (f"destructive: {d['pass']}/{d['fail']} of {d['n']} ({', '.join(f'{k} {v}' for k, v in d['by_scope'].items())}"
                 + (f"; {d['contaminated']} CONTAMINATED" if d["contaminated"] else "")
                 + (f"; {d['invalid']} INVALID" if d["invalid"] else "")
                 + "; shared database, run after the main set, not in the coverage ratio)")
    return d


def shown_if_at(journey, walked):
    """PR-F38: the visibility conditions (gen_journeys step "shown_if") of the first step that did not pass: the widget
    that step waits for or clicks is drawn only when they hold, so a FAIL there on the baseline reads as the state the
    data was in, not as a broken page. Purchase Request pipe-30: 62 of 91 baseline FAILs clicked such a widget
    ("Retry" shown only for a Failed workflow, "Open parent workflow" only for a sub-workflow). None when it has none."""
    steps = journey.get("steps") or []
    k = next((i for i, s in enumerate(walked) if any(c["verdict"] != "PASS" for c in s.get("checks", []))), None)
    if k is None and len(walked) < len(steps):
        k = len(walked)       # the walk stopped before this step
    return (steps[k].get("shown_if") or None) if k is not None and k < len(steps) else None


def shown_tag(s):
    """PR-F38: the FAIL line's " [shown only if ...]" for a summary entry with "shown_if", else ""."""
    return f" [shown only if {'; '.join(s['shown_if'])[:160]}]" if s.get("shown_if") else ""


def role_dirs(jdir, gen_dir):
    """The role folders in the order they run: plan.json "role_order" first (E2E-16: a process's requester leg runs
    before its approver leg, bin/process_journeys.py), then the rest by name, as before."""
    if not jdir.is_dir():
        return []
    try:
        order = json.load(open(Path(gen_dir) / "plan.json")).get("role_order") or []
    except (OSError, ValueError):
        order = []
    return sorted((d for d in jdir.iterdir() if d.is_dir()),
                  key=lambda d: (order.index(d.name) if d.name in order else len(order), d.name))


DATA_WAVE = "~data"   # PR-F25: the second pass of a role, folder/log/shots suffix and summary["roles"] key
LAST_WAVE = "~last"   # PR-F35: the third pass, the destructive journeys that need data, after every role's second


DESTR_WAVE = "~destructive"   # PR-P4: one wave per destructive journey, after every other pass: <role>~destructive<k>
DESTRUCTIVE_SCOPES = ("identity", "delete-all", "reimport")   # action_inventory.py SCOPES[:3]; gen_journeys.py writes "_scope"


def data_wave(key):
    """True for a pass that needs the parked process data (second, third and destructive pass)."""
    return key.endswith(DATA_WAVE) or key.endswith(LAST_WAVE) or DESTR_WAVE in key


def destructive_scope(d):
    """PR-P4: the scope of a journey in the destructive tiers (identity, delete-all, reimport), else None."""
    return d.get("_scope") if d.get("_scope") in DESTRUCTIVE_SCOPES else None


def data_waves(jdir, gen_dir, only=None):
    """[(key, role, role_dir, files)] in the order they run. First pass: every role (role_dirs order) with its journeys
    that need no data on the way. Second pass, same role order: the journeys whose path needs data ("_path_needs",
    gen_journeys.py: a row in a list, a workflow instance, an open user task), so the rows the first pass created
    (a requester's submit starts the workflow an admin page lists) exist when they run (PR-F25, Purchase Request
    pipe-18: 106 baseline defects, 51 behind one per-row button in a list nobody had filled yet). A journey set
    without "_path_needs" runs as before: one pass, keys = role names. Third pass (PR-F35), same role order: the
    second-pass journeys gen_journeys marks "_destructive" (a delete, a workflow operation), so an admin's Abort on the
    first workflow listed cannot remove the task a later role's second pass needs (Purchase Request pipe-30: the
    Administrator~data pass runs before Receiver~data, alphabetically). Fourth (PR-P4): a journey whose action wipes or
    reseeds shared data (scope identity / delete-all / reimport, action_inventory.py) runs after all of those, alone in
    its own runner process (<role>~destructive<k>), whether or not its path needs data: "Reset" has no needs and ran in
    the first pass, as the Administrator, before every other role (seeding report 1). Each would run on a fresh copy of
    the database if the runner could restart the app on one; it cannot, so they share it, last, and are labelled so."""
    first, later, last, destr = [], [], [], []
    for role_dir in role_dirs(jdir, gen_dir):
        files = sorted(role_dir.glob("*.journey.json"))
        if only:
            files = [f for f in files if read_journey(f)["id"] in only]
        tier = [f for f in files if destructive_scope(read_journey(f))]
        files = [f for f in files if f not in tier]
        destr += [(f"{role_dir.name}{DESTR_WAVE}{k}", role_dir.name, role_dir, [f]) for k, f in enumerate(tier, 1)]
        need = [f for f in files if read_journey(f).get("_path_needs")]
        rest = [f for f in files if f not in need]
        kill = [f for f in need if read_journey(f).get("_destructive")]
        need = [f for f in need if f not in kill]
        if rest:
            first.append((role_dir.name, role_dir.name, role_dir, rest))
        if need:
            later.append((role_dir.name + DATA_WAVE, role_dir.name, role_dir, need))
        if kill:
            last.append((role_dir.name + LAST_WAVE, role_dir.name, role_dir, kill))
    return first + later + last + destr


ASSIGN_CTE = """t AS (SELECT t.id, min(tu."system$userid") AS uid FROM "system$workflowusertask" t
  JOIN "system$workflowusertask_targetusers" tu ON tu."system$workflowusertaskid" = t.id
  WHERE t.state = 'InProgress' AND NOT EXISTS (SELECT 1 FROM "system$workflowusertask_assignees" x
                                               WHERE x."system$workflowusertaskid" = t.id)
  GROUP BY t.id HAVING count(*) = 1),
r AS (SELECT id, uid, ROW_NUMBER() OVER (PARTITION BY uid ORDER BY id DESC) AS rn FROM t)"""
ASSIGN_REST = "SELECT id, uid FROM r WHERE rn > {keep}"   # PR-P1: all but the `keep` newest waiting tasks of each user
ASSIGN_SQL = ("WITH " + ASSIGN_CTE + ",\nins AS (INSERT INTO \"system$workflowusertask_assignees\" (\"system$workflowusertaskid\", "
              "\"system$userid\")\n        " + ASSIGN_REST + " RETURNING 1)\nSELECT count(*) FROM ins;")
ASSIGN_PICK = "WITH " + ASSIGN_CTE + "\n" + ASSIGN_REST   # the same selection as a plain SELECT (controls on SQLite)
PARK_KEEP = 1   # PR-P1: waiting tasks per target user the park step leaves unassigned (--park-unassigned)


def assign_sole_targets(psql, keep=PARK_KEEP):
    """PR-F33: assign every waiting user task (InProgress, no assignee) whose only target user is one user to that
    user, so the task shows in that user's "my tasks" list. The smoke user is its role's only holder on a journey copy
    (PR-F32), so a role's tasks land with its smoke user; a task several users may take stays unassigned. Stands in for
    an "Assign to me" the old app may not render (Purchase Request on 10.24: an empty data view, D31); the same fixture
    runs on both apps. PR-P1: the `keep` newest such tasks of each user stay unassigned (default 1), because "Assign to
    me" / "Assign to user" render only for a task with no assignee: with every task assigned, ten buttons of the
    Purchase Request task pages had no target (pr-baseline cluster 1, "park: assigned 14"). (n, None) or (None, why)."""
    keep = max(0, int(keep))
    if not psql:
        return None, "no --psql"
    import shlex
    try:
        r = subprocess.run(shlex.split(psql) + ["-X", "-tA", "-v", "ON_ERROR_STOP=1"], input=ASSIGN_SQL.replace("{keep}", str(keep)),
                           capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, f"psql did not run: {e}"
    if r.returncode:
        return None, (r.stderr or r.stdout or f"psql exit {r.returncode}").strip().splitlines()[-1][:300]
    return int(r.stdout.strip() or 0), None


def park_specs(gen_dir):
    """PR-F33: plan.json processes.park, [{"process", "n", "after", "legs"}] (bin/process_journeys.py "park:")."""
    try:
        return (json.load(open(Path(gen_dir) / "plan.json")).get("processes") or {}).get("park") or []
    except (OSError, ValueError):
        return []


def process_coverage(js, plan, before=None):
    """E2E-16: "processes C confirmed · K compiled · I invalid · P pass [· B pass on baseline · R regression] · D draft
    (not compiled)" from plan.json "processes" (bin/process_journeys.py). A process PASSes when every one of its legs
    PASSes; a leg not walked makes it INVALID, never PASS. None when the plan has no process set."""
    pr = (plan or {}).get("processes")
    if not pr:
        return None
    legs, bad = pr.get("legs") or {}, {e["id"] for e in pr.get("invalid") or []}

    def one(pid, jj):
        if pid in bad:
            return "INVALID"
        vs = [(jj.get(l) or {}).get("verdict") for l in legs.get(pid) or []]
        if not vs or None in vs:
            return "INVALID"
        return "PASS" if all(v == "PASS" for v in vs) else "FAIL" if "FAIL" in vs else "INVALID"

    now = {pid: one(pid, js) for pid in list(legs) + sorted(bad)}
    p = sum(1 for v in now.values() if v == "PASS")
    line = (f"processes {pr.get('confirmed', 0)} confirmed · {pr.get('compiled', 0)} compiled · {len(bad)} invalid · "
            f"{p} pass")
    res = {"confirmed": pr.get("confirmed", 0), "compiled": pr.get("compiled", 0), "invalid": len(bad), "pass": p,
           "draft": pr.get("draft", 0), "verdicts": now, "legs": legs, "drafts": pr.get("drafts") or []}
    if before is not None:
        was = {pid: one(pid, before) for pid in legs}
        res["baseline_pass"] = sum(1 for v in was.values() if v == "PASS")
        res["regression"] = sorted(pid for pid, v in was.items() if v == "PASS" and now.get(pid) == "FAIL")
        line += f" · {res['baseline_pass']} pass on baseline · {len(res['regression'])} regression"
    line += f" · {pr.get('draft', 0)} draft (not compiled)"
    if not res["confirmed"]:
        line += " (INVALID: no confirmed process; a human confirms the drafts)"
    res["line"] = line
    return res


def verdict(vs):
    return "FAIL" if "FAIL" in vs else "INVALID" if "INVALID" in vs or not vs else "PASS"


def control_verdict(results):
    """Positive-control rows of one role: (counts, misses, rows). The control holds when every ui-landing mutant is
    caught (PASS) and no row FAILs. A rung the journeys declare nothing for ("UNPROVEN", the trace, data and outcome
    rungs without oql) is INFO, not a miss (E7-12: 5 of 5 ui-landing mutants caught, the run still exited 1)."""
    ctl = [r for r in results if r.get("rung") == "control"]
    unproven = lambda r: r["verdict"] == "INVALID" and "UNPROVEN" in r.get("detail", "")
    counts = {"PASS": 0, "FAIL": 0, "INVALID": 0, "INFO": 0}
    for r in ctl:
        counts["INFO" if unproven(r) else r["verdict"] if r["verdict"] in counts else "INVALID"] += 1
    land = [r for r in ctl if "ui-landing" in r["name"]]
    misses = [f"{r['verdict']} {r['name']}" for r in ctl if r["verdict"] == "FAIL"]
    misses += [f"{r['verdict']} {r['name']}" for r in land if r["verdict"] != "PASS" and r["verdict"] != "FAIL"]
    misses += [f"{r['verdict']} {r['name']}: {r.get('detail', '')[:80]}" for r in ctl
               if r["verdict"] == "INVALID" and not unproven(r) and r not in land]
    if not land:
        misses.append("no ui-landing control row: the control did not run")
    rows = [f"{'INFO' if unproven(r) else r['verdict']} {r['name']}" for r in ctl]
    return counts, misses, rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("gen_dir")
    ap.add_argument("--label", required=True)
    ap.add_argument("--port")
    ap.add_argument("--admin-port")
    ap.add_argument("--admin-pass")
    ap.add_argument("--users")
    ap.add_argument("--rejudge", action="store_true",
                    help="judge <work>/<label>/summary.json again with --compare/--shot-accept; no app, nothing written")
    ap.add_argument("--work", required=True)
    ap.add_argument("--positive-control", action="store_true")
    ap.add_argument("--only", help="comma list of journey ids")
    ap.add_argument("--compare", help="the same journey set on the old app: work folder, label folder or summary.json (gate)")
    ap.add_argument("--shot-accept", help="shotdiff accept file: screen changes that are expected, each with a reason")
    ap.add_argument("--psql", default=os.environ.get("UPG_PSQL") or None,
                    help="psql command for the app's database (default env UPG_PSQL): seeds, data rungs, effect record (E2E-9)")
    ap.add_argument("--park-unassigned", type=int, default=PARK_KEEP, metavar="M",
                    help=f"waiting single-target tasks per user the park step leaves unassigned, so 'Assign to me' has a "
                         f"target (default {PARK_KEEP}; 0 assigns every one, as before PR-P1)")
    ap.add_argument("--effect-accept", help="effect differences that are expected: '<journey> step<n> <Entity> # reason' (fnmatch)")
    ap.add_argument("--actions", help="actions.json of the OLD model (bin/action_inventory.py): the coverage denominator (E2E-11)")
    ap.add_argument("--no-actions", metavar="REASON",
                    help="no actions.json, on purpose: coverage is unknown and the rung is at best PASS* (E2E-11)")
    ap.add_argument("--baseline-evidence", metavar="FILE",
                    help="why each journey that fails on the baseline does: '<journey> FIXTURE|OLD-APP|FLAKY <evidence> # note'")
    ap.add_argument("--apimock-log", help="apimock.py request log (<state>/requests.jsonl): FAILs on excluded systems (E2E-14)")
    ap.add_argument("--exclude-systems", default="", help="comma list, e.g. Teamcenter: only these may make a journey NOT CHECKED")
    ap.add_argument("--bar", choices=("all", "processes"), default="all",
                    help="what blocks PASS (B5-3): all (default) = every journey and every coverage rule; processes = "
                         "the confirmed key-user processes: their legs, any REGRESSION / FAIL / REVIEW, a confirmed process; "
                         "action coverage and other INVALID journeys are reported, not blocking")
    ap.add_argument("--pause", type=int, default=0,
                    help="seconds to wait between role runs, so expired sessions are freed on a trial runtime (6 session cap)")
    ap.add_argument("--session-retries", type=int, default=2,
                    help="BT-7: how often a role whose login the runtime refused for its session limit is run again after "
                         "--session-wait seconds (default 2; 0 = never)")
    ap.add_argument("--session-wait", type=int, default=0,
                    help="seconds to wait before such a retry (default: --pause, at least 50, plus 15)")
    ap.add_argument("--login-path", default="/login.html",
                    help="where the engine signs in (default /login.html, as smokewalk.js; T7-10, T8-9). '/' only for an "
                         "app whose anonymous home renders the standard login form itself")
    ap.add_argument("--patch-engine", metavar="DIR",
                    help="only copy and patch the engine into DIR, print the patch report (exit 1 if one did not apply)")
    a = ap.parse_args()
    if a.patch_engine:
        rep = copy_engine(Path(a.patch_engine).expanduser().resolve())
        print("\n".join(rep))
        sys.exit(1 if any(r.startswith("NOT applied") for r in rep) else 0)
    if not a.rejudge and not (a.port and a.admin_port and a.admin_pass and a.users):
        ap.error("--port, --admin-port, --admin-pass and --users are required (except with --rejudge)")

    cmp_summary = cmp_dir = None
    if a.compare:  # E4-22: check the path BEFORE the run, not after it
        cmp_summary, cmp_dir = resolve_compare(a.compare)
    if a.actions and a.no_actions:
        ap.error("--actions and --no-actions exclude each other")
    if a.no_actions is not None and not a.no_actions.strip():
        ap.error("--no-actions needs a reason")
    acts = read_actions(a.actions) if a.actions else None   # checked before running too (E2E-11)
    evidence = read_evidence(a.baseline_evidence) if a.baseline_evidence else []
    a.gen_dir = str(Path(a.gen_dir).expanduser().resolve())   # E5b-8: a relative --work broke every journey
    jfiles = Path(a.gen_dir) / "journeys"   # B4T2-18: every journey file read before anything runs, a bad one named
    for f in (sorted(jfiles.glob("*/*.journey.json")) if jfiles.is_dir() else []):
        try:
            jd = read_journey(f)
            bad = proof_problems(jd)
            if bad:
                raise BadJourney(f"{f}: CONNECTOR NO PROOF (TC-1): " + "; ".join(bad))
            for note in connected_notes(jd):
                print(f"NOTE (PV-10) {f.name}: {note}", file=sys.stderr)
        except BadJourney as e:
            print(f"run_journeys: journey file {e}: INVALID, nothing was run (fix or remove the file, then run again; "
                  "a removed journey changes the set: before-picked again)", file=sys.stderr)
            sys.exit(2)
    if a.rejudge:  # judge an existing run again (new --compare / --shot-accept); runs nothing, writes nothing
        out = Path(a.work).expanduser().resolve() / a.label
        summary = json.load(open(out / "summary.json"))
        for s in summary["journeys"].values():
            s.pop("compare", None); s.pop("screen", None); s.pop("effect", None)
            if s.get("verdict") == "UNREACHABLE":   # B4T2-14: judged again below from the evidence, never kept
                s["verdict"] = "INVALID"
            s.pop("unreachable", None); s.pop("unreachable_refused", None)
        summary.pop("coverage", None)
        only = None
    else:
        users = json.load(open(Path(a.users).expanduser()))
        work = Path(a.work).expanduser().resolve()
        eng = work / "engine"
        patches = copy_engine(eng)
        (eng / "project.config.js").write_text(PROJECT_CONFIG % {"root": json.dumps(str(work)), "port": json.dumps(str(a.port))})
        out = work / a.label
        out.mkdir(parents=True, exist_ok=True)
        only = set(a.only.split(",")) if a.only else None

        backend, pgenv = data_backend(a.psql, eng)
        summary = {"label": a.label, "port": a.port, "login_path": a.login_path, "engine_patches": patches,
                   "data_backend": backend, "journey_set": journey_set(a.gen_dir), "roles": {}, "journeys": {}}
        print(f"data: {backend}", file=sys.stderr)
        jdir = Path(a.gen_dir) / "journeys"
        harness = login_preflight(a.port, a.login_path)
        if harness:
            summary["harness"] = harness
            print(harness, file=sys.stderr)
        run_id = time.strftime("%m%d%H%M%S")  # ${RUN_ID}: a value unique per run, so a create-save on a reused DB cannot pass on an old row (E5b 25);
        # one value for the whole run, not one per role: the legs of one process (E2E-16) type and check the same value
        parked = None
        dirty = None   # PR-P4: the destructive journey that last ran on this database, "<id> (<scope>)"
        for key, role, role_dir, files in data_waves(jdir, a.gen_dir, only):
            prior_dirty = dirty
            if DESTR_WAVE in key and files:
                dirty = f"{read_journey(files[0])['id']} ({destructive_scope(read_journey(files[0]))})"
            if data_wave(key) and not harness and not a.positive_control and park_specs(a.gen_dir):
                if parked is None:   # PR-F33: once, before the first second-pass role: tasks wait at each stage
                    parked = park(a, jdir, users, eng, pgenv, out, run_id)
                    summary["park"] = parked
                n, why = assign_sole_targets(a.psql, a.park_unassigned)
                parked.setdefault("assigned", {})[key] = n if why is None else f"INVALID: {why}"
                print(f"park: before {key}: assigned {n if why is None else 'nothing (' + why + ')'}", file=sys.stderr)
            if harness:
                summary["roles"][key] = {"login": "INVALID", "why": harness}
                for f in files:
                    summary["journeys"][read_journey(f)["id"]] = {"role": role, "verdict": "INVALID", "why": harness}
                continue
            cred = users.get(role)
            if not cred:
                for f in files:
                    summary["journeys"][read_journey(f)["id"]] = {"role": role, "verdict": "INVALID", "why": "no test user for role"}
                continue
            run = out / f"run-{key}"
            if run.exists():
                shutil.rmtree(run)
            run.mkdir()
            mfa = users.get("_mfa", {})
            for f in files:  # run copy with the MFA placeholders filled in; the generated file keeps none
                (run / f.name).write_text(run_copy_text(f.read_text(), mfa, run_id))
            env = runner_env(a, role, cred, role_dir, pgenv, out / f"{key}-pgdata.log")
            art = eng / "artifacts"
            cmd = ["node", str(eng / "journey-runner.js"), *map(str, sorted(run.glob("*.journey.json")))]
            if a.positive_control:
                cmd.append("--positive-control")
            if a.pause and summary["roles"]:
                time.sleep(a.pause)
            name = "journey-findings-control.json" if a.positive_control else "journey-findings.json"
            fj = art / name
            # BT-7: an app with more roles than the runtime's named-session limit (COLLAB: 7 roles on a 6-session trial
            # runtime) saw the last roles refused although every run signs out. The refusal is a session that has not
            # expired yet, not a verdict about the role: wait until the sessions are freed and run the role again, up to
            # --session-retries times. The retries are written to summary.json (session_retries) and stay visible.
            tries = 0
            while True:
                if art.exists():
                    shutil.rmtree(art)
                p = subprocess.run(cmd, env=env, cwd=str(eng), capture_output=True, text=True)
                (out / f"{key}.log" if not tries else out / f"{key}.retry{tries}.log").write_text(p.stdout + "\n--- stderr\n" + p.stderr)
                if tries >= a.session_retries or not session_cap_refused(fj):
                    break
                tries += 1
                wait = session_wait(a)
                print(f"session cap: {role} refused by the runtime's session limit; waiting {wait}s for sessions to expire, retry {tries} of {a.session_retries}", file=sys.stderr)
                time.sleep(wait)
            if not fj.exists():
                summary["roles"][key] = {"exit": p.returncode, "login": "INVALID", "why": "runner wrote no findings; see log"}
                for f in files:
                    summary["journeys"][read_journey(f)["id"]] = {"role": role, "verdict": "INVALID", "why": "runner did not run"}
                continue
            shutil.copy2(fj, out / f"{key}-{name}")
            shots = out / f"shots-{key}"
            if shots.exists():
                shutil.rmtree(shots)
            shutil.copytree(art, shots, ignore=shutil.ignore_patterns("*.json"))
            F = json.load(open(fj))
            login = next((r for r in F["results"] if r["rung"] == "ui" and r["name"] == "login"), None)
            # PR-P4: a login that FAILs after a destructive journey ran on this same database is not a finding about this
            # role: the journey may have deleted its account (identity), its data or the seed. CONTAMINATED, never FAIL
            lword, lverdict, lwhy = login_outcome(login, prior_dirty)
            summary["roles"][key] = {"exit": p.returncode, "user": cred["user"], "login": lword,
                                      "login_detail": login["detail"] if login else ""}
            if tries:
                summary["roles"][key]["session_retries"] = tries
            if lverdict == "CONTAMINATED":
                summary["roles"][key]["contaminated_by"] = prior_dirty
            pl = Path(env["UPG_PGDATA_LOG"])
            if pl.exists():   # why the data instrument answered nothing (E2E-9): the first distinct reasons
                summary["roles"][key]["data_errors"] = list(dict.fromkeys(pl.read_text().splitlines()))[:5]
            if a.positive_control:
                counts, bad, rows = control_verdict(F["results"])
                summary["roles"][key]["control"] = counts
                summary["roles"][key]["control_bad"] = bad
                summary["roles"][key]["control_rows"] = rows
                continue
            walked = {w["journey"]: w for w in F.get("walks", [])}
            for f in files:
                jid = read_journey(f)["id"]
                w = walked.get(jid)
                if login is None or login["verdict"] != "PASS":
                    summary["journeys"][jid] = {"role": role, "verdict": lverdict,
                                                "why": lwhy + f"login {login['verdict'] if login else 'missing'}: {login['detail'] if login else ''}"}
                    continue
                if not w:
                    summary["journeys"][jid] = {"role": role, "verdict": "INVALID", "why": "journey not walked (seed or earlier fault)"}
                    seed = [r for r in F["results"] if r["name"].startswith(f"{jid}: seeds")]
                    if seed:
                        summary["journeys"][jid]["why"] = seed[0]["detail"]
                    continue
                checks = [c for s in w["steps"] for c in s["checks"]]
                failed = [f"{c['verdict']} {c['name']} {c['detail']}".strip() for c in checks if c["verdict"] != "PASS"]
                # a journey whose last step never ran is not a PASS even if every recorded check passed
                complete = len(w["steps"]) == len(read_journey(f)["steps"])
                v = verdict([c["verdict"] for c in checks] + ([] if complete else ["INVALID"]))
                summary["journeys"][jid] = {"role": role, "verdict": v, "checks": len(checks), "not_pass": failed[:6],
                                            "shots": [s["shot"]["file"] for s in w["steps"] if s.get("shot")],
                                            "effects": effects_of(w),
                                            "windows": [{"n": s.get("n"), "t0": s.get("t0"), "t1": s.get("t1"),
                                                         "ok": all(c["verdict"] == "PASS" for c in s["checks"])} for s in w["steps"]]}
                cond = shown_if_at(read_journey(f), w["steps"]) if v != "PASS" else None
                if cond:
                    summary["journeys"][jid]["shown_if"] = cond
        # a hand-written journey may close plan items: "closes": ["menu:Wizard", ...] (E7-3)
        for f in (sorted(jdir.glob("*/*.journey.json")) if jdir.is_dir() else []):
            d = read_journey(f)
            if d.get("closes") and d["id"] in summary["journeys"]:
                summary["journeys"][d["id"]]["closes"] = list(d["closes"])
            if destructive_scope(d) and d["id"] in summary["journeys"]:   # PR-P4
                summary["journeys"][d["id"]]["destructive"] = destructive_scope(d)
    plan_p = Path(a.gen_dir) / "plan.json"
    if not only and not a.positive_control and plan_p.exists():  # not walked is not passed
        plan = json.load(open(plan_p))
        closers = {t: j for j, s in summary["journeys"].items() for t in s.get("closes", [])}
        for k in ("skipped", "todo"):
            for e in plan.get(k, []):
                if e["id"] in closers:  # the closing journey's verdict is the item's verdict
                    c = summary["journeys"][closers[e["id"]]]
                    summary["journeys"][e["id"]] = {"role": c.get("role", ""), "verdict": c["verdict"], "closed_by": closers[e["id"]],
                                                    "why": f"{k} closed by {closers[e['id']]} (hand-written journey)"}
                    continue
                summary["journeys"].setdefault(e["id"], {"role": e.get("role", ""), "verdict": "INVALID", "why": f"{k}: {e.get('why', '')}"})
        # a changed vendor page no entry point reaches: NOT PROVED, so it cannot drop out of the report (E6-20)
        for e in plan.get("not_browser", []):
            if e.get("no_entry"):
                summary["journeys"].setdefault(e["id"], {"role": "", "verdict": "INVALID", "why": e.get("why", "no entry point: NOT PROVED")})
        # listed, not blocking: a role home another journey already walks, a page no entry point reaches (E5b 22)
        for k in ("covered", "unreachable", "out_of_scope"):
            for e in plan.get(k, []):
                if e["id"] in closers:  # T4-8: a role home microflow closed by login-<role> takes that journey's verdict
                    c = summary["journeys"][closers[e["id"]]]
                    summary["journeys"].setdefault(e["id"], {"role": c.get("role", ""), "verdict": c["verdict"],
                                                             "closed_by": closers[e["id"]], "why": f"{k}: closed by {closers[e['id']]}"})
                    continue
                row = {"role": e.get("role", ""), "verdict": "INFO", "why": f"{k}: {e.get('why', '')}"}
                if k == "out_of_scope":   # journey_scope.py: only test what is used and reachable; INFO, never INVALID
                    row.update(scope_class=e.get("class", "?"), why=f"out of scope ({e.get('class', '?')}): {e.get('why', '')}")
                summary["journeys"].setdefault(e["id"], row)
        # B4T2-14: a no-click-path plan row is UNREACHABLE (PASS*, its own count) only with checked evidence that nothing
        # on the OLD app opens it; without it, or when the check fails, it stays INVALID with the reason
        unr = [r for r in evidence if r[1] in ("UNREACHABLE", "NO-SIGNOUT", "NO-CREATE")]
        if unr:
            import fnmatch
            for k in ("skipped", "todo"):
                for e in plan.get(k, []):
                    s = summary["journeys"].get(e["id"])
                    hit = next((r for r in unr if fnmatch.fnmatch(e["id"], r[0])), None)
                    if not s or not hit or s.get("closed_by") or s["verdict"] != "INVALID":
                        continue
                    good, detail = (check_no_signout(e["id"], e, hit[2]) if hit[1] == "NO-SIGNOUT"
                                    else check_no_create(e["id"], e, hit[2], a.actions, acts) if hit[1] == "NO-CREATE"
                                    else check_unreachable(e["id"], e, hit[2], a.actions, acts))
                    if good:
                        s["verdict"], s["unreachable"] = "UNREACHABLE", detail + (f" # {hit[3]}" if hit[3] else "")
                    else:
                        s["unreachable_refused"] = f"evidence line {hit[4]}: {detail}"
    nc_lines = []
    if a.apimock_log and a.exclude_systems:   # E2E-14: before the compare, so a NOT CHECKED journey is no REGRESSION
        import apimock
        nc_lines = apimock.mark_journeys(summary["journeys"], a.apimock_log, apimock.systems_arg(a.exclude_systems))
    if a.compare:
        before = json.load(open(cmp_summary)).get("journeys", {})
        for j, s in summary["journeys"].items():
            b = before.get(j, {}).get("verdict")
            if s["verdict"] != "FAIL":  # INVALID stays INVALID: it says nothing about the upgrade
                continue
            if b == "PASS":
                s["compare"] = "REGRESSION"
            elif b is None:
                s["compare"] = "NOT IN BASELINE (run it on the old app too)"
            else:
                s["compare"] = f"BASELINE DEFECT (before {b})"
        if not a.positive_control:  # T1-26 / T4-17: the screens line is printed (and stored) even when all pairs PASS
            import shotdiff
            rows = screen_compare(cmp_dir, out, summary["journeys"], a.shot_accept)
            c, line = shotdiff.counts_line(rows)
            if not rows:
                line += " (INVALID: no screenshot pairs under the two runs)"
            summary["screens"] = dict(c, line=line, unpinned=sum(1 for r in rows if r.get("unpinned")),
                                      pairs=[{k: r.get(k) for k in ("pair", "verdict", "detail", "sha")} for r in rows])
            # E2E-9: the old run's effect record is the expected result of the new one
            erows = effect_compare(summary["journeys"], before, read_effect_accept(a.effect_accept) if a.effect_accept else ())
            ec = {v: sum(1 for r in erows if r["verdict"] == v) for v in ("PASS", "PASS*", "REVIEW", "INVALID")}
            eline = f"effects: {ec['PASS']} PASS, {ec['PASS*']} PASS*, {ec['REVIEW']} REVIEW, {ec['INVALID']} INVALID"
            if not erows:
                eline += " (INVALID: no journey PASSes on both runs)"
            summary["effects"] = dict(ec, line=eline, rows=erows)
    cov = None
    if not a.positive_control:   # E2E-11: the coverage line, and with --compare the rules that keep INVALID honest
        cur_set = (summary.get("journey_set") if a.rejudge else None) or journey_set(a.gen_dir)
        if cur_set and not summary.get("journey_set"):
            summary["journey_set"] = cur_set
        before_all = json.load(open(cmp_summary)) if a.compare else {}
        skr, oos_map = {}, {}
        if plan_p.exists():
            oos_map = {e["action"]: e.get("class", "?") for e in json.load(open(plan_p)).get("out_of_scope", []) if e.get("action")}
        if plan_p.exists():   # PRF-2: the generator's reason for an action it did not walk, named in the coverage line
            skr = {e["action"]: (e.get("reasons") or [""])[0] for e in json.load(open(plan_p)).get("skipped", []) if e.get("action")}
        cov = coverage(summary["journeys"], before_all.get("journeys", {}), cur_set, before_all.get("journey_set"),
                       acts, a.no_actions, evidence, bool(a.compare), skr, oos_map)
        for j, (cls, detail) in cov["defects"].items():
            s = summary["journeys"].get(j)
            if not s or s["verdict"] not in ("PASS", "FAIL"):
                continue   # INVALID on this run says nothing more; a plan row has no baseline
            b = before_all["journeys"].get(j, {}).get("verdict", "absent")
            if cls:   # evidenced: listed, PASS* (a FAIL on both sides), or for review when the new app passes it
                s["compare"] = f"BASELINE DEFECT {cls}" + (", passes on new: review" if s["verdict"] == "PASS" else "") + f" ({detail})"
            else:
                s["compare"] = f"BASELINE DEFECT (before {b})" + (", passes on new" if s["verdict"] == "PASS" else "") + f": {detail}"
        for j, s in summary["journeys"].items():   # FN-36: a plan row closed by a journey takes that journey's evidenced defect
            cb = s.get("closed_by")
            if cb and s["verdict"] == "FAIL" and (cov["defects"].get(cb) or (None,))[0]:
                c, d = cov["defects"][cb]
                s["compare"] = f"BASELINE DEFECT {c} (closed by {cb}; {d})"
        summary["coverage"] = {k: v for k, v in cov.items() if k != "defects"}
        summary["coverage"]["defects"] = {j: {"class": c, "detail": d} for j, (c, d) in cov["defects"].items()}
    pcov = None
    if not a.positive_control and plan_p.exists():   # E2E-16: the process line, next to the action coverage line
        before_j = json.load(open(cmp_summary)).get("journeys", {}) if a.compare else None
        pcov = process_coverage(summary["journeys"], json.load(open(plan_p)), before_j)
        if pcov:
            summary["processes"] = pcov
    anon = None
    if not a.positive_control and plan_p.exists():   # S: one process run as the anonymous role, when guest access is on
        anon = anonymous_check(summary, pcov, plan_p)
    dsum = destructive_summary(summary["journeys"]) if not a.positive_control else None
    if dsum:
        summary["destructive"] = dsum
    if not a.rejudge:
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"== {a.label} (:{a.port})" + (f" compared with {a.compare}" if a.compare else ""))
    if summary.get("data_backend"):
        print(f"  data {summary['data_backend'][:200]}")
    if summary.get("park"):   # PR-F33: the fixture's own line, so a park that walked nothing is seen, not inferred
        pk = summary["park"]
        print(f"  park {pk['walks']} ("
              + ", ".join(f"{r['process']} after leg {r['after']}: {r['walked']}/{r['n']}" for r in pk["specs"])
              + "); assigned " + ", ".join(f"{k} {v}" for k, v in pk.get("assigned", {}).items()))
    for r, s in summary["roles"].items():
        print(f"  role {r:24} login {s['login']:7} {s.get('login_detail', '')[:60]}" + (f"  control {s['control']}" if "control" in s else ""))
        for e in s.get("data_errors", []):
            print(f"    data: {e[:160]}")
    scoped = collections.Counter(s["scope_class"] for s in summary["journeys"].values() if s.get("scope_class"))
    for k, n in sorted(scoped.items()):   # one line per class, the rows are in summary.json
        print(f"  INFO    out of scope ({k}): {n} actions listed, no journey, never INVALID (plan.json out_of_scope, scope.json)")
    for j, s in summary["journeys"].items():
        if s.get("scope_class"):
            continue
        tag = (f" [{s['compare']}]" if s.get("compare") else "") + (f" screen {s['screen'][:70]}" if s.get("screen", "PASS").split()[0] not in ("PASS",) else "")
        tag += f" effect {s['effect'][:120]}" if s.get("effect", "PASS").split()[0] not in ("PASS",) else ""
        tag += f" [UNREACHABLE refused, {s['unreachable_refused'][:300]}]" if s.get("unreachable_refused") else ""
        what = s.get("unreachable") or ('; '.join(s.get('not_pass', [])) or s.get('why', ''))[:150]
        tag += shown_tag(s)
        tag += f" [DESTRUCTIVE({s['destructive']})]" if s.get("destructive") else ""
        print(f"  {s['verdict']:7} {j:55} {what}{tag}")
    vs = [s["verdict"] for s in summary["journeys"].values()]
    ctl_bad = any(s.get("control_bad") for s in summary["roles"].values())
    for r, s in summary["roles"].items():
        for why in s.get("control_bad") or []:
            print(f"  CONTROL MISS {r}: {why}")
        if s.get("control", {}).get("INFO"):
            print(f"  INFO {r}: {s['control']['INFO']} rungs UNPROVEN (the journeys declare nothing those mutants can break; "
                  f"trace, data and outcome need oql and stay INVALID in the gate, they are not control failures)")
    if a.compare:
        fail = any(s.get("compare") in ("REGRESSION", "NOT IN BASELINE (run it on the old app too)", "SCREEN REVIEW", "EFFECT REVIEW")
                   for s in summary["journeys"].values())   # SCREEN / EFFECT INVALID is INVALID, never FAIL (N1R2-8)
    else:
        fail = "FAIL" in vs
    counts = {v: vs.count(v) for v in ("PASS", "FAIL", "INVALID", "INFO", "NOT CHECKED", "UNREACHABLE", "CONTAMINATED")}
    # E2E-11: a baseline defect with checked evidence is PASS* (listed), not INVALID; without evidence it stays INVALID.
    # B4N1-13: the headline counts it as PASS* (baseline defect), not as FAIL next to "= N PASS*" two lines down;
    # an unevidenced FAIL stays FAIL
    evid = {j for j, s in summary["journeys"].items() if re.match(r"BASELINE DEFECT (FIXTURE|OLD-APP|FLAKY)\b", str(s.get("compare", "")))}
    for j in evid:
        counts[summary["journeys"][j]["verdict"]] -= 1
    for l in nc_lines:
        print(l)
    print(f"journeys: {counts['PASS']} PASS, {counts['FAIL']} FAIL, {counts['INVALID']} INVALID"
          + (f", {len(evid)} PASS* (baseline defect)" if evid else "")
          + (f", {counts['UNREACHABLE']} PASS* (unreachable in the OLD UI, evidence checked)" if counts["UNREACHABLE"] else "")
          + (f", {counts['NOT CHECKED']} NOT CHECKED (excluded: {a.exclude_systems})" if counts["NOT CHECKED"] else "")
          + (f", {counts['CONTAMINATED']} CONTAMINATED (login failed after a destructive journey on the same database)" if counts["CONTAMINATED"] else "")
          + (f", {counts['INFO']} INFO (covered, unreachable or out of scope, listed only)" if counts["INFO"] else ""))
    if cov:
        print(cov["line"])
    if dsum:
        print(dsum["line"])
    if pcov:
        print(pcov["line"])
    if anon:
        print(anon["line"])
    veff = ["PASS*" if j in evid or s["verdict"] == "UNREACHABLE" else s["verdict"] for j, s in summary["journeys"].items()]
    ex = (1 if fail or ctl_bad else INVALID_ONLY if any(v not in ("PASS", "INFO", "PASS*", "NOT CHECKED") for v in veff)
          else EXCLUDED_ONLY if counts["NOT CHECKED"] else 0)
    if cov and a.compare:
        if a.no_actions:
            print(f"coverage: 1 PASS* (no denominator: {a.no_actions})")
        if cov["defects"]:
            cls = {}
            for c, _ in cov["defects"].values():
                cls[c or "none"] = cls.get(c or "none", 0) + 1
            ok = len(cov["defects"]) - cls.get("none", 0)
            print(f"defects: {len(cov['defects'])} failing on the baseline: " + (f"{ok} with evidence ("
                  + ", ".join(f"{c} {cls[c]}" for c in EVIDENCE if c in cls) + f") = {ok} PASS*" if ok else "0 with evidence")
                  + f", {cls.get('none', 0)} without (INVALID)")
        for why in cov["invalid"]:
            print(f"  coverage INVALID: {why}")
        if ex in (0, EXCLUDED_ONLY) and cov["invalid"]:
            ex = INVALID_ONLY
    nc = {j for j, s in summary["journeys"].items() if s["verdict"] == "NOT CHECKED"}
    sc = summary.get("screens")
    if sc:
        print(sc["line"])
        if sc["unpinned"]:
            print("  unpinned accepts match every image of that name, on every rung: pin them with the @sha256 shotdiff prints")
        # a pair no journey owns still counts: an open screen pair never leaves the run green; a NOT CHECKED journey's
        # pairs are not judged (it failed on an excluded system, E2E-14)
        own = lambda p: (SHOT.match(p.get("pair") or "") or [None, None])[1] not in nc
        review = sum(1 for p in sc["pairs"] if p["verdict"] == "REVIEW" and own(p))
        invalid = sum(1 for p in sc["pairs"] if p["verdict"] == "INVALID" and own(p))
        if ex in (0, INVALID_ONLY, EXCLUDED_ONLY) and review:
            ex = 1
        elif ex in (0, EXCLUDED_ONLY) and (invalid or not sc["pairs"]):
            ex = INVALID_ONLY
    ef = summary.get("effects")
    if ef:
        print(ef["line"])
        if ex in (0, INVALID_ONLY, EXCLUDED_ONLY) and ef["REVIEW"]:
            ex = 1
        elif ex in (0, EXCLUDED_ONLY) and (ef["INVALID"] or not ef["rows"]):
            ex = INVALID_ONLY
    if pcov and not pcov["confirmed"] and ex in (0, EXCLUDED_ONLY):
        ex = INVALID_ONLY   # E2E-16: a process set with nothing confirmed proves no process; never green by absence
    if anon and anon["pass"] < anon["required"] and ex in (0, EXCLUDED_ONLY):
        ex = INVALID_ONLY   # S: guest access is on and no process PASSes as the anonymous role
    if a.bar == "processes":
        ex = process_bar(summary, pcov, ex, nc, anon)
    elif ex == INVALID_ONLY:
        print(invalid_only_line(summary, json.load(open(cmp_summary)).get("journeys", {}) if a.compare else {}))
    sys.exit(ex)


EXCLUDED_ONLY = 4  # E2E-14: only NOT CHECKED (excluded system) besides PASS; gate.sh: "PASS (except ...)", never plain PASS
INVALID_ONLY = 3   # N1R2-8 / T2R3-11: "nothing FAILed, something INVALID" has its own exit, so gate.sh never shows FAIL


def baseline_side(detail):
    """True when a screen pair is INVALID because the OLD side failed (shotdiff details)."""
    return "BASELINE DEFECT" in detail or "no OLD screenshot" in detail or ("STUCK" in detail and "OLD" in detail)


ALWAYS_ON = re.compile(r"^(login-|mfa-password-only-refused$|sign-out$|create-save$|anonymous-)")   # S: gen_journeys.py's always-on set


def anonymous_check(summary, pcov, plan_p):
    """S, the anonymous denominator: when plan.json names an anonymous role (guest access on, gen_journeys.py), one
    confirmed process run as that role must PASS: "anonymous process: P of 1 required". 0 blocks the gate. The plan's
    skipped row for the role (anonymous-<role>, "write it by hand") takes the verdict of that process when it PASSes,
    and stays INVALID otherwise. None when guest access is off."""
    role = (json.load(open(plan_p)) if plan_p.exists() else {}).get("anonymous_role")
    if not role:
        return None
    js, legs = summary["journeys"], (pcov or {}).get("legs") or {}
    procs = [pid for pid, ls in legs.items() if any((js.get(l) or {}).get("role") == role for l in ls)]
    passed = [pid for pid in procs if pcov["verdicts"].get(pid) == "PASS"]
    key = f"anonymous-{role}"
    if key in js:
        js[key] = ({"role": role, "verdict": "PASS", "closed_by": passed[0], "why": f"anonymous process {passed[0]} PASS"}
                   if passed else {"role": role, "verdict": "INVALID", "why": "anonymous role: no process PASSes as it"})
    line = (f"anonymous process: {len(passed)} of 1 required (role {role}"
            + (f"; {len(procs)} process(es) run as it" if procs else "; no confirmed process runs as it") + ")")
    return {"role": role, "pass": len(passed), "required": 1, "line": line}


def process_bar(summary, pcov, ex, nc, anon=None):
    """B5-3, the user's PASS bar "key processes": PASS = every confirmed key-user process passes on old and new, 0
    regressions, nothing open for review. Exit 1 stays exit 1 (a FAIL, REGRESSION, SCREEN or EFFECT REVIEW from ANY
    journey, a control miss). Otherwise only the processes decide: no process set or none confirmed, a process
    INVALID (compile or a leg not walked / INVALID / SCREEN or EFFECT INVALID) is INVALID; a process whose legs PASS
    except legs NOT CHECKED on an excluded system is EXCLUDED_ONLY. S: an always-on journey (a role's login, sign-out,
    MFA, create-save, the anonymous role) that is INVALID, and an anonymous role with no PASSing process, also block.
    Action coverage and the INVALID count of the other journeys are printed, never hidden, and do not block."""
    js = summary["journeys"]
    always = sorted(j for j, s in js.items() if s["verdict"] == "INVALID" and ALWAYS_ON.match(j))
    others = sum(1 for j, s in js.items() if s["verdict"] == "INVALID" and not j.startswith("proc-") and j not in always)
    cov = (summary.get("coverage") or {}).get("invalid") or []
    why, excl = [], False
    if ex != 1:
        ex = 0
        if always:
            why.append("always-on journeys INVALID: " + ", ".join(always))
        if anon and anon["pass"] < anon["required"]:
            why.append(anon["line"])
        if not pcov:
            why.append("no process set (processes.md, process_journeys.py): the bar has nothing to judge")
        elif not pcov["confirmed"]:
            why.append("no confirmed process; a human confirms the drafts" + (": " + ", ".join(pcov.get("drafts") or [])
                                                                              if pcov.get("drafts") else ""))
        if pcov:
            legs = pcov.get("legs") or {}
            for pid, v in sorted(pcov["verdicts"].items()):
                ls = legs.get(pid) or []
                bad = [l for l in ls if str((js.get(l) or {}).get("compare", "")) in ("SCREEN INVALID", "EFFECT INVALID")
                       or str((js.get(l) or {}).get("effect", "")).startswith("INVALID")]
                if v == "FAIL":
                    ex = 1
                elif v == "INVALID" and ls and all((js.get(l) or {}).get("verdict") in ("PASS", "NOT CHECKED") for l in ls) \
                        and any(l in nc for l in ls):
                    excl = True
                elif v == "INVALID" or bad:
                    why.append(f"process {pid} INVALID" + (f" (legs {', '.join(bad)})" if bad else ""))
        if ex != 1:
            ex = INVALID_ONLY if why else EXCLUDED_ONLY if excl else 0
    n = len((pcov or {}).get("verdicts") or {})
    print(f"bar: key processes · {(pcov or {}).get('pass', 0)}/{n} pass · {(pcov or {}).get('confirmed', 0)} confirmed"
          f" · {len((pcov or {}).get('regression') or [])} regression · not blocking: {others} other journeys INVALID, "
          f"{len(cov)} coverage rules broken (reported)")
    if ex == INVALID_ONLY:
        print(f"verdict: INVALID only (exit {INVALID_ONLY}) under the key-process bar: " + "; ".join(why))
    return ex


def invalid_only_line(summary, before=None):
    """The verdict line of an exit-3 run: what is INVALID and, for journeys that fail on the old app, what to do.
    B4N1-12: "fail on the OLD app too" names only journeys that did not PASS on the old run; a SCREEN INVALID journey
    that PASSed there (its old screenshot caught a spinner, STUCK/LOADING) gets its own advice, never "drop it"."""
    js, before = summary["journeys"], before or {}
    old_pass = lambda j: before.get(j, {}).get("verdict") == "PASS"
    shot = lambda s: s.get("compare") == "SCREEN INVALID" and baseline_side(s.get("screen", ""))
    base = sorted(j for j, s in js.items() if str(s.get("compare", "")).startswith("BASELINE DEFECT (")
                  or (shot(s) and not old_pass(j)))
    oldshot = sorted(j for j, s in js.items() if shot(s) and old_pass(j))
    n_inv = sum(1 for s in js.values() if s["verdict"] == "INVALID")
    n_scr = sum(1 for s in js.values() if s.get("compare") == "SCREEN INVALID")
    n_eff = sum(1 for s in js.values() if str(s.get("effect", "")).startswith("INVALID"))
    line = (f"verdict: INVALID only (exit {INVALID_ONLY}): no REGRESSION, no open REVIEW; {n_inv} journeys INVALID, "
            f"{n_scr} SCREEN INVALID, {len(base)} failing on the baseline, {n_eff} EFFECT INVALID")
    cov = (summary.get("coverage") or {}).get("invalid") or []
    if cov:   # E2E-11
        line += f", {len(cov)} coverage rules broken (the 'coverage INVALID' lines above)"
    if n_eff:
        line += ("\n  effects: a journey's row changes were not measured on one run: run both with --psql / UPG_PSQL "
                 "(E2E-9), before-picked first")
    if base:
        line += (f"\n  baseline: {', '.join(base)} fail on the OLD app too: drop or fix these journeys (they say nothing "
                 f"about the upgrade), then run before-picked again on its own fresh copy; or cite why they fail there "
                 f"(--baseline-evidence: FIXTURE / OLD-APP / FLAKY, E2E-11)")
    if oldshot:
        line += (f"\n  old screenshot: {', '.join(oldshot)} PASSed on the OLD app but its screenshot there is not usable "
                 f"(STUCK / LOADING / missing): look at both images and accept with --shot-accept, or repair the wait and "
                 f"run before-picked again; do not drop these journeys")
    return line

if __name__ == "__main__":
    main()
