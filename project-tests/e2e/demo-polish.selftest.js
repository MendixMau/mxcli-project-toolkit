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
const card = {x: 100, y: 300, width: 500, height: 200};
const focus = (t, box = card) => ({t: T0 + t, kind: 'focus', bbox: box, zoom: box});
const scroll = (t, ms = 800) => ({t: T0 + t + ms, t0: T0 + t, t1: T0 + t + ms, kind: 'scroll', px: 400, bbox: card});

// 1. one note: lead, push-in, hold, zoom-out, capped zoom
{ const {shots: [s]} = P.shots(meta(20000), [focus(5000)]);
  ok('one note gives one shot', !!s, s);
  ok('push-in starts 400 ms before the note', s && s.a === 4600, s);
  ok('push-in lasts 700 ms', s && s.b - s.a === 700, s);
  ok('holds at least 2 s after the note', s && s.c >= 7000, s);
  ok('zoom-out lasts 800 ms', s && s.d - s.c === 800, s);
  ok('zoom never past 1.75x', s && s.z <= 1.75, s); }

// 2. notes closer than 2.5 s merge into one shot framing both
{ const b2 = {x: 700, y: 300, width: 400, height: 200};
  const {shots} = P.shots(meta(20000), [focus(5000), focus(6200, b2)]);
  ok('two notes 1.2 s apart merge', shots.length === 1, shots);
  ok('merged shot frames both regions', shots[0] && shots[0].rect.x <= card.x && shots[0].rect.x + shots[0].rect.w >= b2.x + b2.width, shots[0]); }

// 3. a region that only earns < 1.25x gets no zoom
{ const wide = {x: 64, y: 400, width: 1792, height: 300};
  const r = P.shots(meta(20000), [focus(5000, wide)]);
  ok('full-width region is skipped, not zoomed', r.shots.length === 0 && r.skipped.length === 1, r); }

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

// 7. cuts: time after a cut shifts left, a note inside a cut is ignored
{ const m = meta(30000, [[T0 + 2000, T0 + 12000]]);
  const r = P.shots(m, [focus(1000 + 0), focus(5000), focus(15000)]);
  ok('note inside a cut ignored, later note shifted by the cut', r.shots.some(s => s.a === 15000 - 10000 - 400) && r.len === 20000, r); }

// 8. a kept bottom band: the framed region sits in the visible area above it
{ const low = {x: 300, y: 800, width: 400, height: 120};
  const {shots: [s]} = P.shots(meta(20000), [focus(5000, low)], {keepBottom: 120});
  const visBottom = s && s.rect.y + s.rect.h * (V.height - 120) / V.height;
  ok('zoomed region stays above the kept band', s && visBottom <= V.height - 120 + 0.01 && visBottom >= low.y + low.height, {s, visBottom}); }

// 9. camera(): full frame outside shots, the shot rect while holding, eased in between
{ const {shots} = P.shots(meta(20000), [focus(5000)]), s = shots[0];
  const at = o => P.camera(shots, V, o);
  ok('1x before the shot', at(s.a - 1).w === V.width);
  ok('shot rect while holding', Math.abs(at((s.b + s.c) / 2).w - s.rect.w) < 1e-6);
  const mid = at((s.a + s.b) / 2).w; ok('halfway into the push-in is between 1x and the shot', mid < V.width && mid > s.rect.w, mid);
  ok('1x after the shot', at(s.d + 1).w === V.width); }

console.log(bad ? `\n${bad} check(s) failed` : '\nall camera rules held');
process.exit(bad ? 1 : 0);
