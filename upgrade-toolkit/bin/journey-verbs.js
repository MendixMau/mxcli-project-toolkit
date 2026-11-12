// journey-verbs.js: extra journey actions for the COPY of the shared journey engine (E5b-21, E7-3, E6-8).
// run_journeys.py copies journey-runner.js into <work>/engine, copies this file next to it and patches the copy so
// that act() knows these verbs. The shared toolkit is never edited; research/journey-runner-verbs.patch.md is the
// upstream proposal.
//
//   {"do": "toggle", "widget": "switch1", "value": true}      switch or checkbox inside .mx-name-<widget>; without
//                                                              "value" it flips. Alias: "switch". Reads the state back.
//   {"do": "select", "widget": "referenceSelector1", "match": "Team A"}
//                                                              native <select> (reference selector, enum drop-down)
//                                                              inside .mx-name-<widget> (or the select itself). Exact
//                                                              option text first, then the first option containing it;
//                                                              no option = error with the option list (never a guess).
//                                                              Alias: "reference", "dropdown". Reads the choice back.
//   {"do": "select", "widget": "referenceSelector1", "first": true}
//                                                              E2E-10 (generated journeys): the first non-empty option,
//                                                              whatever its text; no such option = error (an empty
//                                                              list is a fixture gap, never a pass).
//   {"do": "combo", "widget": "comboBox1", "first": true}      PR-F25: Combo box pluggable widget (Downshift):
//   {"do": "combo", "widget": "comboBox1", "match": "Sales"}    opens the menu of THIS widget (its input, not the
//                                                              page's first toggle), takes the first non-empty option
//                                                              (or the one asked), steps the highlight reading it each
//                                                              time and commits with Enter; the input must then show
//                                                              that text. No option = fixture gap error; a highlight
//                                                              that never reaches it or a value that did not commit =
//                                                              error (never a neighbour, see the engine's 2026-08-14
//                                                              note on its own 'combobox' verb, which needs "match").
//   {"do": "row", "widget": "grid1"}                            E2E-10: click the first row of the list, grid or
//                                                              gallery .mx-name-<widget> (selects it, or runs its row
//                                                              on-click). No row = error naming the fixture gap; rows
//                                                              that render but match no selector = instrument gap.
//                                                              Polls up to "timeoutMs" (8000) for late rows (B4T2-16).
//   {"do": "tab", "widget": "tabPage2"}                         B4T2-11: open a tab page and check it is active. Needs
//                                                              a "tab" case in run_journeys.py's act() patch.
//   {"do": "menuitem", "widget": "SettingsMenu", "nth": 0}      menu document item nth (0 based) of menu bar SettingsMenu:
//                                                              .mx-name-SettingsMenu-0. The generator uses it for the
//                                                              side bar and top bar items of a layout.
//   {"do": "menu", "widget": "pop_upMenu5"}                     PR-F35: open a Pop-up menu so its items render; no-op
//                                                              when open, error when it never opens.
//   {"do": "confirm", "optional": true}                       D97: no error when no dialog is open (the app raises it only sometimes)
//   {"do": "confirm"} or {"do": "confirm", "label": "Proceed"}
//                                                              the topmost open dialog: its primary button, or the
//                                                              button with that text; waits until the dialog closes.
// topmost(page, widget): the widget inside the topmost open popup when it is there, else the page's own. Widget
// names are unique per page, not per screen: a popup's actionButton1 and the page behind it can share a name (E6-8),
// and so can the layout around a page and the page itself (R38, Purchase Request 10.24: the Atlas top bar has
// container2..4, so the home page's cards container2..4 were never clicked and the smoke walk read "still on
// Admin_Homepage" for three working cards). The page's own is the shown match nested in the most layout placeholders
// (.mx-placeholder): a layout widget sits outside the placeholder its page renders into. pageWidget is that pick.
// Values keep every character, ':' included (E7-3: a URL value). Only {{var}} placeholders are substituted.
// reached(page, loc, ms): the landing guard check of every step (T8R B2-2). Waits up to ms for the guard (the engine's
// isVisible({timeout}) was an instant check: Playwright ignores that timeout). Reached = visible, or attached with
// visible content: a data view whose content is positioned out of flow has a 0-height box, Playwright calls it hidden
// and the fully drawn page FAILed "never appeared". Absent, display:none, visibility:hidden or no drawn descendant with
// text or an image: not reached. Any match counts, not the first (PR-F39, Purchase Request P02 leg 3: the vendor
// popup's visible "Select" is actionButton4, and the task page behind it holds a hidden actionButton4 of a workflow
// snippet earlier in the DOM; the guard checked only that one and every park walk of leg 3 FAILed "never appeared").

const SETTLE = require('./settle.js');

const DIALOG = '.modal-dialog, .mx-dialog, .mx-window';

async function lastVisible(loc) {
  const n = await loc.count().catch(() => 0);
  for (let i = n - 1; i >= 0; i--) {
    const el = loc.nth(i);
    if (await el.isVisible().catch(() => false)) return el;
  }
  return null;
}

function pageWidget(els) { // runs in the page: index of the shown element nested in the most placeholders, else 0
  let best = 0, depth = -1;
  els.forEach((e, i) => {
    if (!e.getClientRects().length) return;
    let d = 0;
    for (let a = e.parentElement; a; a = a.parentElement) if (a.classList.contains('mx-placeholder')) d++;
    if (d > depth) { best = i; depth = d; }
  });
  return best;
}

function ownRecord(els, near) { // runs in the page: index of the shown element whose list item names `near`, else -1
  const esc = near.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(^|[^A-Za-z0-9])${esc}($|[^A-Za-z0-9])`);
  return els.findIndex((e) => {
    if (!e.getClientRects().length) return false;
    const rec = e.closest('li, [role="row"], tr, .widget-gallery-item, .mx-templategrid-item');
    return !!rec && re.test(rec.innerText || '');
  });
}

// PR-F42: `near` (a process leg's ${RUN_ID}) picks the button in the list item that names this walk's own record. A
// leg after the first opened the FIRST task in the inbox: the oldest, an earlier walk's request stuck later in the
// process, and every park walk of Purchase Request P02 FAILed on that stranger's page (pipe-33). The token must stand
// alone ("1013051833" does not match "1013051833k000"); no match keeps the old choice.
async function topmost(page, widget, near, unassigned) {
  const inDialog = await lastVisible(page.locator(DIALOG.split(', ').map(d => `${d} .mx-name-${widget}`).join(', ')));
  if (inDialog) return inDialog;
  const all = page.locator(`.mx-name-${widget}`);
  if (near) {
    const i = await all.evaluateAll(ownRecord, String(near)).catch(() => -1);
    if (i >= 0) return all.nth(i);
  }
  // PR-C1 (Purchase Request run 4): a journey that opens a task to reach a button shown only for an UNASSIGNED task
  // ("Assign to me", Assignees = empty) took the first list item, an assigned one, and the button never rendered
  // (pr-baseline cluster 1: Task_*.actionButton19, TaskInbox.8/12). `unassigned` ({has: caption of that button}) picks
  // the shown item whose own list item states no assignee (UNASSIGNED_STATE: "Not assigned yet" on the Task Inbox
  // card), else the first whose item shows the button's caption; none: the old choice, and the step guard says so.
  if (unassigned) {
    const i = await all.evaluateAll(unassignedRecord, { state: UNASSIGNED_STATE.source, has: unassigned.has || null }).catch(() => -1);
    if (i >= 0) { if (!/^tabPage\d*$/.test(widget)) page.__lastTab = null; return all.nth(i); }
  }
  // PR-B6: a tab page (tabPageN) just clicked is remembered; when SEVERAL shown elements carry the name, the one inside
  // that tab's pane wins. Purchase Request Admin_Workflow_Instance_View: a snippet in the "Comments and attachments"
  // tab shares actionButton1 (Submit) and actionButton7 (Add attachment) with the page's Save and the header's Back;
  // the first shown match was Back, the click left the page and P04 FAILed on the healthy OLD app. One shown match:
  // nothing changes.
  if (/^tabPage\d*$/.test(widget)) page.__lastTab = widget;
  else if (page.__lastTab) {
    // one shot: only the click right after the tab click. A later same-named widget elsewhere (the Pause item of a
    // Pop-up menu vs a snippet's own actionButton16 in the tab) must keep the old pick (run 3 debug: P10 Pause)
    const t = page.__lastTab;
    page.__lastTab = null;
    const i = await all.evaluateAll(inTab, t).catch(() => -1);
    if (i >= 0) return all.nth(i);
  }
  return all.nth(await all.evaluateAll(pageWidget).catch(() => 0));
}

const UNASSIGNED_STATE = /(^|[^A-Za-z])(not assigned( yet)?|unassigned|no assignee|nobody|no one)($|[^A-Za-z])/i;

function unassignedRecord(els, o) { // runs in the page: index of the shown element whose list item states "no assignee", else -1
  const rec = (e) => e.closest('li, [role="row"], tr, .widget-gallery-item, .mx-templategrid-item');
  const first = (re) => els.findIndex((e) => {
    if (!e.getClientRects().length) return false;
    const r = rec(e);
    return !!r && re.test(r.innerText || '');
  });
  let i = first(new RegExp(o.state, 'i'));
  if (i < 0 && o.has) i = first(new RegExp('(^|[^A-Za-z0-9])' + o.has.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '($|[^A-Za-z0-9])', 'i'));
  return i;
}

function inTab(els, tab) { // runs in the page: index of the shown element inside tab's pane, when 2+ are shown, else -1
  const shown = els.filter((e) => e.getClientRects().length);
  if (shown.length < 2) return -1;
  const cls = (e) => (e.classList || { contains: () => false });
  return els.findIndex((e) => {
    if (!e.getClientRects().length) return false;
    for (let a = e.parentElement; a; a = a.parentElement) {
      if (cls(a).contains('mx-name-' + tab) && a.getAttribute('role') !== 'tab' && a.tagName !== 'LI') return true;
      if (a.getAttribute && a.getAttribute('role') === 'tabpanel') {
        const lb = a.getAttribute('aria-labelledby');
        const h = lb && document.getElementById(lb);
        if (h && (cls(h).contains('mx-name-' + tab) || (h.closest('.mx-name-' + tab)))) return true;
      }
    }
    return false;
  });
}

// PR-F42: a message box (a microflow's Show message, information or warning) is answered with OK by its user before the
// next click; no generated step does that, since no widget asks for it. "The purchase orders have been created."
// covered "Complete PO(s)" and P02 leg 3 FAILed on the healthy OLD app (pipe-33). An error box stays a finding.
// Markup as captured: controls/fixtures/message-captured.html. Returns the message text, or null when there is none.
async function ack(page) {
  const box = await lastVisible(page.locator('.mx-dialog-info, .mx-dialog-warning'));
  if (!box) return null;
  const ok = box.locator('.mx-dialog-footer button');
  if (!(await ok.first().isVisible().catch(() => false))) return null;
  const said = (await box.locator('.mx-dialog-body').innerText().catch(() => '')).trim();
  await ok.first().click();
  await page.waitForTimeout(300);
  return said || '(no text)';
}

// PR-P2: the text of a dialog still open after a step's click ("Warning: Please complete the tasks first than click on
// "Received" button."), or null when none is. A task outcome (Received, Approve, Complete) that answers with a message
// box did not complete the task; the guard `.mx-page` passed it because the page behind the box is still a page
// (Purchase Request: "Received" before the product line was completed, park "8/8 walked" was false). Polls up to ms for
// a box that opens after the microflow ran. Any of DIALOG counts: message boxes and popup pages.
async function openDialog(page, ms = 1500) {
  const end = Date.now() + ms;
  for (;;) {
    const box = await lastVisible(page.locator(DIALOG));
    if (box) {
      const cap = (await box.locator('.mx-dialog-caption, .modal-title, h4').first().innerText().catch(() => '')).trim();
      const body = (await box.locator('.mx-dialog-body, .modal-body').first().innerText().catch(() => '')).trim();
      return `${cap || 'dialog'}: ${body || '(no text)'}`.slice(0, 200);
    }
    if (Date.now() >= end) return null;
    await page.waitForTimeout(250);
  }
}

async function cover(el) { // the class of what a click on el's centre lands on instead of el, or null
  return el.evaluate((n) => {
    const r = n.getBoundingClientRect();
    const e = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
    if (!e || n.contains(e) || e.contains(n)) return null;
    const c = e.closest('[class]') || e;
    return String(c.className || c.tagName).trim().split(/\s+/).slice(0, 3).join('.');
  }).catch(() => null);
}

function contentShows(el) {
  for (let a = el; a; a = a.parentElement) {
    const s = getComputedStyle(a);
    if (s.display === 'none' || s.visibility === 'hidden') return false;
  }
  return [...el.querySelectorAll('*')].some((d) => {
    const r = d.getBoundingClientRect(), s = getComputedStyle(d);
    return r.width > 0 && r.height > 0 && s.visibility === 'visible'
      && (/^(IMG|SVG|CANVAS|INPUT|BUTTON|SELECT|TEXTAREA)$/i.test(d.tagName) || (d.innerText || '').trim() !== '');
  });
}

async function reached(page, loc, ms = 12000) {
  const end = Date.now() + ms;
  for (;;) {
    const n = await loc.count().catch(() => 0);
    for (let i = 0; i < n; i++) {
      const el = loc.nth(i);
      if (await el.isVisible().catch(() => false)) return true;
      if (await el.evaluate(contentShows).catch(() => false)) return true;
    }
    if (Date.now() >= end) return false;
    await page.waitForTimeout(250);
  }
}

async function visibleOrThrow(el, what) {
  if (!(await el.isVisible({ timeout: 6000 }).catch(() => false))) throw new Error(`${what} not visible`);
}

async function toggle(page, a, value) {
  const box = await topmost(page, a.widget);
  await visibleOrThrow(box, `.mx-name-${a.widget}`);
  const sw = box.locator('[role="switch"], input[type="checkbox"]').first();
  if (!(await sw.count().catch(() => 0))) throw new Error(`${a.widget}: no switch or checkbox inside .mx-name-${a.widget}`);
  const state = async () => {
    const ac = await sw.getAttribute('aria-checked').catch(() => null);
    if (ac === 'true' || ac === 'false') return ac === 'true';
    return sw.isChecked();
  };
  const want = value === undefined ? !(await state()) : value === true || String(value).toLowerCase() === 'true';
  if ((await state()) !== want) await sw.click({ force: true });
  await page.waitForTimeout(300);
  const got = await state();
  if (got !== want) throw new Error(`${a.widget}: switch is ${got} after the click, the journey asked for ${want}`);
  return got;
}

async function select(page, a, want) {
  const box = await topmost(page, a.widget);
  await visibleOrThrow(box, `.mx-name-${a.widget}`);
  let sel = box.locator('select').first();
  if (!(await sel.count().catch(() => 0))) {
    const tag = await box.evaluate(e => e.tagName).catch(() => '');
    if (String(tag).toUpperCase() !== 'SELECT') throw new Error(`${a.widget}: no <select> inside .mx-name-${a.widget} (a combobox widget needs "combobox")`);
    sel = box;
  }
  const texts = await sel.evaluate(s => [...s.options].map(o => o.textContent.trim()));
  if (await sel.isDisabled().catch(() => false)) {
    // FN-12: a reference selector the page renders read-only (editable only under a runtime
    // condition) cannot be chosen; selectOption waited 30 s and FAILed a healthy save. Already
    // holding a value: nothing to choose, the form is complete; empty: say so instead of timing out.
    const cur = await sel.evaluate(s => (s.options[s.selectedIndex] ? s.options[s.selectedIndex].textContent.trim() : ''));
    if (cur && (a.first || cur === want)) return cur;
    throw new Error(`${a.widget}: the drop-down is read-only on this page and shows "${cur}"`);
  }
  if (a.first) {   // E2E-10: the generator cannot know a reference's rows; any real one will do, none is a gap
    const i = texts.findIndex(t => t !== '');
    if (i === -1) throw new Error(`${a.widget}: no option to choose (first asked): the list is empty, a fixture gap`);
    want = texts[i];
  }
  let idx = texts.findIndex(t => t === want);
  if (idx === -1) idx = texts.findIndex(t => t.includes(want));
  if (idx === -1) {
    throw new Error(`${a.widget}: no option matches "${want}". Options were: ` +
      texts.slice(0, 8).map(t => `"${t}"`).join(', ') + (texts.length > 8 ? ` (+${texts.length - 8} more)` : ''));
  }
  await sel.selectOption({ index: idx });
  await page.waitForTimeout(300);
  const got = await sel.evaluate(s => (s.options[s.selectedIndex] ? s.options[s.selectedIndex].textContent.trim() : ''));
  if (got !== texts[idx]) throw new Error(`${a.widget}: "${got}" is selected after choosing "${texts[idx]}"`);
  return got;
}

async function combo(page, a, want) {
  const box = await topmost(page, a.widget);
  await visibleOrThrow(box, `.mx-name-${a.widget}`);
  const input = box.locator('input[role="combobox"], [role="combobox"]').first();
  if (!(await input.count().catch(() => 0))) throw new Error(`${a.widget}: no [role=combobox] inside .mx-name-${a.widget} (a native drop-down needs "select")`);
  await box.scrollIntoViewIfNeeded().catch(() => {});
  const listId = await input.getAttribute('aria-controls').catch(() => null) || await input.getAttribute('aria-owns').catch(() => null);
  const opts = listId ? page.locator(`[id="${listId}"] [role="option"]`) : page.locator('[role="option"]');
  // PR-F27, Purchase Request pipe-19: Combo box 2.10 (11.12.5) renders its <input> 0 px wide; the click failed silently
  // and the empty menu read as 'no option matches "Marketing". Options were: ' on all 15 wizard journeys. Click the
  // input when it shows, else the input container (the Downshift toggle); a menu that never opens is said as such.
  const toggle = box.locator('.widget-combobox-input-container, [id$="-toggle-button"]').first();
  let opened = false;
  for (let t = 0; t < 3 && !(opened = await opts.first().isVisible().catch(() => false)); t++) {
    if (await input.isVisible().catch(() => false)) await input.click().catch(() => {});
    else await toggle.click().catch(() => {});
    await opts.first().waitFor({ state: 'visible', timeout: 4000 }).catch(() => {});
  }
  const texts = (await opts.evaluateAll(e => e.map(x => x.textContent.trim())).catch(() => []));
  if (!opened && !texts.length && (await input.getAttribute('aria-expanded').catch(() => null)) !== 'true')
    throw new Error(`${a.widget}: the combo box menu never opened (input and input container clicked 3 times): an instrument gap`);
  if (a.first) {
    want = texts.find(t => t !== '');
    if (want === undefined) throw new Error(`${a.widget}: the combo box lists no option (first asked): the list is empty, a fixture gap`);
  }
  if (!texts.some(t => t.includes(want))) {
    throw new Error(`${a.widget}: no option matches "${want}". Options were: ` +
      texts.slice(0, 8).map(t => `"${t}"`).join(', ') + (texts.length > 8 ? ` (+${texts.length - 8} more)` : ''));
  }
  const active = async () => {
    const id = await input.getAttribute('aria-activedescendant').catch(() => null);
    return id ? String(await page.locator(`[id="${id}"]`).textContent().catch(() => '') || '').trim() : '';
  };
  let landed = false;
  for (let k = 0; k < texts.length + 2; k++) {
    if ((await active()).includes(want)) { landed = true; break; }
    await page.keyboard.press('ArrowDown');
    await page.waitForTimeout(120);
  }
  if (!landed) throw new Error(`${a.widget}: stepped the whole menu without the highlight reaching "${want}" (no aria-activedescendant on the option)`);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(500);
  const got = String(await input.inputValue().catch(() => '') || await input.textContent().catch(() => '') || '').trim()
    || String(await box.textContent().catch(() => '') || '').trim();
  if (!got.includes(want)) throw new Error(`${a.widget}: shows "${got.slice(0, 80)}" after selecting "${want}": the selection did not commit`);
  return want;
}

// E2E-10: rows of a classic data grid, template grid, list view, data grid 2 and gallery, first that has one.
// B4T2-16: Data grid 2 renders its rows as <div class="tr" role="row"> with display: contents (never "visible" to
// Playwright) and its cells as <div class="td" role="gridcell"> (role "cell" in some data-widgets versions); the
// header row holds role="columnheader" cells and an empty grid one gridcell with .empty-placeholder, which is no row
// (clicking it would pass a fixture gap). Only .first() was tried, so one hidden first match lost the whole selector.
const ROWS = ['.mx-listview-item', '.mx-templategrid-item', '.widget-gallery-item', 'tbody tr',
  '[role="row"]:not(:has([role="columnheader"])) [role="gridcell"]:not(:has(.empty-placeholder))',
  '[role="row"]:not(:has([role="columnheader"])) [role="cell"]:not(:has(.empty-placeholder))',
  '.widget-datagrid .td:not(:has(.empty-placeholder))',
  '[role="gridcell"]:not(:has(.empty-placeholder))'];
// what counts as a rendered row when no selector found a clickable one (instrument gap vs. empty list)
const ANY_ROW = '[role="row"]:not(:has([role="columnheader"])):not(:has(.empty-placeholder)), tbody tr, ' +
  '.mx-listview-item, .mx-templategrid-item, .widget-gallery-item';

async function firstVisible(loc, max = 20) {
  const n = Math.min(await loc.count().catch(() => 0), max);
  for (let i = 0; i < n; i++) {
    const el = loc.nth(i);
    if (await el.isVisible().catch(() => false)) return el;
  }
  return null;
}

// PR-F41: the field to type into is the first SHOWN match, the topmost dialog's first. A tab container keeps every tab
// page in the DOM: on Purchase Request's Admin_Workflow_Instance_View the hidden Details tab holds textArea1 ("Request
// reason") before the shown comment box textArea1 of the Comments tab; `fill` took .first(), found it hidden and FAILed
// "input not visible" (pipe-32), and every comment-list journey of the role went with it (no comment row was made).
const FIELD = (w) => `.mx-name-${w} input, .mx-name-${w} textarea, input.mx-name-${w}`;
async function field(page, widget, ms = 6000) {
  const end = Date.now() + ms;
  for (;;) {
    const d = await lastVisible(page.locator(DIALOG.split(', ').map(x => FIELD(widget).split(', ').map(f => `${x} ${f}`).join(', ')).join(', ')));
    const el = d || await firstVisible(page.locator(FIELD(widget)));
    if (el) return el;
    if (Date.now() >= end) return null;
    await page.waitForTimeout(250);
  }
}

// PR-F43: every shown match, for a fill that applies to each row of a list (a process step's row field, "rows": true):
// Purchase Request's PurchaseOrder_Edit holds one PromiseDate per PO in listView1 and Save refuses while any is empty.
// The topmost dialog's matches when a dialog shows one (the PO form is a popup), else the page's.
async function fields(page, widget) {
  const shown = async (loc) => {
    const out = [], n = await loc.count().catch(() => 0);
    for (let i = 0; i < n; i++) if (await loc.nth(i).isVisible().catch(() => false)) out.push(loc.nth(i));
    return out;
  };
  const dlgs = page.locator(DIALOG);
  for (let i = (await dlgs.count().catch(() => 0)) - 1; i >= 0; i--) {
    const d = dlgs.nth(i);
    if (!(await d.isVisible().catch(() => false))) continue;
    const got = await shown(d.locator(FIELD(widget)));
    if (got.length) return got;
    break;
  }
  return shown(page.locator(FIELD(widget)));
}

// PR-F44: a file input (Mendix File manager) gets a small generated file, never one read from disk: Purchase Request's
// workflow attachment views (WorkflowAttachment_View, the Comments and attachments tab) need an attachment, and the
// .jpeg name is what shows the preview button there (actionButton17: the name ends in "jpeg"). The input is hidden
// behind the widget's own button, so it is set, not clicked. Topmost dialog first (WorkflowAttachment_New is a popup).
const SEED_FILE = 'upg-seed.jpeg';
const SEED_JPEG = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA0JCgsKCA0LCgsODg0PEyAVExISEyccHhcgLikxMC4pLSwzOko+MzZGNywtQFdBRkxOUlNSMj5aYVpQYEpRUk//2wBDAQ4ODhMREyYVFSZPNS01T09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0//wAARCAAIAAgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDOooorzT6E/9k=';
async function upload(page, a, name) {
  const sel = `.mx-name-${a.widget} input[type=file], input[type=file].mx-name-${a.widget}`;
  let el = null;
  const dlgs = page.locator(DIALOG);
  for (let i = (await dlgs.count().catch(() => 0)) - 1; i >= 0 && !el; i--) {
    const d = dlgs.nth(i);
    if (!(await d.isVisible().catch(() => false))) continue;
    if (await d.locator(sel).count().catch(() => 0)) el = d.locator(sel).first();
    break;
  }
  if (!el && await page.locator(sel).count().catch(() => 0)) el = page.locator(sel).first();
  if (!el) throw new Error(`upload: no file input in .mx-name-${a.widget}`);
  const file = name || SEED_FILE;
  const jpeg = /\.jpe?g$/i.test(file);
  await el.setInputFiles({ name: file, mimeType: jpeg ? 'image/jpeg' : 'text/plain',
    buffer: jpeg ? Buffer.from(SEED_JPEG, 'base64') : Buffer.from(`upgrade toolkit seed file ${file}\n`) });
  return file;
}

// PR-P4 (pr-baseline 8): a.nth (0-based) takes that row instead of the first. Each destructive workflow journey (Abort,
// Pause, Restart ...) opens its own workflow: they ran alphabetically on the SAME first instance, so after Abort the
// others met an Aborted workflow with the menu hidden. A row that does not exist is a fixture gap, said with the count.
const ROW_BOXES = ['.mx-listview-item', '.mx-templategrid-item', '.widget-gallery-item', 'tbody tr',
  '[role="row"]:not(:has([role="columnheader"])):not(:has(.empty-placeholder))'];
async function nthRow(box, n, ms) {
  const tries = Math.max(1, Math.ceil((ms || 8000) / 250));
  let seen = 0;
  for (let t = 0; t < tries; t++) {
    for (const s of ROW_BOXES) {
      const loc = box.locator(s), vis = [];
      for (let i = 0, c = await loc.count().catch(() => 0); i < c && i < 50; i++)
        if (await loc.nth(i).isVisible().catch(() => false)) vis.push(loc.nth(i));
      if (vis.length > n) {
        const cell = vis[n].locator('[role="gridcell"], [role="cell"]').first();
        return (await cell.count().catch(() => 0)) ? cell : vis[n];
      }
      seen = Math.max(seen, vis.length);
    }
    if (seen > n) break;
    await box.page().waitForTimeout(250);
  }
  return { missing: seen };
}

async function row(page, a) {
  const box = await topmost(page, a.widget);
  await visibleOrThrow(box, `.mx-name-${a.widget}`);
  if (Number.isInteger(a.nth) && a.nth > 0) {
    const r = await nthRow(box, a.nth, a.timeoutMs);
    if (r.missing !== undefined)
      throw new Error(`${a.widget}: row ${a.nth + 1} asked for, the list shows ${r.missing}: the data the journey needs is not there (a fixture gap)`);
    if (a.dblclick) await r.dblclick(); else await r.click();
    await page.waitForTimeout(300);
    return `row ${a.nth + 1}`;
  }
  // B4T2-16: rows of a data source that loads after the grid (OData, microflow) come later: poll, bounded by
  // count so a page that never fills ends in the error below (default 8 s)
  const tries = Math.max(1, Math.ceil((a.timeoutMs || 8000) / 250));
  for (let t = 0; t < tries; t++) {
    for (const s of ROWS) {
      const r = await firstVisible(box.locator(s));
      if (r) {
        // PR-P3: a.dblclick = the grid's onClickTrigger is double (action_inventory "trigger"): a single click only focuses
        if (a.dblclick) await r.dblclick(); else await r.click();
        await page.waitForTimeout(300);
        return s;
      }
    }
    await page.waitForTimeout(250);
  }
  const rendered = await box.locator(ANY_ROW).count().catch(() => 0);
  if (rendered) {
    throw new Error(`${a.widget}: ${rendered} row element(s) render in .mx-name-${a.widget} but none is a visible ` +
      `row or cell for the row verb: an instrument gap (journey-verbs.js ROWS), not a fixture gap. Tried: ${ROWS.join(' | ')}`);
  }
  throw new Error(`${a.widget}: no row to click in .mx-name-${a.widget}: the list is empty, a fixture gap (the data the journey needs is not there)`);
}

// B4T2-11, B4N1-8: open the tab page .mx-name-<widget> (a tab control's page, named tabPageN in the model) and check
// it became the active one. Mendix renders the tab header <li class="mx-name-tabPage1"> in the tab list and marks
// the open one "active" (aria-selected="true" in newer clients). gen_journeys emits {"do": "click", "widget":
// "tabPage1"} today (the shape the B4N1 hand fix PASSed with); this verb adds the check once the runner dispatches it.
async function tab(page, a) {
  const sel = `[role="tab"].mx-name-${a.widget}, li.mx-name-${a.widget}, .mx-name-${a.widget}`;
  let hd = null;
  for (let t = 0; t < 32 && !hd; t++) {
    hd = await firstVisible(page.locator(sel));
    if (!hd) await page.waitForTimeout(250);
  }
  if (!hd) throw new Error(`${a.widget}: no tab header .mx-name-${a.widget} visible (the tab control is not on screen, or a tab hides it)`);
  const active = async () => {
    const cls = String(await hd.getAttribute('class').catch(() => '') || '');
    return /(^|\s)active(\s|$)/.test(cls) || (await hd.getAttribute('aria-selected').catch(() => null)) === 'true';
  };
  if (!(await active())) await hd.click();
  for (let t = 0; t < 12; t++) {
    if (await active()) { await page.waitForTimeout(a.settleMs || 300); return a.widget; }
    await page.waitForTimeout(250);
  }
  throw new Error(`${a.widget}: tab header clicked but it is not the active tab (no "active" class or aria-selected)`);
}

// PR-F35: open the Pop-up menu <widget> so its items render (Purchase Request pipe-30: the admin's workflow actions
// sit in "Possible actions" and all 7 FAILed "not visible" on the healthy OLD app).
// PR-F40: F35 assumed the name sits on the widget root; it does not. Captured from PopupMenu on the 10.24 Purchase
// Request (controls/fixtures/popupmenu-captured.html): <div class="popupmenu"> holds an UNNAMED .popupmenu-trigger and,
// only while open, .widget-popupmenu-root > ul.popupmenu-menu.mx-name-<widget>. Closed, nothing named <widget> exists,
// so F35 waited 8 s for a root that never renders and never clicked (pipe-32: the same 7 journeys failed again). Now:
// a shown .mx-name-<widget> that is the menu = already open; a named root (the layout F35 assumed) = click its trigger;
// else try each shown .popupmenu-trigger on the page until .mx-name-<widget> shows, closing a wrong menu it opened. No
// trigger opens it = error naming the menu.
// PR-C2 (Purchase Request run 3, P10): "Pause Workflow" passed and the next menu step, "Unpause Workflow", FAILed on the
// healthy OLD and NEW app: "none of the 1 pop-up menu trigger(s) on the page opened". The item's microflow re-renders the
// page (a progress bar, the menu rebuilt with the other item), and a trigger clicked meanwhile is lost. A menu step that
// follows an earlier one on the same page (within MENU_AGAIN_MS) first waits until the page has settled (settle.js:
// no loading indicator, DOM still); a page that does not settle in time is said in the error, not hidden.
const MENU_AGAIN_MS = 120000;
// PR-C3 (Purchase Request run 4, P10): "Pause Workflow" answers with a popup page "Confirmation: The changes are being applied
// to the Workflow." and one Close button; it stays open, covers the trigger, and "Unpause Workflow" FAILed "none of the 1
// pop-up menu trigger(s) opened" on the healthy old app (dialog count 1 in the failing DOM). A notice is a dialog with no
// input and exactly one button (Close or OK, not the header's x): its user closes it before the next step. A dialog with
// a field or two buttons is a form or a question and stays open (the step fails on it, as before).
async function closeNotice(page) {
  const box = await lastVisible(page.locator(DIALOG));
  if (!box) return null;
  if (await box.locator('input, textarea, select').count().catch(() => 1)) return null;
  const btns = box.locator('button:visible:not(.close)');
  if ((await btns.count().catch(() => 0)) !== 1) return null;
  if (!/^(close|ok)$/i.test((await btns.first().innerText().catch(() => '')).trim())) return null;
  const said = (await box.innerText().catch(() => '')).replace(/\s+/g, ' ').trim().slice(0, 120);
  await btns.first().click();
  await page.waitForTimeout(300);
  return said || '(no text)';
}

async function menu(page, a) {
  const notice = await closeNotice(page);
  let unsettled = '';
  if (page.__menuAt && Date.now() - page.__menuAt < MENU_AGAIN_MS) {
    const st = await SETTLE.settle(page, { timeout: a.settleTimeoutMs || 10000, stableMs: a.settleStableMs ?? 750 });
    if (!st.ok) unsettled = ` (the page had not settled after the earlier menu step: ${st.reason})`;
  }
  try {
    const got = await menuOpen(page, a);
    page.__menuAt = Date.now();
    return notice ? `${got} (closed a notice first: ${notice})` : got;
  } catch (e) {
    page.__menuAt = Date.now();
    e.message += unsettled;
    throw e;
  }
}

async function menuOpen(page, a) {
  const named = page.locator(`.mx-name-${a.widget}`);
  const isMenu = (el) => el.evaluate((e) => e.classList.contains('popupmenu-menu')).catch(() => false);
  const shown = async () => { const el = await firstVisible(named); return el && (await isMenu(el)) ? el : null; };
  const settle = () => page.waitForTimeout(a.settleMs || 300);
  const waitShown = async (ms) => {
    for (const end = Date.now() + ms; ;) {
      if (await shown()) return true;
      if (Date.now() >= end) return false;
      await page.waitForTimeout(100);
    }
  };
  let triggers = [];
  for (let t = 0; t < 32; t++) {
    if (await shown()) return `${a.widget} already open`;
    const root = await firstVisible(named);
    // FN-4: a Dropdown container (mendix.dropdowncontainer, kebab row menus): <div class="dropdown btn-group
    // mx-name-X"> with a button.dropdown-toggle; its content sits in div.dropdown-menu, hidden until the root has "open"
    const ddToggle = root ? root.locator(':scope > .dropdown-toggle, :scope > .btn-group > .dropdown-toggle').first() : null;
    if (root && (await root.evaluate((e) => e.classList.contains('dropdown')).catch(() => false))) {
      const isOpen = () => root.evaluate((e) => e.classList.contains('open')).catch(() => false);
      if (await isOpen()) return `${a.widget} already open (dropdown container)`;
      await root.scrollIntoViewIfNeeded({ timeout: 2000 }).catch(() => {});
      await ddToggle.click().catch(() => root.locator('.dropdown-toggle').first().click());
      for (let k = 0; k < 32; k++) {
        if (await isOpen()) { await settle(); return `${a.widget} opened (dropdown container)`; }
        await page.waitForTimeout(250);
      }
      throw new Error(`${a.widget}: dropdown container toggle clicked but it did not open`);
    }
    if (root) {   // the name on the widget root: its own trigger, and open = any shown menu (portalled, unnamed)
      const anyOpen = async () => !!(await firstVisible(page.locator('.popupmenu-menu')));
      if (await anyOpen()) return `${a.widget} already open`;
      let trig = root.locator('.popupmenu-trigger').first();
      if (!(await trig.isVisible().catch(() => false))) trig = root;
      await trig.scrollIntoViewIfNeeded({ timeout: 2000 }).catch(() => {});
      await trig.hover().catch(() => {});
      if (!(await anyOpen())) await trig.click();
      for (let k = 0; k < 32; k++) {
        if (await anyOpen()) { await settle(); return `${a.widget} opened`; }
        await page.waitForTimeout(250);
      }
      throw new Error(`${a.widget}: pop-up menu trigger clicked but no .popupmenu-menu opened`);
    }
    const all = page.locator('.popupmenu-trigger');
    const n = Math.min(await all.count().catch(() => 0), 20);
    for (let i = 0; i < n; i++) if (await all.nth(i).isVisible().catch(() => false)) triggers.push(all.nth(i));
    if (triggers.length) break;
    await page.waitForTimeout(250);
  }
  if (!triggers.length) throw new Error(`.mx-name-${a.widget} not on screen and no .popupmenu-trigger to open it (the pop-up menu is not on the page)`);
  for (let i = 0; i < triggers.length; i++) {
    const trig = triggers[i];
    await trig.scrollIntoViewIfNeeded({ timeout: 2000 }).catch(() => {});
    await trig.hover().catch(() => {});
    if (!(await waitShown(400))) await trig.click().catch(() => {});
    if (await waitShown(2000)) { await settle(); return `${a.widget} opened (trigger ${i + 1} of ${triggers.length})`; }
    // a different menu opened: close it so it does not cover the next trigger
    const own = trig.locator('xpath=..').locator('.popupmenu-menu');
    if (await firstVisible(own)) await trig.click().catch(() => {});
  }
  throw new Error(`${a.widget}: none of the ${triggers.length} pop-up menu trigger(s) on the page opened .mx-name-${a.widget}`);
}

// PR-F26: a navigation list item has no widget name; the model gives its position among the list's items. Purchase
// Request pipe-19: a click on the whole .mx-name-navigationList2 landed on its middle item ("Step 2") on the way to
// Step 3, the next page's guard matched a widget Step 2 also has, and the Submit click hit Step 2's Discard button.
// a.of is the model's item count: a list that renders another number (an item with conditional visibility) has no
// trustworthy position, so the step stops rather than click a neighbour.
async function item(page, a) {
  const list = await topmost(page, a.widget);
  if (!(await list.isVisible().catch(() => false))) throw new Error(`.mx-name-${a.widget} not visible`);
  let items = list.locator('.mx-navigationlist-item');
  if (!(await items.count().catch(() => 0))) items = list.locator(':scope > li, :scope > ul > li');
  const n = await items.count().catch(() => 0);
  if (a.of && n !== a.of)
    throw new Error(`${a.widget}: renders ${n} item(s), the model has ${a.of}: item ${a.nth + 1} cannot be told apart`);
  if (a.nth >= n) throw new Error(`${a.widget}: item ${a.nth + 1} of ${n} not rendered`);
  const el = items.nth(a.nth);
  await el.scrollIntoViewIfNeeded({ timeout: 2000 }).catch(() => {});
  await el.click();
  return `${a.widget} item ${a.nth + 1}/${n}`;
}

// Menu document item (a layout's side bar or top bar): the widget is the menu bar, nth the item's position in its menu
// document; the runtime renders it as <a class="mx-name-<bar>-<nth>">. Items without a caption (an icon only) have no
// title, so the position is the only handle. A caption in a.label is checked when the anchor shows one.
async function menuitem(page, a) {
  const el = await topmost(page, `${a.widget}-${a.nth}`);
  if (!(await el.isVisible().catch(() => false))) throw new Error(`.mx-name-${a.widget}-${a.nth} (menu item ${a.nth + 1} of ${a.widget}) not visible`);
  const text = String(await el.getAttribute('title').catch(() => '') || await el.textContent().catch(() => '') || '').trim();
  await el.scrollIntoViewIfNeeded({ timeout: 2000 }).catch(() => {});
  await el.click();
  return `${a.widget} menu item ${a.nth + 1}${text ? ' "' + text + '"' : ''}`;
}

async function confirm(page, a) {
  const dlg = await lastVisible(page.locator(DIALOG));
  if (!dlg) { if (a.optional) return '(no dialog)'; throw new Error('confirm: no dialog is open'); }   // D97: optional = answer a dialog the app may or may not raise
  const btn = a.label ? dlg.locator('button', { hasText: a.label }).first() : dlg.locator('.btn-primary').first();
  await visibleOrThrow(btn, a.label ? `dialog button "${a.label}"` : 'dialog primary button');
  const text = String(await btn.textContent().catch(() => '') || '').trim();
  const before = String(await dlg.innerText().catch(() => '') || '').trim();
  await btn.click();
  // FN-13: the flow can answer with a message box ("Information: Done!") in a dialog at the same
  // DOM position, so the nth-dialog locator stays visible and a healthy confirm FAILed "still open". The confirm is
  // done when its dialog is hidden or now shows another text; the step's own guards judge that message.
  for (let t = 0; t < 8000; t += 250) {
    if (!(await dlg.isVisible().catch(() => false))) return text;
    const now = String(await dlg.innerText().catch(() => '') || '').trim();
    if (now && now !== before && /(^|\n|× ?)\s*error\b/i.test(now.slice(0, 40)))
      throw new Error(`confirm: "${text}" answered by an error dialog: ${now.replace(/\s+/g, ' ').slice(0, 120)}`);
    if (now && now !== before) { console.log(`    confirm: "${text}" answered by a new dialog: ${now.replace(/\s+/g, ' ').slice(0, 80)}`); return text; }
    await page.waitForTimeout(250);
  }
  throw new Error(`confirm: the dialog is still open after clicking "${text}"`);
}

// PR-F27, Purchase Request pipe-19: 11.12.5 date pickers show their format as the placeholder ("dd mmm yyyy") and
// reject the generator's en_US "1/15/2027" (Invalid date) where 10.24 took it. A generated M/d/yyyy [h:mm AM] value is
// typed in the placeholder's pattern; any other value or placeholder stays as it is. {value, note}.
const MON = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
function dateAs(ph, v) {
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})(?: (\d{1,2}):(\d{2}) ?(AM|PM))?$/.exec(v || '');
  if (!m || !ph || !/^(?:[dmyhsa]+|[^A-Za-z]+)+$/i.test(ph) || !/y/i.test(ph) || !/d/i.test(ph)) return { value: v };
  const [, M, D, Y, h = '12', mi = '00', ap = 'PM'] = m;
  const p2 = x => String(x).padStart(2, '0');
  let hour = false, out = '';
  for (const t of ph.match(/([dmyhsa])\1*|[^dmyhsa]+/gi)) {
    const c = t[0].toLowerCase(), n = t.length;
    if (c === 'd') out += n > 1 ? p2(D) : String(+D);
    else if (c === 'y') out += n > 2 ? Y : Y.slice(-2);
    else if (c === 'h') { hour = true; out += n > 1 ? p2(h) : String(+h); }
    else if (c === 'm' && hour) out += p2(mi);
    else if (c === 'm') out += n >= 4 ? MON[M - 1] : n === 3 ? MON[M - 1].slice(0, 3) : n === 2 ? p2(M) : String(+M);
    else if (c === 's') out += '00';
    else if (c === 'a') out += ap;
    else out += t;
  }
  return { value: out, note: `date typed as "${ph}" (the picker's placeholder): ${out}` };
}

module.exports = { openDialog, dateAs, field, fields, upload, SEED_FILE, DIALOG, ROWS, ANY_ROW, topmost, ack, cover, pageWidget, toggle, select, combo, row, tab, item, menuitem, menu, confirm, reached };
