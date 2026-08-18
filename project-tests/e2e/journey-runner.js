'use strict';
// ============================================================================
// journey-runner.js — walk a persona down a golden path and check all four rungs
// ----------------------------------------------------------------------------
//   node tests/e2e/journey-runner.js journeys/FieldScan.journey.json
//   node tests/e2e/journey-runner.js journeys/*.journey.json --positive-control
//
// WHY THIS EXISTS
// The suite's 14 `TARGETS['full-app']` entries are independent PAGE STOPS: navigate,
// assert widgets present, count rows. Nothing in the corpus performs
// create → link → transition → verify-downstream with state carried between steps,
// which is the only shape that can answer the question the requirements actually ask:
// "does the user's journey, end to end, do what was specified?"
//
// FOUR RUNGS PER STEP, in this order, and the order matters:
//   1. LANDING GUARD  — did we actually arrive? A nav click that silently didn't
//      navigate leaves every later assertion measuring the PREVIOUS page and
//      screenshotting it under the new page's title. Assertions live only inside
//      the else branch. (e2e-ui-test-honesty.md)
//   2. ORDERED SPANS  — otel.assertSequence, not assertFired. Existence checks
//      cannot tell a skipped step from a reordered one.
//   3. DATA EFFECTS   — the row exists AND every association that must be set IS set.
//      An order created with no link to the unit it is for is a broken golden path
//      even though it saved, and every other rung goes green over it.
//   4. REQUIREMENT    — each finding carries its BRD pointer, so the report answers
//      "did we build what was decided", not just "did it work".
//
// A missing instrument is an INVALID RUN, never a PASS and never a FAIL. Jaeger down
// means the trace rung did not run; saying "passed" there is the exact false-green
// this harness was built to retire.
// ============================================================================

const fs = require('fs');
const path = require('path');
const H = require(__dirname + '/helpers.js');
const O = require(__dirname + '/otel.js');
const { cfg } = require(__dirname + '/config.js');

const POSITIVE_CONTROL = process.argv.includes('--positive-control');
const files = process.argv.slice(2).filter(a => !a.startsWith('--'));
// `require.main === module` guard: tests/e2e/journey-rung4-scope.test.js requires this
// file to exercise the rung-4 SQL builders directly. Without the guard, requiring it
// would parse the TEST runner's argv, find no journey files and exit(3).
if (require.main === module && !files.length) {
  console.error('usage: node tests/e2e/journey-runner.js <journey.json...> [--positive-control]');
  process.exit(3);
}

// ── Verdicts ────────────────────────────────────────────────────────────────
// PASS / FAIL / INVALID are never collapsed. "The test could not run" and "the
// feature is broken" send you to different places, and blending them is how a
// week gets spent debugging a page that was never reached.
const results = [];

// ── The walk ────────────────────────────────────────────────────────────────
// The assertions above answer "did it work". The walk answers "what did it DO" —
// which page, which button, what was typed, what the screen looked like at the
// moment each assertion was taken. It exists so a reviewer can follow the persona
// through the app and see the requirement being exercised, rather than reading a
// list of selectors and trusting it.
//
// A SCREENSHOT IS NOT AN ASSERTION, and this structure is built so it can never be
// mistaken for one. Every shot is attached to the checks that ran against that exact
// page state; the verdict always comes from the checks. The combobox off-by-one of
// 2026-08-14 is why: it committed "Seoul Gangnam Center" for "Seoul Gwanghwamun
// Center" — a real, valid, neighbouring row. The screenshot of that step looked
// perfect. Only the committed-value assertion caught it. Screenshots are for
// locating and understanding a failure, never for establishing one.
const walks = [];
// `evidenceStrength` is carried on the row AND folded into `detail`, deliberately.
// report-normalize.js reconciles emitted rows against declaredChecks() BY NAME, so the
// check names below must not change; and it copies `detail` verbatim into the rendered
// report while dropping fields it does not know. A strength that lives only in a new
// field would therefore be invisible in the artefact a human actually reads — which is
// the same "green cell that means less than it looks like" this rung exists to retire.
function record(rung, name, verdict, detail, req, evidenceStrength) {
  let text = String(detail ?? '');
  if (evidenceStrength === 'weak') text = text ? `${text}  [WEAK EVIDENCE]` : '[WEAK EVIDENCE]';
  const row = { rung, name, verdict, detail: text, requirement: req || '' };
  if (evidenceStrength) row.evidenceStrength = evidenceStrength;
  results.push(row);
  const mark = { PASS: '\x1b[32mPASS\x1b[0m', FAIL: '\x1b[31mFAIL\x1b[0m', INVALID: '\x1b[33mINVL\x1b[0m' }[verdict];
  console.log(`  ${mark} [${rung}] ${name}${text ? '  — ' + text : ''}`);
}
// Adapter so otel.js's reporter signature (name, ok, detail) can write into `record`.
const otelReporter = (req) => (name, ok, detail) =>
  record('trace', name, ok ? 'PASS' : 'FAIL', detail, req);

// ── Seeds: journey inputs come from the live DB, never hardcoded ────────────
// Test data drifts on every reseed. A journey pinned to 'SAM-NB-001' fails as
// "Receive is broken" the first time someone reseeds, which is a false FINDING —
// the mirror image of a false green and just as expensive.
//
// A seed that cannot be resolved is fatal to the journey: continuing with
// `undefined` in a scan field measures nothing and reports it as a feature bug.
function resolveSeeds(j) {
  const vars = {};
  for (const s of j.seeds || []) {
    // Seeds may reference earlier seeds ({{locId}}), so that a name and an id come
    // from the SAME row. Two independent `LIMIT 1` queries are not guaranteed to.
    const v = H.oqlScalar(subst(s.sql, vars));
    if (v === null || v === '') return { ok: false, missing: s.name, vars };
    vars[s.name] = String(v);
  }
  return { ok: true, vars };
}
const subst = (v, vars) =>
  typeof v === 'string' ? v.replace(/\{\{(\w+)\}\}/g, (m, k) => (k in vars ? vars[k] : m)) : v;

// ── Step actions ────────────────────────────────────────────────────────────
// A small, closed vocabulary addressed by Mendix widget name, not raw CSS — the
// convention the whole suite already uses, and the one that survives a re-render.
// Anything a journey cannot express with these belongs in a spec: the schema is
// meant to stay declarative enough to generate from a module brief's golden-path
// table.
const PAUSE = ms => new Promise(r => setTimeout(r, ms));

// A human-readable account of what the action WILL do, in the vocabulary a reviewer
// uses ("click Receive"), not the harness's (".mx-name-bReceive"). Both are kept: the
// sentence is for the person reading the walk, the selector for the person fixing it.
// One screenshot, recorded with the page's own title and URL so a reviewer can tell
// WHICH page they are looking at without decoding the selector. Returns null rather
// than throwing: a walk that loses its pictures is degraded, not invalid, and must
// never turn a real verdict into a harness failure.
async function shoot(page, name) {
  try {
    fs.mkdirSync(cfg.artifactsDir, { recursive: true });
    const file = path.join(cfg.artifactsDir, `${name}.png`);
    await page.screenshot({ path: file });
    return {
      file: path.relative(cfg.root, file),
      title: await page.title().catch(() => null),
      url: page.url(),
      at: new Date().toISOString(),
    };
  } catch { return null; }
}

function describeAct(a, vars) {
  const v = x => String(subst(x, vars));
  switch (a.do) {
    case 'nav':      return { verb: 'Navigate', target: [a.group, a.item].filter(Boolean).join(' › '), selector: null };
    case 'click':    return { verb: 'Click', target: a.label || a.widget, selector: `.mx-name-${a.widget}` };
    case 'fill':     return { verb: 'Type', target: `"${v(a.value)}" into ${a.label || a.widget}`, selector: `.mx-name-${a.widget}` };
    case 'combobox': return { verb: 'Select', target: `"${v(a.match)}" in ${a.label || a.widget}`, selector: `.mx-name-${a.widget}` };
    case 'wait':     return { verb: 'Wait', target: `${a.ms || 0}ms`, selector: null };
    default:         return { verb: a.do, target: a.widget || '', selector: a.widget ? `.mx-name-${a.widget}` : null };
  }
}

async function act(page, a, vars, note) {
  const w = n => page.locator(`.mx-name-${n}`).first();
  switch (a.do) {
    case 'nav':
      await H.navTo(page, a.group || null, a.item);
      break;
    case 'click': {
      const el = w(a.widget);
      await el.waitFor({ state: 'attached', timeout: 8000 }).catch(() => {});
      await el.scrollIntoViewIfNeeded({ timeout: 2000 }).catch(() => {});
      if (!(await el.isVisible({ timeout: 6000 }).catch(() => false)))
        throw new Error(`.mx-name-${a.widget} not visible`);
      await el.click({ force: true }).catch(() => el.click());
      break;
    }
    case 'fill': {
      const el = page.locator(`.mx-name-${a.widget} input, .mx-name-${a.widget} textarea`).first();
      if (!(await el.isVisible({ timeout: 6000 }).catch(() => false)))
        throw new Error(`.mx-name-${a.widget} input not visible`);
      await el.fill(String(subst(a.value, vars)));
      break;
    }
    case 'combobox': {
      // Atlas pluggable comboboxes are Downshift-backed: options render
      // position:fixed OUTSIDE the widget container, so a locator scoped to
      // .mx-name-<widget> finds nothing and a plain fill() does not commit a
      // selection. Toggle, then keyboard-select — the technique proven in
      // spec-fieldscan-otel.js.
      const box = w(a.widget);
      if (!(await box.isVisible({ timeout: 6000 }).catch(() => false)))
        throw new Error(`.mx-name-${a.widget} not visible`);
      await box.scrollIntoViewIfNeeded().catch(() => {});
      await PAUSE(400);
      await page.locator('[id^="downshift-"][id$="-toggle-button"]').first()
                .click({ force: true }).catch(() => {});
      await PAUSE(1200);
      const opts = page.locator('[role="option"]');
      await opts.first().waitFor({ state: 'visible', timeout: 5000 }).catch(() => {});
      const texts = await opts.evaluateAll(e => e.map(x => x.textContent.trim())).catch(() => []);
      const want = String(subst(a.match, vars));
      const idx = texts.findIndex(t => t.includes(want));

      // CONFIRMED FALSE GREEN, 2026-08-14 — this line used to read `if (idx === -1)
      // idx = 0;`. The seed asked for "Seoul Gwanghwamun Center", the option was not
      // in the list, and the journey silently selected whatever sat at position 0
      // ("Seoul Gangnam Center") and reported PASS. Every downstream rung then agreed
      // with it: the placement saved, both associations were non-null, assocGap was 0.
      // `assocMustBeSet` verifies that a link EXISTS — never that it points where the
      // journey intended — so the wrong-location run is indistinguishable from a
      // correct one on every instrument the harness had.
      //
      // A fallback that quietly substitutes a different input is not resilience. It
      // makes the journey measure something nobody asked for and call it the thing
      // they did ask for. If the seeded option is absent, that is the finding.
      if (idx === -1) {
        throw new Error(
          `${a.widget}: no option matches "${want}" — the seeded value is not selectable. ` +
          `Options were: ${texts.slice(0, 8).map(t => `"${t}"`).join(', ')}` +
          (texts.length > 8 ? ` (+${texts.length - 8} more)` : ''));
      }
      // MEASURED 2026-08-14, two failed approaches before this one. Both computed
      // where to land instead of checking where they had landed:
      //
      //   1. `idx + 1` ArrowDown presses, then Enter. Landed one option SHORT —
      //      asked for "Seoul Gwanghwamun Center", committed "Seoul Gangnam Center".
      //      Downshift's highlight index is not the same coordinate system as the
      //      DOM array index, so the press count and `idx` never had to agree.
      //   2. `opts.nth(idx).click({force:true})`. Closed the menu and committed
      //      NOTHING — Downshift does not treat a synthetic forced click as a select.
      //
      // Approach 1's failure is the dangerous one: an off-by-one lands on a REAL,
      // VALID neighbouring row, so nothing downstream looks wrong. Approach 2 at
      // least failed loudly.
      //
      // So: step the highlight and READ IT each time, committing only once the
      // highlighted option is the one asked for. Self-correcting whatever index
      // Downshift starts from, and it cannot commit a neighbour by construction.
      const activeText = async () => {
        const id = await box.locator('input[role="combobox"]')
                            .getAttribute('aria-activedescendant').catch(() => null);
        if (!id) return null;
        // Attribute selector, not `#id` — Downshift ids contain hyphens and digits
        // that a bare CSS id selector mis-parses, and `CSS.escape` is a BROWSER API
        // that is undefined here in Node (it threw "CSS is not defined" on the first
        // attempt, and the runner correctly reported that as a FAIL of the step
        // rather than skipping the assertion).
        return page.locator(`[id="${id}"]`).textContent().catch(() => null);
      };
      let landed = false;
      for (let k = 0; k < texts.length + 2; k++) {
        const cur = (await activeText() || '').trim();
        if (cur && cur.includes(want)) { landed = true; break; }
        await page.keyboard.press('ArrowDown');
        await PAUSE(120);
      }
      if (!landed) {
        throw new Error(
          `${a.widget}: stepped the whole menu without the highlight ever reaching ` +
          `"${want}". The option is listed but not reachable by keyboard.`);
      }
      await page.keyboard.press('Enter');
      await PAUSE(500);

      // Selecting is not committing. Downshift can close the menu without writing the
      // value back, so the committed input is read and compared to the seed — not
      // merely checked for non-emptiness, which the previous version did and which
      // any wrong value passes.
      const val = await box.locator('input[role="combobox"]').inputValue().catch(() => '');
      if (!val) throw new Error(`${a.widget} still empty after selecting "${want}"`);
      if (!val.includes(want)) {
        throw new Error(
          `${a.widget} committed "${val}" but the journey asked for "${want}" — ` +
          'the selection did not take. Every later assertion would be about the wrong row.');
      }
      note('ui', `combobox ${a.widget} committed the seeded value`, 'PASS', val);
      break;
    }
    case 'dismissModal': await H.dismissModal(page); break;
    case 'wait':         await page.waitForTimeout(a.ms || 1000); break;
    default: throw new Error(`unknown action "${a.do}"`);
  }
  await page.waitForTimeout(a.settleMs ?? 1200);
}

// ── Rung 3 helpers ──────────────────────────────────────────────────────────
// oql() swallows every error and returns null, so null must mean "no measurement",
// never "zero". A count assertion that treats null as 0 passes when the instrument
// is dead — the same failure mode as an empty span capture.
function count(sql) {
  const v = H.oqlScalar(sql);
  return v === null ? null : Number(v);
}

// A declared OQL expectation. `expect` is exact, `atLeast` is a floor — the floor
// exists because seeded data carries history, so "this item now has a placement" is
// the honest claim while "exactly one" would be a lie about the fixture.
//
// A query with NEITHER is a check that cannot fail, so it is reported as INVALID
// rather than PASS. A green cell that could never have been red is decoration, and
// this whole harness exists because the corpus is full of them.
function checkOql(q, vars) {
  const v = H.oqlScalar(subst(q.sql, vars));
  if (v === null) return { verdict: 'INVALID', detail: 'OQL returned nothing — admin API unreachable or query rejected' };
  if (q.expect !== undefined)
    return { verdict: String(q.expect) === v ? 'PASS' : 'FAIL', detail: `got ${v}, expected ${q.expect}` };
  if (q.atLeast !== undefined)
    return { verdict: Number(v) >= Number(q.atLeast) ? 'PASS' : 'FAIL', detail: `got ${v}, need >= ${q.atLeast}` };
  return { verdict: 'INVALID', detail: `got ${v}, but no expect/atLeast declared — this check cannot fail` };
}

// ── Rung 4 row scoping: which rows is this step allowed to be judged on? ────
//
// THE DEFECT THIS REPLACES (both directions, on the same two checks):
//
//   assocMustBeSet ran `SELECT COUNT(*) FROM Entity` against `... INNER JOIN` over the
//   WHOLE TABLE. One legacy row with a null FK — seeded years of runs ago, nothing to do
//   with this journey — makes the gap non-zero forever. The step is reported as "saved
//   without its association" on every future run, for a row it never touched. A standing
//   red that no fix can clear teaches the reader to ignore the cell.
//
//   mustPointAt ran `... WHERE t.<attr> = '<seed>'` over the WHOLE TABLE and passed on
//   `n >= 1`. A row a PREVIOUS run wrote already satisfies it. So the check goes green
//   whether or not this journey did anything at all — including when the commit silently
//   no-ops. It is the check added to catch the 2026-08-14 wrong-combobox run, and as
//   written it could be satisfied by that very run's leftover row.
//
// Opposite verdicts, one cause: neither query could distinguish the rows THIS STEP wrote
// from everything else in the table.
//
// THE FIX — a DB-sourced high-water mark taken immediately before the step's actions.
// The step declares `data.scope.newRowsBy: "<attr>"`; the runner reads
// `SELECT MAX(<attr>) FROM <entity>` first, then scopes both checks to `e.<attr> > <mark>`.
//
// Why MAX() from the database and not the runner's clock: it removes clock skew from the
// question entirely. A `createdDate > <runner's Date.now()>` scope compares a timestamp
// written by the runtime (in its container, on its clock) against one read in Node on the
// host, and a container running even 2s behind silently scopes out the row the journey
// just wrote — a false FAIL that looks exactly like a broken commit. A watermark read out
// of the same database that will answer the assertion has no second clock in it.
//
// Why `id` is the recommended attribute — verified, not assumed, against
// .ai-context/skills/demo-data.md:87, which gives the Mendix object-ID layout as
//   id = (short_id << 48) | (sequence_number << 7) | random_7bits
// short_id is constant per entity, so within one entity ordering by id is ordering by
// sequence_number, and sequence_number is allocated strictly increasing (demo-data.md:122,
// "object_sequence is the next available sequence number for that entity"). The 7-bit
// random suffix sits BELOW the sequence field, so it cannot reorder two rows: consecutive
// sequences differ by 128 while the suffix can only vary by at most 127. Monotonic by
// construction, and immune to an UPDATE — unlike a stamped DateTime.
//
// `newRowsBy: "PlacedOn"` (or any stamped DateTime) also works and is the fallback if the
// runtime's OQL will not aggregate `id`, with one documented weakness: FieldScan's Move
// RE-STAMPS PlacedOn (mdlsource/fieldscan/04-microflows.mdl:165), so a pre-existing row
// that some other actor moves during the step re-enters scope. `id` cannot do that.
//
// A declared scope that cannot be measured is INVALID, never a quiet fall back to the
// whole table. Falling back would restore precisely the two false verdicts above while
// the report still showed the scoped wording.
function sqlRowCount(entity) { return `SELECT COUNT(*) AS n FROM ${entity}`; }
function sqlWatermark(entity, attr) { return `SELECT MAX(${attr}) AS w FROM ${entity}`; }

// Numeric marks (ids) go in bare; anything else (a DateTime) is quoted. Decided from the
// value the database returned, not from a hardcoded attribute-name list, so a journey can
// scope on any monotonic column without the runner knowing its type.
const scopeLiteral = (w) => (/^-?\d+$/.test(String(w)) ? String(w) : `'${w}'`);

// The WHERE tail shared by both scoped checks. `extra` (e.g. `t.LocId = 'L1'`) comes
// first so the generated SQL reads in the order a human would write it.
function whereScoped(sc, alias, extra) {
  const terms = [];
  if (extra) terms.push(extra);
  if (sc && sc.state === 'scoped') terms.push(`${alias}.${sc.attr} > ${scopeLiteral(sc.watermark)}`);
  return terms.length ? ` WHERE ${terms.join(' AND ')}` : '';
}

function sqlAssocTotal(entity, sc) {
  return `SELECT COUNT(*) AS n FROM ${entity} AS e${whereScoped(sc, 'e')}`;
}
function sqlAssocLinked(entity, assoc, target, sc) {
  return `SELECT COUNT(*) AS n FROM ${entity} AS e ` +
         `INNER JOIN e/${assoc}/${target} AS t${whereScoped(sc, 'e')}`;
}
function sqlMustPointAt(entity, assoc, target, attr, want, sc) {
  return `SELECT COUNT(*) AS n FROM ${entity} AS e ` +
         `INNER JOIN e/${assoc}/${target} AS t${whereScoped(sc, 'e', `t.${attr} = '${want}'`)}`;
}

// Read the high-water mark. Four outcomes, kept distinct because they mean different
// things to the reader:
//   unscoped — the journey declared no scope. Legacy contract; still runs, reported WEAK.
//   empty    — the table held no rows, so "rows this step wrote" is "all rows". No WHERE
//              needed and the evidence is STRONG: nothing older exists to be confused with.
//   scoped   — a mark was read; both checks are restricted to rows above it.
//   broken   — the table is non-empty but MAX() came back with nothing. The instrument
//              did not run; the checks that depend on it are INVALID.
function captureScope(entity, decl, countFn, scalarFn) {
  const c = countFn || count;
  const s = scalarFn || H.oqlScalar;
  if (!decl || !decl.newRowsBy) return { state: 'unscoped', entity };
  const attr = decl.newRowsBy;
  const n = c(sqlRowCount(entity));
  if (n === null)
    return { state: 'broken', entity, attr,
             reason: `row count for ${entity} returned nothing — admin API unreachable` };
  if (n === 0) return { state: 'empty', entity, attr };
  const w = s(sqlWatermark(entity, attr));
  if (w === null || w === '')
    return { state: 'broken', entity, attr,
             reason: `SELECT MAX(${attr}) FROM ${entity} returned nothing although the table ` +
                     `holds ${n} row(s) — this runtime's OQL will not aggregate "${attr}". ` +
                     `Declare a different data.scope.newRowsBy (e.g. a stamped DateTime).` };
  return { state: 'scoped', entity, attr, watermark: String(w), rowsBefore: n };
}

// How much a green cell from this scope is worth, in the report's own vocabulary.
function scopeEvidence(sc) {
  if (!sc || sc.state === 'unscoped')
    return { strength: 'weak',
             tag: 'unscoped: judged over the WHOLE table, so a row from an earlier run can ' +
                  'satisfy it and a legacy row can break it — declare data.scope.newRowsBy' };
  if (sc.state === 'empty')
    return { strength: 'strong', tag: `${sc.entity} was empty before this step, so every row is this step's` };
  return { strength: 'strong', tag: `scoped to rows with ${sc.attr} > ${sc.watermark}` };
}

// "Association set" is measured as: rows reachable through the association vs rows
// total. An INNER JOIN drops rows whose foreign key is null, so the difference is
// exactly the number of records that saved without their link — now counted only over
// the rows this step is answerable for.
function assocGap(entity, assoc, target, sc) {
  const total = count(sqlAssocTotal(entity, sc));
  const linked = count(sqlAssocLinked(entity, assoc, target, sc));
  if (total === null || linked === null) return null;
  return { total, linked, gap: total - linked };
}

// ── One journey ─────────────────────────────────────────────────────────────
// ── Positive controls: one deliberately broken precondition per rung ────────
// Each mutant returns the journey to run, which rung it challenges, and a predicate
// naming the check that MUST catch it. A mutant is only useful if the journey
// actually declares the thing being broken — `mustPointAt` cannot be proven on a
// journey that has none — so unsupported mutants are skipped rather than faked.
function controlMutants(j) {
  const clone = () => JSON.parse(JSON.stringify(j));
  const out = [];
  const add = (rung, what, mutate, expectFail) => {
    const c = clone();
    if (mutate(c) === false) return;          // journey does not support this mutant
    c.id = `${j.id}-CTL-${rung}`;
    c.title = `(positive control · ${rung} — ${what}; MUST fail)`;
    out.push({ rung, what, journey: c, expectFail });
  };
  const named = (s) => (r) => r.name.includes(s);

  // Rung 1 — the landing guard that stops the walk.
  add('ui-landing', 'first step lands on a widget that does not exist', (c) => {
    if (!c.steps[0] || !c.steps[0].ui) return false;
    c.steps[0].ui.ready = '.mx-name-__this_widget_does_not_exist__';
  }, named('reached'));

  // Rung 2 — what the screen SAYS. The rung that caught P-1; if it cannot fail,
  // the one genuine product defect this harness has found was luck.
  add('ui-text', 'expect text the page never renders', (c) => {
    const s = c.steps.find(x => x.ui && x.ui.textPresent);
    if (!s) return false;
    s.ui.textPresent = ['__text_this_page_will_never_render__'];
    delete s.ui.textAbsent;                   // isolate: only the textPresent claim
  }, named('page says'));

  // Rung 3a — span ORDER. assertFired is existence-only; ordering is the claim.
  add('trace-order', 'expect a microflow that never fires', (c) => {
    const s = c.steps.find(x => x.spans && x.spans.ordered);
    if (!s) return false;
    s.spans.ordered = ['FieldScan.__ACT_This_Microflow_Does_Not_Exist__'];
    delete s.spans.mustNotFire;
  }, named('ordered'));

  // Rung 3b — the NEGATIVE trace claim. A mustNotFire that cannot fail would let
  // any out-of-sequence microflow through unnoticed.
  add('trace-negative', 'assert a microflow that DID run must not have run', (c) => {
    const s = c.steps.find(x => x.spans && x.spans.ordered && x.spans.ordered.length);
    if (!s) return false;
    s.spans.mustNotFire = [s.spans.ordered[0].split('.').pop()];
  }, named('did not run'));

  // Rung 4a — the row-count delta.
  add('data-delta', 'expect +2 rows from a +1 action', (c) => {
    const s = c.steps.find(x => x.data && typeof x.data.delta === 'number');
    if (!s) return false;
    s.data.delta = s.data.delta + 1;
  }, named('+'));

  // Rung 4b — mustPointAt. Added 2026-08-14 and never yet observed failing; it is
  // the check that would have caught the wrong-location run, so leaving it unproven
  // would be exactly the decoration this whole exercise exists to retire.
  add('data-target', 'association must point at a value the journey never picked', (c) => {
    for (const s of c.steps) {
      for (const spec of (s.data && s.data.assocMustBeSet) || []) {
        if (spec.mustPointAt) {
          spec.mustPointAt.value = '__LOC_THAT_WAS_NEVER_SELECTED__';
          return;
        }
      }
    }
    return false;
  }, named('points at the seeded'));

  // Rung 5 — the end-to-end outcome claim.
  add('outcome', 'outcome query with an unreachable floor', (c) => {
    if (!c.outcome || c.outcome.atLeast === undefined) return false;
    c.outcome.atLeast = 999999;
  }, named('end state'));

  return out;
}

// Return to a known start state BETWEEN journeys.
//
// MEASURED 2026-08-14: without this, the 7 positive-control mutants ran back-to-back
// on one page and 5 of them died at step 1 on `.mx-name-bR never appeared` — the REAL
// selector, not the mutated one. Mutant 2 finished standing on the Receive page, so
// mutant 3 began its walk from there: the home button is absent on that screen and the
// nav group was already expanded, where a click COLLAPSES it. Five rungs reported
// "unproven" for a reason that had nothing to do with the rung.
//
// This is a RESET between independent journeys, which is legitimate. It is NOT the
// mid-journey `page.goto` recovery that e2e-harness notes forbid — that one hides state
// carry-over inside a walk. Here, carry-over between walks is precisely the bug.
async function resetToStart(page) {
  await page.goto(cfg.baseUrl, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(2500);
}

async function runJourney(page, j) {
  console.log(`\n=== JOURNEY ${j.id} — ${j.title || ''}`);
  console.log(`    persona: ${j.persona || cfg.user}   requirements: ${(j.requirement || []).join(', ') || '(none declared)'}`);

  const seeded = resolveSeeds(j);
  if (!seeded.ok) {
    record('data', `${j.id}: seeds resolved`, 'INVALID',
      `"${seeded.missing}" returned nothing — the DB has no row to drive this journey, ` +
      'or the admin API is unreachable. Journey NOT run; this is not a feature failure.',
      (j.requirement || []).join(', '));
    return;
  }
  const vars = seeded.vars;
  if (Object.keys(vars).length) console.log(`    seeds: ${JSON.stringify(vars)}`);

  // Baselines for every declared data effect, captured BEFORE the journey runs.
  // A delta needs a before. Taking it per-step instead of up front would let an
  // earlier step's write be counted as a later step's.
  const baseline = {};
  for (const s of j.steps) {
    const d = s.data;
    if (d && d.creates && !(d.creates in baseline)) {
      baseline[d.creates] = count(`SELECT COUNT(*) AS n FROM ${d.creates}`);
    }
  }

  const walk = { journey: j.id, title: j.title || '', persona: j.persona || cfg.user,
                 requirement: j.requirement || [], seeds: vars, steps: [] };
  walks.push(walk);

  for (const [i, step] of j.steps.entries()) {
    console.log(`\n  --- step ${i + 1}/${j.steps.length}: ${step.name}`);
    const req = (step.requirement || j.requirement || []).join(', ');
    const t0 = Date.now();
    const from = results.length;   // every check recorded from here belongs to this step
    const leg = { n: i + 1, name: step.name, requirement: req ? req.split(', ') : [],
                  actions: (step.actions || []).map(a => describeAct(a, vars)),
                  expects: {
                    landsOn: (step.ui && step.ui.ready) || null,
                    pageSays: (step.ui && step.ui.textPresent) || [],
                    pageDoesNotSay: (step.ui && step.ui.textAbsent) || [],
                    microflows: (step.spans && step.spans.ordered) || [],
                    writes: step.data && step.data.creates
                      ? { entity: step.data.creates, delta: step.data.delta ?? null,
                          associations: (step.data.assocMustBeSet || []).map(s => s.assoc || s) }
                      : null,
                  },
                  shot: null, reached: null, checks: [], ms: null };
    walk.steps.push(leg);
    // Attach this step's checks and timing however the step ends — including the
    // early `return`s below, which is why it is a finaliser called at each exit and
    // not a line at the bottom of the loop. A step that bailed still has to show
    // what it managed, or the walk goes quiet exactly where it matters most.
    const seal = () => {
      leg.checks = results.slice(from).map(r =>
        ({ rung: r.rung, name: r.name, verdict: r.verdict, detail: r.detail }));
      leg.ms = Date.now() - t0;
    };

    // Actions may assert as they go — a combobox that commits the seeded value is a
    // real measurement and belongs in the findings, not buried in a side effect.
    const note = (rung, name, verdict, detail) =>
      record(rung, `${step.name}: ${name}`, verdict, detail, req);

    // ── Rung 4 watermarks, taken BEFORE the actions ──────────────────────────
    // This is the only moment they can be taken. A mark read after the click already
    // includes the row the click wrote, and the scoped checks would then look for it
    // strictly above itself and find nothing — a false FAIL on a correct commit.
    // One mark per distinct entity the step will assert on.
    const scopes = new Map();
    if (step.data) {
      const decl = step.data.scope;
      const ents = new Set();
      if (step.data.creates) ents.add(step.data.creates);
      for (const spec of step.data.assocMustBeSet || [])
        ents.add(spec.entity || step.data.creates);
      for (const e of ents) if (e) scopes.set(e, captureScope(e, decl));
    }

    try {
      for (const a of step.actions || []) await act(page, a, vars, note);
    } catch (e) {
      record('ui', `${step.name}: actions completed`, 'FAIL', e.message.split('\n')[0], req);
      leg.shot = await shoot(page, `${j.id}-step${i + 1}-ACTION-FAILED`);
      seal();
      return; // the journey's state is now unknown; later steps would measure noise
    }

    // ── RUNG 1: landing guard ────────────────────────────────────────────────
    let onPage = true;
    if (step.ui && step.ui.ready) {
      onPage = await page.locator(step.ui.ready).first()
                         .isVisible({ timeout: 12000 }).catch(() => false);
      if (!onPage) {
        leg.shot = await shoot(page, `${j.id}-step${i + 1}-NOT-REACHED`);
        record('ui', `${step.name}: reached`, 'FAIL',
               `"${step.ui.ready}" never appeared — screenshot ${path.basename(leg.shot.file)}`, req);
      } else {
        record('ui', `${step.name}: reached`, 'PASS', step.ui.ready, req);
      }
      leg.reached = onPage;
    }

    // The success shot, taken HERE: after the actions and the landing guard, before
    // the text/trace/data rungs. That ordering is the whole point — this image is the
    // page state those rungs measured, not a later one. A shot taken at the bottom of
    // the loop would show the app after any navigation the rungs provoked, and would
    // quietly stop being evidence for the checks printed beside it.
    if (onPage && !leg.shot) leg.shot = await shoot(page, `${j.id}-step${i + 1}`);

    // Everything below asserts about THIS page. If we never landed, it would be
    // asserting about the previous one — so it does not run at all.
    if (!onPage) {
      record('ui', `${step.name}: downstream rungs`, 'INVALID', 'not reached; nothing measured', req);
      seal();
      return;
    }

    for (const c of (step.ui && step.ui.checks) || []) {
      const seen = await page.locator(`.mx-name-${c}`).first().isVisible({ timeout: 4000 }).catch(() => false);
      record('ui', `${step.name}: widget ${c}`, seen ? 'PASS' : 'FAIL', '', req);
    }

    // What the page SAYS, not just which widgets exist. Every other rung answers
    // "did the machine do the work"; only this one answers "does the screen tell the
    // user the truth about it". FieldScan's Receive commits the row correctly and
    // then renders "No placements yet" on the panel listing that very row — a defect
    // that mxbuild, the microflow span, the activity spans and the OQL delta all
    // agree is fine, because by their own lights it is.
    const body = ((step.ui && (step.ui.textPresent || step.ui.textAbsent))
      ? await page.locator('body').innerText().catch(() => '') : '');
    for (const t of (step.ui && step.ui.textPresent) || []) {
      const want = String(subst(t, vars));
      record('ui', `${step.name}: page says "${want}"`,
             body.includes(want) ? 'PASS' : 'FAIL',
             body.includes(want) ? '' : 'not found in rendered text', req);
    }
    for (const t of (step.ui && step.ui.textAbsent) || []) {
      const bad = String(subst(t, vars));
      record('ui', `${step.name}: page does NOT say "${bad}"`,
             body.includes(bad) ? 'FAIL' : 'PASS',
             body.includes(bad) ? 'rendered — the screen contradicts the data' : '', req);
    }

    // ── RUNG 2: ordered spans ────────────────────────────────────────────────
    if (step.spans && step.spans.ordered && step.spans.ordered.length) {
      const spans = await O.capture(t0, { min: 1 });
      if (!spans.length) {
        record('trace', `${step.name}: spans`, 'INVALID',
               'zero spans captured — Jaeger down or OTel off. Trace rung did NOT run.', req);
      } else {
        O.guard(spans, otelReporter(req), `${step.name}: capture non-empty`);
        O.assertSequence(spans, step.spans.ordered, otelReporter(req), `${step.name}: ordered`);
        O.assertNoErrors(spans, otelReporter(req), `${step.name}: no ERROR at any level`);
        for (const n of step.spans.mustNotFire || []) {
          O.assertNotFired(spans, new RegExp(n), otelReporter(req), `${step.name}: ${n} did not run`);
        }
      }
    }

    // ── RUNG 3: data effects ─────────────────────────────────────────────────
    const d = step.data;
    if (d) {
      if (d.creates) {
        const before = baseline[d.creates];
        const after = count(`SELECT COUNT(*) AS n FROM ${d.creates}`);
        if (before === null || after === null) {
          record('data', `${step.name}: ${d.creates} created`, 'INVALID',
                 'OQL returned nothing — admin API unreachable. Data rung did NOT run.', req);
        } else {
          const want = d.delta ?? 1;
          record('data', `${step.name}: ${d.creates} +${want}`,
                 after - before === want ? 'PASS' : 'FAIL',
                 `before=${before} after=${after} delta=${after - before}`, req);
          baseline[d.creates] = after;
        }
      }
      for (const spec of d.assocMustBeSet || []) {
        const entity = spec.entity || d.creates;
        const sc = scopes.get(entity) || { state: 'unscoped', entity };
        const ev = scopeEvidence(sc);

        // A declared-but-unreadable watermark stops both checks here. Running them
        // unscoped instead would print the scoped claim over whole-table numbers.
        if (sc.state === 'broken') {
          record('data', `${step.name}: ${spec.assoc} set on every row`, 'INVALID', sc.reason, req);
          if (spec.mustPointAt)
            record('data', `${step.name}: ${spec.assoc} points at the seeded ${spec.mustPointAt.attr}`,
                   'INVALID', sc.reason, req);
          continue;
        }

        const g = assocGap(entity, spec.assoc, spec.target, sc);
        if (g === null) {
          record('data', `${step.name}: ${spec.assoc} set`, 'INVALID', 'OQL returned nothing', req);
        } else if (sc.state !== 'unscoped' && g.total === 0) {
          // Scoped to nothing: the step wrote no row at all, so there is no association
          // to judge. Reporting "0/0 linked, gap 0" as PASS is the vacuous green the
          // scoping was added to remove — the delta check above owns this failure.
          record('data', `${step.name}: ${spec.assoc} set on every row`, 'FAIL',
                 `no ${entity} row was written by this step (${ev.tag}), so the association ` +
                 'could not be verified — nothing to link', req, 'strong');
        } else {
          record('data', `${step.name}: ${spec.assoc} set on every row`,
                 g.gap === 0 ? 'PASS' : 'FAIL',
                 `${g.linked}/${g.total} linked, ${g.gap} row(s) saved with no association ` +
                 `(${ev.tag})`, req, ev.strength);
        }

        // "Set" and "set to the right thing" are different claims, and the gap between
        // them is where a wrong-input run hides: a placement linked to SOME location
        // satisfies the check above no matter which location the user actually picked.
        // `mustPointAt` closes it by naming the seed the target has to match.
        if (spec.mustPointAt) {
          const { attr, value } = spec.mustPointAt;
          const want = subst(value, vars);
          const n = count(sqlMustPointAt(entity, spec.assoc, spec.target, attr, want, sc));
          if (n === null) {
            record('data', `${step.name}: ${spec.assoc} points at the seeded ${attr}`,
                   'INVALID', 'OQL returned nothing', req);
          } else {
            record('data', `${step.name}: ${spec.assoc} points at the seeded ${attr}`,
                   n >= 1 ? 'PASS' : 'FAIL',
                   `${n} row(s) link to ${spec.target} where ${attr} = '${want}' (${ev.tag})`,
                   req, ev.strength);
          }
        }
      }
      for (const q of d.oql || []) {
        const c = checkOql(q, vars);
        record('data', `${step.name}: ${q.label}`, c.verdict, c.detail, req);
      }
    }
    seal();
  }

  // ── RUNG 4: outcome ────────────────────────────────────────────────────────
  if (j.outcome && j.outcome.sql) {
    const c = checkOql(j.outcome, vars);
    record('outcome', `${j.id} end state`, c.verdict, c.detail, (j.requirement || []).join(', '));
  }
}

// ── Exports for the rung-4 scope unit test ──────────────────────────────────
// The SQL builders are pure and exported so their behaviour can be proven against
// fixture rows without a running app. See tests/e2e/journey-rung4-scope.test.js.
module.exports = {
  sqlRowCount, sqlWatermark, whereScoped, scopeLiteral,
  sqlAssocTotal, sqlAssocLinked, sqlMustPointAt, captureScope, scopeEvidence,
};

// ── Main ────────────────────────────────────────────────────────────────────
if (require.main !== module) return;
(async () => {
  const journeys = files.map(f => JSON.parse(fs.readFileSync(f, 'utf8')));

  const { browser, page } = await H.launchBrowser();

  const li = await H.login(page);
  // Identity, not presence. A silent degrade to admin bypasses the role grants the
  // journey exists to exercise, and every assertion below would be measuring an
  // access path no real user takes.
  if (!li.ok && li.fault) {
    // The runtime refused the login for a reason that is not the credential.
    // INVALID, not FAIL: nothing was measured, so there is no finding to report.
    record('ui', 'login', 'INVALID',
      `login faulted: "${li.reason}" — not a credential failure. The runtime refused ` +
      'the session (measured cause on 2026-08-18: trial-licence concurrent-session cap). ' +
      'Check the runtime log; no rung below this ran.');
  } else if (!li.ok) {
    record('ui', 'login', 'FAIL', li.reason || 'login failed');
  } else if (li.usedFallback) {
    record('ui', 'login', 'INVALID',
      `fell back to "${li.user}" instead of "${cfg.user}" — admin bypasses the role grants ` +
      'these journeys test; the whole run measures the wrong access path');
  } else {
    record('ui', 'login', 'PASS', li.user);
  }

  if (li.ok && !li.usedFallback) {
    for (const j of journeys) {
      if (POSITIVE_CONTROL) {
        // Non-vacuity, per RUNG. testing-shape.md §6 asks for this and only one spec
        // in the whole corpus had ever been shown to fail when it should.
        //
        // MEASURED 2026-08-14: the previous version of this block broke exactly one
        // thing — step 1's `ready` selector — and then reported "assertions can fail"
        // for the whole journey. That green was far broader than what it tested:
        // breaking step 1 stops the walk before the trace, data and outcome rungs run,
        // so those were never challenged at all. On the live run they were 20 of the
        // 24 results. A control that only exercises the guard which stops the walk
        // proves the least interesting assertion in the harness and licenses a claim
        // about all the others.
        //
        // So: one mutant per rung, each requiring that THE TARGETED CHECK failed —
        // not merely that something did. Accepting any FAIL would let a mutant that
        // breaks by accident vouch for a rung it never reached, which is the same
        // vacuity bug one level up.
        for (const m of controlMutants(j)) {
          const before = results.length;
          await resetToStart(page);
          await runJourney(page, m.journey);
          const produced = results.slice(before);
          const hit = produced.find(r => r.verdict === 'FAIL' && m.expectFail(r));
          const anyFail = produced.some(r => r.verdict === 'FAIL');
          record('control', `${j.id} · ${m.rung}: ${m.what}`,
                 hit ? 'PASS' : 'FAIL',
                 hit ? `caught by "${hit.name}"`
                     : anyFail
                       ? 'the run failed, but NOT on the targeted check — this rung is still unproven'
                       : 'BROKEN PRECONDITION WENT GREEN — this rung proves nothing');
        }
      } else {
        await resetToStart(page);
        await runJourney(page, j);
      }
    }
  }

  // Release the server-side session BEFORE closing the browser. Closing the
  // browser does not end a Mendix session; on an unlicensed runtime the leaked
  // sessions accumulate across runs until every later login is refused, and the
  // UI reports that as a wrong password. Measured 2026-08-18.
  if (li.ok) await H.logout(page);
  await browser.close();

  const n = v => results.filter(r => r.verdict === v).length;
  console.log('\n=== SUMMARY ===');
  console.log(`  PASS ${n('PASS')}   FAIL ${n('FAIL')}   INVALID ${n('INVALID')}`);
  if (n('INVALID')) {
    console.log('  ⚠ INVALID means an instrument did not run. Those checks are NOT green —');
    console.log('    they are absent. Fix the instrument before reading this report as coverage.');
  }

  fs.mkdirSync(cfg.artifactsDir, { recursive: true });
  // A control run NEVER writes to the real walk's slot.
  //
  // MEASURED 2026-08-14: it used to, and the control run silently replaced 24 real
  // results with 146 mutant ones. Nothing errored; the file was simply the wrong run
  // afterwards, and the next report would have described seven deliberately-broken
  // journeys as if they were the product. The raw evidence for that day's real walk
  // is gone — only its normalized copy in docs/report.json survived.
  //
  // These two files answer different questions ("does the app work" / "can this
  // harness tell when it doesn't") and must never share storage.
  const out = path.join(cfg.artifactsDir,
    POSITIVE_CONTROL ? 'journey-findings-control.json' : 'journey-findings.json');
  fs.writeFileSync(out, JSON.stringify({
    capturedAt: new Date().toISOString(),
    configuredUser: cfg.user, actualUser: li.user, usedFallback: !!li.usedFallback,
    baseUrl: cfg.baseUrl, positiveControl: POSITIVE_CONTROL, results, walks,
  }, null, 2));
  console.log(`  findings → ${path.relative(cfg.root, out)}`);

  process.exit(n('FAIL') === 0 && n('INVALID') === 0 ? 0 : 1);
})().catch(e => {
  console.error('ERR', e.stack?.split('\n').slice(0, 8).join('\n'));
  process.exit(1);
});
