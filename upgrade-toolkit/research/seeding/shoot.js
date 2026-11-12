// shoot.js <base url> <user> <pass> <outdir> [menu text ...]
// Log in as one smoke user, screenshot the landing page, then click each menu text in turn and screenshot it.
// Prints the visible text length and the first 400 chars so "empty page" is a number, not an impression.
const { chromium } = require(process.env.PW_MODULE || 'playwright');
(async () => {
  const [base, user, pass, out, ...menus] = process.argv.slice(2);
  const fs = require('fs'); fs.mkdirSync(out, { recursive: true });
  const b = await chromium.launch({ executablePath: process.env.PW_CHROME || undefined, args: ['--no-sandbox'] });
  const p = await (await b.newContext({ viewport: { width: 1400, height: 900 } })).newPage();
  const errs = []; p.on('pageerror', e => errs.push(String(e).slice(0, 160)));
  await p.goto(base + '/login.html', { waitUntil: 'load' });
  await p.fill('#usernameInput', user); await p.fill('#passwordInput', pass); await p.click('#loginButton');
  await p.waitForTimeout(6000);
  const snap = async (name) => {
    await p.waitForTimeout(2500);
    const t = (await p.innerText('body').catch(() => '')).replace(/\s+/g, ' ');
    const f = out + '/' + name.replace(/[^A-Za-z0-9]+/g, '_') + '.png';
    await p.screenshot({ path: f, fullPage: false });
    console.log(`${name}: ${t.length} chars | ${t.slice(0, 400)}`);
  };
  await snap('landing');
  for (const m of menus) {
    try { const box = await p.evaluate((t) => { const e = [...document.querySelectorAll('a,button,li,span')].filter(x => x.offsetParent !== null && x.textContent.trim() === t)[0]; if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; }, m); if (!box) throw new Error('no visible element with that text'); await p.mouse.click(box.x, box.y); await snap(m); }
    catch (e) { console.log(`${m}: NOT CLICKABLE ${String(e).slice(0,200)}`); }
  }
  if (errs.length) console.log('pageerrors:', errs.join(' | '));
  await b.close();
})();
