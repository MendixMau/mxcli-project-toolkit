'use strict';
// Generic link simulator: a logging, throttling HTTP proxy with fault injection. Node, no dependencies.
//   node link-proxy.js --link name:listenPort:targetPort [--link ...] [--control 4900]
// Library: const { makeLink, startControl, client } = require('./link-proxy');
// Control API (JSON over HTTP, loopback only), per link <name>:
//   POST /ctl/<name>/profile {rttMs, upKbps, downKbps, lossPct}   0 = unlimited
//   POST /ctl/<name>/mode    {mode, count, method?, status?}
//        normal       pass through
//        down         every connection is destroyed on arrival
//        request-lost the next <count> requests are dropped before they reach the target
//        reply-lost   the next <count> requests reach the target, the reply is destroyed (sender cannot know)
//        refuse       the next <count> requests get <status> (default 503) without reaching the target
//   POST /ctl/<name>/tag {tag}   label for the log rows that follow
//   GET|DELETE /ctl/<name>/log   GET /ctl/<name>/state
// <method> optionally limits request-lost, reply-lost and refuse to one HTTP method.
// Model: connect (1 RTT, new client connection) + RTT/2 + bytes/upRate, target time, RTT/2 + bytes/downRate.
// Not modelled: TLS handshake, slow start, retransmission, jitter. Real links are slower on a cold connection.
const http = require('http');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const xfer = (bytes, kbps) => (kbps > 0 ? ((bytes * 8) / (kbps * 1000)) * 1000 : 0);
const readBody = async (s) => { const c = []; for await (const x of s) c.push(x); return Buffer.concat(c); };

function makeLink(name, listenPort, targetPort, host = '127.0.0.1') {
  const st = { rttMs: 0, upKbps: 0, downKbps: 0, lossPct: 0, mode: 'normal', count: 0, only: '', status: 503, tag: '', log: [] };
  const agent = new http.Agent({ keepAlive: true });
  // Consume one armed fault when the request matches; returns true if it applies to this request.
  const take = (m, method) => {
    if (st.mode !== m || st.count <= 0 || (st.only && st.only !== method)) return false;
    if (--st.count === 0) st.mode = 'normal';
    return true;
  };
  const srv = http.createServer(async (req, res) => {
    const t0 = Date.now(), sock = req.socket;
    const row = { t: new Date(t0).toISOString(), link: name, tag: st.tag, method: req.method, url: req.url, reqBytes: 0, respBytes: 0, status: null, ms: 0, outcome: 'ok' };
    const body = await readBody(req);
    row.reqBytes = req.method.length + req.url.length + 12 + req.rawHeaders.join('').length + req.rawHeaders.length * 2 + 2 + body.length;
    const finish = (outcome) => { row.outcome = outcome; row.ms = Date.now() - t0; st.log.push(row); };
    if (st.mode === 'down') { finish('link-down'); return sock.destroy(); }
    if (!sock._linkSeen) { sock._linkSeen = true; await sleep(st.rttMs); }
    await sleep(st.rttMs / 2 + xfer(row.reqBytes, st.upKbps));
    if (st.lossPct > 0 && Math.random() * 100 < st.lossPct) { finish('lost-random'); return sock.destroy(); }
    if (take('request-lost', req.method)) { finish('request-lost'); return sock.destroy(); }
    if (take('refuse', req.method)) { row.status = st.status; finish('refused'); res.writeHead(st.status, { 'content-length': 0 }); return res.end(); }
    const replyLost = take('reply-lost', req.method);
    const headers = { ...req.headers }; delete headers.connection;
    const up = http.request({ host, port: targetPort, method: req.method, path: req.url, headers, agent }, async (ur) => {
      const rb = await readBody(ur);
      row.status = ur.statusCode;
      row.respBytes = 15 + ur.rawHeaders.join('').length + ur.rawHeaders.length * 2 + 2 + rb.length;
      if (replyLost) { finish('reply-lost'); return sock.destroy(); }
      await sleep(st.rttMs / 2 + xfer(row.respBytes, st.downKbps));
      const h = { ...ur.headers }; delete h['transfer-encoding']; delete h.connection; h['content-length'] = rb.length;
      res.writeHead(ur.statusCode, h); res.end(rb); finish('ok');
    });
    up.on('error', () => { row.status = 502; finish('target-error'); sock.destroy(); });
    up.end(body);
  });
  srv.keepAliveTimeout = 60000;
  srv.on('clientError', (e, s) => s.destroy());
  return { name, st, srv, listenPort, listen: () => new Promise((r) => srv.listen(listenPort, host, r)) };
}

function startControl(links, port, host = '127.0.0.1') {
  const ctl = http.createServer(async (req, res) => {
    const send = (c, o) => { res.writeHead(c, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
    const m = /^\/ctl\/([\w-]+)\/(profile|mode|tag|log|state)$/.exec(req.url);
    if (!m || !links[m[1]]) return send(404, { error: 'unknown link or route' });
    const L = links[m[1]].st, raw = (await readBody(req)).toString();
    let b = {}; try { b = raw ? JSON.parse(raw) : {}; } catch { return send(400, { error: 'bad json' }); }
    if (m[2] === 'log') { if (req.method === 'DELETE') { L.log.length = 0; return send(200, { cleared: true }); } return send(200, L.log); }
    if (m[2] === 'profile') for (const k of ['rttMs', 'upKbps', 'downKbps', 'lossPct']) if (b[k] !== undefined) L[k] = +b[k];
    if (m[2] === 'mode') { L.mode = b.mode || 'normal'; L.count = +b.count || 0; L.only = (b.method || '').toUpperCase(); L.status = +b.status || 503; }
    if (m[2] === 'tag') L.tag = b.tag || '';
    const { log, ...rest } = L; send(200, { ...rest, logRows: log.length });
  });
  return new Promise((r) => ctl.listen(port, host, () => r(ctl)));
}

// Tiny client for tests: const link = client(4900, 'hub'); await link.mode('reply-lost', 1, 'POST');
const client = (port, name) => {
  const call = async (what, body, method) => (await fetch(`http://127.0.0.1:${port}/ctl/${name}/${what}`, { method: method || (body ? 'POST' : 'GET'), body: body ? JSON.stringify(body) : undefined })).json();
  return {
    profile: (p) => call('profile', p), mode: (mode, count = 0, method, status) => call('mode', { mode, count, method, status }),
    tag: (tag) => call('tag', { tag }), log: () => call('log'), clearLog: () => call('log', null, 'DELETE'), state: () => call('state'),
  };
};

module.exports = { makeLink, startControl, client };

if (require.main === module) {
  const a = process.argv.slice(2), links = {}; let control = 4900;
  for (let i = 0; i < a.length; i++) {
    if (a[i] === '--control') control = +a[++i];
    else if (a[i] === '--link') { const [n, lp, tp] = a[++i].split(':'); links[n] = makeLink(n, +lp, +tp); }
  }
  if (!Object.keys(links).length) { console.error('usage: node link-proxy.js --link name:listenPort:targetPort [--link ...] [--control 4900]'); process.exit(2); }
  Promise.all(Object.values(links).map((l) => l.listen())).then(() => startControl(links, control)).then(() => console.log(`link-proxy: ${Object.values(links).map((l) => `${l.name} :${l.listenPort}`).join(', ')}, control :${control}`));
}
