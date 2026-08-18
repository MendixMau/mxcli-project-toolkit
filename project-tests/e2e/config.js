'use strict';
// ============================================================================
// E2E demo harness — configuration
// ----------------------------------------------------------------------------
// ENGINE. Carries no knowledge of which project it is running in: every
// project-specific value (credentials, nav captions, walkthrough targets, the
// .mpr) comes from ./project.config.js, which is the only file to edit when
// porting this harness.
// ============================================================================
const path = require('path');

const fs = require('fs');

const PROJ = require('./project.config');

const ROOT = PROJ.root;

// ── Port resolution: measured first, guessed last ────────────────────────────
// The app has bound 8080 (Docker), 8081 (SP Run Locally) and 8084 at different
// times. A spec pointed at a dead port does not report "unreachable" — it reports
// the feature as broken, which is the most expensive kind of false finding.
// `bin/test-stack-up.sh` is the only thing that PROVES which port answers, so it
// writes .claude/loop/stack.env and we read that. Precedence:
//   1. APP_PORT env             — explicit operator override, always wins
//   2. stack.env                — measured by the last test-stack-up run
//   3. project.config defaultPort — a guess, and labelled as one
//
// ── Ownership, and why a port alone is not enough ────────────────────────────
// MEASURED 2026-08-18: stack.env held APP_PORT=8080 for a day. :8080 was
// `poctiborbjj-mendix-1` — a DIFFERENT PROJECT's Mendix, serving a real login page
// on 200. Every rung of this harness would have run green or red against another
// project's software and reported it as ours. A dead port fails loudly; a live
// port belonging to someone else does not fail at all, which is far worse.
//
// test-stack-up.sh now records APP_OWNERSHIP: `verified` means the port is published
// by a container whose compose working_dir is THIS project (the one identity claim
// that cannot be true of two projects at once); `unverified` means a port scan found
// a Mendix and nothing more. We refuse `unverified` rather than warn about it —
// this whole harness exists because a warning on stderr is not a guard.
function resolveStack() {
  let port = null, ownership = 'unknown', source = 'guess';
  try {
    const txt = fs.readFileSync(path.join(ROOT, '.claude', 'loop', 'stack.env'), 'utf8');
    const p = txt.match(/^APP_PORT=(\d+)/m);
    const o = txt.match(/^APP_OWNERSHIP=(\w+)/m);
    if (p) { port = p[1]; source = 'stack.env'; }
    // A stack.env written before ownership was recorded has no marker. Treat the
    // absence as 'unknown', never as 'verified' — missing evidence is not evidence.
    if (o) ownership = o[1];
  } catch { /* not run yet — fall through to the guess */ }

  if (process.env.APP_PORT) {
    // An explicit override is an operator asserting ownership by hand. Honour it,
    // and record that it was asserted rather than measured.
    return { port: process.env.APP_PORT, ownership: 'asserted', source: 'APP_PORT env' };
  }
  if (port) return { port, ownership, source };
  // DEFECT FIXED 2026-08-18: this used to be a literal 8081 while page-audit.js's
  // own appStatus() fell back to 8084. One fallback, one place.
  return { port: PROJ.defaultPort, ownership: 'unknown', source: 'guess' };
}

const STACK = resolveStack();
if (STACK.ownership !== 'verified' && STACK.ownership !== 'asserted'
    && process.env.ALLOW_UNVERIFIED_APP !== '1') {
  console.error(
    `\n  REFUSING TO RUN — app ownership is "${STACK.ownership}" for :${STACK.port} (from ${STACK.source}).\n` +
    `  A Mendix may be answering there, but nothing proves it is THIS project's.\n` +
    `  On 2026-08-18 this exact path pointed at another project's app on :8080.\n\n` +
    `  Fix:  ./bin/test-stack-up.sh          (starts our stack and verifies ownership)\n` +
    `  Or:   APP_PORT=<port> ...             (assert it by hand, recorded as "asserted")\n` +
    `  Or:   ALLOW_UNVERIFIED_APP=1 ...      (proceed anyway; the report will say "unverified")\n`);
  process.exit(2);   // 2 = instrument fault, never 1 = finding. See report-schema.md.
}
const PORT = STACK.port;
// The M2EE admin API sits on runtime port + 10 (see adminPort below).

// TEST_USER/TEST_PASS with APP_USER/APP_PASS accepted as deprecated aliases —
// see the DEFECT note in project.config.js. Resolved in one place so this file
// and page-audit.js cannot end up running as two different identities.
const CREDS = PROJ.credentials();

const cfg = {
  root: ROOT,
  port: PORT,
  // Populates run.env.ownership / ownershipBasis in report.json. The schema has
  // carried these fields since 1.0 and nothing has ever written them, so every
  // report to date has been silent about which application it measured.
  ownership: STACK.ownership,
  ownershipBasis: STACK.source,
  baseUrl: process.env.APP_URL || `http://localhost:${PORT}`,
  // Preferred identity: the User-role demo account, so the walkthrough exercises
  // the app the way a real end user sees it rather than as an administrator.
  // NOT blocked — verified logging in as this user on 2026-08-03. A previous
  // comment here claimed the account was permanently blocked; that was a
  // transient 3-failed-attempt lockout, cleared by an app restart. If login
  // does fail, check Administration → Accounts before believing the password
  // is wrong: the login page shows the same generic message either way.
  user: CREDS.user,
  pass: CREDS.pass,
  // Last-resort identity so a credential problem degrades to a reported finding
  // instead of a zero-coverage run. Set FALLBACK_USER='' to disable.
  fallbackUser: CREDS.fallbackUser,
  fallbackPass: CREDS.fallbackPass,
  // HEADLESS by default. Verification runs are read by their report, not watched,
  // and a window that steals focus makes the machine unusable for the length of a
  // run. Opt in with HEADED=1 for the demo/watch-me mode this harness also serves.
  headed: process.env.HEADED === '1',
  // 'chromium' = Playwright's bundled build. BROWSER_CHANNEL=chrome uses the real
  // installed Google Chrome for higher-fidelity demo recordings.
  channel: process.env.BROWSER_CHANNEL || 'chromium',
  slowMo: parseInt(process.env.SLOWMO || '0', 10),
  viewport: { width: 1440, height: 900 },
  target: process.env.TARGET || 'full-app',
  speed: parseFloat(process.env.DEMO_SPEED || '4'),
  artifactsDir: path.join(__dirname, 'artifacts'),
  reportDir: path.join(__dirname, 'report'),
  dsCss: PROJ.dsCss,
  // `dsHtml` used to sit here (design/design-system.html). Nothing in the repo
  // ever read it — deleted 2026-08-18 rather than carried into project.config.
  mpr: PROJ.mpr,
  // The mxcli binary, so an engine file never hardcodes './mxcli'.
  mxcli: PROJ.mxcli,
  // Post-login readiness selectors. The engine's own default is the two generic
  // Mendix ones; a project adds its own via project.config (the phone layout of
  // this app has no nav tree, so '.mx-navigationtree, .mx-page' alone is not
  // enough to prove it routed).
  readySelectors: PROJ.readySelectors || ['.mx-navigationtree', '.mx-page'],
  // This project runs natively under Studio Pro (no Docker), so `mxcli oql -p`
  // alone would try to route through `docker compose exec` and fail. --direct
  // connects straight to the M2EE admin API on the host instead.
  adminHost: process.env.M2EE_ADMIN_HOST || 'localhost',
  adminPort: process.env.M2EE_ADMIN_PORT || String(Number(PORT) + 10),
  adminToken: process.env.M2EE_ADMIN_PASS || '1',
};

// ── Navigation captions and walkthrough targets ──────────────────────────────
// Both are statements about THIS model (menu captions, widget names, domain
// entities), so both live in project.config.js. Re-exported here unchanged so
// every existing `require('./config')` keeps working.
const NAV = PROJ.NAV;
const TARGETS = PROJ.TARGETS;

function resolveTarget() {
  const t = TARGETS[cfg.target];
  if (!t) throw new Error(`Unknown TARGET "${cfg.target}" (expected: ${Object.keys(TARGETS).join(', ')})`);
  return t;
}

module.exports = { cfg, NAV, TARGETS, resolveTarget };
