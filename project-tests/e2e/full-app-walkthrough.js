'use strict';
// ============================================================================
// full-app-walkthrough.js — ONE business process, ACROSS modules, ACROSS roles.
// ----------------------------------------------------------------------------
//   node tests/e2e/full-app-walkthrough.js
//   HEADED=1 node tests/e2e/full-app-walkthrough.js        (watch it happen)
//
// Writes tests/e2e/artifacts/findings.json — the `findings` input of
// report-normalize.js, declared in project.config.js `walkthroughs[]` as the
// instrument named `full-app-walkthrough`.
//
// WHY THIS EXISTS
// journey-runner.js walks ONE persona down ONE golden path and grades it on five
// rungs. Run it once per module and you get what PROJECT-A got on 2026-08-20:
// six per-module journey files, every one of them recording
// `configuredUser == actualUser == erika.engineer`, `usedFallback:false`, no role
// change anywhere in the run. Six isolated single-persona smoke tests. The thing
// a business process actually does — engineer raises it, planner approves it,
// operator consumes it — was measured by nothing, because the handoff between two
// roles is exactly the seam that falls BETWEEN two per-module journeys.
//
// This instrument owns that seam and nothing else:
//   * it logs in as role A, does A's part of the process, and asserts the DB
//     effect A was supposed to leave behind;
//   * it LOGS OUT and logs in as role B — no session reuse, no impersonation
//     switch — and asserts that B can see the state A produced. That assertion
//     is the handoff, and it is the reason this file is not six journey files;
//   * it asserts the negatives a single-persona run can never reach: the screens
//     and buttons a role must NOT have.
//
// HONEST SELF-CLASSIFICATION — READ BEFORE TRUSTING A GREEN FROM HERE
// report-normalize.js stamps this instrument `canExpressFault:false,
// evidenceStrength:'weak'` (:1140-1163) and it is right to. The findings.json
// dialect has two states, pass and fail; it has no way to say "did not run". A
// green here is weaker evidence than a green from journey-runner, which can say
// INVALID. This instrument SUPPLEMENTS the mechanical checks — page-audit,
// journey-runner's four rungs, the verify loop — and must never be accepted in
// place of one. Do not add anything here that would make it look stronger than
// that classification: no `evidenceStrength` field on the rows (the dialect has
// no column for it and the renderer would drop it), no verdict vocabulary beyond
// pass/fail, no synthesised BRD requirement pointers.
//
// The one thing this file does do about that weakness: every step of every act is
// DECLARED up front, and any step the run never reached is written out as an
// explicit `fail` carrying "NOT REACHED". The dialect cannot say "did not run",
// so silence is the only alternative — and silence is what let 353 non-runs read
// as health. A loud wrong-shaped verdict beats an absent one. (report-normalize's
// own selftest settles the same question the same way: "walkthrough missing →
// fail (not fault: the source cannot mean 'did not run')".)
//
// ENGINE / CONFIG LINE
// Nothing in this file knows a module, an entity, a page, a widget, a menu
// caption, a user or a URL. All of that is `WALKTHROUGH` and `ROLES` in
// project.config.js — see project.config.template.js, which ships a worked
// example and the mxcli command that produces the right answer for each field.
// ============================================================================

const H = require(__dirname + '/helpers.js');
const { cfg } = require(__dirname + '/config.js');
const PROJ = require(__dirname + '/project.config.js');
const fs = H.fs;
const path = H.path;

const ROLES = PROJ.roles || {};
const WT = PROJ.walkthrough || null;

// ── Not configured is an INSTRUMENT FAULT, and it must not write a file ──────
// walkthroughInstrument() reads `verdict: 'pass'` off a findings.json that merely
// EXISTS. A file with zero checks in it would therefore be reported as a clean
// walkthrough. So when there is nothing to run we exit 2 (the harness's fault
// code, same as config.js's ownership refusal) and leave no artifact — the
// normalizer then says, correctly, "the instrument did not run".
if (!WT || !Array.isArray(WT.acts) || WT.acts.length === 0) {
  console.error(
    '\n  NOT CONFIGURED — project.config.js exports no `walkthrough` with acts.\n' +
    '  This instrument walks ONE business process across modules and roles; the process\n' +
    '  is a statement about your application, so it lives in project.config.js.\n' +
    '  Copy the WALKTHROUGH / ROLES blocks from project.config.template.js and fill them in.\n' +
    '  Writing an empty findings.json here would report a clean walkthrough that never ran.\n');
  process.exit(2);
}

const PAUSE = (ms) => new Promise((r) => setTimeout(r, ms));
const p = (ms) => PAUSE(Math.round(ms / cfg.speed));   // speed-scaled, for pacing only
const R = H.makeReporter(WT.label || `${PROJ.displayName} — full-app walkthrough`);

const artifacts = cfg.artifactsDir;
const appDir = path.join(artifacts, 'app');
const videoDir = path.join(artifacts, 'video');

const pageResults = [];
const consoleErrors = [];
const pageErrors = [];
const vars = {};                 // seeds + captures, referenced as {{name}}
const baselines = {};            // named row counts taken before an action
const rolesUsed = [];            // [{ role, configured, actual, usedFallback }]
const modulesTouched = new Set();
let stoppedAt = null;            // set when the walk aborts; every later step is NOT REACHED

// ── findings.json page/step model ────────────────────────────────────────────
// The shape is not ours to choose: report-normalize.js collectWalkthrough()
// (:1166-1206) reads exactly `pages[].{key,label,screenshot,widgets[],oqlRows[],
// steps[]}` and maps each entry to one check. Any other shape renders as nothing
// at all, which is the class of bug this whole effort is retiring.
function newPage(key, label) {
  const meta = { key, label, widgets: [], oqlRows: [], steps: [], screenshot: '' };
  pageResults.push(meta);
  return meta;
}

// status must be one of V_WALK's keys (report-normalize.js:143): ok|pass|fail|
// missing|error. Anything else normalizes to `fault`, and this dialect has no
// honest way to mean fault.
function step(meta, ok, label, detail) {
  meta.steps.push({ label, status: ok ? 'pass' : 'fail', detail: String(detail || '') });
  if (ok) R.pass(`${meta.key}:${label}`, label);
  else R.fail(`${meta.key}:${label}`, label, detail || 'failed');
  return ok;
}

// A step whose only evidence is what the screen showed. Marked in the detail text
// the way journey-runner marks its weak rows (:70-80), because `detail` is the one
// field the renderer copies verbatim — a weakness recorded anywhere else is
// invisible in the artefact a human actually reads.
function weakStep(meta, ok, label, detail) {
  const text = String(detail || '');
  return step(meta, ok, label, text ? `${text}  [WEAK EVIDENCE]` : '[WEAK EVIDENCE]');
}

function dbRow(meta, label, sql, value, pass, detail) {
  meta.oqlRows.push({ label, sql, value: String(value ?? ''), pass: !!pass, detail: detail || '' });
  if (pass) R.pass(`${meta.key}:oql:${label}`, `DB — ${label} = ${value}`);
  else R.fail(`${meta.key}:oql:${label}`, `DB — ${label}`, detail || `got "${value}"`);
  return pass;
}

const subst = (v) => (typeof v === 'string'
  ? v.replace(/\{\{(\w+)\}\}/g, (m, k) => (k in vars ? vars[k] : m))
  : v);

async function shot(page, meta, name) {
  const file = path.join(appDir, `${name}.png`);
  await H.fullPageShot(page, file);
  if (!meta.screenshot) meta.screenshot = `app/${name}.png`;   // relative to artifacts/
  return `app/${name}.png`;
}

// ── Step vocabulary ──────────────────────────────────────────────────────────
// Small and closed, addressed by Mendix WIDGET NAME rather than raw CSS — the
// convention journey-runner.js already established and the one that survives a
// re-render. A process that cannot be said in this vocabulary is a signal that
// the step belongs in a journey file, not that this list should grow a special
// case per project.
//
// DELIBERATELY ABSENT: `combobox`. Atlas pluggable comboboxes are Downshift-backed
// and render their options position:fixed OUTSIDE the widget container; the working
// handling lives in journey-runner.js's `act()` and is not exported. Copying it here
// would make a second copy that drifts — the exact failure documented in
// bin/lib/discover-brds.sh's header. If a walkthrough needs a combobox, EXPORT the
// existing one from journey-runner.js and call it; do not paste it.
async function runStep(page, meta, s) {
  const label = s.label || describe(s);
  const w = (n) => page.locator(`.mx-name-${n}`).first();
  const vis = (n, ms = 6000) => w(n).isVisible({ timeout: ms }).catch(() => false);

  switch (s.do) {
    case 'nav': {
      await H.navTo(page, s.group ? subst(s.group) : null, subst(s.item));
      await p(600);
      const ok = s.ready ? await vis(s.ready, 12000) : true;
      return step(meta, ok, label, ok ? '' : `.mx-name-${s.ready} never rendered after navigating to "${s.item}"`);
    }

    // LANDING GUARD, rung 1 of journey-runner's ladder and the reason it is first:
    // a nav click that silently did not navigate leaves every later assertion
    // grading the PREVIOUS page and screenshotting it under this page's name.
    case 'expect': {
      const ok = await vis(s.widget, s.timeout || 8000);
      return step(meta, ok, label, ok ? '' : `.mx-name-${s.widget} not visible`);
    }

    // The negative a single-persona run can never take: a screen or control this
    // role must NOT have. Absence is only evidence if the app shell is actually up,
    // so prove that first — otherwise a dead page passes every access check.
    case 'expectAbsent': {
      const shellUp = await page.locator(cfg.readySelectors.join(', ')).first()
        .isVisible({ timeout: 8000 }).catch(() => false);
      if (!shellUp) {
        return step(meta, false, label,
          'cannot judge absence — the app shell never rendered, so EVERY control is "absent" here');
      }
      const present = await w(s.widget).isVisible({ timeout: s.timeout || 3000 }).catch(() => false);
      return step(meta, !present, label,
        present ? `.mx-name-${s.widget} IS present for this role — the grant is wider than specified`
                : `.mx-name-${s.widget} not offered to this role (app shell confirmed up)`);
    }

    case 'click': {
      if (!(await vis(s.widget, s.timeout || 6000)))
        return step(meta, false, label, `.mx-name-${s.widget} not clickable`);
      await H.humanClick(page, w(s.widget));
      await p(s.settle || 2000);
      await H.dismissModal(page);
      return step(meta, true, label, '');
    }

    case 'fill': {
      const el = page.locator(`.mx-name-${s.widget} input, .mx-name-${s.widget} textarea`).first();
      if (!(await el.isVisible({ timeout: s.timeout || 6000 }).catch(() => false)))
        return step(meta, false, label, `.mx-name-${s.widget} has no visible input`);
      // humanTypeKeys fires real key events. fill() sets .value without them, and a
      // React-backed filter or an on-change microflow never sees the change — the
      // assertion afterwards then grades an unfiltered grid and passes. Measured in
      // PROJECT-C's Datagrid 2 filter, 2026-08.
      if (s.keys === false) await H.humanType(page, el, String(subst(s.value)));
      else await H.humanTypeKeys(page, el, String(subst(s.value)));
      await PAUSE(s.debounceMs || 0);   // REAL ms: a debounce does not scale with DEMO_SPEED
      return step(meta, true, label, `typed "${subst(s.value)}"`);
    }

    case 'wait':
      await PAUSE(s.ms || 1000);
      return true;                                   // pacing, not an assertion

    case 'shot':
      await shot(page, meta, subst(s.name));
      return true;                                   // A SCREENSHOT IS NOT AN ASSERTION

    case 'expectText': {
      const scope = s.widget ? `.mx-name-${s.widget}` : '.mx-page';
      const text = (await page.locator(scope).first().innerText().catch(() => '')).trim();
      const want = String(subst(s.text));
      const ok = text.includes(want);
      return weakStep(meta, ok, label,
        ok ? `"${want}" found in ${scope}` : `"${want}" NOT in ${scope} (saw: "${text.slice(0, 120)}")`);
    }

    case 'expectRows': {
      const n = await page.locator(`.mx-name-${s.widget} [role="row"], .mx-name-${s.widget} tbody tr`)
        .count().catch(() => 0);
      // DG2 renders a header row inside the same role="row" family; subtract it
      // unless the project says otherwise.
      const rows = s.countsHeader === false ? n : Math.max(0, n - 1);
      const ok = rows >= (s.min === undefined ? 1 : s.min);
      return step(meta, ok, label, `${rows} data row(s) in ${s.widget}`);
    }

    // The screen and the database, compared. The strongest thing in this file: a
    // KPI tile rendered from a non-persistent object can be confidently wrong and
    // no DB-only assertion will ever notice.
    case 'expectMatchesDb': {
      const shown = (await w(s.widget).innerText().catch(() => '')).trim();
      const norm = (x) => (s.digitsOnly === false ? String(x).trim() : String(x).replace(/[^0-9-]/g, ''));
      const db = H.oqlScalar(subst(s.sql));
      if (db === null) return step(meta, false, label, `OQL returned nothing: ${subst(s.sql)}`);
      const ok = norm(shown) === norm(db);
      dbRow(meta, label, subst(s.sql), db, ok, `screen "${shown}" vs DB "${db}"`);
      return ok;
    }

    case 'baseline': {
      const v = H.oqlScalar(subst(s.sql));
      if (v === null) return step(meta, false, label, `baseline "${s.name}" could not be read: ${subst(s.sql)}`);
      baselines[s.name] = v;
      return step(meta, true, label || `baseline ${s.name}`, `${s.name} = ${v}`);
    }

    case 'capture': {
      const v = H.oqlScalar(subst(s.sql));
      // A capture that fails is fatal to the rest of the walk: continuing puts
      // "undefined" into the next scan field and reports a feature bug that is
      // really a missing seed. Same rule as journey-runner's resolveSeeds().
      if (v === null || v === '') {
        step(meta, false, label || `capture ${s.name}`, `no value for "${s.name}" — ${subst(s.sql)}`);
        throw new Error(`capture "${s.name}" resolved to nothing`);
      }
      vars[s.name] = String(v);
      return step(meta, true, label || `capture ${s.name}`, `${s.name} = ${v}`);
    }

    case 'oql': {
      const sql = subst(s.sql);
      const raw = H.oqlScalar(sql);
      if (raw === null) return dbRow(meta, label, sql, '(unavailable)', false, 'query returned nothing');
      let ok, why = `= ${raw}`;
      if (s.expect !== undefined) {
        ok = String(raw) === String(subst(s.expect));
        why = `expected "${subst(s.expect)}", got "${raw}"`;
      } else if (s.atLeast !== undefined) {
        ok = Number(raw) >= Number(s.atLeast);
        why = `${raw} (need >= ${s.atLeast})`;
      } else if (s.deltaFrom !== undefined) {
        const before = baselines[s.deltaFrom];
        if (before === undefined)
          return dbRow(meta, label, sql, raw, false, `no baseline named "${s.deltaFrom}" was taken`);
        const by = s.by === undefined ? 1 : Number(s.by);
        ok = Number(raw) - Number(before) === by;
        why = `${before} → ${raw} (expected ${by >= 0 ? '+' : ''}${by})`;
      } else {
        ok = true;                                   // a reading, not a claim
      }
      return dbRow(meta, label, sql, raw, ok, why);
    }

    default:
      return step(meta, false, label, `unknown step verb "${s.do}" — see the vocabulary in full-app-walkthrough.js`);
  }
}

function describe(s) {
  switch (s.do) {
    case 'nav': return `navigate to ${[s.group, s.item].filter(Boolean).join(' › ')}`;
    case 'click': return `click ${s.widget}`;
    case 'fill': return `type into ${s.widget}`;
    case 'expect': return `${s.widget} is visible`;
    case 'expectAbsent': return `${s.widget} is NOT offered to this role`;
    case 'expectText': return `screen shows "${s.text}"`;
    case 'expectRows': return `${s.widget} has data rows`;
    case 'expectMatchesDb': return `${s.widget} matches the database`;
    case 'oql': return s.label || 'database check';
    default: return `${s.do} ${s.widget || s.name || ''}`.trim();
  }
}

// ── Identity, and the handoff between two of them ────────────────────────────
// helpers.login() reads cfg.user/cfg.pass, so a role switch is: end the server-side
// session, point cfg at the next role, log in again. Nothing here impersonates or
// reuses a session — the whole point is to exercise the app the way a second human
// at a second desk does.
//
// THE FALLBACK IS DISABLED FOR THE DURATION. cfg.fallbackUser exists so a credential
// problem degrades to a reported finding instead of a zero-coverage run, and for a
// single-persona run that trade is right. Here it is not: silently continuing as
// MxAdmin means every role boundary this instrument exists to test is measured
// against an account that has all of them. That is not a weaker result, it is the
// wrong one, reported green.
let currentRole = null;

async function switchTo(page, roleKey, handoffMeta) {
  const role = ROLES[roleKey];
  if (!role || !role.user) {
    step(handoffMeta, false, `sign in as role "${roleKey}"`,
      `project.config.js ROLES has no usable entry "${roleKey}" — the process cannot cross into it`);
    return false;
  }

  if (currentRole) {
    const out = await H.logout(page);
    step(handoffMeta, out, `sign out ${ROLES[currentRole].label || currentRole}`,
      out ? '' : 'the xas logout action did not return 200 — the previous session may still hold a seat '
               + '(an unlicensed runtime caps concurrent sessions and the next login then reads as a bad password)');
  }

  const savedFallback = cfg.fallbackUser;
  cfg.fallbackUser = '';
  cfg.user = role.user;
  cfg.pass = role.pass;
  const li = await H.login(page);
  cfg.fallbackUser = savedFallback;

  rolesUsed.push({ role: roleKey, label: role.label || roleKey,
                   configured: role.user, actual: li.user, usedFallback: !!li.usedFallback });

  if (!li.ok) {
    step(handoffMeta, false, `sign in as ${role.label || roleKey} ("${role.user}")`,
      li.fault
        ? `the runtime REFUSED the session: "${li.reason}" — this is not a credential failure and not a `
          + 'finding about the app. Check the runtime log (a trial licence\'s concurrent-session cap looks '
          + 'exactly like a wrong password in the UI).'
        : `credentials rejected: "${li.reason}"`);
    return false;
  }
  // usedFallback cannot be true here (the fallback is disabled above); assert it
  // anyway, so that re-enabling it later can never make this pass quietly.
  step(handoffMeta, !li.usedFallback, `signed in as the configured identity "${role.user}"`,
    li.usedFallback ? `fell back to "${li.user}" — every role assertion below is measuring the wrong access path` : '');
  currentRole = roleKey;
  return !li.usedFallback;
}

// ── Main ─────────────────────────────────────────────────────────────────────
(async () => {
  H.ensureDirs(artifacts, appDir, videoDir);

  // WINDOW_POS/WINDOW_SIZE let a dual-window runner pin this window to one half of
  // the screen (the other half being a phone-viewport instrument). Unset — the
  // normal case — is unchanged behaviour.
  const winPos = process.env.WINDOW_POS;
  const winSize = process.env.WINDOW_SIZE;
  const { browser, context, page } = winPos && winSize
    ? await (async () => {
        const [x, y] = winPos.split(',').map(Number);
        const [wd, ht] = winSize.split(',').map(Number);
        return H.launchBrowserAt(x, y, wd, ht, { videoDir, trace: true });
      })()
    : await H.launchBrowser({ videoDir, trace: true });

  if (cfg.headed) { await H.injectCursor(context); await H.injectOqlOverlay(context); }
  page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 300)); });
  page.on('pageerror', (e) => pageErrors.push(String(e).slice(0, 300)));

  // Pages are emitted in creation order, so the two that describe the run come
  // first and the acts follow in process order.
  const mPre = newPage('process-shape', 'Process shape (what this instrument claims to cover)');
  const mSeed = newPage('seeds', 'Seeds (live values this walk is built on)');

  // Every act gets its page up front, in order, so that an act the run never
  // reaches still has somewhere to write its NOT REACHED rows.
  const actMetas = WT.acts.map((a, i) =>
    newPage(a.key || `act-${i + 1}`,
            `Act ${i + 1} · ${(ROLES[a.role] && ROLES[a.role].label) || a.role} — ${a.label || a.key || ''}`));

  try {
    // ── PRE-FLIGHT: is this actually a cross-role, cross-module walk? ────────
    // A walkthrough configured with one role and one module is the six-single-
    // persona-journeys situation with extra steps, and it must not be able to
    // report itself as coverage of a business process.
    const declaredRoles = [...new Set(WT.acts.map((a) => a.role).filter(Boolean))];
    const declaredModules = [...new Set(WT.acts.map((a) => a.module).filter(Boolean))];
    step(mPre, declaredRoles.length >= 2, 'the process crosses at least two roles',
      declaredRoles.length >= 2
        ? `roles: ${declaredRoles.join(' → ')}`
        : `only "${declaredRoles[0] || 'none'}" — a single-persona walk. The per-module journeys already `
          + 'cover that; the handoff between roles is what nothing else measures and what this instrument is for.');
    step(mPre, declaredModules.length >= 2, 'the process crosses at least two modules',
      declaredModules.length >= 2
        ? `modules: ${declaredModules.join(', ')}`
        : 'one module or none declared — this is a module journey, not an end-to-end process');
    step(mPre, !!WT.process, 'the process is named in the user\'s language',
      WT.process || 'WALKTHROUGH.process is empty — the report cannot say what business process was walked');

    // ── SEEDS ────────────────────────────────────────────────────────────────
    // Live values, never literals. A walkthrough pinned to 'RT-PCBA-008' reports
    // "the feature is broken" the first time somebody reseeds — a false finding,
    // the mirror image of a false green and just as expensive.
    for (const s of WT.seeds || []) {
      const v = H.oqlScalar(subst(s.sql));
      if (v === null || v === '') {
        step(mSeed, false, `seed ${s.name}`,
          `resolved to nothing: ${subst(s.sql)} — the walk cannot proceed with an empty ${s.name}`);
        throw new Error(`seed "${s.name}" resolved to nothing`);
      }
      vars[s.name] = String(v);
      step(mSeed, true, `seed ${s.name}`, `${s.name} = ${v}`);
    }

    // ── THE WALK ─────────────────────────────────────────────────────────────
    for (let i = 0; i < WT.acts.length; i++) {
      const act = WT.acts[i];
      const meta = actMetas[i];
      if (act.module) modulesTouched.add(act.module);

      // A role change is a HANDOFF, and it gets its own page in the report so the
      // seam is visible as a thing that was tested rather than buried inside an act.
      if (act.role !== currentRole) {
        const from = currentRole ? (ROLES[currentRole].label || currentRole) : '(nobody)';
        const to = (ROLES[act.role] && ROLES[act.role].label) || act.role;
        const mH = newPage(`handoff-${i + 1}`, `Handoff · ${from} → ${to}`);
        const ok = await switchTo(page, act.role, mH);
        await shot(page, mH, `handoff-${String(i + 1).padStart(2, '0')}-${act.role}`);
        if (!ok) { stoppedAt = `handoff into "${act.role}"`; break; }

        // THE HANDOFF ASSERTION. Everything above proves a second human got in.
        // This proves the second human can SEE the first one's work — which is the
        // one claim six per-module journeys can never make between them.
        for (const s of act.handoffAssert || []) {
          if (!(await runStep(page, mH, s))) {
            if (s.fatal) { stoppedAt = `handoff assertion "${s.label || describe(s)}"`; break; }
          }
        }
        if (stoppedAt) break;
      }

      console.log(`\n── ${meta.label} ──`);

      // Widget presence for the act's landing page, recorded as widgets[] so the
      // report groups them the way it groups every other walkthrough's.
      for (const name of act.checks || []) {
        const visible = await page.locator(`.mx-name-${name}`).first()
          .isVisible({ timeout: 2500 }).catch(() => false);
        meta.widgets.push({ name, status: visible ? 'ok' : 'missing',
                            detail: visible ? '' : `.mx-name-${name} not visible` });
        if (visible) R.pass(`${meta.key}:widget:${name}`, `Widget ${name} present`);
        else R.fail(`${meta.key}:widget:${name}`, `Widget ${name} present`, `.mx-name-${name} not visible`);
      }

      for (const s of act.steps || []) {
        const ok = await runStep(page, meta, s);
        // `fatal` is the config's way of saying "there is no point continuing" —
        // a form that never opened, a record that was never created. Everything
        // after it is reported NOT REACHED rather than left absent.
        if (!ok && s.fatal) { stoppedAt = `${meta.label}: ${s.label || describe(s)}`; break; }
      }
      if (!meta.screenshot) await shot(page, meta, `act-${String(i + 1).padStart(2, '0')}-${meta.key}`);
      if (stoppedAt) break;
    }

    // ── CLEANUP ──────────────────────────────────────────────────────────────
    // A walkthrough that writes must put the data back, or the second run measures
    // the first run's leftovers. Reported, not silent: a cleanup that failed is a
    // fact the next reader needs.
    if (WT.cleanup && Array.isArray(WT.cleanup.steps) && WT.cleanup.steps.length) {
      const mC = newPage('cleanup', 'Cleanup (restore what this walk changed)');
      if (WT.cleanup.role && WT.cleanup.role !== currentRole) {
        await switchTo(page, WT.cleanup.role, mC);
      }
      for (const s of WT.cleanup.steps) await runStep(page, mC, s).catch(() => false);
    }

  } catch (err) {
    stoppedAt = stoppedAt || String(err).slice(0, 200);
    console.error(err);
  } finally {
    // ── NOT REACHED accounting ───────────────────────────────────────────────
    // The dialect cannot say "did not run". Absent checks are how a half-finished
    // run reads as a healthy one, so every declared-but-unexecuted step is written
    // out as an explicit fail that says so in its detail.
    if (stoppedAt) {
      const reason = `NOT REACHED — the walk stopped at ${stoppedAt}. This is not a verdict about the `
                   + 'feature: it was never exercised. The findings.json dialect has no "did not run" '
                   + 'state, so it is recorded as a fail rather than left silently absent.';
      WT.acts.forEach((act, i) => {
        const meta = actMetas[i];
        const executed = new Set(meta.steps.map((s) => s.label));
        for (const s of act.steps || []) {
          const label = s.label || describe(s);
          if (!executed.has(label)) meta.steps.push({ label, status: 'fail', detail: reason });
        }
        for (const name of act.checks || []) {
          if (!meta.widgets.some((wd) => wd.name === name))
            meta.widgets.push({ name, status: 'missing', detail: reason });
        }
      });
    }

    // ── Runtime health ───────────────────────────────────────────────────────
    const mHealth = newPage('runtime', 'Runtime health');
    step(mHealth, pageErrors.length === 0, 'no uncaught page errors',
      pageErrors.length ? `${pageErrors.length}: ${pageErrors[0]}` : '');
    // helpers.loginOnce() clears cookies before every sign-in, so the Mendix client
    // always finds a stale token on the first request of each role and logs a 401
    // "Could not create a session". That is this harness's own doing — excluded from
    // the gate, kept in full in the error log below.
    const realConsoleErrors = consoleErrors.filter((e) =>
      !/Could not create a session|401 \(Unauthorized\)/.test(e));
    step(mHealth, realConsoleErrors.length === 0, 'no unexpected console errors',
      realConsoleErrors.length
        ? `${realConsoleErrors.length}: ${realConsoleErrors[0]}`
        : `${consoleErrors.length} sign-in 401s ignored (the harness clears cookies per role)`);

    const summary = R.summary();

    await context.tracing.stop({ path: path.join(artifacts, 'trace.zip') }).catch(() => {});
    const video = page.video();
    // Release the server-side session BEFORE closing the browser: closing a browser
    // does NOT end a Mendix session, and on an unlicensed runtime the leaked seats
    // accumulate until later logins are refused and report as bad passwords.
    if (currentRole) await H.logout(page).catch(() => {});
    await context.close().catch(() => {});
    if (video) {
      const vp = await video.path().catch(() => null);
      if (vp && fs.existsSync(vp)) fs.copyFileSync(vp, path.join(artifacts, 'walkthrough.webm'));
    }
    await browser.close().catch(() => {});

    const configured = rolesUsed.map((r) => r.configured).join(' → ');
    const actual = rolesUsed.map((r) => r.actual).join(' → ');
    fs.writeFileSync(path.join(artifacts, 'findings.json'), JSON.stringify({
      target: 'full-app',
      label: WT.label || `${PROJ.displayName} — full-app walkthrough`,
      process: WT.process || null,
      baseUrl: cfg.baseUrl,
      // collectWalkthrough() derives userFallbackUsed from `configuredUser !== user`
      // (:1203). This instrument runs as SEVERAL users, so both fields carry the whole
      // chain in order: they compare equal only when every role signed in as itself.
      configuredUser: configured,
      user: actual,
      roles: rolesUsed,
      modulesTouched: [...modulesTouched],
      stoppedAt,
      capturedAt: new Date().toISOString(),
      pages: pageResults,
      functional: summary.results,
      passed: summary.passed,
      failed: summary.failed,
      consoleErrors,
      pageErrors,
      hasVideo: fs.existsSync(path.join(artifacts, 'walkthrough.webm')),
      hasTrace: fs.existsSync(path.join(artifacts, 'trace.zip')),
      // Not read by report-normalize — it is here for whoever opens the raw file and
      // needs to know what a green from this instrument is worth.
      selfDescription:
        'Narrative cross-role walkthrough. report-normalize.js classifies this instrument '
        + 'canExpressFault:false / evidenceStrength:"weak": the dialect has only pass and fail and '
        + 'cannot express "did not run". Use it to supplement the mechanical instruments '
        + '(journey-runner rungs, page-audit, the verify loop) — never in place of one.',
    }, null, 2));

    console.log(`\nArtifacts → ${artifacts}`);
    if (stoppedAt) console.log(`  ⚠ the walk STOPPED at: ${stoppedAt} — later steps are recorded NOT REACHED`);
    // journey-runner's convention: 0 clean, 1 findings, 2 instrument fault.
    process.exitCode = summary.failed > 0 ? 1 : 0;
  }
})().catch((e) => { console.error(e); process.exit(2); });
