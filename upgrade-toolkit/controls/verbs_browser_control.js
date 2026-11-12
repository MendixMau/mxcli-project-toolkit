'use strict';
// verbs_browser_control.js: the row and tab verbs of bin/journey-verbs.js in a real browser (B4T2-16, B4T2-11).
//
//   node verbs_browser_control.js            (NODE_PATH must resolve playwright with its chromium)
//
// The markup follows Data grid 2 (data-widgets): the grid is a CSS grid, every <div class="tr" role="row"> is
// display: contents, so Playwright never sees a row as visible; cells are <div class="td" role="gridcell">, role
// "cell" in some versions; the header row holds role="columnheader" cells; an empty grid renders one gridcell holding
// .empty-placeholder. The tab markup follows the Mendix tab container: <li class="mx-name-tabPageN"> headers, the
// open one "active". No Mendix needed; page.setContent only.
// Cases, one line each ("ok <case>" or "FAIL <case>"); exit 0 when every case holds.
//   dg2 rows (display: contents)      PASS: a data cell of row 1 is clicked, never a header
//   dg2 rows load late (1.5 s)        PASS: the verb waits (B4T2-16: rows of an OData source came after the check)
//   dg2 cells with role="cell"        PASS
//   dg2 empty placeholder             CATCH: fixture-gap error (the placeholder cell is no row; clicking it passed)
//   rows render, unknown markup       CATCH: instrument-gap error, not "the list is empty"
//   tab opens a tab page              PASS: header active afterwards, the page content visible
//   tab never activates               CATCH: error, not a silent pass
//   item clicks the asked list item   PASS: item 3 of 3 clicked, not the list's middle (PR-F26)
//   item count differs from model     CATCH: error, never a neighbour clicked (an item with conditional visibility)
//   combo 2.10 hidden input           PASS: the input container opens the menu, "Marketing" commits (PR-F27; markup as
//                                     captured from Combo box 2.10 on the 11.12.5 Purchase Request: input 0 px wide)
//   combo menu never opens            CATCH: "never opened" instrument-gap error, not 'Options were: ' (empty)
//   menu named on the list            PASS: PopupMenu as captured (fixtures/popupmenu-captured.html: the name is on the
//                                     list that exists only while open, the trigger unnamed) opens, actionButton16 shows
//   menu behind a decoy menu          PASS: another menu's trigger comes first; its menu is closed again, ours opens
//   menu already open                 PASS: no click (a click would close it), "already open"
//   menu opens on hover               PASS: the hover opens it and no click follows (a click would toggle it shut)
//   menu named on the root            PASS: the F35 layout (name on the widget root, the list unnamed) still opens
//   menu never opens                  CATCH: error naming the menu, not a silent pass
//   near picks the own record         PASS: the Task Inbox item naming the walk's id (fixtures/inbox-captured.html, PR-F42)
//   near is no part of another id     CATCH: "42B" never matches "F42B"; the first item, as without near
//   near skips a longer id            PASS: "F42B" takes "F42B", not the earlier "F42BX"
//   near absent takes the first       PASS: the old choice
//   ack an information / warning box  PASS: OK clicked, the message returned, the button no longer covered
//                                     (fixtures/message-captured.html, PR-F42)
//   ack leaves an error box           CATCH: null, still covered (an error stays a finding)
//   ack with no box                   PASS: null, nothing clicked
//   dialog open (PR-P2)               PASS: the text of a warning box / popup page, also one that opens late; null for none or a hidden one
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');
const V = require(path.join(__dirname, '..', 'bin', 'journey-verbs.js'));
// PR-F27: Combo box 2.10 as captured on the 11.12.5 Purchase Request (Department): the <input role="combobox"> is 0 px
// wide; the Downshift toggle is the input container; options render as li[role=option] in the aria-controls list.
const COMBO = (opens) => `<style>.widget-combobox-input{width:0;padding:0;border:0}.widget-combobox-input-container{display:flex;
min-height:30px;border:1px solid}.widget-combobox-menu-hidden{visibility:hidden}</style>
<div class="mx-name-dropDown1 form-group"><label id="l">Department</label><div class="widget-combobox">
<div tabindex="-1" class="widget-combobox-input-container form-control" id="downshift-0-toggle-button"><div class="widget-combobox-selected-items">
<input class="widget-combobox-input" aria-activedescendant="" aria-controls="downshift-0-menu" aria-expanded="false" role="combobox" value="">
<div class="widget-combobox-placeholder-text"><span class="widget-combobox-caption-text"></span></div></div></div>
<div class="widget-combobox-menu widget-combobox-menu-hidden"><ul class="widget-combobox-menu-list" id="downshift-0-menu" role="listbox"></ul></div></div></div>
<script>(() => { const OPTS = ['Marketing', 'Sales', 'Finance']; const inp = document.querySelector('input'), menu = document.querySelector('.widget-combobox-menu'),
  ul = document.querySelector('ul'), cap = document.querySelector('.widget-combobox-caption-text'); let k = -1;
  document.getElementById('downshift-0-toggle-button').addEventListener('click', () => { if (!${opens}) return;
    ul.innerHTML = OPTS.map((t, i) => '<li role="option" id="o' + i + '">' + t + '</li>').join('');
    menu.classList.remove('widget-combobox-menu-hidden'); inp.setAttribute('aria-expanded', 'true'); inp.focus(); });
  document.addEventListener('keydown', e => { if (inp.getAttribute('aria-expanded') !== 'true') return;
    if (e.key === 'ArrowDown') { k = (k + 1) % OPTS.length; inp.setAttribute('aria-activedescendant', 'o' + k); }
    if (e.key === 'Enter' && k >= 0) { cap.textContent = OPTS[k]; ul.innerHTML = ''; menu.classList.add('widget-combobox-menu-hidden');
      inp.setAttribute('aria-expanded', 'false'); } }); })();</script>`;

const CSS = `<style>.table{display:grid;grid-template-columns:1fr 1fr}.tr{display:contents}.td,.th{padding:4px}
.mx-tabcontainer-pane{display:none}.mx-tabcontainer-pane.active{display:block}</style>`;
const header = `<div class="tr" role="row"><div class="th" role="columnheader">Code</div><div class="th" role="columnheader">Name</div></div>`;
const rowsHtml = (role) => [1, 2].map(i => `<div class="tr" role="row" onclick="document.body.dataset.clicked='row${i}'">` +
  `<div class="td" role="${role}">U${i}</div><div class="td" role="${role}">Unit ${i}</div></div>`).join('');
const grid = (inner) => `${CSS}<div class="mx-name-dataGrid21 widget-datagrid"><div class="table" role="grid">` +
  `<div class="table-content" role="rowgroup">${header}${inner}</div></div></div>`;
const EMPTY = `<div class="tr" role="row"><div class="td" role="gridcell" onclick="document.body.dataset.clicked='placeholder'">` +
  `<div class="empty-placeholder">No data</div></div></div>`;
const LATE = `<script>setTimeout(() => { document.querySelector('.table-content').insertAdjacentHTML('beforeend', ` +
  `${JSON.stringify(rowsHtml('gridcell'))}); }, 1500);</script>`;
const ODD = `${CSS}<div class="mx-name-dataGrid21"><div role="row" style="display:contents"><span style="display:contents">U1</span></div></div>`;
const TABS = (works) => `${CSS}<div class="mx-tabcontainer mx-name-tabContainer1"><ul class="mx-tabcontainer-tabs nav nav-tabs">` +
  `<li class="mx-name-tabPage1 active"><a href="#">Data</a></li><li class="mx-name-tabPage2"><a href="#">Logic</a></li></ul>` +
  `<div class="mx-tabcontainer-content"><div class="mx-tabcontainer-pane mx-name-tabPage1 active">one</div>` +
  `<div class="mx-tabcontainer-pane mx-name-tabPage2"><button class="mx-name-actionButton1">Go</button></div></div></div>` +
  (works ? `<script>document.querySelectorAll('li').forEach(li => li.addEventListener('click', e => { e.preventDefault();
    const n = [...li.classList].find(c => c.startsWith('mx-name-'));
    document.querySelectorAll('.active').forEach(x => x.classList.remove('active'));
    document.querySelectorAll('.' + n).forEach(x => x.classList.add('active')); }));</script>` : '');

// Mendix navigation list: <ul class="mx-navigationlist mx-name-..."> with <li class="mx-navigationlist-item"> items
const NAV = (n) => `<ul class="mx-navigationlist mx-name-navigationList2">` + [1, 2, 3].slice(0, n).map(i =>
  `<li class="mx-navigationlist-item" onclick="document.body.dataset.clicked='item${i}'">Step ${i}</li>`).join('') + '</ul>';

let fail = 0;
const line = (ok, name, detail) => { if (!ok) fail++; console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}: ${detail}`); };

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const rowCase = async (name, html, want) => {
    await page.setContent(html);
    try {
      const s = await V.row(page, { widget: 'dataGrid21', timeoutMs: 2500 });
      const clicked = await page.evaluate(() => document.body.dataset.clicked || '');
      line(want === 'row1' && clicked === 'row1', name, `returned ${s}, clicked ${clicked || 'nothing'}`);
    } catch (e) {
      line(want instanceof RegExp && want.test(e.message), name, `threw ${e.message.slice(0, 160)}`);
    }
  };
  await rowCase('dg2 rows (display: contents)', grid(rowsHtml('gridcell')), 'row1');
  await rowCase('dg2 rows load late (1.5 s)', grid('') + LATE, 'row1');
  await rowCase('dg2 cells with role="cell"', grid(rowsHtml('cell')), 'row1');
  await rowCase('dg2 empty placeholder', grid(EMPTY), /the list is empty, a fixture gap/);
  await rowCase('rows render, unknown markup', ODD, /row element\(s\) render .* an instrument gap/);
  // PR-P3: a Data grid 2 with onClickTrigger = double (Purchase Request Product_Overview): the row fires on a double click only
  const DBL = grid(rowsHtml('gridcell')).replace(/onclick="document.body.dataset.clicked='row(\d)'"/g,
    `ondblclick="document.body.dataset.clicked='row$1'"`);
  for (const [name, act, want] of [['dg2 double-click trigger: dblclick opens the row', { dblclick: true }, 'row1'],
    ['dg2 double-click trigger: a single click opens nothing', {}, '']]) {
    await page.setContent(DBL);
    await V.row(page, Object.assign({ widget: 'dataGrid21', timeoutMs: 2500 }, act));
    const clicked = await page.evaluate(() => document.body.dataset.clicked || '');
    line(clicked === want, name, `clicked ${clicked || 'nothing'}`);
  }
  for (const [name, works] of [['tab opens a tab page', true], ['tab never activates', false]]) {
    await page.setContent(TABS(works));
    try {
      await V.tab(page, { widget: 'tabPage2', settleMs: 50 });
      const vis = await page.locator('.mx-name-actionButton1').isVisible();
      line(works && vis, name, `active, actionButton1 visible ${vis}`);
    } catch (e) {
      line(!works && /not the active tab/.test(e.message), name, `threw ${e.message}`);
    }
  }
  for (const [name, n] of [['item clicks the asked list item', 3], ['item count differs from model', 2]]) {
    await page.setContent(NAV(n));
    try {
      const got = await V.item(page, { widget: 'navigationList2', nth: 2, of: 3 });
      const clicked = await page.evaluate(() => document.body.dataset.clicked || '');
      line(n === 3 && clicked === 'item3', name, `returned ${got}, clicked ${clicked || 'nothing'}`);
    } catch (e) {
      const clicked = await page.evaluate(() => document.body.dataset.clicked || '');
      line(n === 2 && /cannot be told apart/.test(e.message) && !clicked, name, `threw ${e.message}`);
    }
  }
  for (const [name, opens] of [['combo 2.10 hidden input', true], ['combo menu never opens', false]]) {
    await page.setContent(COMBO(opens));
    try {
      const got = await V.combo(page, { widget: 'dropDown1' }, 'Marketing');
      const shown = await page.evaluate(() => document.querySelector('.widget-combobox-caption-text').textContent);
      line(opens && got === 'Marketing' && shown === 'Marketing', name, `returned ${got}, shows ${shown}`);
    } catch (e) {
      line(!opens && /never opened/.test(e.message), name, `threw ${e.message}`);
    }
  }
  // PR-F40: the captured PopupMenu; a click on a trigger toggles the captured open list inside its root
  const CAP = fs.readFileSync(path.join(__dirname, 'fixtures', 'popupmenu-captured.html'), 'utf8');
  const MENU = (decoy, works, open, hover = false, rootNamed = false) => `${CAP}<div id="host"></div><script>(() => {
    const host = document.getElementById('host'), T = (id) => document.getElementById(id).innerHTML;
    if (${decoy}) host.insertAdjacentHTML('beforeend', T('closed').replace('Possible actions', 'Other'));
    host.insertAdjacentHTML('beforeend', T('closed'));
    const roots = host.querySelectorAll('.popupmenu'), mine = roots[roots.length - 1];
    const OPEN = ${rootNamed} ? T('open').replace(' mx-name-pop_upMenu5', '') : T('open');
    const toggle = (root, html) => { const o = root.querySelector('.widget-popupmenu-root');
      if (o) o.remove(); else root.insertAdjacentHTML('beforeend', html); };
    if (${decoy}) roots[0].querySelector('.popupmenu-trigger').addEventListener('click', () =>
      toggle(roots[0], T('open').replace(/pop_upMenu5/g, 'pop_upMenu9').replace(/actionButton1(\\d)/g, 'actionButton9$1')));
    if (${works}) mine.querySelector('.popupmenu-trigger').addEventListener('click', () => {
      document.body.dataset.clicks = (+document.body.dataset.clicks || 0) + 1; toggle(mine, OPEN); });
    if (${hover}) mine.querySelector('.popupmenu-trigger').addEventListener('mouseenter', () => {
      if (!mine.querySelector('.widget-popupmenu-root')) toggle(mine, OPEN); });
    if (${rootNamed}) mine.classList.add('mx-name-pop_upMenu5');
    if (${open}) toggle(mine, OPEN);
  })();</script>`;
  for (const [name, decoy, works, open, hover, rootNamed] of [['menu named on the list', false, true, false], ['menu behind a decoy menu', true, true, false],
    ['menu already open', false, true, true], ['menu never opens', false, false, false],
    ['menu opens on hover', false, true, false, true], ['menu named on the root', false, true, false, false, true]]) {
    await page.mouse.move(700, 590);   // off every trigger: the pointer left on one would hover-open the next page's menu
    await page.setContent(MENU(decoy, works, open, hover, rootNamed));
    try {
      const got = await V.menu(page, { widget: 'pop_upMenu5', settleMs: 50 });
      const vis = await page.locator('.mx-name-actionButton16').isVisible();
      const other = await page.locator('.mx-name-pop_upMenu9').count();
      const clicks = await page.evaluate(() => +document.body.dataset.clicks || 0);
      line(works && vis && !other && (open ? /already open/.test(got) && !clicks : /opened/.test(got)) && !(hover && clicks), name,
        `returned ${got}, actionButton16 visible ${vis}, decoy menu open ${other}, clicks ${clicks}`);
    } catch (e) {
      line(!works && /pop_upMenu5/.test(e.message), name, `threw ${e.message}`);
    }
  }
  // PR-C2 (Purchase Request run 3, P10): the menu step after an earlier one waits for the page to settle. The captured
  // PopupMenu; its item "Pause Workflow" (actionButton16) starts a re-render: the menu closes, a progress bar shows for
  // `busyMs` and the trigger ignores clicks meanwhile (a trigger replaced by the re-render is lost the same way); then
  // it opens again. busyMs 0 = the page never gets busy.
  const AGAIN = (busyMs, forever) => `${CAP}<div id="host"></div><div id="dom"></div><script>(() => {
    const host = document.getElementById('host'), T = (id) => document.getElementById(id).innerHTML;
    host.insertAdjacentHTML('beforeend', T('closed'));
    const mine = host.querySelector('.popupmenu');
    let busy = false;
    const shut = () => { const o = mine.querySelector('.widget-popupmenu-root'); if (o) o.remove(); };
    mine.querySelector('.popupmenu-trigger').addEventListener('click', () => {
      if (busy) return;
      document.body.dataset.opens = (+document.body.dataset.opens || 0) + 1;
      if (!mine.querySelector('.widget-popupmenu-root')) mine.insertAdjacentHTML('beforeend', T('open')); });
    mine.addEventListener('click', (e) => { if (!e.target.closest('.mx-name-actionButton16')) return;
      document.body.dataset.paused = '1'; shut();
      if (!${busyMs}) return;
      busy = true; document.body.insertAdjacentHTML('beforeend', '<div class="mx-progress">Loading</div>');
      const tick = setInterval(() => { document.getElementById('dom').insertAdjacentHTML('beforeend', '<i>.</i>'); }, 100);
      if (!${forever}) setTimeout(() => { clearInterval(tick); busy = false; document.querySelector('.mx-progress').remove(); }, ${busyMs}); });
  })();</script>`;
  for (const [name, busyMs, forever, want] of [['menu again after a re-render: waits for the page to settle', 1500, false, 'opens'],
    ['menu again, nothing re-renders: opens', 0, false, 'opens'],
    ['menu again, the page never settles: says so', 800, true, 'never settles']]) {
    await page.mouse.move(700, 590);
    await page.setContent(AGAIN(busyMs, forever));
    page.__menuAt = undefined;
    try {
      await V.menu(page, { widget: 'pop_upMenu5', settleMs: 50 });
      await page.locator('.mx-name-actionButton16').click();   // Pause
      const got = await V.menu(page, { widget: 'pop_upMenu5', settleMs: 50, settleTimeoutMs: forever ? 800 : 10000 });
      const opens = await page.evaluate(() => +document.body.dataset.opens || 0);
      line(want === 'opens' && opens === 2 && /opened/.test(got), name, `returned ${got}, trigger opened the menu ${opens} time(s)`);
    } catch (e) {
      line(want === 'never settles' && /none of the 1 pop-up menu trigger/.test(e.message) && /had not settled after the earlier menu step: .*still loading: mx-progress/.test(e.message), name,
        `threw ${e.message.slice(0, 220)}`);
    }
  }
  // PR-C3 (Purchase Request run 4, P10): "Pause Workflow" leaves a popup page "Confirmation: The changes are being applied
  // to the Workflow." with one Close button over the trigger; the next menu step closes such a notice first. A dialog with a
  // field, or with two buttons (a question), is not a notice and stays open: the step fails on it as before.
  const NOTICE = (inner) => `<style>.modal-dialog { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: #fff; z-index: 9 }</style>
    <div class="modal-dialog"><div class="modal-header"><button class="close">x</button><h4>Confirmation</h4></div>${inner}</div>
    <script>document.addEventListener('click', (e) => { const d = document.querySelector('.modal-dialog');
      if (e.target.closest('.modal-footer button:not(.close)') && d) { document.body.dataset.closed = '1'; if (!e.target.closest('.keep')) d.remove(); return; }
      if (d && e.target.closest('.popupmenu-trigger')) e.stopPropagation(); }, true);</script>`;
  for (const [name, inner, closes] of [
    ['menu with a notice open (one Close button): closes it first', '<div class="modal-body">The changes are being applied to the Workflow.</div><div class="modal-footer"><button>Close</button></div>', true],
    ['menu with a form dialog open (a field): leaves it', '<div class="modal-body"><textarea></textarea></div><div class="modal-footer"><button class="keep">Close</button></div>', false],
    ['menu with a question open (two buttons): leaves it', '<div class="modal-body">Abort the workflow?</div><div class="modal-footer"><button class="keep">Yes</button><button class="keep">No</button></div>', false]]) {
    await page.mouse.move(700, 590);
    await page.setContent(AGAIN(0, false) + NOTICE(inner));
    page.__menuAt = undefined;
    try {
      const got = await V.menu(page, { widget: 'pop_upMenu5', settleMs: 50 });
      line(closes && /closed a notice first: .*Confirmation.*applied to the Workflow/.test(got) && (await page.evaluate(() => document.body.dataset.closed)) === '1', name, `returned ${got}`);
    } catch (e) {
      line(!closes && /none of the 1 pop-up menu trigger/.test(e.message) && (await page.evaluate(() => document.body.dataset.closed)) !== '1', name, `threw ${e.message.slice(0, 120)}`);
    }
  }
  // PR-B6 (Purchase Request run 3, P04): a click right after a tab click takes the same-named widget inside that tab's
  // pane when 2+ are shown (the header's Back and the comment row's Add attachment are both actionButton7); one shown
  // match, a later click and another tab keep the old pick
  const PANES = (extra) => `${CSS}<div class="mx-name-container1"><button class="mx-name-actionButton7">Back</button></div>
    <div class="mx-tabcontainer mx-name-tabContainer1"><ul class="mx-tabcontainer-tabs nav nav-tabs" role="tablist">
    <li class="mx-name-tabPage1 active" role="tab"><a href="#">Details</a></li><li class="mx-name-tabPage2" role="tab"><a href="#">Comments</a></li></ul>
    <div class="mx-tabcontainer-content"><div class="mx-tabcontainer-pane mx-name-tabPage1 active" role="tabpanel"><button class="mx-name-actionButton2">Save</button></div>
    <div class="mx-tabcontainer-pane mx-name-tabPage2" role="tabpanel"><button class="mx-name-actionButton7">Add attachment</button>${extra}</div></div></div>
    <script>document.querySelectorAll('li').forEach(li => li.addEventListener('click', e => { e.preventDefault();
      const n = [...li.classList].find(c => c.startsWith('mx-name-'));
      document.querySelectorAll('.active').forEach(x => x.classList.remove('active'));
      document.querySelectorAll('.' + n).forEach(x => x.classList.add('active')); }));</script>`;
  const textOf = async (el) => (await el.innerText()).trim();
  await page.setContent(PANES(''));
  await (await V.topmost(page, 'tabPage2')).click();
  line(await textOf(await V.topmost(page, 'actionButton7')) === 'Add attachment', 'tab pane tiebreak: the button inside the clicked tab', 'picked Add attachment');
  line(await textOf(await V.topmost(page, 'actionButton7')) === 'Back', 'tab pane tiebreak is one shot: a later click keeps the old pick', 'picked Back');
  await page.setContent(PANES(''));
  await (await V.topmost(page, 'tabPage1')).click();
  line(await textOf(await V.topmost(page, 'actionButton7')) === 'Back', 'tab pane tiebreak: the duplicate is not in the clicked tab (catch)', 'picked Back, not the other tab\'s button');
  await page.setContent(PANES('').replace('<button class="mx-name-actionButton7">Back</button>', ''));
  await (await V.topmost(page, 'tabPage2')).click();
  line(await textOf(await V.topmost(page, 'actionButton7')) === 'Add attachment', 'tab pane tiebreak: one shown match is unchanged', 'picked the only Add attachment');
  // PR-C1 (Purchase Request run 4): a journey that must open an UNASSIGNED task takes the list item that states no
  // assignee. Golden: the Task Inbox "Open tasks" list as captured (fixtures/inbox-captured.html), item 2 made unassigned
  // as the page model says (Unassign button -> "Assign to me", actionButton8, Visible: $currentObject = empty); the
  // first item stays assigned. Without `unassigned` the first item is taken (the pre-run-4 pick).
  const INB = fs.readFileSync(path.join(__dirname, 'fixtures', 'inbox-captured.html'), 'utf8');
  const UNA = INB.replace(/<button type="button" class="btn mx-button mx-name-actionButton11([^>]*)> Unassign<\/button>/g,
    (m, rest, off) => off > INB.indexOf('index-1') ? `<button type="button" class="btn mx-button mx-name-actionButton8${rest}> Assign to me</button>` : m);
  const UNA2 = INB.replace(/<button type="button" class="btn mx-button mx-name-actionButton11([^>]*)> Unassign<\/button>/g,
    (m, rest) => `<button type="button" class="btn mx-button mx-name-actionButton8${rest}> Assign to me</button>`);
  const who = (el) => el.evaluate((n) => (n.closest('li').innerText.match(/Appr \w+/) || ['none'])[0]).catch(() => 'none');
  await page.setContent(UNA);
  line(UNA !== INB, 'unassigned fixture: item 2 differs from the capture', 'derived');
  line(await who(await V.topmost(page, 'container20', undefined, { has: 'Assign to me' })) === 'Appr F42B',
    'unassigned picks the item showing Assign to me, not the first', 'picked Appr F42B');
  line(await who(await V.topmost(page, 'container20')) === 'Appr F42A', 'unassigned absent takes the first (the old pick)', 'picked Appr F42A');
  line(await who(await V.topmost(page, 'container20', undefined, { has: 'Assign to me' })) !== 'Appr F42A',
    'unassigned is not the assigned first item (catch)', 'not Appr F42A');
  await page.setContent(INB);
  line(await who(await V.topmost(page, 'container20', undefined, { has: 'Assign to me' })) === 'Appr F42A',
    'unassigned with every item assigned keeps the first (the step guard says it)', 'picked Appr F42A');
  await page.setContent(UNA2);
  line(await who(await V.topmost(page, 'container20', undefined, { has: 'Assign to me' })) === 'Appr F42A',
    'unassigned with every item unassigned takes the first', 'picked Appr F42A');
  await page.setContent(INB.replace('<h4 class="mx-text mx-name-text14 spacing-outer-bottom-none">Appr F42B</h4>',
    '<h4 class="mx-text mx-name-text14 spacing-outer-bottom-none">Appr F42B</h4><p>Not assigned yet</p>'));
  line(await who(await V.topmost(page, 'container20', undefined, { has: 'Assign to me' })) === 'Appr F42B',
    'unassigned picks the item that states no assignee, also without the button', 'picked Appr F42B');
  // PR-F41: the captured comment box; a same-name field on a hidden tab page comes first in the DOM
  const TA = fs.readFileSync(path.join(__dirname, 'fixtures', 'textarea-captured.html'), 'utf8');
  const FILL = (hiddenFirst, shown, dialog) => `${TA}<div id="host"></div><script>(() => {
    const host = document.getElementById('host'), T = (id) => document.getElementById(id).innerHTML;
    if (${hiddenFirst}) host.insertAdjacentHTML('beforeend', '<div class="mx-tabcontainer-pane" style="display:none">' + T('hidden') + '</div>');
    if (${shown}) host.insertAdjacentHTML('beforeend', '<div class="mx-tabcontainer-pane active">' + T('shown') + '</div>');
    if (${dialog}) host.insertAdjacentHTML('beforeend', '<div class="modal-dialog">' + T('shown').replace('Leave a comment...', 'In the dialog') + '</div>');
  })();</script>`;
  for (const [name, hiddenFirst, shown, dialog] of [['fill behind a hidden tab field', true, true, false],
    ['fill in the dialog first', true, true, true], ['fill only a hidden field', true, false, false]]) {
    await page.setContent(FILL(hiddenFirst, shown, dialog));
    const el = await V.field(page, 'textArea1', 300);
    if (!el) { line(!shown, name, 'no shown match'); continue; }
    await el.fill('U-run-1');
    const got = await page.evaluate(() => [...document.querySelectorAll('textarea')].map(t => `${t.placeholder || 'reason'}=${t.value}`).join(' | '));
    line(shown && new RegExp(`${dialog ? 'In the dialog' : 'Leave a comment...'}=U-run-1`).test(got) && !/reason=U-run/.test(got), name, `filled ${got}`);
  }
  // PR-F42: the captured Task Inbox list (two parked requests); `near` takes the item that names the walk's own id
  const INBOX = fs.readFileSync(path.join(__dirname, 'fixtures', 'inbox-captured.html'), 'utf8');
  for (const [name, near, want, longer] of [['near picks the own record', 'F42B', 'Appr F42B', false],
    ['near is no part of another id', '42B', 'Appr F42A', false], ['near skips a longer id', 'F42B', 'Appr F42B', true],
    ['near absent takes the first', undefined, 'Appr F42A', false]]) {
    await page.setContent(longer ? INBOX.replace('>Appr F42A<', '>Appr F42BX<') : INBOX);
    const el = await V.topmost(page, 'actionButton7', near);
    const got = await el.evaluate((n) => (n.closest('li').innerText.match(/Appr \w+/) || ['none'])[0]).catch(() => 'none');
    line(got === want, name, `picked ${got}`);
  }
  const DBLN = () => grid([1, 2, 3].map(i => `<div class="tr" role="row" ondblclick="document.body.dataset.clicked='row${i}'">` +
    `<div class="td" role="gridcell">U${i}</div></div>`).join(''));
  // PR-P4: a.nth takes the n-th row (0-based): each destructive workflow journey opens its own workflow
  const ROW3 = grid([1, 2, 3].map(i => `<div class="tr" role="row" onclick="document.body.dataset.clicked='row${i}'">` +
    `<div class="td" role="gridcell">U${i}</div><div class="td" role="gridcell">Unit ${i}</div></div>`).join(''));
  await page.setContent(ROW3);
  const g3 = await V.row(page, { widget: 'dataGrid21', nth: 2, timeoutMs: 1500 });
  line((await page.evaluate(() => document.body.dataset.clicked)) === 'row3' && g3 === 'row 3', 'dg2 row nth: row 3 clicked', `returned ${g3}`);
  await page.setContent(DBLN());
  await V.row(page, { widget: 'dataGrid21', nth: 1, dblclick: true, timeoutMs: 1500 });
  line((await page.evaluate(() => document.body.dataset.clicked)) === 'row2', 'dg2 row nth with dblclick: row 2', 'double-clicked row 2 of 3');
  await page.setContent(grid(rowsHtml('gridcell')));
  try { await V.row(page, { widget: 'dataGrid21', nth: 2, timeoutMs: 800 }); line(false, 'dg2 row nth: row 3 of 2 shown', 'no error'); }
  catch (e) { line(/row 3 asked for, the list shows 2: .*a fixture gap/.test(e.message), 'dg2 row nth: row 3 of 2 shown: threw', e.message.slice(0, 140)); }
  // PR-F42: the captured message box over "Complete PO(s)": an information box gets its OK, an error box stays
  const MSG = fs.readFileSync(path.join(__dirname, 'fixtures', 'message-captured.html'), 'utf8');
  const BOX = (cls) => `<style>.mx-underlay { position: fixed; inset: 0 } .modal-dialog { position: fixed }</style>
    <button class="mx-name-actionButton5" style="position: absolute; top: 200px; left: 520px; width: 200px; height: 40px">Complete PO(s)</button>
    ${cls ? MSG.replace('mx-dialog-info', cls) : ''}<script>(() => { const ok = document.querySelector('.mx-dialog-footer button');
    if (ok) ok.onclick = () => { document.querySelector('.modal-dialog').remove(); document.querySelector('.mx-underlay').remove(); }; })();</script>`;
  for (const [name, cls, said] of [['ack an information box', 'mx-dialog-info', true], ['ack a warning box', 'mx-dialog-warning', true],
    ['ack leaves an error box', 'mx-dialog-error', false], ['ack with no box', '', false]]) {
    await page.setContent(BOX(cls));
    const btn = page.locator('.mx-name-actionButton5');
    const before = await V.cover(btn);
    const got = await V.ack(page);
    const after = await V.cover(btn);
    line(said ? got === 'The purchase orders have been created.' && before && !after : got === null && !!after === !!cls, name,
      `returned ${JSON.stringify(got)}, covered before ${before}, after ${after}`);
  }
  // PR-P2: a dialog still open after a task-outcome click: the captured box as a Warning ("Please complete the tasks
  // first than click on Received" on Purchase Request), one that opens late, a hidden one, none
  const WARN = (cls) => MSG.replace('mx-dialog-info', cls).replace('The purchase orders have been created.',
    'Please complete the tasks first than click on "Received" button.').replace('>Information<', '>Warning<');
  for (const [name, html, want] of [
    ['dialog open: a warning box', WARN('mx-dialog-warning'), /^Warning: Please complete the tasks first/],
    ['dialog open: a popup page', '<div class="modal-dialog mx-dialog"><div class="modal-body">Pick a vendor</div></div>', /Pick a vendor/],
    ['dialog open: none', '<div class="mx-name-actionButton5">Received</div>', null],
    ['dialog open: hidden', '<div class="modal-dialog mx-dialog" style="display:none"><div class="modal-body">Gone</div></div>', null],
    ['dialog open: one that opens late', '<div id="x"></div><script>setTimeout(() => { document.getElementById("x").innerHTML = ' +
      JSON.stringify(WARN('mx-dialog-warning')) + '; }, 600);</script>', /^Warning: Please complete/]]) {
    await page.setContent(html);
    const got = await V.openDialog(page, 1500);
    line(want === null ? got === null : want.test(String(got)), name, `returned ${JSON.stringify(got)}`);
  }
  await browser.close();
  process.exit(fail ? 1 : 0);
})().catch(e => { console.log(`FAIL setup: ${e.message}`); process.exit(1); });
