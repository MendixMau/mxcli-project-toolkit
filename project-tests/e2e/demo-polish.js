'use strict';
// demo-polish.js — polished demo capture for Playwright: smooth 60 fps, a visible cursor with a click ripple,
// eased scrolling, and a camera that zooms in on dense moments AFTER the take (Screen Studio style).
//
//   const polish = require('./demo-polish');
//   const ctx = await browser.newContext({viewport:{width:1920,height:1080}, deviceScaleFactor:2});
//   await polish.prepare(ctx);                       // cursor + ripple + scroll helpers, survive navigation
//   const page = await ctx.newPage(); ...log in, set up...
//   const rec = await polish.startCapture(page, {dir:'take/'});   // CDP screencast, timestamped JPEGs
//   await polish.scrollTo(page, locator);            // eased, on the real scroll container
//   await polish.click(page, locator, {zoom: cardLocator});        // glide, pause, ripple, click; camera note
//   await polish.focus(page, denseCard);             // camera note without a click
//   await polish.park(page, {near: nextTarget});     // rest the cursor beside the next target, off the content
//   await rec.stop();                                // writes frames.json + events.json
//   await polish.render('take/', 'take.mp4', {fps:60}); // composite: eased push-in/hold/zoom-out, sub-pixel
//   polish.assemble('take/', 'flat.mp4');            // same frames, no camera (fast, ffmpeg only)
//
// Why zoom afterwards: a CSS transform on the page breaks position:fixed bands, popups and hit-testing, and every
// retake costs a re-shoot. The recorder only logs {t, bbox, kind}; the camera is a pure function of the log, so
// re-framing is a re-render. Plain ffmpeg zoompan rounds the crop to whole pixels and judders; the compositor here
// draws each output frame on a canvas with a fractional source rectangle instead.
//
// Needs: playwright (chromium) and ffmpeg on PATH (or FFMPEG=/path). No other dependencies.
const fs = require('fs'), path = require('path'), {spawn, execFileSync} = require('child_process');
const FF = process.env.FFMPEG || 'ffmpeg';
const nap = ms => new Promise(r => setTimeout(r, ms));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const ease = t => t < .5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;   // easeInOutCubic
const rnd = (a, b) => a + Math.random() * (b - a);

// Knobs. Every number is a default a caller can override per call; the skill explains where each comes from.
const KNOBS = {
  cursorPx: 30,                 // arrow height at 1080p
  moveMs: [500, 900],           // per cursor move, scaled by distance
  preClickMs: [150, 250],       // settle on the target before pressing
  ripplePx: 60, rippleMs: 450,  // 0 -> 60 px, ease-out; opacity held near .9 to half-way, then 0
  rippleColor: 'rgba(17,24,39,.95)', rippleFill: 'rgba(17,24,39,.18)',  // dark ring, white halo (in the overlay)
  scrollMs: px => clamp(400 + 0.5 * px, 600, 1400),
  afterScrollMs: [400, 600],
  zoomMax: 1.75, zoomMin: 1.25, // never past 1.75; a region that only earns < 1.25 gets no zoom at all
  zoomPad: .08,                 // padding around the framed element, as a share of its size per side
  centreBand: .2,               // the target's centre must land within 0.5 +- this of the zoomed frame, or no zoom
  parkInsetPx: 32,              // between actions the cursor rests this far in from the side edge, never mid-content
  parkMs: 800, parkAfterMs: 450,
  leadMs: 400,                  // push-in starts this long before the click
  inMs: 700, holdMs: 2000, outMs: 800,
  mergeMs: 2500,                // camera notes closer than this share one shot
  clickRegion: [960, 540],      // zoom:true on a click frames at least this much around it (~1.7x), not the bare button
  minHoldMs: 800,               // a shot that cannot hold this long before the next scroll/move is dropped, not squeezed
};

// ---------------------------------------------------------------- in-page overlay (runs in the browser)
const OVERLAY = `(()=>{if(window.__dp)return;const K=${JSON.stringify({c: KNOBS.cursorPx, r: KNOBS.ripplePx, rm: KNOBS.rippleMs, rc: KNOBS.rippleColor, rf: KNOBS.rippleFill})};
 const ease=t=>t<.5?4*t*t*t:1-Math.pow(-2*t+2,3)/2;let cur=null,pos={x:-100,y:-100};
 const svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 30" width="'+(K.c*2/3)+'" height="'+K.c+'"><path d="M1.5 1.5v23.5l6-5.6 3.9 8.9 4.1-1.8-3.9-8.7 8.2-.4z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>';
 const ensure=()=>{if(cur&&cur.isConnected)return cur;cur=document.createElement('div');cur.id='__dp-cursor';cur.innerHTML=svg;
  cur.style.cssText='position:fixed;left:0;top:0;z-index:2147483647;pointer-events:none;filter:drop-shadow(0 2px 3px rgba(0,0,0,.35));will-change:transform';
  (document.body||document.documentElement).append(cur);place(pos.x,pos.y);return cur;};
 const place=(x,y)=>{pos={x,y};if(cur)cur.style.transform='translate('+(x-1.5*K.c/30)+'px,'+(y-1.5*K.c/30)+'px)';};
 const frame=()=>new Promise(r=>requestAnimationFrame(r));
 async function move(x,y,ms){ensure();const x0=pos.x,y0=pos.y,dx=x-x0,dy=y-y0,d=Math.hypot(dx,dy)||1;
  // one cubic Bezier with both handles bowed to the same side: a slight arc, never a ruler line
  const b=Math.min(80,d*.18)*(Math.random()<.5?-1:1),nx=-dy/d*b,ny=dx/d*b;
  const p1={x:x0+dx*.3+nx,y:y0+dy*.3+ny},p2={x:x0+dx*.7+nx*.6,y:y0+dy*.7+ny*.6};const t0=performance.now();
  for(;;){await frame();const u=Math.min(1,(performance.now()-t0)/ms),t=ease(u),m=1-t;
   place(m*m*m*x0+3*m*m*t*p1.x+3*m*t*t*p2.x+t*t*t*x,m*m*m*y0+3*m*m*t*p1.y+3*m*t*t*p2.y+t*t*t*y);if(u>=1)break;}}
 function ripple(x,y){const r=document.createElement('div');
  // dark ring + white halo: visible on light and dark UI, and never the same colour as a page's own highlight
  r.style.cssText='position:fixed;left:'+x+'px;top:'+y+'px;width:'+K.r+'px;height:'+K.r+'px;margin:-'+K.r/2+'px 0 0 -'+K.r/2+'px;border-radius:50%;border:4px solid '+K.rc+';box-shadow:0 0 0 3px rgba(255,255,255,.95),inset 0 0 0 2px rgba(255,255,255,.9);background:'+K.rf+';z-index:2147483646;pointer-events:none';
  document.body.append(r);r.animate([{transform:'scale(0.1)',opacity:.95},{transform:'scale(.7)',opacity:.85,offset:.5},{transform:'scale(1)',opacity:0}],{duration:K.rm,easing:'cubic-bezier(.22,.61,.36,1)',fill:'forwards'}).onfinish=()=>r.remove();}
 const scroller=el=>{for(let n=el.parentElement;n;n=n.parentElement){const s=getComputedStyle(n);if(/(auto|scroll)/.test(s.overflowY)&&n.scrollHeight>n.clientHeight+1)return n;}return document.scrollingElement;};
 // Eased scroll of the element's real scroll container; returns how far it went so the caller can time the wait.
 async function scroll(el,block,msFor){if(getComputedStyle(el).display==='contents'&&el.firstElementChild)el=el.firstElementChild;
  const sc=scroller(el),root=sc===document.scrollingElement,vr=root?{top:0,height:innerHeight}:sc.getBoundingClientRect();
  const r=el.getBoundingClientRect(),pad=Number(document.documentElement.dataset.dpBottomPad||0),vh=vr.height-(root?pad:0);
  let off=block==='start'?r.top-vr.top-24:r.top-vr.top-(vh-Math.min(r.height,vh))/2;
  const from=sc.scrollTop,to=Math.max(0,Math.min(sc.scrollHeight-sc.clientHeight,from+off)),px=Math.abs(to-from);if(px<2)return 0;
  const ms=msFor(px),t0=performance.now();for(;;){await frame();const u=Math.min(1,(performance.now()-t0)/ms);sc.scrollTop=from+(to-from)*ease(u);if(u>=1)break;}return px;}
 window.__dp={ensure,place,move,ripple,scroll,pos:()=>pos};
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',ensure);else ensure();})()`;

async function prepare(ctx) { await ctx.addInitScript(OVERLAY); }
// Page.startScreencast sends frames at the CSS viewport size, whatever the context's deviceScaleFactor. Only this
// launch flag makes it send device pixels (3840x2160 for a 1920x1080 viewport) — the headroom a zoom needs to stay sharp.
const launchArgs = (dsf = 2) => [`--force-device-scale-factor=${dsf}`];
const st = page => page.__dp || (page.__dp = {x: null, y: null, rec: null});
async function ready(page) {
  await page.evaluate(OVERLAY);
  const s = st(page);
  if (s.x == null) { const v = page.viewportSize(); s.x = KNOBS.parkInsetPx; s.y = v.height * .5; }   // rest at the side, not on content
  await page.evaluate(([x, y]) => { window.__dp.ensure(); window.__dp.place(x, y); }, [s.x, s.y]);
}
// Tell the scroller about a fixed band at the bottom (a caption strip) so "center" means the visible area.
async function bottomPad(page, px) { await page.evaluate(px => { document.documentElement.dataset.dpBottomPad = px; }, px); }

const boxOf = async loc => { const b = await loc.boundingBox(); return b && {x: b.x, y: b.y, width: b.width, height: b.height}; };
function note(page, kind, bbox, extra) {
  const r = st(page).rec; if (r && bbox) r.events.push({t: Date.now(), kind, bbox, ...extra});
}

async function moveTo(page, x, y, o = {}) {
  await ready(page); const s = st(page), d = Math.hypot(x - s.x, y - s.y);
  const [a, b] = o.moveMs || KNOBS.moveMs, ms = o.ms || clamp(a + d * .45, a, b);
  await page.evaluate(([x, y, ms]) => window.__dp.move(x, y, ms), [x, y, ms]);
  s.x = x; s.y = y; await page.mouse.move(x, y);   // the real pointer lands too, so hover states are true
}

// Park the cursor between actions: beside o.near (a Locator: just left of it, or right when it hugs the left edge),
// else in the nearest side gutter at the current height. Never left resting on the content the viewer is reading.
async function park(page, o = {}) {
  await ready(page); const s = st(page), V = page.viewportSize(), k = KNOBS.parkInsetPx;
  let x = s.x < V.width / 2 ? k : V.width - k, y = clamp(s.y, V.height * .12, V.height * .85);
  if (o.near) { const b = await boxOf(o.near.first ? o.near.first() : o.near).catch(() => null);
    if (b) { x = b.x > 3 * k ? b.x - k : b.x + b.width + k; y = clamp(b.y + b.height / 2, V.height * .12, V.height * .85); } }
  await moveTo(page, x, y, {ms: o.ms || KNOBS.parkMs});
}

async function scrollTo(page, loc, o = {}) {
  await ready(page); const t0 = Date.now();
  const px = await loc.evaluate((el, [b]) => window.__dp.scroll(el, b, px => Math.max(600, Math.min(1400, 400 + .5 * px))), [o.block || 'center']);
  if (px) { note(page, 'scroll', await boxOf(loc), {px, t0, t1: Date.now()}); await nap(rnd(...KNOBS.afterScrollMs)); }
  return px;
}

// zoom: true (frame the clicked element), a Locator (frame that region), or false/undefined (no camera note).
async function click(page, loc, o = {}) {
  await loc.waitFor({state: 'visible', timeout: o.timeout || 15000});
  await scrollTo(page, loc, o);
  const b = await boxOf(loc); if (!b) throw new Error('click target has no box');
  const x = b.x + b.width * clamp(o.fx ?? .5, .1, .9), y = b.y + b.height * clamp(o.fy ?? .5, .2, .8);
  const t0 = Date.now(); await moveTo(page, x, y, o);
  await nap(rnd(...KNOBS.preClickMs));
  const [rw, rh] = KNOBS.clickRegion, V = page.viewportSize(), tClick = Date.now();
  await page.evaluate(([x, y]) => window.__dp.ripple(x, y), [x, y]);
  await page.mouse.click(x, y);
  // A Locator zoom region is measured AFTER the click: it is often what the click reveals (a tab pane, a popup),
  // invisible before it. The note keeps the click's time, so the push-in still starts before the press.
  let zb = null;
  if (o.zoom === true) zb = {x: clamp(x - Math.max(rw, b.width) / 2, 0, V.width), y: clamp(y - Math.max(rh, b.height) / 2, 0, V.height), width: Math.max(rw, b.width), height: Math.max(rh, b.height)};
  else if (o.zoom) { const z = o.zoom.first ? o.zoom.first() : o.zoom;
    if (await z.waitFor({state: 'visible', timeout: o.zoomWait || 5000}).then(() => true, () => false)) { await nap(300); zb = await boxOf(z); } }
  const r = st(page).rec; if (r) r.events.push({t: tClick, kind: 'click', bbox: b, x, y, t0, zoom: zb || undefined});
  if (o.park !== false) { await nap(KNOBS.parkAfterMs); await park(page, {near: o.parkNear}); }
}

async function focus(page, loc, o = {}) {
  await scrollTo(page, loc, o); note(page, 'focus', await boxOf(loc), {zoom: await boxOf(loc), until: o.until});
}
// The narration line ends at t (epoch ms): hold the current shot at least until then.
function holdUntil(page, t) { const r = st(page).rec; if (r) r.events.push({t: Date.now(), kind: 'hold', until: t}); }

// ---------------------------------------------------------------- capture (CDP screencast)
function jpegSize(file) {  // width x height from the SOF marker; no image library needed
  const b = fs.readFileSync(file); for (let i = 2; i < b.length - 9;) { if (b[i] !== 0xFF) { i++; continue; } const m = b[i + 1];
    if (m >= 0xC0 && m <= 0xC3) return {width: b.readUInt16BE(i + 7), height: b.readUInt16BE(i + 5)}; i += 2 + b.readUInt16BE(i + 2); } return null;
}
async function startCapture(page, o = {}) {
  const dir = path.resolve(o.dir); fs.rmSync(dir, {recursive: true, force: true}); fs.mkdirSync(path.join(dir, 'frames'), {recursive: true});
  const v = page.viewportSize(), dsf = await page.evaluate(() => devicePixelRatio);
  const cdp = await page.context().newCDPSession(page);
  const frames = [], events = [], pending = [];
  let n = 0, skew = [];
  cdp.on('Page.screencastFrame', f => {
    const file = `f${String(n++).padStart(6, '0')}.jpg`, t = f.metadata.timestamp * 1000;
    skew.push(Date.now() - t);
    pending.push(fs.promises.writeFile(path.join(dir, 'frames', file), Buffer.from(f.data, 'base64')));
    frames.push({file, t});
    cdp.send('Page.screencastFrameAck', {sessionId: f.sessionId}).catch(() => {});
  });
  await ready(page);
  await cdp.send('Page.startScreencast', {format: 'jpeg', quality: o.quality || 88, maxWidth: Math.round(v.width * dsf), maxHeight: Math.round(v.height * dsf), everyNthFrame: 1});
  // The screencast only sends a frame when the compositor paints; nudge one so the take has a first frame.
  await page.evaluate(() => window.__dp.place(window.__dp.pos().x + .01, window.__dp.pos().y));
  const rec = {dir, events, frames, t0: Date.now(), cuts: [],
    begin() { rec.t0 = Date.now(); }, cut(a, b) { if (b > a) rec.cuts.push([a, b]); },
    async stop() {
      // hold the last picture until now, then close the stream
      await page.evaluate(() => window.__dp.place(window.__dp.pos().x, window.__dp.pos().y + .01)).catch(() => {});
      await nap(150); const end = Date.now();
      await cdp.send('Page.stopScreencast').catch(() => {}); await Promise.all(pending); await cdp.detach().catch(() => {});
      skew.sort((a, b) => a - b); const med = skew[skew.length >> 1] || 0;
      const meta = {viewport: v, dsf, frameSize: frames.length ? jpegSize(path.join(dir, 'frames', frames[0].file)) : null, t0: rec.t0, end, cuts: rec.cuts, frames: frames.length, clockSkewMs: med,
        captureFps: frames.length / Math.max(.001, (end - rec.t0) / 1000)};
      fs.writeFileSync(path.join(dir, 'frames.json'), JSON.stringify({meta, frames}, null, 0));
      fs.writeFileSync(path.join(dir, 'events.json'), JSON.stringify(events, null, 1));
      st(page).rec = null; return meta;
    }};
  st(page).rec = rec; return rec;
}

// ---------------------------------------------------------------- timeline helpers
function load(dir) {
  const {meta, frames} = JSON.parse(fs.readFileSync(path.join(dir, 'frames.json')));
  const events = JSON.parse(fs.readFileSync(path.join(dir, 'events.json')));
  return {meta, frames, events};
}
// Map wall-clock ms to output ms (cuts removed); null when inside a cut.
function mapper(meta) {
  const cuts = [...meta.cuts].sort((a, b) => a[0] - b[0]);
  const toOut = t => { let o = t - meta.t0; for (const [a, b] of cuts) { if (t >= b) o -= b - a; else if (t > a) return null; } return o; };
  const toWall = o => { let t = meta.t0 + o; for (const [a, b] of cuts) if (t >= a) t += b - a; return t; };
  const len = toOut(meta.end);
  return {toOut, toWall, len};
}

// Shots: one zoom per shot, notes closer than mergeMs merged, nothing overlaps, every take ends zoomed out.
function shots(meta, events, k = {}) {
  k = {...KNOBS, ...k}; const {toOut, len} = mapper(meta), V = meta.viewport, kb = k.keepBottom || 0, vis = (V.height - kb) / V.height;
  // with a kept bottom band only the area above it shows the zoomed picture, so frame inside that area
  const P = 1 + 2 * k.zoomPad, fit = b => Math.min(V.width / (b.width * P), (V.height - kb) / (b.height * P));
  // A target partly outside the frame is clipped to what is visible and never zoomed past zoomMin.
  const clip = b => { const x = Math.max(0, b.x), y = Math.max(0, b.y), r = Math.min(V.width, b.x + b.width), btm = Math.min(V.height - kb, b.y + b.height);
    return {x, y, width: Math.max(0, r - x), height: Math.max(0, btm - y), cut: r - x < b.width - 4 || btm - y < b.height - 4}; };
  const union = (a, b) => { const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y); return {x, y, width: Math.max(a.x + a.width, b.x + b.width) - x, height: Math.max(a.y + a.height, b.y + b.height) - y, cut: a.cut || b.cut}; };
  const notes = events.filter(e => e.zoom).map(e => ({t: toOut(e.t), box: clip(e.zoom), until: e.until && toOut(e.until)})).filter(e => e.t != null).sort((a, b) => a.t - b.t);
  // Boundaries: the camera must be back at 1x before the page scrolls or the cursor sets off for an unzoomed click,
  // or the hold frames a region the content has already left.
  const bounds = events.filter(e => (e.kind === 'scroll' && e.px > 40) || (e.kind === 'click' && !e.zoom)).map(e => ({t: toOut(e.t0 || e.t), end: toOut(e.t1 || e.t)})).filter(e => e.t != null).sort((a, b) => a.t - b.t);
  const holds = events.filter(e => e.kind === 'hold').map(e => ({t: toOut(e.t), until: toOut(e.until)})).filter(e => e.t != null && e.until != null);
  const out = [], skipped = [];
  for (const n of notes) {
    const last = out[out.length - 1];
    if (last && n.t - last.lastT < k.mergeMs && fit(union(last.box, n.box)) >= k.zoomMin) { last.box = union(last.box, n.box); last.lastT = n.t; if (n.until) last.until = Math.max(last.until || 0, n.until); continue; }
    if (fit(n.box) < k.zoomMin) { skipped.push({t: n.t, why: 'region too large to earn a zoom', fit: +fit(n.box).toFixed(2)}); continue; }
    out.push({firstT: n.t, lastT: n.t, box: n.box, until: n.until});
  }
  let prevEnd = 0; const res = [];
  for (const s of out) {
    const z = clamp(fit(s.box), k.zoomMin, s.box.cut ? k.zoomMin : k.zoomMax), cx = s.box.x + s.box.width / 2, cy = s.box.y + s.box.height / 2;
    const w = V.width / z, h = V.height / z, rect = {x: clamp(cx - w / 2, 0, V.width - w), y: clamp(cy - h * vis / 2, 0, V.height - kb - h * vis), w, h};
    // Centred or nothing: near a frame edge the camera rect clamps and the target slides off-centre. A lower zoom only
    // widens the rect and makes that worse, so a target that cannot sit near the middle is not zoomed at all.
    const u = (cx - rect.x) / w, v = (cy - rect.y) / (h * vis);
    if (Math.abs(u - .5) > k.centreBand || Math.abs(v - .5) > k.centreBand) { skipped.push({t: s.firstT, why: 'target at the frame edge: cannot be centred', u: +u.toFixed(2), v: +v.toFixed(2)}); continue; }
    const prevB = bounds.filter(x => x.end <= s.firstT).pop(), nextB = bounds.find(x => x.t > s.lastT);
    let a = Math.max(prevEnd, prevB ? prevB.end : 0, s.firstT - k.leadMs), b = a + k.inMs;
    let hold = Math.max(s.lastT + k.holdMs, b + k.holdMs, s.until || 0);
    // a narration line that is playing when the shot starts (or starts during it) keeps the shot until it ends
    for (const h of holds) if (h.t <= hold && h.until >= s.firstT) hold = Math.max(hold, h.until);
    const limit = Math.min(len, nextB ? nextB.t : len);
    let c = hold, d = c + k.outMs;
    if (d > limit) { d = limit; c = d - k.outMs; }
    if (c - b < k.minHoldMs) { skipped.push({t: s.firstT, why: nextB && nextB.t < len ? 'next scroll or move comes too soon to hold' : 'no room to zoom out before the end', holdMs: Math.round(c - b)}); continue; }
    res.push({z: +z.toFixed(3), rect, a, b, c, d, u: +u.toFixed(2), v: +v.toFixed(2)}); prevEnd = d;
  }
  return {shots: res, skipped, len};
}
// Camera rect (CSS px) at output time o.
function camera(shotList, V, o) {
  const full = {x: 0, y: 0, w: V.width, h: V.height};
  for (const s of shotList) {
    if (o < s.a || o > s.d) continue;
    const u = o < s.b ? ease((o - s.a) / (s.b - s.a)) : o <= s.c ? 1 : 1 - ease((o - s.c) / (s.d - s.c));
    return {x: full.x + (s.rect.x - full.x) * u, y: full.y + (s.rect.y - full.y) * u, w: full.w + (s.rect.w - full.w) * u, h: full.h + (s.rect.h - full.h) * u};
  }
  return full;
}

// ---------------------------------------------------------------- output
const ENC = (crf = 18) => ['-c:v', 'libx264', '-crf', String(crf), '-preset', 'slow', '-pix_fmt', 'yuv420p',
  '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv', '-movflags', '+faststart'];

// No camera: ffmpeg concat with per-frame durations, resampled to a constant fps.
function assemble(dir, out, o = {}) {
  const {meta, frames} = load(dir), {toOut, len} = mapper(meta), fps = o.fps || 60, W = o.width || meta.viewport.width;
  const kept = frames.map(f => ({...f, o: toOut(f.t)})).filter(f => f.o != null);
  // the picture on screen at t0 is the last frame before it
  const before = frames.filter(f => f.t <= meta.t0).pop(); if (before && !kept.some(f => f.o <= 0)) kept.unshift({...before, o: 0});
  const lines = [];
  kept.forEach((f, i) => { const nx = i + 1 < kept.length ? kept[i + 1].o : len, d = Math.max(0, nx - Math.max(0, f.o)) / 1000; if (d > 0) lines.push(`file 'frames/${f.file}'`, `duration ${d.toFixed(4)}`); });
  lines.push(lines[lines.length - 2]);  // concat demuxer drops the last duration otherwise
  const list = path.join(dir, 'concat.txt'); fs.writeFileSync(list, lines.join('\n') + '\n');
  execFileSync(FF, ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', list, '-vf', `fps=${fps},scale=${W}:-2:flags=lanczos`, '-t', (len / 1000).toFixed(3), ...ENC(o.crf), out]);
  return out;
}

const COMPOSE_HTML = `<!doctype html><html><body style="margin:0;background:#000"><canvas id="c"></canvas><script>
const c=document.getElementById('c'),g=c.getContext('2d');let img=null,src='',VW=1;
window.setup=(w,h,vw)=>{c.width=w;c.height=h;VW=vw;g.imageSmoothingEnabled=true;g.imageSmoothingQuality='high';};
// x,y,w,h: camera rect in CSS px; keep: CSS px of a fixed bottom band drawn unzoomed. Source scale = real image width.
window.draw=async(file,x,y,w,h,keep)=>{if(file!==src){const i=new Image();i.src='frames/'+file;await i.decode();img=i;src=file;}
 const W=c.width,H=c.height,s=img.naturalWidth/VW;g.drawImage(img,x*s,y*s,w*s,h*s,0,0,W,H);
 if(keep>0){const k=keep*s,ko=keep*W/VW;g.drawImage(img,0,img.naturalHeight-k,img.naturalWidth,k,0,H-ko,W,ko);}
 return c.toDataURL('image/jpeg',.95).slice(23);};
</script></body></html>`;

// Camera render: each output frame drawn on a canvas from a fractional source rect (sub-pixel), piped to x264.
// o.keepBottom: CSS px of a fixed bottom band (caption strip) composited unzoomed on top of the zoomed picture.
async function render(dir, out, o = {}) {
  const {chromium} = require('playwright');
  dir = path.resolve(dir); const {meta, frames, events} = load(dir), {toOut, len} = mapper(meta), V = meta.viewport, fps = o.fps || 60;
  const plan = shots(meta, events, {...o.knobs, keepBottom: o.keepBottom || 0}); fs.writeFileSync(path.join(dir, 'shots.json'), JSON.stringify(plan, null, 1));
  const W = o.width || V.width, H = Math.round(W * V.height / V.width / 2) * 2, keep = o.keepBottom || 0;
  const kept = frames.map(f => ({...f, o: toOut(f.t)})).filter(f => f.o != null);
  const before = frames.filter(f => f.t <= meta.t0).pop(); if (before && !kept.some(f => f.o <= 0)) kept.unshift({...before, o: 0});
  // Served from a fake http origin: file:// images taint the canvas and toDataURL refuses to export it.
  const browser = await chromium.launch(), page = await browser.newPage();
  await page.route('http://dp.local/**', r => { const u = new URL(r.request().url()).pathname;
    if (u === '/') return r.fulfill({contentType: 'text/html', body: COMPOSE_HTML});
    r.fulfill({path: path.join(dir, 'frames', path.basename(u))}); });
  await page.goto('http://dp.local/'); await page.evaluate(([w, h, vw]) => setup(w, h, vw), [W, H, V.width]);
  const ff = spawn(FF, ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-', ...ENC(o.crf), out], {stdio: ['pipe', 'inherit', 'inherit']});
  const done = new Promise((res, rej) => ff.on('close', c => c ? rej(new Error('ffmpeg exit ' + c)) : res()));
  const N = Math.round(len / 1000 * fps); let j = 0, last = null, lastKey = '';
  const t0 = Date.now();
  try {
    for (let i = 0; i < N; i++) {
      const ot = i * 1000 / fps; while (j + 1 < kept.length && kept[j + 1].o <= ot) j++;
      const cam = camera(plan.shots, V, ot), r = [cam.x, cam.y, cam.w, cam.h].map(v => +v.toFixed(3));
      const key = kept[j].file + r.join(',');
      if (key !== lastKey) { last = Buffer.from(await page.evaluate(a => draw(...a), [kept[j].file, ...r, cam.w < V.width - .01 ? keep : 0]), 'base64'); lastKey = key; }
      if (!ff.stdin.write(last)) await new Promise(r => ff.stdin.once('drain', r));
    }
  } finally { ff.stdin.end(); await browser.close(); }
  await done;
  return {out, frames: N, shots: plan.shots.length, skipped: plan.skipped, renderSec: (Date.now() - t0) / 1000, captureFps: +meta.captureFps.toFixed(1)};
}

// Unique-picture rate of the source: how much real motion the 60 fps container carries.
function sourceStats(dir) {
  const {meta, frames} = load(dir), {toOut} = mapper(meta), ts = frames.map(f => toOut(f.t)).filter(v => v != null);
  const gaps = ts.slice(1).map((v, i) => v - ts[i]).filter(g => g > 0).sort((a, b) => a - b);
  const q = p => gaps.length ? +gaps[Math.floor(p * (gaps.length - 1))].toFixed(1) : null;
  return {frames: ts.length, captureFps: +meta.captureFps.toFixed(1), gapMsP50: q(.5), gapMsP90: q(.9), gapMsMax: q(1), clockSkewMs: meta.clockSkewMs};
}

module.exports = {KNOBS, launchArgs, prepare, ready, bottomPad, moveTo, park, scrollTo, click, focus, holdUntil, startCapture, assemble, render, shots, camera, sourceStats};

// CLI: node demo-polish.js render <takeDir> <out.mp4> [--keep-bottom 120]   |   assemble <takeDir> <out.mp4>   |   stats <takeDir>
if (require.main === module) {
  const [cmd, dir, out, ...rest] = process.argv.slice(2), kb = rest.indexOf('--keep-bottom');
  (async () => {
    if (cmd === 'render') console.log(JSON.stringify(await render(dir, out, {keepBottom: kb >= 0 ? +rest[kb + 1] : 0})));
    else if (cmd === 'assemble') console.log(assemble(dir, out));
    else if (cmd === 'stats') console.log(JSON.stringify(sourceStats(dir)));
    else { console.error('usage: demo-polish.js render|assemble|stats <takeDir> [out.mp4] [--keep-bottom px]'); process.exit(2); }
  })().catch(e => { console.error(e); process.exit(1); });
}
