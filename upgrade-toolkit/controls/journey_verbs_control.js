// Control for E7-3 / E5b-21 / E6-8 / R38: the journey verbs added to the engine copy (bin/journey-verbs.js).
// Catch cases: a missing option, a switch that does not change, no dialog open, a popup button hidden behind a page
// button of the same name. Pass cases: the asked state is reached and read back. Fake Playwright page; exit 0 = pass.
const V = require('../bin/journey-verbs.js');
let fail = 0;
const check = (name, ok, detail) => { if (!ok) fail++; console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}: ${detail}`); };
const loc = (els) => ({
  els, count: async () => els.length, nth: i => one(els[i]), evaluateAll: async f => f(els.map(e => e.dom)), first: () => one(els[0]), last: () => one(els[els.length - 1]),
});
const empty = loc([]);
function one(e) {
  if (!e) return Object.assign(loc([]), { isVisible: async () => false, locator: () => empty, evaluate: async () => { throw new Error('none'); } });
  return Object.assign(loc([e]), {
    id: e.id, isVisible: async () => e.visible !== false, click: async () => { e.clicked = (e.clicked || 0) + 1; if (e.onClick) e.onClick(); },
    getAttribute: async n => (n === 'aria-checked' && 'checked' in e ? String(e.checked) : null),
    isChecked: async () => !!e.checked, textContent: async () => e.text || '',
    isDisabled: async () => !!e.disabled, innerText: async () => (typeof e.inner === 'function' ? e.inner() : e.inner || ''),
    scrollIntoViewIfNeeded: async () => {},
    locator: (sel, o) => (e.kids && e.kids[sel + (o && o.hasText ? ':' + o.hasText : '')]) || empty,
    evaluate: async f => f(e.dom || { tagName: e.tag || 'DIV' }),
    selectOption: async ({ index }) => { e.dom.selectedIndex = e.stuck ? e.dom.selectedIndex : index; },
    waitFor: async ({ state }) => { if (state === 'hidden' && e.visible !== false) throw new Error('timeout'); },
  });
}
const page = map => ({ locator: s => map[s] || empty, waitForTimeout: async () => {} });
const sel = (names, stuck) => ({ stuck, dom: { tagName: 'SELECT', selectedIndex: 0, options: names.map(t => ({ textContent: t })) } });
const dlgSel = n => `.modal-dialog .mx-name-${n}, .mx-dialog .mx-name-${n}, .mx-window .mx-name-${n}`;
const run = async (name, f, want) => {
  try { const r = await f(); check(name, want === 'throw' ? false : r === want, `returned ${JSON.stringify(r)}`); }
  catch (e) { check(name, want === 'throw' || (want instanceof RegExp && want.test(e.message)), `threw ${e.message}`); }
};
(async () => {
  // select: pass, exact and contains; catch: missing option, a select that does not take the choice
  const s1 = sel(['', 'Team A', 'Team B (old)']);
  const P1 = page({ '.mx-name-ref1': loc([{ kids: { select: loc([s1]) } }]) });
  await run('select exact option', () => V.select(P1, { widget: 'ref1' }, 'Team A'), 'Team A');
  await run('select contained option', () => V.select(P1, { widget: 'ref1' }, 'Team B'), 'Team B (old)');
  await run('select missing option catch', () => V.select(P1, { widget: 'ref1' }, 'Team C'), /no option matches "Team C". Options were: "", "Team A"/);
  const P1b = page({ '.mx-name-ref1': loc([{ kids: { select: loc([sel(['', 'Team A'], true)]) } }]) });
  await run('select not taken catch', () => V.select(P1b, { widget: 'ref1' }, 'Team A'), /"" is selected after choosing "Team A"/);
  // E2E-10: select first takes the first non-empty option whatever was passed; an empty list is a fixture gap
  await run('select first option', () => V.select(P1, { widget: 'ref1', first: true }, 'undefined'), 'Team A');
  const P1c = page({ '.mx-name-ref1': loc([{ kids: { select: loc([sel([''])]) } }]) });
  await run('select first on empty list catch', () => V.select(P1c, { widget: 'ref1', first: true }, 'undefined'), /no option to choose \(first asked\): the list is empty, a fixture gap/);
  // E2E-10: row clicks the first row of the list; no row is a fixture gap, never a pass
  const r1 = {};
  const P5 = page({ '.mx-name-grid1': loc([{ kids: { '.mx-listview-item': empty, '.mx-templategrid-item': empty, '.widget-gallery-item': empty, 'tbody tr': loc([r1]) } }]) });
  await run('row clicks the first grid row', async () => { const s = await V.row(P5, { widget: 'grid1' }); return `${s} ${r1.clicked}`; }, 'tbody tr 1');
  const P5b = page({ '.mx-name-grid1': loc([{ kids: {} }]) });
  await run('row on empty list catch', () => V.row(P5b, { widget: 'grid1' }), /no row to click in \.mx-name-grid1: the list is empty, a fixture gap/);
  await run('row on missing list catch', () => V.row(page({}), { widget: 'grid1' }), /\.mx-name-grid1 not visible/);
  // B4T2-16: a hidden first match no longer loses the selector; rows that render but match no selector are an
  // instrument gap, never reported as an empty list (fixture gap)
  const r2 = {};
  const P5c = page({ '.mx-name-grid1': loc([{ kids: { 'tbody tr': loc([{ visible: false }, r2]) } }]) });
  await run('row skips a hidden first row', async () => { const s = await V.row(P5c, { widget: 'grid1' }); return `${s} ${r2.clicked}`; }, 'tbody tr 1');
  const P5d = page({ '.mx-name-grid1': loc([{ kids: { [V.ANY_ROW]: loc([{}, {}]) } }]) });
  await run('row renders but no selector catch', () => V.row(P5d, { widget: 'grid1' }), /2 row element\(s\) render in \.mx-name-grid1 but none .*an instrument gap .*not a fixture gap/);
  // B4T2-11: tab opens the tab page and checks it became active
  const th = { cls: 'mx-name-tabPage2' }; th.onClick = () => { th.cls += ' active'; };
  const tabEl = e => Object.assign(one(e), { getAttribute: async n => (n === 'class' ? e.cls : null) });
  const tsel = '[role="tab"].mx-name-tabPage2, li.mx-name-tabPage2, .mx-name-tabPage2';
  const tl = els => Object.assign(loc(els), { nth: i => tabEl(els[i]) });
  await run('tab opens the tab page', () => V.tab(page({ [tsel]: tl([th]) }), { widget: 'tabPage2' }), 'tabPage2');
  await run('tab stays inactive catch', () => V.tab(page({ [tsel]: tl([{ cls: 'mx-name-tabPage2' }]) }), { widget: 'tabPage2' }), /tab header clicked but it is not the active tab/);
  await run('tab missing catch', () => V.tab(page({}), { widget: 'tabPage2' }), /no tab header \.mx-name-tabPage2 visible/);
  // toggle: pass sets and reads back; catch: a switch whose state does not change
  const sw = { checked: false }; sw.onClick = () => { sw.checked = !sw.checked; };
  const P2 = page({ '.mx-name-sw1': loc([{ kids: { '[role="switch"], input[type="checkbox"]': loc([sw]) } }]) });
  await run('toggle to true', () => V.toggle(P2, { widget: 'sw1' }, true), true);
  await run('toggle already true stays', () => V.toggle(P2, { widget: 'sw1' }, 'true'), true);
  await run('toggle flips without value', () => V.toggle(P2, { widget: 'sw1' }), false);
  const P2b = page({ '.mx-name-sw1': loc([{ kids: { '[role="switch"], input[type="checkbox"]': loc([{ checked: false }]) } }]) });
  await run('toggle stuck catch', () => V.toggle(P2b, { widget: 'sw1' }, true), /switch is false after the click, the journey asked for true/);
  // confirm: catch no dialog; pass clicks the primary button and the dialog closes
  await run('confirm without dialog catch', () => V.confirm(page({}), {}), /no dialog is open/);
  // D97: optional = the app raises the dialog only sometimes; no dialog is then not an error
  await run('confirm optional without dialog pass', () => V.confirm(page({}), { optional: true }), '(no dialog)');
  const d = { visible: true }; const ok = { text: 'Proceed', onClick: () => { d.visible = false; } };
  d.kids = { '.btn-primary': loc([ok]) };
  await run('confirm clicks primary', () => V.confirm(page({ [V.DIALOG]: loc([d]) }), {}), 'Proceed');
  const d2 = { visible: true }; d2.kids = { '.btn-primary': loc([{ text: 'Proceed' }]) };
  await run('confirm dialog stays open catch', () => V.confirm(page({ [V.DIALOG]: loc([d2]) }), {}), /still open after clicking "Proceed"/);
  // FN-13: a message box answers the confirm in a dialog at the same position: still visible, other text. A new
  // dialog is answered; an error dialog is not; the same dialog is still open
  const d3 = { visible: true, inner: 'Delete all?' }; d3.kids = { '.btn-primary': loc([{ text: 'Delete', onClick: () => { d3.inner = 'Information: Done!'; } }]) };
  await run('confirm answered by a new dialog', () => V.confirm(page({ [V.DIALOG]: loc([d3]) }), {}), 'Delete');
  const d4 = { visible: true, inner: 'Delete all?' }; d4.kids = { '.btn-primary': loc([{ text: 'Delete', onClick: () => { d4.inner = 'Error\nCould not delete'; } }]) };
  await run('confirm answered by an error dialog catch', () => V.confirm(page({ [V.DIALOG]: loc([d4]) }), {}), /answered by an error dialog: Error Could not delete/);
  const d5 = { visible: true, inner: 'Delete all?' }; d5.kids = { '.btn-primary': loc([{ text: 'Delete' }]) };
  await run('confirm same dialog stays open catch', () => V.confirm(page({ [V.DIALOG]: loc([d5]) }), {}), /still open after clicking "Delete"/);
  // FN-12: a read-only reference selector: holding the wanted (or any, when first is asked) value is complete; empty or other is said
  const ro = (names, i) => Object.assign(sel(names), { disabled: true, dom: { tagName: 'SELECT', selectedIndex: i, options: names.map(t => ({ textContent: t })) } });
  const PR = i => page({ '.mx-name-ref1': loc([{ kids: { select: loc([ro(['', 'Team A', 'Team B'], i)]) } }]) });
  await run('select read-only holding the wanted value', () => V.select(PR(1), { widget: 'ref1' }, 'Team A'), 'Team A');
  await run('select read-only holding a value, first asked', () => V.select(PR(2), { widget: 'ref1', first: true }, 'undefined'), 'Team B');
  await run('select read-only other value catch', () => V.select(PR(2), { widget: 'ref1' }, 'Team A'), /read-only on this page and shows "Team B"/);
  await run('select read-only empty catch', () => V.select(PR(0), { widget: 'ref1' }, 'Team A'), /read-only on this page and shows ""/);
  // FN-4: a Dropdown container (class dropdown, button.dropdown-toggle, class open) is opened by its toggle
  const ddRoot = (open, stuck) => {
    const cls = new Set(['dropdown', 'btn-group']); if (open) cls.add('open');
    const toggle = { onClick: () => { if (!stuck) cls.add('open'); } };
    return { dom: { classList: { contains: c => cls.has(c) } }, kids: { ':scope > .dropdown-toggle, :scope > .btn-group > .dropdown-toggle': loc([toggle]) }, toggle };
  };
  const dd1 = ddRoot(false);
  await run('menu opens a dropdown container', () => V.menu(page({ '.mx-name-kebab1': loc([dd1]) }), { widget: 'kebab1' }), 'kebab1 opened (dropdown container)');
  await run('menu dropdown container already open', () => V.menu(page({ '.mx-name-kebab1': loc([ddRoot(true)]) }), { widget: 'kebab1' }), 'kebab1 already open (dropdown container)');
  await run('menu dropdown container that stays closed catch', () => V.menu(page({ '.mx-name-kebab1': loc([ddRoot(false, true)]) }), { widget: 'kebab1' }), /toggle clicked but it did not open/);
  // topmost (E6-8): the popup's actionButton1 wins over the page's actionButton1 behind it
  const behind = { id: 'page' }, front = { id: 'popup' };
  const P3 = page({ '.mx-name-actionButton1': loc([behind, front]), [dlgSel('actionButton1')]: loc([front]) });
  await run('topmost picks the popup button', async () => (await V.topmost(P3, 'actionButton1')).id, 'popup');
  const P4 = page({ '.mx-name-actionButton1': loc([behind]) });
  await run('topmost without popup picks the page button', async () => (await V.topmost(P4, 'actionButton1')).id, 'page');
  // R38: the layout around the page can share a widget name with the page (Atlas top bar container2 vs the home
  // page's card container2); the page's own is the shown one nested in the most .mx-placeholder elements
  const node = (cls, parent, shown = true) => ({ classList: { contains: c => cls.includes(c) }, parentElement: parent, getClientRects: () => (shown ? [1] : []) });
  const root = node([], null), ph = node(['mx-placeholder'], root);
  const bar = { id: 'layout', dom: node(['mx-name-container2'], node(['region-topbar'], root)) };
  const card = { id: 'card', dom: node(['mx-name-container2'], node(['row'], ph)) };
  const PL1 = page({ '.mx-name-container2': loc([bar, card]) });
  await run('topmost picks the page widget over the layout one', async () => (await V.topmost(PL1, 'container2')).id, 'card');
  const hid = { id: 'card', dom: node(['mx-name-container2'], ph, false) };
  const PL2 = page({ '.mx-name-container2': loc([bar, hid]) });
  await run('topmost skips a hidden page widget', async () => (await V.topmost(PL2, 'container2')).id, 'layout');
  // PR-F27: a generated date is typed in the picker's placeholder pattern (11.12.5: "dd mmm yyyy"); else unchanged
  await run('dateAs follows the placeholder', async () => V.dateAs('dd mmm yyyy', '1/15/2027').value, '15 Jan 2027');
  await run('dateAs time after hours is minutes', async () => V.dateAs('dd-mm-yyyy hh:mm', '1/15/2027 12:00 PM').value, '15-01-2027 12:00');
  await run('dateAs leaves a text placeholder catch', async () => V.dateAs('Enter a date', '1/15/2027').value, '1/15/2027');
  await run('dateAs leaves a non-date value catch', async () => V.dateAs('dd mmm yyyy', 'U-1-2').value, 'U-1-2');
  process.exit(fail ? 1 : 0);
})();
