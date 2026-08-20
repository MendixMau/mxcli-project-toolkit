'use strict';
// ============================================================================
// E2E harness — shared helpers (login, capture, computed styles, DB).
// ----------------------------------------------------------------------------
// ENGINE. Every project-specific value reaches this file through `cfg`
// (tests/e2e/config.js -> tests/e2e/project.config.js). Nothing here may name a
// project, a widget, a page or an .mpr.
// ============================================================================
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
// DEFECT FIXED 2026-08-18: this was a bare top-level `require('playwright')`,
// so a machine without the dependency got a stack trace and a non-2 exit —
// while page-audit.js, requiring the very same module, wrapped it and degraded
// to `fault`. A missing dependency is an instrument fault (rc 2), never a
// crash. The require is kept at top level (callers destructure `chromium` at
// call time, and lazy-loading it would change that), but its failure is now
// carried and raised as a fault by the first function that actually needs a
// browser. Everything in this file that does NOT need Playwright — oql(),
// parseTokens(), makeReporter(), ensureDirs() — keeps working without it.
let chromium = null, devices = null, playwrightError = null;
try { ({ chromium, devices } = require('playwright')); }
catch (e) { playwrightError = e; }

// Call before touching `chromium`/`devices`. Exits 2 (instrument fault) with an
// actionable message instead of throwing an unhandled MODULE_NOT_FOUND.
function requirePlaywright() {
  if (chromium) return;
  console.error(
    `\n  INSTRUMENT FAULT — playwright is not installed: ${playwrightError && playwrightError.message}\n` +
    `  Nothing was measured. This is not a finding about the application.\n\n` +
    `  Fix:  npm install playwright && npx playwright install chromium\n`);
  process.exit(2);   // 2 = instrument fault, never 1 = finding. See report-schema.md.
}

const { cfg } = require('./config');

// Track last known mouse position so humanMove() always has a sensible start.
let _mouseX = 720;
let _mouseY = 450;

// ── Browser ─────────────────────────────────────────────────────────────────
async function launchBrowser({ videoDir = null, trace = false, viewport = null } = {}) {
  requirePlaywright();
  const vp = viewport || cfg.viewport;
  const launchOpts = {
    headless: !cfg.headed,
    slowMo: 0,   // cursor animation is JS-driven; slowMo is set via script-level pauses
    args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream'],
  };
  if (cfg.channel && cfg.channel !== 'chromium') launchOpts.channel = cfg.channel;
  const browser = await chromium.launch(launchOpts);
  const context = await browser.newContext({
    viewport: vp,
    recordVideo: videoDir ? { dir: videoDir, size: vp } : undefined,
  });
  if (trace) await context.tracing.start({ screenshots: true, snapshots: true, sources: true });
  const page = await context.newPage();
  return { browser, context, page };
}

// Launch a browser positioned at (x, y) with window size (w × h).
// Used for dual-window narrative demo to place desktop + mobile side-by-side.
async function launchBrowserAt(x, y, w, h, { videoDir = null, trace = false, mobile = false, deviceName = 'iPhone 14' } = {}) {
  requirePlaywright();
  const launchOpts = {
    headless: !cfg.headed,
    slowMo: 0,   // cursor animation is JS-driven; pauses live in the script
    args: [
      '--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream',
      `--window-position=${x},${y}`,
      `--window-size=${w},${h}`,
      // Note: --app mode was removed for mobile — it caused page context to close
      // on re-navigation. iPhone routing is done via the device UA/viewport profile.
    ],
  };
  if (cfg.channel && cfg.channel !== 'chromium') launchOpts.channel = cfg.channel;
  const browser = await chromium.launch(launchOpts);
  // mobile:true → use the real Playwright device profile (iPhone 14 by default).
  // This gives the correct UA, viewport, deviceScaleFactor and touch flags so the
  // Mendix app's device-routing sends the user to the FieldScan (PhoneScan) home.
  const device = mobile ? devices[deviceName] || devices['iPhone 14'] : {};
  const context = await browser.newContext({
    ...device,
    viewport: mobile ? device.viewport : { width: w, height: h },
    recordVideo: videoDir ? { dir: videoDir, size: mobile ? device.viewport : { width: w, height: h } } : undefined,
    // Increase default navigation + action timeouts to survive slow Mendix pages.
    navigationTimeout: 60000,
    actionTimeout: 30000,
  });
  if (trace) await context.tracing.start({ screenshots: true, snapshots: true, sources: true });
  const page = await context.newPage();
  return { browser, context, page };
}

// ── Cursor: green dot positioned only by the automation (not your real mouse) ─
async function injectCursor(context) {
  await context.addInitScript(() => {
    const dot = document.createElement('div');
    dot.id = '__e2e-cursor';
    dot.style.cssText =
      'position:fixed;z-index:2147483647;width:18px;height:18px;margin:-9px 0 0 -9px;' +
      'border-radius:50%;background:rgba(34,197,94,.55);border:2.5px solid #22c55e;' +
      'pointer-events:none;left:-100px;top:-100px;' +
      'box-shadow:0 0 8px rgba(34,197,94,.6);';
    const attach = () => { if (document.body && !document.getElementById('__e2e-cursor')) document.body.appendChild(dot); };
    if (document.readyState !== 'loading') attach();
    else document.addEventListener('DOMContentLoaded', attach);
    // Exposed so humanMove() can update position directly (no real-mouse tracking)
    window.__e2eCursorMove = (x, y) => { dot.style.left = x + 'px'; dot.style.top = y + 'px'; };
  });
}

// ── OQL overlay — live DB assertion panel pinned to bottom-right ─────────────
// Survives page navigations via addInitScript. Each showOqlResult() call
// adds a line to the panel so the demo audience sees DB state in real-time.
async function injectOqlOverlay(context) {
  await context.addInitScript(() => {
    window.__e2eOql = {
      _ready: false,
      _queue: [],
      init() {
        if (document.getElementById('__e2e-oql')) { this._ready = true; this._flush(); return; }
        const p = document.createElement('div');
        p.id = '__e2e-oql';
        p.style.cssText =
          'position:fixed;bottom:16px;left:16px;z-index:2147483646;width:380px;' +
          'background:rgba(10,10,11,0.93);border:1px solid #2a2a2a;border-radius:14px;' +
          'padding:12px 14px 10px;font-family:ui-monospace,SFMono-Regular,monospace;' +
          'font-size:11px;color:#e0e0e0;max-height:280px;overflow-y:auto;' +
          'backdrop-filter:blur(6px);box-shadow:0 8px 40px rgba(0,0,0,.6);';
        p.innerHTML =
          '<div style="font-size:10px;text-transform:uppercase;letter-spacing:.08em;' +
          'color:#555;margin-bottom:8px;font-family:system-ui,sans-serif;display:flex;gap:6px">' +
          '<span style="color:#22c55e">●</span> DB Assertions</div>' +
          '<div id="__e2e-oql-list"></div>';
        document.body.appendChild(p);
        this._ready = true;
        this._flush();
      },
      _flush() {
        while (this._queue.length) {
          const args = this._queue.shift();
          this._add(...args);
        }
      },
      add(label, sql, value, pass) {
        if (this._ready) this._add(label, sql, value, pass);
        else this._queue.push([label, sql, value, pass]);
      },
      _add(label, sql, value, pass) {
        const list = document.getElementById('__e2e-oql-list');
        if (!list) return;
        const color = pass ? '#4ade80' : '#f87171';
        const icon  = pass ? '✓' : '✗';
        const entry = document.createElement('div');
        entry.style.cssText =
          'border-top:1px solid #1e1e1e;padding:6px 0 4px;' +
          'transition:background .6s;background:' +
          (pass ? 'rgba(74,222,128,.10)' : 'rgba(248,113,113,.10)');
        entry.innerHTML =
          '<div style="display:flex;align-items:baseline;gap:6px">' +
          '<span style="color:' + color + ';font-weight:700;font-size:13px">' + icon + '</span>' +
          '<span style="color:#d4d4d4;font-family:system-ui,sans-serif;font-size:11.5px;flex:1">' + label + '</span>' +
          '<span style="color:' + color + ';font-weight:700;font-size:13px;margin-left:8px">' + String(value) + '</span>' +
          '</div>' +
          '<div style="color:#4a4a4a;font-size:9.5px;margin-top:2px;word-break:break-all">' + sql + '</div>';
        list.prepend(entry);
        setTimeout(() => { entry.style.background = ''; }, 1600);
      },
    };
    if (document.readyState !== 'loading') window.__e2eOql.init();
    else document.addEventListener('DOMContentLoaded', () => window.__e2eOql.init());
  });
}

// Push a result into the overlay already injected in the page.
async function showOqlResult(page, label, sql, value, pass = true) {
  await page.evaluate(([l, s, v, p]) => {
    if (window.__e2eOql) window.__e2eOql.add(l, s, v, p);
  }, [label, sql, String(value), pass]).catch(() => {});
  await page.waitForTimeout(Math.round(500 / cfg.speed)).catch(() => {});
}

// ── Human-like mouse movement ─────────────────────────────────────────────────
// Snappy + consistent: a gentle ease-in-out curve toward the element centre with
// a FIXED step budget. The earlier version used ±80px control-point jitter that
// produced loops/overshoot reading as "very slow, wandering" — speed was fine,
// the wander was the problem. This keeps it quick and direct.
async function humanMove(page, locator) {
  const box = await locator.boundingBox().catch(() => null);
  if (!box) return;
  const targetX = box.x + box.width  * (0.45 + (Math.random() - 0.5) * 0.2);
  const targetY = box.y + box.height * (0.5  + (Math.random() - 0.5) * 0.2);
  const steps = 12;
  const cpX = (_mouseX + targetX) / 2 + (Math.random() - 0.5) * 24;
  const cpY = (_mouseY + targetY) / 2 + (Math.random() - 0.5) * 18;
  // Move the real Playwright mouse in one jump (avoids slowMo stacking per step),
  // then animate only the visible green cursor dot via JS — smooth for the audience,
  // instant for Playwright.
  await page.mouse.move(targetX, targetY).catch(() => {});
  await page.evaluate(async ([sx, sy, tx, ty, cpx, cpy, n]) => {
    if (!window.__e2eCursorMove) return;
    for (let i = 1; i <= n; i++) {
      const t = i / n;
      const e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      const mt = 1 - e;
      const x = mt * mt * sx + 2 * mt * e * cpx + e * e * tx;
      const y = mt * mt * sy + 2 * mt * e * cpy + e * e * ty;
      window.__e2eCursorMove(x, y);
      await new Promise((r) => setTimeout(r, 14));   // ~170ms total — fast but visible
    }
  }, [_mouseX, _mouseY, targetX, targetY, cpX, cpY, steps]).catch(() => {});
  _mouseX = targetX;
  _mouseY = targetY;
}

// Click: move to element, brief pause, then click.
async function humanClick(page, locator) {
  await humanMove(page, locator);
  await page.waitForTimeout(Math.round((30 + Math.random() * 20) / cfg.speed));
  await locator.click({ force: true }).catch(() => locator.click().catch(() => {}));
}

// Type into a field using fill() — reliable across Mendix form fields.
async function humanType(page, locator, text) {
  await humanMove(page, locator);
  await locator.click({ force: true }).catch(() => {});
  await page.waitForTimeout(Math.round(30 / cfg.speed));
  await locator.fill(text).catch(async () => {
    // Fallback: select-all + keyboard type
    await page.keyboard.press('Control+a');
    for (const ch of text) {
      await page.keyboard.type(ch);
      await page.waitForTimeout(Math.round((20 + Math.random() * 25) / cfg.speed));
    }
  });
  await page.waitForTimeout(Math.round(40 / cfg.speed));
}

// Type with real key events, one character at a time.
//
// Datagrid 2's filter inputs are React-controlled and only re-filter on key
// events — locator.fill() sets the value without them, so the grid never
// updates and a filter assertion silently sees an unfiltered grid. Use this
// for any filter/search box; humanType() (fill-based) is fine for form fields.
async function humanTypeKeys(page, locator, text) {
  await humanMove(page, locator);
  await locator.click({ force: true }).catch(() => {});
  await page.waitForTimeout(Math.round(60 / cfg.speed));
  await locator.fill('').catch(() => {});
  if (text) await locator.pressSequentially(text, { delay: Math.round(60 / cfg.speed) }).catch(() => {});
  await page.waitForTimeout(Math.round(80 / cfg.speed));
}

// Scroll the REAL Mendix scroll container (content lives in
// `.mx-scrollcontainer-center`, not window — window.scrollY is always 0, which
// is why wheel-over-window produced random jumps/bounces). We scrollTo an
// absolute, CLAMPED target so it can never bounce past the top or the bottom —
// this kills the "random scroll up at the top of the page" jank.
async function humanScroll(page, { distance = 300, axis = 'down' } = {}) {
  const sign = axis === 'down' ? 1 : -1;
  await page.evaluate(async ([delta]) => {
    const sc = document.querySelector('.mx-scrollcontainer-center')
            || document.scrollingElement || document.body;
    const max = Math.max(0, sc.scrollHeight - sc.clientHeight);
    const start = sc.scrollTop;
    const target = Math.min(max, Math.max(0, start + delta));   // clamped — no bounce
    if (Math.abs(target - start) < 2) return;                   // already at edge → no-op
    const steps = 16, dur = 260;
    for (let i = 1; i <= steps; i++) {
      const t = i / steps;
      const e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;  // ease-in-out
      sc.scrollTop = start + (target - start) * e;
      await new Promise((r) => setTimeout(r, dur / steps));
    }
  }, [distance * sign]).catch(() => {});
  await page.waitForTimeout(Math.round(120 / cfg.speed));
}

// ── Login ───────────────────────────────────────────────────────────────────
// Retries, because clearing cookies makes the Mendix client find a stale session
// token, log a 401 and *restart itself*. That restart re-renders the login form
// underneath us — a single-shot fill races it and silently submits nothing
// (the runtime then shows 0 failed logins, since no attempt ever arrived).
// Returns { ok, user, usedFallback, reason } so the caller can report which
// identity the walkthrough actually ran under — never assume it was the
// configured one.
//
// CRITICAL: submit each identity's credentials AT MOST ONCE per run. Mendix
// blocks an account after 3 failed attempts, so a retry loop around a bad
// password does not recover — it permanently locks the account out and every
// later run then fails for a different reason than the original one. (This
// harness learned that the hard way: a single transient failure plus two
// automatic retries blocked demo_test_user, and the symptom then read as
// "wrong password" instead of "blocked".)
//
// A submitted-but-rejected credential is therefore final. We only re-attempt
// when the form never rendered — i.e. nothing was submitted and no attempt was
// consumed.
async function login(page) {
  const identities = [{ user: cfg.user, pass: cfg.pass, fallback: false }];
  if (cfg.fallbackUser) {
    identities.push({ user: cfg.fallbackUser, pass: cfg.fallbackPass, fallback: true });
  }
  let reason = '';
  for (const id of identities) {
    for (let attempt = 1; attempt <= 3; attempt++) {
      const submitted = await loginOnce(page, id.user, id.pass);
      if (!submitted) {
        // Login form never rendered — no credentials sent, no attempt burned.
        // Safe to wait for the client to settle and try again.
        reason = 'login form did not render';
        await page.waitForTimeout(3000);
        continue;
      }
      const inApp = await page.waitForFunction(() => {
        const onLogin = /login\.html|\/login(\b|\/|$)/.test(location.href);
        return !onLogin && !!document.querySelector('.mx-navigationtree, .mx-page');
      }, { timeout: 12000 }).then(() => true).catch(() => false);
      if (inApp) {
        await dismissModal(page);
        return { ok: true, user: id.user, usedFallback: id.fallback, reason: '' };
      }
      // Credentials were submitted and rejected. Do NOT retry this identity.
      reason = (await page.locator('.login-message, .alert-danger, #loginMessage').first()
        .innerText().catch(() => '')).trim() || 'credentials rejected';

      // Mendix shows exactly one message for a bad credential. Anything else is
      // the runtime refusing the login for a reason that has nothing to do with
      // the password — and the UI does not say which. Measured 2026-08-18:
      // "Sign in failed." was the trial licence's concurrent-session cap
      // (`Maximum number of sessions exceeded!`, visible only in the runtime log).
      // That is an INSTRUMENT FAULT, not a finding: the harness never got to run.
      // Reporting it as a credential failure sends the reader to fix a password
      // that was correct all along, and trying the fallback identity on top of it
      // burns a second account against the same cap.
      if (!/username or password/i.test(reason)) {
        console.log(`    ✗ login as "${id.user}" FAULTED: "${reason}" — not a credential failure.`);
        console.log(`      Check the runtime log for the real cause:  docker logs <container> | grep -i login`);
        return { ok: false, user: id.user, usedFallback: false, fault: true, reason };
      }
      console.log(`    ⚠ login as "${id.user}" rejected: ${reason} (not retrying — avoids account lockout)`);
      break;
    }
  }
  return { ok: false, user: cfg.user, usedFallback: false, fault: false, reason };
}

// Ends the Mendix session server-side. Mandatory at the end of every run: an
// unlicensed runtime caps concurrent sessions, and a closed browser does NOT
// release one. Measured 2026-08-18 — leaked sessions from earlier journeys
// accumulated until every later login failed, which reads as a wrong password.
// GET /logout does NOT work — it renders a page and leaves the session alive
// (measured: the app root still resolved to the dashboard afterwards). The xas
// `logout` action does; after it, / redirects to login.html.
async function logout(page) {
  try {
    const status = await page.evaluate(async () => {
      const token = (window.mx && mx.session && mx.session.getCSRFToken)
        ? mx.session.getCSRFToken() : '';
      const res = await fetch('/xas/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Csrf-Token': token },
        body: JSON.stringify({ action: 'logout', params: {} }),
      });
      return res.status;
    });
    return status === 200;
  } catch { return false; }
}

// Submits one set of credentials. Returns true only if they were actually sent,
// so the caller can distinguish "rejected" (never retry) from "form never
// appeared" (safe to retry — no login attempt was consumed).
async function loginOnce(page, user, pass) {
  let submitted = false;
  await page.context().clearCookies();
  await page.goto(cfg.baseUrl + '/', { waitUntil: 'domcontentloaded' });
  // Wait for the form itself rather than a speed-scaled sleep — at DEMO_SPEED=8
  // that sleep collapses to ~125ms and reliably loses the race with the Mendix
  // client's own "clear stored session and restart" cycle.
  await page.locator('#passwordInput, input[type=password]').first()
    .waitFor({ state: 'visible', timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(600).catch(() => {});
  const pwField = page.locator('#passwordInput, input[type=password]').first();
  // Already inside the app (no form at all) — nothing to submit.
  if (!(await page.locator('#passwordInput, input[type=password]').count().catch(() => 0))
      && await page.locator('.mx-page').first().isVisible({ timeout: 1000 }).catch(() => false)) {
    return true;
  }
  if (await pwField.isVisible({ timeout: 5000 }).catch(() => false)) {
    // Use fill() directly — fast, skips humanMove bezier for the login form
    const userField = page.locator('#usernameInput, input[type=text]').first();
    await userField.fill(user);
    await page.waitForTimeout(Math.round(200 / cfg.speed)).catch(() => {});
    await pwField.fill(pass);
    await page.waitForTimeout(Math.round(200 / cfg.speed)).catch(() => {});
    const btn = page.locator('#loginButton, button[type=submit]').first();
    if (await btn.isVisible({ timeout: 1500 }).catch(() => false)) {
      await btn.click({ noWaitAfter: true }).catch(() => pwField.press('Enter').catch(() => {}));
    } else await pwField.press('Enter').catch(() => {});
    submitted = true;
    await page.waitForLoadState('domcontentloaded').catch(() => {});
  }
  // Wait for the SPA to actually finish routing into the app shell — NOT a fixed
  // sleep. Device-agnostic: desktop shows the nav tree / copilot; the PHONE
  // layout has neither (it auto-routes to the FieldScan tiles), so we accept any
  // real app content and only require that we've left the login page.
  // The selector list is cfg.readySelectors (project.config), not a literal:
  // three of the five entries here were this project's own widget names.
  await page.waitForFunction((sel) => {
    const onLogin = /login\.html|\/login(\b|\/|$)/.test(location.href);
    const ready = document.querySelector(sel);
    return !onLogin && !!ready;
  }, cfg.readySelectors.join(', '), { timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(Math.round(1200 / cfg.speed)).catch(() => {});
  await dismissModal(page);
  return submitted;
}

// Asserts the run is executing under the identity the spec was written for.
// `A('[UI] logged in', li.ok, li.user)` — the line every otel spec was copied
// with — passes when login() silently degraded to MxAdmin. Admin bypasses the
// role grants those specs exist to test, so the whole suite goes green while
// measuring an access path no real user takes. Assert identity, not presence.
//
// The fallback stays available (a credential problem should degrade to a
// reported finding, not a zero-coverage run) but it can no longer be silent.
function assertIdentity(li, A) {
  A('[UI] logged in', li.ok, li.user || li.reason);
  A(`[UI] running as configured identity "${cfg.user}"`,
    li.ok && !li.usedFallback && li.user === cfg.user,
    li.usedFallback
      ? `FELL BACK to "${li.user}" — admin bypasses the role grants this spec tests; ` +
        'every assertion below is measuring the wrong access path'
      : li.user);
  return li.ok && !li.usedFallback;
}

async function dismissModal(page, retries = 3) {
  for (let i = 0; i < retries; i++) {
    const btn = page.locator('.mx-dialog-footer button, .mx-name-closeButton').first();
    if (await btn.isVisible({ timeout: 800 }).catch(() => false)) {
      await btn.click().catch(() => {});
      await page.waitForTimeout(500);
    } else break;
  }
}

// ── Navigation (act like a user — click real nav anchors, no URLs) ────────────
// The top nav is a collapsible dropdown whose flyout is overlapped by the page
// grid, so Playwright's physical .click() gets pointer-intercepted. We still
// click the REAL nav anchor via el.click() so the Mendix handler fires reliably
// (no deeplink navigation). parentTitle opens the group; childTitle is the dest.
async function navTo(page, parentTitle, childTitle) {
  const clickTitle = (t) => page.evaluate((title) => {
    const a = [...document.querySelectorAll('.mx-navigationtree a')]
      .find((x) => x.getAttribute('title') === title);
    if (a) { a.scrollIntoView({ block: 'nearest' }); a.click(); return true; }
    return false;
  }, t).catch(() => false);
  if (parentTitle) { await clickTitle(parentTitle); await page.waitForTimeout(Math.round(500 / cfg.speed)); }
  await clickTitle(childTitle);
  await page.waitForTimeout(Math.round(1500 / cfg.speed));
  await dismissModal(page);
}

// The AI Copilot sidebar (.copilot) must stay open on every desktop key page —
// the demo's premise is one continuous conversation across the flow. If a layout
// ever collapses it, click the toggle to re-open.
async function ensureSidebar(page) {
  const isOpen = () => page.locator('.copilot .mx-name-textAreaUserPrompt, .mx-name-textAreaUserPrompt')
    .first().isVisible({ timeout: 1500 }).catch(() => false);
  if (await isOpen()) return true;
  const toggle = page.locator('[class*="mx-name-sidebarToggle"]').first();
  if (await toggle.isVisible({ timeout: 1000 }).catch(() => false)) {
    await toggle.click().catch(() => {});
    await page.waitForTimeout(Math.round(600 / cfg.speed));
  }
  return await isOpen();
}

// Read the Copilot message history (excludes the textarea input so placeholder
// text like "Shift+Enter for new line" never bleeds into reply assertions).
async function copilotText(page) {
  // Try to read only the messages/history container, not the input area.
  const msgContainer = page.locator(
    '.copilot .mx-name-lvChatMessages, .copilot .mx-name-lvMessages, ' +
    '.copilot [class*="messages"], .copilot [class*="history"], .copilot [class*="chat-content"]'
  ).first();
  const hasMsg = await msgContainer.isVisible({ timeout: 300 }).catch(() => false);
  if (hasMsg) return await msgContainer.innerText().catch(() => '');
  // Fallback: full sidebar minus the textarea value.
  const full = await page.locator('.copilot').first().innerText().catch(() => '');
  const taVal = await page.locator('.copilot textarea').first().inputValue().catch(() => '');
  return full.replace(taVal, '').replace('Shift+Enter for a new line.', '').replace('Please validate the output.', '').trim();
}

// Ask the Copilot a real question and WAIT for the actual streamed reply to
// settle (poll sidebar text growth) — replaces blind fixed waits. Returns the
// reply delta so callers can assert on real data (item/location codes).
async function askCopilot(page, question, { maxMs = 60000 } = {}) {
  await ensureSidebar(page);
  const input = page.locator('.copilot .mx-name-textAreaUserPrompt textarea, .mx-name-textAreaUserPrompt textarea').first();
  const before = await copilotText(page);
  await humanType(page, input, question);
  await page.waitForTimeout(Math.round(250 / cfg.speed));
  const sendBtn = page.locator('.copilot .mx-name-btnSendMessage, .mx-name-btnSendMessage').first();
  if (await sendBtn.isVisible({ timeout: 1500 }).catch(() => false)) await humanClick(page, sendBtn);
  else await input.press('Enter').catch(() => {});

  const t0 = Date.now();
  let last = '', stableSince = 0, answered = false;
  while (Date.now() - t0 < maxMs) {
    await page.waitForTimeout(700);
    const now = await copilotText(page);
    if (now.length > before.length + question.length + 8) {   // a real answer arrived
      answered = true;
      if (now === last) {
        if (!stableSince) stableSince = Date.now();
        if (Date.now() - stableSince > 1600) break;            // streaming settled
      } else { stableSince = 0; }
    } else if (!answered && Date.now() - t0 > 15000) {
      break;   // no reply even started in 15s → don't freeze the demo
    }
    last = now;
  }
  return last.slice(before.length);
}

// Approve the Copilot MoveItem / UpdateItem confirmation card if one appears.
// The write tools surface a confirmation card with an approve button; we look
// for common confirm affordances and click. Returns true if a card was approved.
async function approveConfirmCard(page, { maxMs = 12000 } = {}) {
  const selectors = [
    '.copilot .mx-name-btnConfirm', '.copilot .mx-name-btnApprove',
    '.copilot .mx-name-btnYes', '.mx-name-btnConfirmMove', '.mx-name-btnConfirm',
    '.copilot button:has-text("Confirm")', '.copilot button:has-text("Approve")',
    '.copilot button:has-text("Yes")', 
  ];
  const t0 = Date.now();
  while (Date.now() - t0 < maxMs) {
    for (const sel of selectors) {
      const btn = page.locator(sel).first();
      if (await btn.isVisible({ timeout: 400 }).catch(() => false)) {
        await humanClick(page, btn);
        await page.waitForTimeout(Math.round(1200 / cfg.speed));
        return true;
      }
    }
    await page.waitForTimeout(500);
  }
  return false;
}

async function gotoTarget(page, target) {
  if (target.nav) {
    const nav = page.locator(target.nav).first();
    if (await nav.isVisible({ timeout: 3000 }).catch(() => false)) {
      await humanClick(page, nav);
      await page.waitForTimeout(1500);
    }
  }
  if (target.ready) {
    await page.locator(target.ready).first().isVisible({ timeout: 6000 }).catch(() => false);
  }
}

// ── Capture ─────────────────────────────────────────────────────────────────
async function screenshotEl(page, selector, file) {
  const el = page.locator(selector).first();
  if (!(await el.count()) || !(await el.isVisible({ timeout: 2500 }).catch(() => false))) return false;
  await el.scrollIntoViewIfNeeded().catch(() => {});
  await page.waitForTimeout(Math.round(250 / cfg.speed));
  await el.screenshot({ path: file }).catch(async () => {
    await page.screenshot({ path: file, fullPage: false });
  });
  return true;
}

async function fullPageShot(page, file) {
  await page.screenshot({ path: file, fullPage: true }).catch(() => {});
}

async function computedStyles(page, checks) {
  return await page.evaluate((checks) => {
    return checks.map((c) => {
      const el = document.querySelector(c.sel);
      const rec = { sel: c.sel, found: !!el, values: {} };
      if (el) {
        const cs = getComputedStyle(el);
        for (const p of c.props) rec.values[p] = cs[p];
      }
      return rec;
    });
  }, checks);
}

// ── DB assertion — OQL through the M2EE admin API ────────────────────────────
// This project runs natively under Studio Pro, so `mxcli oql -p` would route
// through `docker compose exec` and fail. --direct talks HTTP to the admin API.
//
// Two shapes come back depending on mxcli version: {rows:[[v]]} (positional) or
// a bare array of column-keyed objects [{n: "30"}]. Normalise both to
// {rows:[[v]]} so callers only deal with one shape. Note OQL requires every
// select column to be aliased — `SELECT COUNT(*) AS n`, never `SELECT COUNT(*)`.
function oql(sql) {
  try {
    const out = execFileSync(cfg.mxcli, [
      'oql', '--direct',
      '--host', cfg.adminHost, '--port', String(cfg.adminPort), '--token', cfg.adminToken,
      '--json', sql,
    ], { cwd: cfg.root, encoding: 'utf8', timeout: 20000 });

    // mxcli prints a "Using project:" banner and a trailing "(n rows)" line
    // around the JSON — slice out the JSON body before parsing.
    const start = out.search(/[[{]/);
    if (start < 0) return null;
    let depth = 0, end = -1;
    for (let i = start; i < out.length; i++) {
      const c = out[i];
      if (c === '[' || c === '{') depth++;
      else if (c === ']' || c === '}') { depth--; if (depth === 0) { end = i + 1; break; } }
    }
    if (end < 0) return null;
    const parsed = JSON.parse(out.slice(start, end));

    if (Array.isArray(parsed)) {
      return { rows: parsed.map((r) => (r && typeof r === 'object' ? Object.values(r) : [r])) };
    }
    if (parsed && parsed.rows !== undefined) return parsed;
  } catch (_) {}
  return null;
}

// Convenience: first cell of the first row, or null.
function oqlScalar(sql) {
  const r = oql(sql);
  return r && r.rows && r.rows[0] !== undefined && r.rows[0][0] !== undefined
    ? String(r.rows[0][0]) : null;
}

// ── Reporter ────────────────────────────────────────────────────────────────
function makeReporter(suiteName) {
  const results = [];
  const pass = (id, description) => {
    console.log(`  ✓ ${id}: ${description}`);
    results.push({ id, description, status: 'pass' });
  };
  const fail = (id, description, detail) => {
    console.error(`  ✗ ${id}: ${description} — ${detail}`);
    results.push({ id, description, status: 'fail', detail });
  };
  const summary = () => {
    const p = results.filter((r) => r.status === 'pass').length;
    const f = results.filter((r) => r.status === 'fail').length;
    console.log(`\n${suiteName}: ${p} passed, ${f} failed`);
    return { suite: suiteName, passed: p, failed: f, results };
  };
  return { pass, fail, summary, results };
}

// ── Misc ────────────────────────────────────────────────────────────────────
function ensureDirs(...dirs) { for (const d of dirs) fs.mkdirSync(d, { recursive: true }); }

function parseTokens() {
  const tokens = {};
  try {
    const css = fs.readFileSync(cfg.dsCss, 'utf8');   // path from project.config
    const m = css.match(/:root\s*\{([^}]*)\}/s);
    if (m) for (const line of m[1].split(';')) {
      const kv = line.match(/\s*(--[a-zA-Z0-9-]+)\s*:\s*(.+)/);
      if (kv) tokens[kv[1]] = kv[2].trim();
    }
  } catch {}
  return tokens;
}

module.exports = {
  launchBrowser, launchBrowserAt, injectCursor, injectOqlOverlay, showOqlResult,
  humanMove, humanClick, humanType, humanTypeKeys, humanScroll,
  navTo, ensureSidebar, copilotText, askCopilot, approveConfirmCard,
  login, logout, assertIdentity, dismissModal, gotoTarget,
  screenshotEl, fullPageShot, computedStyles, oql, oqlScalar, makeReporter,
  ensureDirs, parseTokens, path, fs,
};
