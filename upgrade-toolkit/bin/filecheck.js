#!/usr/bin/env node
// filecheck.js: upload one file and download it again through the app's own client, as one signed-in user, on a running app.
//
// Why: a major upgrade can change where uploaded files live (file storage), how the runtime stores and serves them and how
// an Image makes its thumbnail, and no page walk notices: the page shows a file name either way. This sends the same
// bytes through the client's own upload call (mx.data.saveDocument, the call every File manager widget makes), commits the
// object, reads it back through the client's download URL and compares the bytes (sha256). For an Image entity it also
// asks for the thumbnail. Run it on the old app and on the new app with the same entity and user and compare the two
// JSON files (filecheck_compare in this file's --compare mode).
//
//   node filecheck.js --url http://localhost:8080 --user U --password P --entity Module.Entity [--login-path /login.html]
//                     [--name gap.png] [--out result.json]
//   node filecheck.js --compare old.json new.json         exit 0 when the two sides agree, 1 when they differ
// Exit: 0 uploaded, committed, downloaded identical; 1 a step failed or the bytes differ; 2 usage or runner error.
// The object stays in the database copy; run it on a copy. The file is a fixed 32x32 PNG made here (same bytes every run).
const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const crypto = require('crypto');

function args() {
  const a = process.argv.slice(2), o = { loginPath: '/login.html', name: 'filecheck.png', timeout: 20000 };
  for (let i = 0; i < a.length; i++) {
    const k = a[i];
    if (k === '--url') o.url = a[++i].replace(/\/$/, '');
    else if (k === '--user') o.user = a[++i];
    else if (k === '--password') o.password = a[++i];
    else if (k === '--entity') o.entity = a[++i];
    else if (k === '--login-path') o.loginPath = a[++i];
    else if (k === '--name') o.name = a[++i];
    else if (k === '--out') o.out = a[++i];
    else if (k === '--compare') { o.compare = [a[++i], a[++i]]; }
    else { console.error('unknown arg ' + k); process.exit(2); }
  }
  return o;
}

// A deterministic 32x32 RGB PNG (a gradient), no image library needed.
function png32() {
  const crcT = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crcT[n] = c >>> 0; }
  const crc = b => { let c = 0xffffffff; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const w = 32, h = 32, raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 3 + 1)] = 0; for (let x = 0; x < w; x++) { const o = y * (w * 3 + 1) + 1 + x * 3; raw[o] = x * 8; raw[o + 1] = y * 8; raw[o + 2] = 128; } }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

function loadPlaywright() {
  const dirs = [process.env.PLAYWRIGHT_DIR, path.join(os.homedir(), 'mendix-playwright/node_modules/playwright'), 'playwright'].filter(Boolean);
  for (const d of dirs) { try { return require(d); } catch (e) { /* next */ } }
  console.error('filecheck: playwright not found (set PLAYWRIGHT_DIR)'); process.exit(2);
}

// Runs in the browser. Promise-wraps the client's callbacks, each with its own timeout, never throws.
async function inBrowser({ entity, name, b64, ms }) {
  const out = { steps: [] };
  const wait = (label, fn) => new Promise(res => {
    let done = false; const t = setTimeout(() => { if (!done) { done = true; out.steps.push(label + ': timeout'); res({ err: 'timeout' }); } }, ms);
    try { fn(v => { if (!done) { done = true; clearTimeout(t); out.steps.push(label + ': ok'); res({ v }); } },
             e => { if (!done) { done = true; clearTimeout(t); out.steps.push(label + ': ' + String(e && e.message || e).slice(0, 200)); res({ err: String(e && e.message || e) }); } }); }
    catch (e) { if (!done) { done = true; clearTimeout(t); out.steps.push(label + ' threw: ' + String(e && e.message || e).slice(0, 200)); res({ err: String(e) }); } }
  });
  const sha = async buf => [...new Uint8Array(await crypto.subtle.digest('SHA-256', buf))].map(b => b.toString(16).padStart(2, '0')).join('');
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  out.upload_sha = await sha(bytes); out.upload_size = bytes.length;
  const blob = new Blob([bytes], { type: 'image/png' });
  const c = await wait('create', (ok, bad) => mx.data.create({ entity, callback: ok, error: bad }));
  if (c.err) return out;
  const obj = c.v; out.guid = obj.getGuid();
  const s = await wait('saveDocument', (ok, bad) => mx.data.saveDocument(out.guid, name, {}, blob, ok, bad));
  if (s.err) return out;
  const m = await wait('commit', (ok, bad) => mx.data.commit({ mxobj: obj, callback: ok, error: bad }));
  if (m.err) return out;
  const g = await wait('reload', (ok, bad) => mx.data.get({ guid: out.guid, callback: o => ok(o && (Array.isArray(o) ? o[0] : o)), error: bad }));
  const o2 = g.v || obj;
  const attr = a => { try { return o2.get(a); } catch (e) { return null; } };
  out.name = attr('Name'); out.size = attr('Size'); out.hasContents = attr('HasContents');
  out.changedDate = (() => { try { return o2.get('changedDate'); } catch (e) { return null; } })();
  const dl = async (thumb) => {
    let url; try { url = mx.data.getDocumentUrl(out.guid, out.changedDate, thumb); } catch (e) { return { status: 'no url: ' + e.message }; }
    url = String(await url);   // the new client returns a Promise of the URL, the old one a string
    try { const r = await fetch(url, { credentials: 'include' }); const buf = await r.arrayBuffer(); return { status: r.status, type: r.headers.get('content-type'), bytes: buf.byteLength, sha: await sha(buf), url: url.replace(/changedDate=\d+/, 'changedDate=N') }; }
    catch (e) { return { status: 'fetch failed: ' + e.message }; }
  };
  out.download = await dl(false);
  if (/image/i.test(entity) || true) out.thumbnail = await dl(true);
  return out;
}

function compare(oldF, newF) {
  const a = JSON.parse(fs.readFileSync(oldF, 'utf8')), b = JSON.parse(fs.readFileSync(newF, 'utf8')), diffs = [];
  const pick = r => ({ ok: r.ok, name: r.name, size: r.size, hasContents: r.hasContents, upload_sha: r.upload_sha,
    dl_status: r.download && r.download.status, dl_bytes: r.download && r.download.bytes, dl_sha: r.download && r.download.sha, dl_type: r.download && r.download.type,
    th_status: r.thumbnail && r.thumbnail.status, th_type: r.thumbnail && r.thumbnail.type });
  const x = pick(a), y = pick(b);
  // two failed runs agree on nothing: a side that did not upload and download its file is a difference of its own
  if (!a.ok) diffs.push('old side did not complete: ' + (a.steps || []).join(', '));
  if (!b.ok) diffs.push('new side did not complete: ' + (b.steps || []).join(', '));
  for (const k of Object.keys(x)) if (JSON.stringify(x[k]) !== JSON.stringify(y[k])) diffs.push(k + ': old ' + JSON.stringify(x[k]) + ' new ' + JSON.stringify(y[k]));
  // the thumbnail bytes may differ between two image libraries: judge status and content type, report the size apart
  const thOld = a.thumbnail && a.thumbnail.bytes, thNew = b.thumbnail && b.thumbnail.bytes;
  console.log(diffs.length ? 'DIFFERENT\n  ' + diffs.join('\n  ') : 'SAME: upload, download (sha256 ' + String(x.dl_sha).slice(0, 12) + '), stored name and size, thumbnail status');
  if (thOld !== thNew) console.log('  note: thumbnail bytes old ' + thOld + ' new ' + thNew);
  process.exit(diffs.length ? 1 : 0);
}

(async () => {
  const o = args();
  if (o.compare) return compare(o.compare[0], o.compare[1]);
  if (!o.url || !o.user || !o.password || !o.entity) { console.error('need --url --user --password --entity'); process.exit(2); }
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch();
  let res = { ok: false, entity: o.entity, user: o.user, steps: [] };
  try {
    // desktop size: a field app sends screen.width <= 1280 to the Tablet profile and reloads the page
    const page = await (await browser.newContext({ viewport: { width: 1440, height: 900 }, screen: { width: 1440, height: 900 } })).newPage();
    await page.goto(o.url + o.loginPath, { waitUntil: 'domcontentloaded' });
    await page.fill('#usernameInput', o.user); await page.fill('#passwordInput', o.password); await page.click('#loginButton');
    await page.waitForFunction(() => { try { return !!(mx.session.getUserName() && mx.ui.getContentForm && mx.ui.getContentForm()); } catch (e) { return false; } }, null, { timeout: o.timeout });
    res = Object.assign(res, await page.evaluate(inBrowser, { entity: o.entity, name: o.name, b64: png32().toString('base64'), ms: o.timeout }));
    res.ok = !!(res.guid && res.download && res.download.status === 200 && res.download.sha === res.upload_sha && res.hasContents !== false);
    try { await page.evaluate(() => new Promise(r => { try { mx.logout(); } catch (e) {} setTimeout(r, 1000); })); } catch (e) { /* gone */ }
  } catch (e) { res.error = String(e && e.message || e).slice(0, 300); }
  await browser.close();
  const text = JSON.stringify(res, null, 1);
  if (o.out) fs.writeFileSync(o.out, text + '\n'); else console.log(text);
  console.log('filecheck ' + (res.ok ? 'OK' : 'FAIL') + ' ' + o.entity + ' as ' + o.user + ': ' + (res.steps || []).join(', ') + (res.error ? ' ' + res.error : ''));
  process.exit(res.ok ? 0 : 1);
})().catch(e => { console.error('filecheck: ' + (e && e.stack || e)); process.exit(2); });
