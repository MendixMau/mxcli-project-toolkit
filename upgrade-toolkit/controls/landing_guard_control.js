'use strict';
// landing_guard_control.js: the landing guard check of the journey engine in a real browser (T8R B2-2).
//
//   node landing_guard_control.js          (NODE_PATH must reach playwright with a browser)
//
// T8R: login-ServiceDeskEmployee waited on .mx-name-dataView1, a data view whose content is positioned out of flow:
// box 256 x 0, Playwright isVisible false, the dashboard fully drawn, the step FAILed "never appeared". The engine's
// isVisible({ timeout }) was also an instant check (Playwright ignores that timeout), so a slow page FAILed too.
// Cases, one line each ("ok <case>" or "FAIL <case>"):
//   old check on a 0-height data view   false (the fixture reproduces B2-2: a CATCH of the old check)
//   old check on a late guard            false (the instant check)
//   reached: 0-height data view, drawn   true
//   reached: late guard (1 s)            true
//   reached: guard display:none          false
//   reached: guard visibility:hidden     false
//   reached: 0-height wrapper, empty     false
//   reached: guard absent                false
//   old check on a hidden first match   false (PR-F39: a hidden snippet widget before the popup's shown one)
//   reached: hidden first, shown popup   true
//   reached: every match hidden          false
//   old check on a union, hidden Set URL first   false (T7: modelled on the field report, not captured live)
//   reached: union, hidden Set URL first          true
//   reached: union, Set URL only                  false
// Exit 0 when every case holds, 1 otherwise.
const { chromium } = require('playwright');
const V = require('../bin/journey-verbs.js');

const ZERO = `<div class="mx-page"><div class="mx-name-dataView1" style="position:relative;width:256px">
  <div style="position:absolute;top:0;left:0"><h2>Open work orders</h2><span>12</span></div></div></div>`;
const LATE = `<div class="mx-page"></div><script>setTimeout(() => { const d = document.createElement('div');
  d.className = 'mx-name-dataView1'; d.textContent = 'Open work orders'; document.querySelector('.mx-page').append(d); }, 1000);</script>`;
// T7, modelled on the field report (quality-inspection login journeys), not captured live: the generator's guard was
// ".mx-name-setURL1, .mx-name-dataView4"; the Set URL widget renders 0 x 0 and is the first DOM match, the data view
// (1208 x 481 in the field) is the second.
const SETURL = `<div class="mx-page"><div class="mx-name-setURL1" style="width:0;height:0"></div>
  <div class="mx-name-dataView4" style="width:300px;height:120px"><h2>Inspections</h2></div></div>`;
const SETURL_ONLY = `<div class="mx-page"><div class="mx-name-setURL1" style="width:0;height:0"></div></div>`;
const U = '.mx-name-setURL1, .mx-name-dataView4';
const NONE = `<div class="mx-page"><div class="mx-name-dataView1" style="display:none"><h2>Open work orders</h2></div></div>`;
const HIDDEN = `<div class="mx-page"><div class="mx-name-dataView1" style="visibility:hidden"><h2>Open work orders</h2></div></div>`;
const EMPTY = `<div class="mx-page"><div class="mx-name-dataView1" style="position:relative;width:256px">
  <div style="position:absolute;top:0;left:0"></div></div></div>`;
const ABSENT = `<div class="mx-page"><div class="mx-name-pageTitle1">Dashboard</div></div>`;
const DUP = `<div class="mx-page"><div class="mx-name-dataView1" style="display:none">Manage assignee(s)</div></div>
  <div class="modal-dialog"><div class="mx-name-dataView1">Select</div></div>`;
const DUPHID = `<div class="mx-page"><div class="mx-name-dataView1" style="display:none">Manage assignee(s)</div></div>
  <div class="modal-dialog"><div class="mx-name-dataView1" style="visibility:hidden">Select</div></div>`;
const G = '.mx-name-dataView1';

(async () => {
  let fail = 0;
  const check = (name, got, want) => { const ok = got === want; if (!ok) fail++; console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}: ${got}`); };
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const old = () => page.locator(G).first().isVisible({ timeout: 12000 }).catch(() => false);
  const neu = (ms = 3000) => V.reached(page, page.locator(G).first(), ms);
  await page.setContent(ZERO); check('old check on a 0-height data view', await old(), false);
  check('reached: 0-height data view, drawn', await neu(), true);
  await page.setContent(LATE); check('old check on a late guard', await old(), false);
  await page.setContent(LATE); check('reached: late guard (1 s)', await neu(), true);
  await page.setContent(NONE); check('reached: guard display:none', await neu(1000), false);
  await page.setContent(HIDDEN); check('reached: guard visibility:hidden', await neu(1000), false);
  await page.setContent(EMPTY); check('reached: 0-height wrapper, empty', await neu(1000), false);
  await page.setContent(ABSENT); check('reached: guard absent', await neu(1000), false);
  await page.setContent(DUP); check('old check on a hidden first match', await V.reached(page, page.locator(G).first(), 1000), false);
  const all = (ms) => V.reached(page, page.locator(G), ms);
  check('reached: hidden first, shown popup', await all(1000), true);
  await page.setContent(DUPHID); check('reached: every match hidden', await all(1000), false);
  await page.setContent(SETURL);
  check('old check on a union, hidden Set URL first', await page.locator(U).first().isVisible({ timeout: 1000 }).catch(() => false), false);
  check('reached: union, hidden Set URL first', await V.reached(page, page.locator(U), 1000), true);
  await page.setContent(SETURL_ONLY); check('reached: union, Set URL only', await V.reached(page, page.locator(U), 1000), false);
  await browser.close();
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log(`FAIL control crashed: ${e.message}`); process.exit(1); });
