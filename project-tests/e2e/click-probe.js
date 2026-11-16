'use strict';
// ============================================================================
// click-probe.js — does a click land, and does the page stay inside the screen? ADVISORY.
// ----------------------------------------------------------------------------
//   node tests/e2e/click-probe.js                    # every navigation page, each persona, 1280 + 390 px
//   node tests/e2e/click-probe.js --json             # one JSON object on stdout, RESULT line on stderr
//   node tests/e2e/click-probe.js --pages /p/home,/p/team   # these pages instead of the navigation's
//   node tests/e2e/click-probe.js --accepted <file>  # accepted list (default below)
//
// WHAT IT CHECKS, per page, per persona, at 1280 and at 390 px
//   (a) every visible, enabled button/link: document.elementFromPoint at its centre must be the
//       control, something inside it, or an interactive ancestor. Otherwise a layer sits on top and
//       a user's click does not reach it:
//         click does not land: /p/flashcards btnFlip "Show meaning" covered by promoStrip
//   (b) document.scrollWidth > clientWidth: the page scrolls sideways.
//         page scrolls sideways at 390: /p/team, widest element filterBar, 17 px over
//
// WHY. A planted-defect experiment (2026-11, a toolkit-built demo app, six defects) found these two
// with a 66 s probe (7 pages x 2 widths x 2 personas) that the whole existing check set and two blind
// screenshot reviews missed: an invisible container over two buttons (clicks did not land) and a
// filter bar that made the page scroll sideways at 390 px. A screenshot cannot show either.
//
// READ-ONLY. It never clicks, types, submits or hovers; it navigates by URL, scrolls, and reads
// geometry. Opening a page still runs that page's own load logic, exactly as a visitor's would.
//
// EXIT CODES  0 clean (nothing found over a non-empty denominator) · 1 findings · 2 usage ·
//             4 could not run: app not reachable, login failed, credentials still the template
//             placeholder, Playwright missing, zero pages found, zero controls checked, or a page
//             that could not be measured and nothing found. NEVER 0 when it probed nothing.
// OUTPUT      human lines, one `MXTK-RESULT click-probe verdict=<clean|findings|could-not-run>
//             findings=N accepted=N pages=N controls=N personas=N exit=C` line (stdout; with --json
//             the object is stdout and this line goes to stderr, as security-check.sh does), and a
//             `denominator:` line stating what was and was not measured.
//
// ACCEPTED LIST  <root>/.claude/loop/click-probe-accepted.tsv (or the parent's, for an app/ layout):
//   kind<TAB>page<TAB>element<TAB>reason   kind = click | sideways; element = the widget name the
//   finding prints, or * for any. A line WITHOUT a reason is ignored and reported, so the finding
//   stays a finding: same footing as security-check.sh's accepted list.
//
// FALSE-POSITIVE SOURCES handled (the clean app reported 0 findings in 20 page-views, 2026-11-16):
//   disabled / aria-disabled / pointer-events:none controls, invisible, zero-size, display:none,
//   aria-hidden and closed-dropdown controls, and controls that stay outside the viewport after
//   scrolling (an off-canvas drawer) are SKIPPED and COUNTED in the denominator, never judged.
//   Hover-only layers (tooltips) never exist because nothing is hovered.
//
// PRODUCER / CONSUMER. Consumer: project-bin/module-close.sh runs this file at the module boundary
// and prints one advisory line (never a verdict, never an exit code). Installed into projects by
// bin/lib/install-manifest.sh (MXTK_PROJECT_TESTS). Needs only what the journey runner needs:
// project.config.js, a running app (bin/test-stack-up.sh), Playwright, TEST_USER/TEST_PASS.
//
// FIELD RUN, honestly. The prototype this grew from ran on a toolkit-built demo app, clean (20
// page-views, 232 controls, 0 findings) and with six planted defects (24 page-views, 288 controls:
// two covered buttons at both widths, one page 17 px over at 390), 66 s for 7 pages x 2 widths x 2
// personas; its output is captured in tests/wave2/fixtures/click-probe/. THIS file (login through the
// shared helpers, skip counts, accepted list, exit 4 paths) has run only against the local stand-in
// pages of tests/wave2/test-click-probe.sh: first run on a live Mendix app is still owed.
// ============================================================================

const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');

const WIDTHS = [[1280, 900], [390, 844]];
const MAX_PAGES = Number(process.env.CLICK_PROBE_MAX_PAGES || 60);

// ── pure functions (exported; the fixture asserts them on captured real output) ─────────────────

// `mx-name-<w>` out of a class string ("btn mx-button mx-name-btnFlip btn-primary" -> btnFlip).
function mxName(cls) {
  const m = /(?:^|[\s.])mx-name-([\w-]+)/.exec(String(cls || ''));
  return m ? m[1] : '';
}

// One probed page-view -> its findings. Works on the record this file writes AND on the stage-A
// capture (fields cls / coveredBy as `TAG.class...`; no `name`, `coveredByName` or `widest`).
function viewFindings(v) {
  const out = [];
  for (const c of (v.covered || [])) {
    const widget = c.name || mxName(c.cls) || (c.label ? `"${c.label}"` : 'control');
    const by = c.coveredByName || mxName(c.coveredBy) || String(c.coveredBy || 'unknown');
    out.push({ kind: 'click', persona: v.persona, width: v.width, page: v.landed || v.page, widget,
               label: c.label || '', coveredBy: by });
  }
  if (v.overflowPx > 0) {
    const w = v.widest || {};
    out.push({ kind: 'sideways', persona: v.persona, width: v.width, page: v.landed || v.page,
               widget: w.name || mxName(w.cls) || w.cls || 'unknown', over: v.overflowPx });
  }
  return out;
}
function findingText(f) {
  return f.kind === 'click'
    ? `click does not land: ${f.page} ${f.widget}${f.label ? ` "${f.label}"` : ''} covered by ${f.coveredBy}`
    : `page scrolls sideways at ${f.width}: ${f.page}, widest element ${f.widget}, ${f.over} px over`;
}

// The same defect seen by several personas at one width is one finding with the personas listed.
function dedupeFindings(list) {
  const seen = new Map();
  for (const f of list) {
    const k = [f.kind, f.width, f.page, f.widget, f.coveredBy || ''].join('|');
    if (!seen.has(k)) seen.set(k, { ...f, personas: [f.persona] });
    else if (!seen.get(k).personas.includes(f.persona)) seen.get(k).personas.push(f.persona);
  }
  return [...seen.values()];
}

// Accepted list text -> { entries, problems }. A line needs kind, page, element AND a reason.
function parseAccepted(text) {
  const entries = [], problems = [];
  String(text || '').split('\n').forEach((raw, i) => {
    const line = raw.replace(/\r$/, '');
    if (!line.trim() || /^\s*#/.test(line)) return;
    const c = line.split('\t').map(s => s.trim());
    if (!['click', 'sideways'].includes(c[0]) || !c[1] || !c[2]) {
      problems.push({ line: i + 1, text: line.slice(0, 80), why: 'needs kind (click|sideways), page, element, reason, tab-separated' });
    } else if (!c[3]) {
      problems.push({ line: i + 1, text: line.slice(0, 80), why: 'no reason: ignored, the finding stays a finding' });
    } else entries.push({ kind: c[0], page: c[1], element: c[2], reason: c[3], used: false });
  });
  return { entries, problems };
}
function applyAccepted(findings, entries) {
  const open = [], accepted = [];
  for (const f of findings) {
    const e = entries.find(a => a.kind === f.kind && a.page === f.page && (a.element === '*' || a.element === f.widget));
    if (e) { e.used = true; accepted.push({ ...f, reason: e.reason }); } else open.push(f);
  }
  return { open, accepted, stale: entries.filter(e => !e.used) };
}

// Counts from the page-view records. `views` holds only views that were measured.
function denominator(views, personaPages) {
  const controls = views.reduce((n, v) => n + (v.checked || 0), 0);
  const skipped = views.reduce((n, v) => n + Object.values(v.skipped || {}).reduce((a, b) => a + b, 0), 0);
  const per = Object.keys(personaPages).map(p => `${p} ${personaPages[p]} page${personaPages[p] === 1 ? '' : 's'}`).join(', ');
  const nW = new Set(views.map(v => v.width)).size || WIDTHS.length;
  return { pageViews: views.length, controls, skipped, personas: Object.keys(personaPages).length, widths: nW,
           text: `${views.length} page-views (${per || 'none'}; x ${nW} widths), ${controls} controls checked, ${skipped} skipped (hidden, disabled or off-screen)` };
}
function resultLine(verdict, c) {
  return `MXTK-RESULT click-probe verdict=${verdict} findings=${c.findings} accepted=${c.accepted} pages=${c.pages} controls=${c.controls} personas=${c.personas} exit=${c.exit}`;
}

// ── in the browser (page.evaluate): self-contained, no closure over node values ──────────────────
function inPage() {
  const SEL = 'button, a[href], [role=button], [role=link], .mx-link, input[type=button], input[type=submit]';
  const FWD = 'a, button, label, summary, [role=button], [role=link], .mx-link';
  const mx = (el) => {
    for (let e = el; e && e !== document.body && e.getAttribute; e = e.parentElement) {
      const m = /(?:^|\s)mx-name-([\w-]+)/.exec(e.getAttribute('class') || '');
      if (m) return m[1];
    }
    return '';
  };
  const tag = (el) => el.tagName + '.' + String(el.getAttribute('class') || '').slice(0, 60);
  const viol = [], skipped = { hidden: 0, disabled: 0, offscreen: 0 };
  let checked = 0;
  for (const el of document.querySelectorAll(SEL)) {
    const cs = getComputedStyle(el), r = el.getBoundingClientRect();
    if (cs.display === 'none' || cs.visibility === 'hidden' || r.width < 2 || r.height < 2 || el.closest('[aria-hidden=true]')
        || (el.checkVisibility && !el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true }))) { skipped.hidden++; continue; }
    if (el.disabled || el.getAttribute('aria-disabled') === 'true' || cs.pointerEvents === 'none'
        || el.classList.contains('disabled')) { skipped.disabled++; continue; }
    el.scrollIntoView({ block: 'center', inline: 'center' });
    const r2 = el.getBoundingClientRect();
    const x = r2.left + r2.width / 2, y = r2.top + r2.height / 2;
    if (x < 0 || y < 0 || x > innerWidth || y > innerHeight) { skipped.offscreen++; continue; }
    checked++;
    const top = document.elementFromPoint(x, y);
    const fwd = top && top.closest(FWD);
    if (!top || !(top === el || el.contains(top) || (fwd && (fwd === el || fwd.contains(el))))) {
      viol.push({ label: (el.innerText || el.getAttribute('aria-label') || el.getAttribute('title') || '').trim().replace(/\s+/g, ' ').slice(0, 40),
                  cls: String(el.getAttribute('class') || '').slice(0, 60), name: mx(el),
                  coveredBy: top ? tag(top) : 'null', coveredByName: top ? mx(top) : '' });
    }
  }
  window.scrollTo(0, 0);
  const de = document.documentElement, over = de.scrollWidth - de.clientWidth;
  let widest = null;
  if (over > 0) {   // the element reaching furthest right, ignoring anything an ancestor clips
    let best = -1, bestDepth = -1;
    for (const el of document.body.querySelectorAll('*')) {
      const cs = getComputedStyle(el);
      if (cs.display === 'none' || cs.position === 'fixed') continue;
      const r = el.getBoundingClientRect();
      if (r.width < 1 || r.right <= de.clientWidth) continue;
      let clipped = false, depth = 0;
      for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
        depth++;
        if (getComputedStyle(p).overflowX !== 'visible') { clipped = true; break; }
      }
      if (clipped) continue;
      if (r.right > best || (r.right === best && depth > bestDepth)) { best = r.right; bestDepth = depth; widest = { name: mx(el), cls: tag(el) }; }
    }
  }
  return { checked, skipped, viol, scrollWidth: de.scrollWidth, clientWidth: de.clientWidth, overflowPx: over, widest };
}

// ── driver ───────────────────────────────────────────────────────────────────────────────────────
function reachable(url, ms = 6000) {
  return new Promise((resolve) => {
    let u; try { u = new URL(url); } catch (e) { return resolve(false); }
    const req = (u.protocol === 'https:' ? https : http).get(u, { timeout: ms }, (res) => { res.resume(); resolve(true); });
    req.on('timeout', () => { req.destroy(); resolve(false); });
    req.on('error', () => resolve(false));
  });
}
const pathOf = (url, base) => { try { const u = new URL(url, base); return u.pathname.replace(/\/+$/, '') || '/'; } catch (e) { return String(url); } };

async function main(argv) {
  const opt = { json: false, pages: null, accepted: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--json') opt.json = true;
    else if (a === '--pages' && argv[i + 1]) opt.pages = argv[++i].split(',').map(s => s.trim()).filter(Boolean);
    else if (a === '--accepted' && argv[i + 1]) opt.accepted = argv[++i];
    else if (a === '-h' || a === '--help') {
      console.log('usage: node tests/e2e/click-probe.js [--json] [--pages /p/a,/p/b] [--accepted <file>]');
      return 0;
    } else { console.error(`click-probe: unknown or incomplete argument "${a}" (try --help)`); return 2; }
  }
  if (opt.json) console.log = (...a) => console.error(...a);   // the login helper prints to stdout; --json owns stdout
  const say = (s) => { if (!opt.json) console.log(s); };
  const state = { verdict: 'could-not-run', exit: 4, findings: [], accepted: [], stale: [], problems: [], views: [], skippedPersonas: [], notMeasured: [], error: '' };
  const finish = (c) => {
    const counts = { findings: state.findings.length, accepted: state.accepted.length, pages: c.pages || 0, controls: c.controls || 0, personas: c.personas || 0, exit: state.exit };
    const line = resultLine(state.verdict, counts);
    if (opt.json) {
      process.stdout.write(JSON.stringify({ verdict: state.verdict, exit: state.exit, error: state.error || undefined, findings: state.findings.map(f => ({ ...f, text: findingText(f) })),
        accepted: state.accepted, staleAccepted: state.stale, acceptedProblems: state.problems, skippedPersonas: state.skippedPersonas,
        notMeasured: state.notMeasured, counts, denominator: c.text || '', views: state.views }, null, 1) + '\n');
      console.error(line);
    } else console.log(line);
    return state.exit;
  };
  const stop = (msg) => {   // exit 4: the instrument could not run
    state.error = msg;
    if (opt.json) console.error(`click-probe: could not run - ${msg}`); else console.error(`click-probe: COULD NOT RUN - ${msg}\nThis is the instrument failing, not the app passing: nothing was measured.`);
    return finish({ text: 'nothing measured' });
  };

  // config.js and helpers.js call process.exit(2) on a refused app / missing config; turn that into 4.
  let H, cfg, PROJ, settle;
  const realExit = process.exit;
  try {
    process.exit = (code) => { throw new Error(`refused at load (exit ${code}); the message above says why`); };
    PROJ = require('./project.config');
    ({ cfg } = require('./config'));
    H = require('./helpers');
    ({ settle } = require('./settle'));
  } catch (e) { process.exit = realExit; return stop(String(e.message).split('\n')[0]); }
  process.exit = realExit;
  if (!H.deviceProfiles()) return stop('playwright is not installed (npm install playwright && npx playwright install chromium)');
  if (cfg.passSource === 'template placeholder' && process.env.ALLOW_CONFIG_CREDENTIALS !== '1') {
    return stop('credentials are the template placeholder: set TEST_USER/TEST_PASS (or ALLOW_CONFIG_CREDENTIALS=1); no login was attempted');
  }
  if (!(await reachable(cfg.baseUrl + '/'))) return stop(`app not reachable at ${cfg.baseUrl} (start it: bin/test-stack-up.sh)`);

  // accepted list (reason required)
  const ROOT = PROJ.root;
  const accFile = opt.accepted || [path.join(ROOT, '.claude', 'loop', 'click-probe-accepted.tsv'), path.join(path.dirname(ROOT), '.claude', 'loop', 'click-probe-accepted.tsv')].find(f => fs.existsSync(f));
  let acc = { entries: [], problems: [] };
  if (accFile) { try { acc = parseAccepted(fs.readFileSync(accFile, 'utf8')); } catch (e) { acc.problems.push({ line: 0, text: accFile, why: 'unreadable: ' + e.message }); } }
  state.problems = acc.problems;

  // personas: the configured user first, then project.config.js `roles`; never the admin fallback
  cfg.fallbackUser = '';
  const personas = [{ user: cfg.user, pass: cfg.pass, main: true }];
  for (const k of Object.keys(PROJ.roles || {})) {
    const r = PROJ.roles[k];
    if (r && r.user && !personas.some(p => p.user === r.user)) personas.push({ user: r.user, pass: r.pass, main: false });
  }

  say(`click-probe: ${cfg.baseUrl}, ${personas.length} persona(s) configured, widths ${WIDTHS.map(w => w[0]).join(' + ')} px`);
  const personaPages = {};
  let navPages = opt.pages;
  for (const pr of personas) {
    let pages = navPages ? navPages.slice() : null, ok = true, why = '';
    for (const [w, h] of WIDTHS) {
      let br = null;
      try {
        br = await H.launchBrowser({ viewport: { width: w, height: h } });
        const { page } = br;
        cfg.user = pr.user; cfg.pass = pr.pass;
        const li = await H.login(page);
        if (!li.ok || li.usedFallback) { ok = false; why = `login as "${pr.user}" failed (${li.reason || 'fell back to another account'})`; break; }
        const landing = pathOf(page.url(), cfg.baseUrl);
        if (!pages) {   // discover the navigation once, at 1280, from the shell's own links
          const hrefs = await page.evaluate(() => {
            const bad = /logout|login|signout|^javascript:|^mailto:|^#/i;
            const out = [];
            for (const a of document.querySelectorAll('.mx-navigationtree a[href], .mx-navbar a[href], nav a[href], [role=navigation] a[href]')) {
              const h = a.getAttribute('href');
              if (!h || bad.test(h)) continue;
              const u = new URL(h, location.href);
              if (u.origin === location.origin) out.push(u.pathname + u.search);
            }
            return out;
          });
          pages = [...new Set(hrefs.map(h => (h.replace(/\/+$/, '') || '/')))];
          if (!pages.length) state.notMeasured.push(`${pr.user}: the navigation lists no page links, only the landing page was probed (pass --pages)`);
        }
        const list = [landing, ...pages.filter(p => pathOf(p, cfg.baseUrl) !== landing)].slice(0, MAX_PAGES);
        if (pages.length + 1 > MAX_PAGES) state.notMeasured.push(`${pr.user}: navigation has ${pages.length + 1} pages, only the first ${MAX_PAGES} probed (CLICK_PROBE_MAX_PAGES)`);
        const seen = new Set();
        for (const href of list) {
          if (href !== landing || seen.size) { await page.goto(cfg.baseUrl + href, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => {}); }
          await settle(page, { fallbackMs: 2200 });
          const landed = pathOf(page.url(), cfg.baseUrl);
          if (seen.has(landed)) continue;   // a redirect to a page already probed
          seen.add(landed);
          if (/login(\.html)?$/.test(landed)) { state.notMeasured.push(`${pr.user} ${w}px ${href}: redirected to the login page`); continue; }
          let r;
          try { r = await page.evaluate(inPage); } catch (e) { state.notMeasured.push(`${pr.user} ${w}px ${href}: ${String(e.message).split('\n')[0]}`); continue; }
          state.views.push({ persona: pr.user, width: w, page: href, landed, checked: r.checked, skipped: r.skipped, covered: r.viol, overflowPx: r.overflowPx, widest: r.widest });
          personaPages[pr.user] = Math.max(personaPages[pr.user] || 0, state.views.filter(v => v.persona === pr.user && v.width === w).length);
          say(`  ${pr.user} ${w}px ${landed}: ${r.checked} controls${r.viol.length || r.overflowPx > 0 ? ' - FINDING' : ''}`);
        }
        await H.logout(page).catch(() => {});   // an open session counts against the licence cap
      } catch (e) {
        ok = false; why = String(e.message).split('\n')[0];
      } finally { if (br) await br.browser.close().catch(() => {}); }
      if (!ok) break;
      if (!navPages) navPages = null;   // discovery is per persona
    }
    if (!ok) {
      if (pr.main) return stop(`the configured persona could not be probed: ${why}`);
      state.skippedPersonas.push({ persona: pr.user, why });
      say(`  ${pr.user}: NOT PROBED - ${why}`);
      for (let i = state.views.length - 1; i >= 0; i--) if (state.views[i].persona === pr.user) state.views.splice(i, 1);
      delete personaPages[pr.user];
    }
  }

  const d = denominator(state.views, personaPages);
  const res = applyAccepted(dedupeFindings(state.views.flatMap(viewFindings)), acc.entries);
  state.findings = res.open; state.accepted = res.accepted; state.stale = res.stale;
  const c = { pages: d.pageViews, controls: d.controls, personas: d.personas, text: d.text };
  if (d.pageViews === 0) return stop('zero pages found to probe (the navigation lists no page links; pass --pages)');
  if (d.controls === 0) return stop(`zero controls checked on ${d.pageViews} page-view(s)`);
  state.exit = state.findings.length ? 1 : (state.notMeasured.length ? 4 : 0);
  state.verdict = state.findings.length ? 'findings' : (state.notMeasured.length ? 'could-not-run' : 'clean');
  const lines = [];
  for (const f of state.findings) lines.push(`FINDING ${findingText(f)} (${f.personas.join(', ')} at ${f.width} px)`);
  for (const f of state.accepted) lines.push(`accepted ${findingText(f)} - ${f.reason}`);
  for (const p of state.problems) lines.push(`accepted list line ${p.line}: ${p.why} [${p.text}]`);
  for (const s of state.stale) lines.push(`accepted entry matches nothing now (stale): ${s.kind} ${s.page} ${s.element}`);
  for (const n of state.notMeasured) lines.push(`NOT MEASURED ${n}`);
  for (const s of state.skippedPersonas) lines.push(`NOT PROBED persona ${s.persona}: ${s.why}`);
  if (!opt.json) {
    for (const l of lines) console.log(l);
    // the RESULT line comes before the closing human lines, as security-check.sh does
  }
  const code = finish(c);
  if (!opt.json) {
    console.log(`denominator: ${d.text}`);
    console.log(state.findings.length ? `click-probe: ${state.findings.length} finding(s)` : state.notMeasured.length ? 'click-probe: nothing found, but not every page was measured: this is not a clean result' : 'click-probe: clean over that denominator (a probe of clicks and sideways scroll, not proof the page works)');
  }
  return code;
}

module.exports = { mxName, viewFindings, findingText, dedupeFindings, parseAccepted, applyAccepted, denominator, resultLine, inPage };

if (require.main === module) {
  main(process.argv.slice(2)).then((code) => process.exit(code),
    (e) => { console.error('click-probe: COULD NOT RUN - ' + (e && e.stack ? e.stack.split('\n').slice(0, 4).join('\n') : e)); console.log('MXTK-RESULT click-probe verdict=could-not-run findings=0 accepted=0 pages=0 controls=0 personas=0 exit=4'); process.exit(4); });
}
