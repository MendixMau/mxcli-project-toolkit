'use strict';
// login_page_home_control.js: the engine login on an app whose ANONYMOUS HOME IS A LOGIN PAGE (T8-9, T7-10).
//
//   node login_page_home_control.js <patched engine dir> <unpatched engine dir>
//
// Both dirs are engine COPIES (run_journeys.py --patch-engine output, and a plain copy of vendor/e2e); this script
// writes a project.config.js into each. A local HTTP server plays a Mendix app:
//   /            anonymous: a Mendix page (.mx-page) with a custom login widget whose button needs the Mendix client
//                (FSM General.Login_Web, the T7 Atlas login template): fill + Enter there never signs in.
//                signed in: the app shell (.mx-navigationtree, .mx-name-homeGrid).
//   /login.html  the standard login form (#usernameInput, #passwordInput, #loginButton) posting the xas login action.
// Cases, one line each ("ok <case>" or "FAIL <case>"):
//   unpatched engine on /          reports a login PASS while a password input is still visible (the defect: this
//                                  line proves the fixture reproduces T8-9; it is a CATCH of the old engine)
//   patched engine, LOGIN_PATH=/   no false PASS: login is refused while the login page is still shown
//   patched engine, /login.html    signs in, lands on the app shell, no password input visible
//   patched engine, already in, READY a union whose first DOM match is hidden (a Set URL widget, T7)
//                                  recognises the signed-in app (any match counts; a first-match check says no)
// Exit 0 when every case holds, 1 otherwise.
const http = require('http');
const fs = require('fs');
const path = require('path');

const [patchedDir, plainDir] = process.argv.slice(2).map((d) => path.resolve(d));
const USER = 'smoke_inspector', PASS = 'Smoke-only-1!';

const ANON = `<!doctype html><html><body><div class="mx-page mx-name-Login_Web">
  <h1>Field Service</h1>
  <input type="text" class="form-control mx-name-userName">
  <input type="password" class="form-control mx-name-password">
  <button class="btn mx-button mx-name-signInButton">Sign in</button></div></body></html>`;
const SHELL_UNION = `<!doctype html><html><body><div class="mx-page">
  <div class="mx-name-setURL1" style="width:0;height:0"></div>
  <div class="mx-name-homeGrid" style="width:300px;height:100px">Work orders</div></div></body></html>`;
let forceIn = false;
const SHELL = `<!doctype html><html><body><div class="mx-page">
  <div class="mx-navigationtree"><a title="Home" href="#">Home</a></div>
  <div class="mx-name-homeGrid">Work orders</div></div></body></html>`;
const LOGIN_HTML = `<!doctype html><html><body><form onsubmit="return false">
  <input id="usernameInput" type="text"><input id="passwordInput" type="password">
  <button id="loginButton" type="button" onclick="go()">Sign in</button><div id="loginMessage"></div></form>
  <script>
  function go() {
    fetch('/xas/', { method: 'POST', body: JSON.stringify({ action: 'login', params: {
      username: document.getElementById('usernameInput').value, password: document.getElementById('passwordInput').value } }) })
      .then((r) => { if (r.status === 200) location.href = '/';
        else document.getElementById('loginMessage').textContent = 'The username or password you entered is incorrect.'; });
  }
  </script></body></html>`;

const server = http.createServer((req, res) => {
  const signedIn = forceIn || /(^|;\s*)sess=ok/.test(req.headers.cookie || '');
  if (req.method === 'POST' && req.url === '/xas/') {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      const p = (JSON.parse(body || '{}').params) || {};
      if (p.username === USER && p.password === PASS) {
        res.writeHead(200, { 'Set-Cookie': 'sess=ok; Path=/', 'Content-Type': 'application/json' }); res.end('{}');
      } else { res.writeHead(401); res.end('{}'); }
    });
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/html' });
  if (req.url.startsWith('/login.html')) return res.end(LOGIN_HTML);
  return res.end(signedIn ? (forceIn ? SHELL_UNION : SHELL) : ANON);
});

function engine(dir, port, ready = "'.mx-name-homeGrid'") {
  fs.writeFileSync(path.join(dir, 'project.config.js'), `'use strict';
module.exports = { root: ${JSON.stringify(dir)}, mpr: null, mxcli: 'mxcli', dsCss: null, defaultPort: '${port}',
  readySelectors: [${ready}], NAV: {}, TARGETS: { 'full-app': [] },
  credentials: () => ({ user: '${USER}', pass: '${PASS}', fallbackUser: '', fallbackPass: '' }) };\n`);
  return require(path.join(dir, 'helpers.js'));
}

async function attempt(H) {
  const { browser, page } = await H.launchBrowser();
  try {
    const li = await H.login(page);
    const pw = await page.locator('input[type=password]').first().isVisible().catch(() => false);
    const shell = await page.locator('.mx-name-homeGrid').first().isVisible().catch(() => false);
    return { ok: !!li.ok, pw, shell, reason: li.reason || '' };
  } finally { await browser.close().catch(() => {}); }
}

(async () => {
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  process.env.APP_PORT = String(port);
  process.env.APP_URL = `http://127.0.0.1:${port}`;
  const plain = engine(plainDir, port), patched = engine(patchedDir, port);
  let bad = 0;
  const line = (good, name, r) => { if (!good) bad++; console.log(`${good ? 'ok  ' : 'FAIL'} ${name}: login ${r.ok ? 'PASS' : 'refused'}, password input visible ${r.pw}, app shell ${r.shell}${r.reason ? ', ' + r.reason : ''}`); };
  process.env.LOGIN_PATH = '/';
  const [a, b] = await Promise.all([attempt(plain), attempt(patched)]);
  line(a.ok && a.pw && !a.shell, 'unpatched engine on / reports a false login PASS (T8-9 reproduced)', a);
  line(!b.ok && !b.shell, 'patched engine on / gives no false PASS', b);
  process.env.LOGIN_PATH = '/login.html';
  const c = await attempt(patched);
  line(c.ok && !c.pw && c.shell, 'patched engine on /login.html signs in', c);
  // already signed in, READY is a union whose first DOM match draws nothing: loginOnce must still see the app
  const unionDir = patchedDir + '-union'; fs.rmSync(unionDir, { recursive: true, force: true }); fs.cpSync(patchedDir, unionDir, { recursive: true });
  const union = engine(unionDir, port, "'.mx-name-setURL1, .mx-name-homeGrid'");
  forceIn = true; process.env.LOGIN_PATH = '/';
  const d = await attempt(union);
  line(d.ok && d.shell, 'patched engine already in, READY union with a hidden first match recognises the app', d);
  server.close();
  process.exit(bad ? 1 : 0);
})().catch((e) => { console.error('control error:', e && e.stack || e); server.close(); process.exit(3); });
