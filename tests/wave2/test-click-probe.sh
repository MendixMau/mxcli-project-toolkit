#!/usr/bin/env bash
# Usage: bash test-click-probe.sh [path-to-click-probe.js]
#
# Fixture for project-tests/e2e/click-probe.js, the advisory click-and-overflow probe.
#
# Two kinds of evidence, kept apart on purpose:
#  1. PARSER assertions on CAPTURED output (tests/wave2/fixtures/click-probe/, provenance in its
#     PROVENANCE.md): the probe's first version run on a toolkit-built demo app, clean and with
#     planted defects, 2026-11-16. The shipped viewFindings/dedupe/denominator code reads those
#     records and must reproduce what that run found: 0 findings on the clean app, and on the
#     seeded app "Show meaning" and "Next" covered by promoStrip plus /p/team scrolling sideways.
#  2. BEHAVIOUR in a real headless Chromium against small static pages served on localhost behind a
#     stand-in sign-in (SKIPs, and says so, without a Playwright browser): a clean page, a covered
#     button, a 393 px bar at 390 (and none at 1280), disabled/hidden controls ignored, nothing
#     measurable -> exit 4 never 0, app down, wrong password, template-placeholder credentials,
#     accepted list with and without a reason (single tree and the two-tree app/ layout), --json.
# The stand-in pages are hand-written HTML on purpose: they are the INPUT whose defects are planted
# here; what the probe makes of them is asserted, and part 1 is what ties the parser to real output.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/click-probe.js"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E="$(cd "$(dirname "$SUT")" && pwd)"
FIX="$HERE/fixtures/click-probe"
CFG="$E2E/project.config.template.js"
[ -f "$CFG" ] || CFG="$HERE/../../project-tests/e2e/project.config.template.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

# ── 1. parser on captured output ────────────────────────────────────────────────────────────────
PARSE="$(CP="$SUT" FIX="$FIX" node -e '
const P = require(process.env.CP), fs = require("fs");
const rd = f => JSON.parse(fs.readFileSync(process.env.FIX + "/" + f, "utf8"));
const clean = rd("stageA-clean.json"), seeded = rd("stageA-seeded.json");
const all = v => P.dedupeFindings(v.flatMap(P.viewFindings));
const personaPages = v => { const o = {}; for (const r of v) o[r.persona] = new Set(v.filter(x => x.persona === r.persona).map(x => x.landed)).size; return o; };
console.log("CLEAN " + JSON.stringify(all(clean).length));
console.log("SEEDED " + JSON.stringify(all(seeded).map(f => P.findingText(f) + " @" + f.width + " by " + f.personas.join("+"))));
console.log("DEN " + P.denominator(clean, { learner1: 4, trainer1: 6 }).text);
console.log("NAMES " + JSON.stringify([P.mxName("btn mx-button mx-name-btnFlip btn-primary"), P.mxName("DIV.mx-name-promoStrip"), P.mxName("plain")]));
const A = P.parseAccepted("# c\nclick\t/p/a\tbtn\tbecause\nclick\t/p/a\tbtn2\t\nsideways\t/p/b\n\nbogus\t/p/c\tx\tr\n");
console.log("ACC " + JSON.stringify([A.entries.length, A.problems.map(p => p.line)]));
' 2>&1)"
get() { printf '%s\n' "$PARSE" | sed -n "s/^$1 //p"; }
[ "$(get CLEAN)" = "0" ] && ok "captured CLEAN app (20 page-views, 232 controls): 0 findings" || bad "clean capture" "$(get CLEAN)"
WANT='["click does not land: /p/flashcards btnFlip \"Show meaning\" covered by promoStrip @1280 by learner1+trainer1","click does not land: /p/flashcards btnNextCard \"Next\" covered by promoStrip @1280 by learner1+trainer1","click does not land: /p/flashcards btnFlip \"Show meaning\" covered by promoStrip @390 by learner1+trainer1","click does not land: /p/flashcards btnNextCard \"Next\" covered by promoStrip @390 by learner1+trainer1","page scrolls sideways at 390: /p/team, widest element unknown, 17 px over @390 by learner1+trainer1"]'
[ "$(get SEEDED)" = "$WANT" ] && ok "captured SEEDED app: both covered buttons named with the covering element, /p/team 17 px sideways at 390 only, same defect seen by two personas = one finding" || bad "seeded capture" "$(get SEEDED)"
[ "$(get DEN)" = "20 page-views (learner1 4 pages, trainer1 6 pages; x 2 widths), 232 controls checked, 0 skipped (hidden, disabled or off-screen)" ] && ok "denominator line states page-views, personas, widths, controls checked" || bad "denominator" "$(get DEN)"
[ "$(get NAMES)" = '["btnFlip","promoStrip",""]' ] && ok "mx-name is read from a class string and from TAG.class" || bad "mxName" "$(get NAMES)"
[ "$(get ACC)" = "[1,[3,4,6]]" ] && ok "accepted list: 1 valid line; a line with no reason, a short line and an unknown kind are reported, not accepted" || bad "parseAccepted" "$(get ACC)"

# ── 2. behaviour against local pages ────────────────────────────────────────────────────────────
WORK="$(mktemp -d "${TMPDIR:-/tmp}/click-probe.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mk_tree() {  # mk_tree <dir-with-the-tests/e2e-tree> <dir-holding-the-.mpr>
  mkdir -p "$1/tests/e2e" "$2"; : > "$2/Fixture.mpr"
  cp "$SUT" "$E2E/helpers.js" "$E2E/settle.js" "$E2E/config.js" "$1/tests/e2e/"
  cp "$CFG" "$1/tests/e2e/project.config.js"
}
mk_tree "$WORK/one" "$WORK/one"
mk_tree "$WORK/two" "$WORK/two/app"
mk_tree "$WORK/three" "$WORK/three"
mkdir -p "$WORK/three/.claude/loop" "$WORK/two/.claude/loop"
printf '# kind\tpage\telement\treason\nclick\t/p/covered\tbtnGo\tthe promo strip is meant to sit there until dismissed\nsideways\t/p/bar\twideBar\tdesktop-only bar, phone layout tracked separately\nclick\t/p/gone\tbtnOld\tpage was removed\n' > "$WORK/two/.claude/loop/click-probe-accepted.tsv"
printf 'click\t/p/covered\tbtnGo\t\nsideways\t/p/bar\twideBar\tdesktop-only bar\n' > "$WORK/three/.claude/loop/click-probe-accepted.tsv"

DRIVER="$WORK/driver.js"
cat > "$DRIVER" <<'JSEOF'
const http = require('http'), { spawn } = require('child_process');
const root = process.argv[2], two = process.argv[3], three = process.argv[4];
const nav = '<div class="mx-navigationtree" style="position:sticky;top:0;background:#fff;margin:0">' +
  '<a href="/p/home">Home</a> <a href="/p/covered">Covered</a> <a href="/p/bar">Bar</a> <a href="/p/ignored">Ignored</a></div>';
const page = (body) => '<!doctype html><html><body style="margin:0"><div class="mx-page">' + nav + body + '</div></body></html>';
const PAGES = {
  '/p/home': page('<button class="mx-name-btnOk">OK</button> <a href="/p/home" class="mx-name-lnkSelf">Refresh</a>'),
  '/p/covered': page('<div style="position:relative;width:200px;height:60px"><button class="mx-name-btnGo" style="width:200px;height:60px">Go</button>' +
    '<div class="mx-name-promoStrip" style="position:absolute;left:0;top:0;width:200px;height:60px;opacity:0"></div></div>'),
  '/p/bar': page('<div class="mx-name-wideBar" style="width:393px;height:30px;background:#ccc">filter</div><button class="mx-name-btnApply">Apply</button>'),
  '/p/ignored': page('<button class="mx-name-btnFine">Fine</button><button disabled>Off</button><button aria-disabled="true">Off2</button>' +
    '<button style="display:none">Hidden</button><button style="visibility:hidden">Invisible</button>' +
    '<button style="position:absolute;left:-500px;top:100px">Drawer</button><ul style="display:none"><li><a href="/p/home">menu</a></li></ul>'),
  '/p/blank': '<!doctype html><html><body><div class="mx-page">nothing to click here</div></body></html>',
};
const USERS = { alice: ['pw', '/p/home'], bob: ['pw', '/p/home'], dave: ['pw', '/p/blank'] };
const srv = http.createServer((q, s) => {
  const ck = /sid=(\w+)/.exec(q.headers.cookie || '');
  if (q.method === 'POST' && q.url === '/auth') {
    let b = ''; q.on('data', d => b += d); q.on('end', () => {
      const { u, p } = JSON.parse(b || '{}'); const rec = USERS[u];
      if (rec && rec[0] === p) { s.setHeader('set-cookie', 'sid=' + u + '; path=/'); s.end(JSON.stringify({ ok: true, to: rec[1] })); }
      else s.end(JSON.stringify({ ok: false }));
    }); return;
  }
  if (q.url === '/' && !ck) {
    s.setHeader('content-type', 'text/html');
    s.end('<html><body><input id="usernameInput" type="text"><input id="passwordInput" type="password"><button id="loginButton">Sign in</button><div class="login-message"></div>' +
      '<script>loginButton.onclick=async()=>{const r=await(await fetch("/auth",{method:"POST",body:JSON.stringify({u:usernameInput.value,p:passwordInput.value})})).json();' +
      'if(r.ok)location.href=r.to;else document.querySelector(".login-message").textContent="The username or password is incorrect"}</script></body></html>');
    return;
  }
  if (q.url === '/') { s.statusCode = 302; s.setHeader('location', USERS[ck[1]][1]); s.end(); return; }
  const pg = PAGES[q.url.split('?')[0]];
  s.setHeader('content-type', 'text/html'); if (!pg) { s.statusCode = 404; s.end('no'); } else s.end(pg);
});
const only = (process.env.CP_CASES || '').split(',').filter(Boolean);
const run = (name, cwd, args, env) => new Promise((res) => {
  if (only.length && !only.includes(name)) return res();
  const p = spawn('node', ['click-probe.js', ...args], { cwd: cwd + '/tests/e2e', env: { ...process.env, FALLBACK_USER: '', ...env } });
  let o = '', e = ''; p.stdout.on('data', d => o += d); p.stderr.on('data', d => e += d);
  const t0 = Date.now();
  p.on('close', (code) => { console.log('CASE ' + name + ' ' + JSON.stringify({ code, out: o, err: e, sec: Math.round((Date.now() - t0) / 100) / 10 })); res(); });
});
(async () => {
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  const port = String(srv.address().port);
  try { require('playwright').chromium.executablePath(); } catch (e) { console.log('SKIPB ' + e.message.split('\n')[0]); srv.close(); return; }
  const base = { APP_PORT: port, TEST_USER: 'alice', TEST_PASS: 'pw', ROLE_REQUESTER_USER: 'bob', ROLE_REQUESTER_PASS: 'pw', ROLE_APPROVER_USER: 'carol', ROLE_APPROVER_PASS: 'wrong' };
  await run('full-json', root, ['--json'], base);
  await run('clean', root, ['--pages', '/p/home,/p/ignored'], { ...base, ROLE_APPROVER_USER: 'alice', ROLE_REQUESTER_USER: 'alice' });
  await run('noreason', three, ['--pages', '/p/covered,/p/bar'], { ...base, ROLE_APPROVER_USER: 'alice', ROLE_REQUESTER_USER: 'alice' });
  await run('accepted-two-tree', two, ['--pages', '/p/covered,/p/bar'], { ...base, ROLE_APPROVER_USER: 'alice', ROLE_REQUESTER_USER: 'alice' });
  await run('nothing', root, [], { ...base, TEST_USER: 'dave', ROLE_APPROVER_USER: 'dave', ROLE_REQUESTER_USER: 'dave' });
  await run('app-down', root, [], { ...base, APP_PORT: '1' });
  await run('bad-login', root, [], { ...base, TEST_PASS: 'nope' });
  await run('placeholder', root, [], { ...base, TEST_PASS: '' });
  await run('usage', root, ['--frobnicate'], base);
  srv.close();
})();
JSEOF
OUT="$(cd "$WORK" && timeout 400 node "$DRIVER" "$WORK/one" "$WORK/two" "$WORK/three" 2>&1)"
[ -n "${CP_DEBUG:-}" ] && printf '%s\n' "$OUT" > "$CP_DEBUG"
if printf '%s\n' "$OUT" | grep -q '^SKIPB'; then
  echo "  skip — no Playwright browser here ($(printf '%s\n' "$OUT" | sed -n 's/^SKIPB //p'))"
else
  J() { printf '%s\n' "$OUT" | sed -n "s/^CASE $1 //p"; }   # one JSON line per case
  Q() { J "$1" | node -e 'const r=JSON.parse(require("fs").readFileSync(0,"utf8")); const f=new Function("r","return "+process.argv[1]); console.log(JSON.stringify(f(r)))' "$2" 2>&1; }

  # full run, --json: 2 personas probed, the third (wrong password) reported not probed
  R='(()=>{const j=JSON.parse(r.out);return [r.code,j.verdict,j.findings.map(f=>f.kind+"|"+f.page+"|"+f.width+"|"+f.widget+"|"+(f.coveredBy||f.over)).sort(),j.counts.personas,j.skippedPersonas.map(s=>s.persona),r.err.split("\n").filter(l=>l.startsWith("MXTK-RESULT")).length]})()'
  [ "$(Q full-json "$R")" = '[1,"findings",["click|/p/covered|1280|btnGo|promoStrip","click|/p/covered|390|btnGo|promoStrip","sideways|/p/bar|390|wideBar|3"],2,["carol"],1]' ] \
    && ok "covered button names both elements (btnGo, promoStrip) at 1280 and 390; the 393 px bar overflows at 390 only (3 px = 393 - 390), widest element wideBar; clean/ignored pages add nothing; an unusable persona (wrong password) is reported as skipped, not hidden, and the login helper's own console noise cannot break the JSON on stdout; --json puts the RESULT line on stderr" \
    || bad "full run" "$(Q full-json "$R")"
  R='(()=>{const j=JSON.parse(r.out);const h=j.views.filter(v=>v.page==="/p/ignored");return [h.length,h.every(v=>v.skipped.hidden>=3&&v.skipped.disabled>=2&&v.skipped.offscreen>=1),j.views.filter(v=>v.page==="/p/home").every(v=>v.checked===6)]})()'
  [ "$(Q full-json "$R")" = '[4,true,true]' ] && ok "disabled, aria-disabled, display:none, visibility:hidden, closed-dropdown and off-canvas controls are skipped AND counted; sticky nav + links on the clean page all land (6 of 6)" || bad "ignored controls" "$(Q full-json "$R")"
  R='(()=>{const j=JSON.parse(r.out);return j.denominator})()'
  case "$(Q full-json "$R")" in *"16 page-views"*"controls checked"*) ok "denominator in --json: $(Q full-json "$R")" ;; *) bad "denominator" "$(Q full-json "$R")" ;; esac

  # human output on a clean run: RESULT line before the closing lines, exit 0
  R='[r.code,r.out.split("\n").findIndex(l=>l.startsWith("MXTK-RESULT click-probe verdict=clean findings=0 accepted=0 pages=4 controls="))>=0,r.out.split("\n").findIndex(l=>l.startsWith("MXTK-RESULT"))<r.out.split("\n").findIndex(l=>l.startsWith("denominator:")),/clean over that denominator/.test(r.out)]'
  [ "$(Q clean "$R")" = '[0,true,true,true]' ] && ok "clean pages: exit 0, MXTK-RESULT line (pages=4 = 2 pages x 2 widths) printed before the denominator line" || bad "clean run" "$(Q clean "$R")"

  # accepted list: no reason -> still a finding, line reported; a reason -> accepted
  R='[r.code,/FINDING click does not land: \/p\/covered btnGo "Go" covered by promoStrip/.test(r.out),/accepted list line 1: no reason/.test(r.out),/accepted page scrolls sideways at 390: \/p\/bar, widest element wideBar, 3 px over - desktop-only bar/.test(r.out)]'
  [ "$(Q noreason "$R")" = '[1,true,true,true]' ] && ok "accepted line WITHOUT a reason is ignored and reported (finding stays, exit 1); the line with a reason is accepted and printed with it" || bad "accepted, no reason" "$(Q noreason "$R")"
  R='[r.code,/MXTK-RESULT click-probe verdict=clean findings=0 accepted=3 /.test(r.out),/stale.*click \/p\/gone btnOld/.test(r.out)]'
  [ "$(Q accepted-two-tree "$R")" = '[0,true,true]' ] && ok "two-tree layout (.mpr under app/, list at the parent's .claude/loop): the three findings (one click defect at two widths, one overflow) accepted with reasons, exit 0, an entry matching nothing is named stale" || bad "accepted, two-tree" "$(Q accepted-two-tree "$R")"

  # could not run: exit 4, never 0, and a RESULT line that says so
  R='[r.code,/MXTK-RESULT click-probe verdict=could-not-run /.test(r.out),/exit=4/.test(r.out),/COULD NOT RUN - (.*)/.exec(r.err)&&/COULD NOT RUN - (.*)/.exec(r.err)[1].slice(0,39)]'
  [ "$(Q nothing "$R")" = '[4,true,true,"zero controls checked on 2 page-view(s)"]' ] && ok "a landing page with nothing to click and no navigation: exit 4 (zero controls over 2 page-views), not 0" || bad "nothing reachable" "$(Q nothing "$R")"
  [ "$(Q app-down "$R")" = '[4,true,true,"app not reachable at http://localhost:1"]' ] && ok "app not reachable: exit 4" || bad "app down" "$(Q app-down "$R")"
  R='[r.code,/COULD NOT RUN - the configured persona could not be probed: login as "alice" failed/.test(r.err)]'
  [ "$(Q bad-login "$R")" = '[4,true]' ] && ok "login failed for the configured persona: exit 4 (no retry of a rejected password)" || bad "bad login" "$(Q bad-login "$R")"
  R='[r.code,/template placeholder/.test(r.err)]'
  [ "$(Q placeholder "$R")" = '[4,true]' ] && ok "template-placeholder credentials: exit 4 before any login (no lockout)" || bad "placeholder" "$(Q placeholder "$R")"
  R='[r.code,/unknown or incomplete argument "--frobnicate"/.test(r.err)]'
  [ "$(Q usage "$R")" = '[2,true]' ] && ok "unknown flag: exit 2" || bad "usage" "$(Q usage "$R")"
  echo "  time — $(printf '%s\n' "$OUT" | sed -n 's/^CASE \([a-z-]*\) .*"sec":\([0-9.]*\)}$/\1 \2s/p' | tr '\n' ' ')"
fi

echo
echo "SCORE: $PASS/$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
