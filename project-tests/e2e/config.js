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
// `otherapp-mendix-1` — a DIFFERENT PROJECT's Mendix, serving a real login page
// on 200. Every rung of this harness would have run green or red against another
// project's software and reported it as ours. A dead port fails loudly; a live
// port belonging to someone else does not fail at all, which is far worse.
//
// test-stack-up.sh now records APP_OWNERSHIP: `verified` means the port is published
// by a container whose compose working_dir is THIS project (the one identity claim
// that cannot be true of two projects at once), or by a live `mxcli run --local` whose
// .mxcli/run-local.json sits beside THIS project's .mpr; `unverified` means a port scan found
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

// Where the test password came from, never the password itself (#278, #302 follow-up).
//   env                  — TEST_PASS (or its APP_PASS alias)
//   project.config.js    — a password the project set there (the template tells every
//                          project to put its real demo password in DEFAULT_PASS)
//   template placeholder — the value the shipped template carries, i.e. nobody set one
// Only the last is refused by journey-runner's preflight. Refusing every non-env password
// (as #302 first did) broke every project whose real password lives in project.config.js,
// because nothing in the toolkit loads an env file before verify-module runs the journeys.
const TEMPLATE_PASSWORDS = ['Demo2025!'];   // project.config.template.js DEFAULT_PASS
function passwordSource({ env = process.env, creds = CREDS } = {}) {
  if (env.TEST_PASS || env.APP_PASS) return 'env';
  if (TEMPLATE_PASSWORDS.includes(creds.pass)) return 'template placeholder';
  return 'project.config.js';
}

// ── M2EE admin credential: where it came from, never what it is ──────────────
// Every data rung, seed and outcome query goes through `mxcli oql --direct` with this
// token. It used to be `M2EE_ADMIN_PASS || '1'`: a literal default that silently differed
// from the app's real one. Field run 2026-10-12 (14 journeys): the default was wrong, every
// data rung got HTTP 403 and read INVALID, and the suite ran to the end anyway — the first
// pass was discarded. The workaround was reading the password out of the running app.
//
// Resolution, first hit wins. The SOURCE is recorded (cfg.adminSource) so a refusal can name
// where to fix it; the value itself is never printed:
//   1. M2EE_ADMIN_PASS env                  explicit operator setting, always wins
//   2. <mpr dir>/.mxcli/run-local.json      `mxcli run --local` handshake — adminPass and
//      adminPort of the app it serves, used only when its appPort is the port under test
//      (test-stack-up.sh reads pid/appPort from the same file and deliberately never copies
//      the password; reading it here, in-process, is the same "read the running app" fix)
//   3. <root>/.docker/.env                  M2EE_ADMIN_PASS / ADMIN_PORT, as `mxcli docker
//      init` writes them (fixture-manifest.sh and run-hub.sh read the same file)
//   4. the legacy guess '1'                 kept so a project that relied on it still runs,
//      but LABELLED: journey-runner's preflight names it when the admin API refuses it.
// M2EE_ADMIN_PORT env overrides the port from any source; otherwise the port comes from the
// same source as the password (they are a pair), falling back to runtime port + 10.
function readEnvFile(file) {
  const out = {};
  let txt;
  try { txt = fs.readFileSync(file, 'utf8'); } catch { return null; }
  for (const line of txt.split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (m) out[m[1]] = m[2].replace(/^(['"])(.*)\1$/, '$2');
  }
  return out;
}
function resolveAdmin({ env = process.env, root = ROOT, mprPath = null, appPort = null } = {}) {
  const fallbackPort = String(Number(appPort) + 10);
  const pick = (token, port, source) => ({
    token, port: env.M2EE_ADMIN_PORT || port || fallbackPort, source,
  });
  if (env.M2EE_ADMIN_PASS) return pick(env.M2EE_ADMIN_PASS, null, 'M2EE_ADMIN_PASS env');
  if (mprPath) {
    const dirs = [path.dirname(mprPath)];
    try { dirs.push(path.dirname(fs.realpathSync(mprPath))); } catch { /* no symlink target */ }
    for (const d of [...new Set(dirs)]) {
      const f = path.join(d, '.mxcli', 'run-local.json');
      let hs = null;
      try { hs = JSON.parse(fs.readFileSync(f, 'utf8')); } catch { continue; }
      if (hs && hs.adminPass && String(hs.appPort) === String(appPort)) {
        return pick(String(hs.adminPass), hs.adminPort ? String(hs.adminPort) : null,
                    `${path.relative(root, f) || f} (the run --local handshake for :${appPort})`);
      }
    }
  }
  const de = readEnvFile(path.join(root, '.docker', '.env'));
  if (de && de.M2EE_ADMIN_PASS) return pick(de.M2EE_ADMIN_PASS, de.ADMIN_PORT || null, '.docker/.env');
  return pick('1', null, "built-in guess '1' — no credential configured");
}
let MPR_PATH = null;
try { MPR_PATH = PROJ.mpr; } catch { /* reported where cfg.mpr is used */ }
const ADMIN = resolveAdmin({ mprPath: MPR_PATH, appPort: PORT });

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
  // Whether the test password came from the environment (TEST_PASS, or its APP_PASS alias),
  // and passSource (see passwordSource above). journey-runner's preflight refuses to log in on
  // the TEMPLATE PLACEHOLDER only (#278): a runner started without the project's env-loading
  // step submitted the template password, then the admin fallback, and locked two demo
  // accounts for ~5 min each. A password the project set in project.config.js is accepted.
  passFromEnv: !!(process.env.TEST_PASS || process.env.APP_PASS),
  passSource: passwordSource(),
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
  // Extra sign-out captions for monkey.js, ADDED to its multilingual default (#469): a RegExp
  // or regex string from project.config.js `signOutPattern`, or SIGN_OUT_PATTERN in the env.
  signOutPattern: process.env.SIGN_OUT_PATTERN || PROJ.signOutPattern || null,
  // This project runs natively under Studio Pro (no Docker), so `mxcli oql -p`
  // alone would try to route through `docker compose exec` and fail. --direct
  // connects straight to the M2EE admin API on the host instead.
  adminHost: process.env.M2EE_ADMIN_HOST || 'localhost',
  // Resolved by resolveAdmin() above. adminSource says where the token came from and is
  // safe to print; adminToken is never printed.
  adminPort: ADMIN.port,
  adminToken: ADMIN.token,
  adminSource: ADMIN.source,
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

module.exports = { cfg, NAV, TARGETS, resolveTarget, resolveAdmin, passwordSource, TEMPLATE_PASSWORDS };
