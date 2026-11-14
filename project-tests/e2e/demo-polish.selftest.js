'use strict';
// demo-polish.selftest.js — proves the camera planner keeps its rules. No browser, no app, no ffmpeg.
//
//   node tests/e2e/demo-polish.selftest.js     # exit 0 = every rule held
//
// The planner turns the recorder's event log into zoom shots. Each check below is one camera rule
// from skills/demo-recording-polish.md; a rule that breaks here shows up as a zoom that frames the
// wrong area, holds over a page that has scrolled away, or ends a scene zoomed in.
const P = require(__dirname + '/demo-polish.js');

let bad = 0;
const ok = (name, cond, info) => { if (!cond) bad++; console.log(`${cond ? 'ok  ' : 'FAIL'} ${name}${cond ? '' : '  ' + JSON.stringify(info)}`); };
const V = {width: 1920, height: 1080}, T0 = 1e12;
const meta = (lenMs, cuts = []) => ({viewport: V, t0: T0, end: T0 + lenMs, cuts});
const card = {x: 760, y: 340, width: 400, height: 200};   // mid-frame: at the 1.4x cap the zoomed rect is wide, so a target near a side cannot be centred
const focus = (t, box = card) => ({t: T0 + t, kind: 'focus', bbox: box, zoom: box});
const scroll = (t, ms = 800) => ({t: T0 + t + ms, t0: T0 + t, t1: T0 + t + ms, kind: 'scroll', px: 400, bbox: card});

// 1. one note: lead, push-in, hold, zoom-out, capped zoom
{ const {shots: [s]} = P.shots(meta(20000), [focus(5000)]);
  ok('one note gives one shot', !!s, s);
  ok('push-in starts 400 ms before the note', s && s.a === 4600, s);
  ok('push-in lasts 500 ms', s && s.b - s.a === 500, s);
  ok('holds at least 2 s after the note', s && s.c >= 7000, s);
  ok('zoom-out lasts 600 ms', s && s.d - s.c === 600, s);
  ok('zoom never past 1.4x', s && s.z <= 1.4, s); }

// 2. notes closer than 2.5 s merge into one shot framing both
{ const b2 = {x: 500, y: 340, width: 400, height: 200};
  const {shots} = P.shots(meta(20000), [focus(5000), focus(6200, b2)]);
  ok('two notes 1.2 s apart merge', shots.length === 1, shots);
  ok('merged shot frames both regions', shots[0] && shots[0].rect.x <= b2.x && shots[0].rect.x + shots[0].rect.w >= card.x + card.width, shots[0]); }

// 3. a region that only earns < 1.15x gets no zoom, only a highlight
{ const wide = {x: 64, y: 400, width: 1792, height: 300};
  const r = P.shots(meta(20000), [focus(5000, wide)]);
  ok('full-width region is skipped, not zoomed', r.shots.length === 0 && r.skipped.length === 1 && r.skipped[0].highlightOnly === true, r); }

// 4. the camera is back at 1x before the next scroll starts
{ const {shots: [s]} = P.shots(meta(20000), [focus(5000), scroll(9000)]);
  ok('zoom-out ends by the next scroll', s && s.d <= 9000, s);
  const r = P.shots(meta(20000), [focus(5000), scroll(5900)]);
  ok('shot with no room to hold before a scroll is dropped', r.shots.length === 0 && /too soon/.test((r.skipped[0] || {}).why), r); }

// 5. every take ends zoomed out
{ const {shots: [s]} = P.shots(meta(7000), [focus(4000)]);
  ok('zoom-out finishes by the end of the take', s && s.d <= 7000, s);
  const r = P.shots(meta(5000), [focus(4600)]);
  ok('a note too close to the end is dropped', r.shots.length === 0, r); }

// 6. narration holds the shot until the line ends
{ const {shots: [s]} = P.shots(meta(30000), [focus(5000), {t: T0 + 5100, kind: 'hold', until: T0 + 12000}]);
  ok('hold extends to the end of the narration line', s && s.c >= 12000, s); }

{ const {shots: [s]} = P.shots(meta(30000), [{t: T0 + 4000, kind: 'hold', until: T0 + 14000}, focus(5000)]);
  ok('a line already playing when the shot starts holds it to the line end', s && s.c >= 14000, s); }

// 7. cuts: time after a cut shifts left, a note inside a cut is ignored
{ const m = meta(30000, [[T0 + 2000, T0 + 12000]]);
  const r = P.shots(m, [focus(1000 + 0), focus(5000), focus(15000)]);
  ok('note inside a cut ignored, later note shifted by the cut', r.shots.some(s => s.a === 15000 - 10000 - 400) && r.len === 20000, r); }

// 8. a kept bottom band: the framed region sits in the visible area above it
{ const low = {x: 760, y: 540, width: 400, height: 160};
  const {shots: [s]} = P.shots(meta(20000), [focus(5000, low)], {keepBottom: 120});
  const visBottom = s && s.rect.y + s.rect.h * (V.height - 120) / V.height;
  ok('zoomed region stays above the kept band', s && visBottom <= V.height - 120 + 0.01 && visBottom >= low.y + low.height, {s, visBottom}); }

// 10. framing: the element itself, centred, with ~8% padding on every side
{ const box = {x: 700, y: 400, width: 500, height: 200};
  const {shots: [s]} = P.shots(meta(20000), [focus(5000, box)]);
  const pad = Math.min(box.x - s.rect.x, s.rect.x + s.rect.w - box.x - box.width, box.y - s.rect.y, s.rect.y + s.rect.h - box.y - box.height);
  ok('framed element sits inside the rect with at least 8% padding', s && pad >= 0.08 * box.height - 0.01, {s, pad});
  ok('framed element is centred (u, v within 0.5 +- 0.2)', s && Math.abs(s.u - .5) <= .2 && Math.abs(s.v - .5) <= .2, s); }

// 11. a target hugging a frame edge cannot be centred, so it gets no zoom
{ const edge = {x: 1456, y: 327, width: 400, height: 170};
  const r = P.shots(meta(20000), [focus(5000, edge)]);
  ok('edge target is skipped, not zoomed off-centre', r.shots.length === 0 && /frame edge/.test((r.skipped[0] || {}).why), r); }

// 12. a target cut by the frame edge is clipped and never zoomed past zoomMin
{ const cut = {x: 660, y: 500, width: 600, height: 700};
  const {shots: [s]} = P.shots(meta(20000), [focus(5000, cut)]);
  ok('half-cut target zooms at most zoomMin', s && s.z <= P.KNOBS.zoomMin, s); }

// 13. new camera rule: full page by default, zoom is rare and small
{ ok('knobs: cap 1.4x, floor 1.15x, budget 2', P.KNOBS.zoomMax === 1.4 && P.KNOBS.zoomMin === 1.15 && P.KNOBS.maxZooms === 2, P.KNOBS);
  // a small card would earn ~3x at the old cap; it is held to 1.4x
  const small = {x: 800, y: 440, width: 320, height: 200};
  const {shots: [s]} = P.shots(meta(30000), [focus(5000, small)]);
  ok('a small target is capped at 1.4x', s && s.z === 1.4, s);
  // zoom:true click framing: the region around a click, never past 1.4x
  const [rw, rh] = P.KNOBS.clickRegion, click = {x: 960 - rw / 2, y: 540 - rh / 2, width: rw, height: rh};
  const c = P.shots(meta(30000), [focus(5000, click)]);
  ok('zoom:true click region frames at <= 1.4x and >= 1.15x', c.shots.length === 1 && c.shots[0].z <= 1.4 && c.shots[0].z >= 1.15, c);
  // budget: 4 well-separated zoomable notes give 2 zooms, the rest are skipped with the reason 'zoom budget'
  const four = [5000, 15000, 25000, 35000].map(t => focus(t));
  const b = P.shots(meta(50000), four);
  ok('budget: 4 notes give 2 zooms', b.shots.length === 2, b);
  ok('budget: the extra notes are listed as "zoom budget" and highlight-only', b.skipped.length === 2 && b.skipped.every(x => x.why === 'zoom budget' && x.highlightOnly), b.skipped);
  ok('budget: the first two notes win (time order)', b.shots[0].a < b.shots[1].a && b.shots[1].b < 16000, b.shots);
  // a note skipped for another reason does not use up the budget
  const wide = {x: 64, y: 400, width: 1792, height: 300};
  const w = P.shots(meta(50000), [focus(5000, wide), focus(15000), focus(25000), focus(35000)]);
  ok('a skipped wide note does not eat the budget', w.shots.length === 2 && w.skipped.filter(x => x.why === 'zoom budget').length === 1, w);
  // a zoom never opens a shot
  const o = P.shots(meta(20000), [focus(300)]);
  ok('a zoom at t=0.3 s is skipped ("zoom opens the shot"), not played', o.shots.length === 0 && /opens the shot/.test((o.skipped[0] || {}).why) && o.skipped[0].highlightOnly, o);
  const o2 = P.shots(meta(20000), [focus(P.KNOBS.openMs + P.KNOBS.leadMs + 100)]);
  ok('a zoom after the opening beat is allowed', o2.shots.length === 1, o2);
  // every shot of every take ends at 1x, whatever the notes
  const all = P.shots(meta(60000), [5000, 12000, 20000, 30000, 40000, 58000].map(t => focus(t)));
  ok('every take ends at 1x', all.shots.every(x => x.d <= all.len) && P.camera(all.shots, V, all.len).w === V.width, all);
  ok('never more than 2 zooms per take', all.shots.length <= 2, all); }

// 8b. every skipped note, whatever the reason, is highlight-only
{ const all = [P.shots(meta(60000), [5000, 12000, 20000, 30000, 40000, 58000].map(t => focus(t))), P.shots(meta(20000), [focus(300)]), P.shots(meta(20000), [{t: 5000, box: {x: 0, y: 0, w: V.width, h: V.height}}])];
  const sk = all.flatMap(r => r.skipped);
  ok('every skipped note carries highlightOnly: true', sk.length > 0 && sk.every(x => x.highlightOnly === true), sk); }

// 9. camera(): full frame outside shots, the shot rect while holding, eased in between
{ const {shots} = P.shots(meta(20000), [focus(5000)]), s = shots[0];
  const at = o => P.camera(shots, V, o);
  ok('1x before the shot', at(s.a - 1).w === V.width);
  ok('shot rect while holding', Math.abs(at((s.b + s.c) / 2).w - s.rect.w) < 1e-6);
  const mid = at((s.a + s.b) / 2).w; ok('halfway into the push-in is between 1x and the shot', mid < V.width && mid > s.rect.w, mid);
  ok('1x after the shot', at(s.d + 1).w === V.width); }

console.log(bad ? `\n${bad} check(s) failed` : '\nall camera rules held');
process.exit(bad ? 1 : 0);
