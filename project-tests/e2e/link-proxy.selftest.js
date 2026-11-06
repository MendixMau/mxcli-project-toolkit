'use strict';
// Self-test for link-proxy.js and exactly-once.js. Random free ports, no app needed. Run: node link-proxy.selftest.js
const http = require('http');
const { makeLink, startControl, client } = require('./link-proxy');
const { assertExactlyOnce } = require('./exactly-once');
let fails = 0;
const check = (n, ok, d = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${n}${d ? '  [' + d + ']' : ''}`); if (!ok) fails++; };
const free = () => new Promise((r) => { const s = http.createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => r(p)); }); });
(async () => {
  const received = [];                      // the "receiver": records every request id it actually processed
  const target = http.createServer((req, res) => { received.push(req.headers['idempotency-key']); res.end('ok'); });
  const tp = await free(); await new Promise((r) => target.listen(tp, '127.0.0.1', r));
  const lp = await free(), cp = await free();
  const link = makeLink('t', lp, tp); await link.listen();
  const ctl = await startControl({ t: link }, cp);
  const c = client(cp, 't');
  const send = (id) => fetch(`http://127.0.0.1:${lp}/x`, { method: 'POST', headers: { 'idempotency-key': id, connection: 'close' }, body: 'p' }).then((r) => r.status, () => 'error');

  check('normal passes through', (await send('a')) === 200);
  await c.mode('refuse', 1, 'POST', 429);
  check('refuse answers with status, target not reached', (await send('b')) === 429 && !received.includes('b'));
  await c.mode('request-lost', 1);
  check('request-lost: sender sees an error, target not reached', (await send('c')) === 'error' && !received.includes('c'));
  await c.mode('reply-lost', 1);
  check('reply-lost: sender sees an error, target DID process it', (await send('d')) === 'error' && received.includes('d'));
  check('fault is consumed after count', (await send('e')) === 200);
  await c.profile({ rttMs: 120 }); const t0 = Date.now(); await send('f');
  check('latency profile slows the call', Date.now() - t0 >= 150, `${Date.now() - t0} ms`);
  await c.profile({ rttMs: 0 });
  await c.mode('down'); check('down destroys connections', (await send('g')) === 'error'); await c.mode('normal');
  const log = await c.log();
  check('log records outcomes', ['refused', 'request-lost', 'reply-lost', 'link-down'].every((o) => log.some((r) => r.outcome === o)));

  await send('d');                          // client retry after the lost reply: a receiver without dedup sees d twice
  const r1 = assertExactlyOnce(received, ['a', 'd', 'e', 'f']);
  check('helper flags the redelivery of d', !r1.ok && r1.duplicates.some((x) => x.id === 'd' && x.n === 2), r1.message);
  const r2 = assertExactlyOnce([...new Set(received)], ['a', 'd', 'e', 'f']);
  check('helper passes when deduplicated', r2.ok, r2.message);
  check('helper flags missing', assertExactlyOnce(['a'], ['a', 'z']).missing[0] === 'z');

  ctl.close(); link.srv.close(); target.close(); process.exit(fails ? 1 : 0);
})();
