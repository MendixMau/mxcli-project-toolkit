const http = require('http'), fs = require('fs');
(async () => {
  const srv = http.createServer((q, s) => { s.setHeader('content-type','text/html');
    s.end('<div class="mx-name-ready">Order SO-1001 details</div><button class="mx-name-btnShip">Ship</button>'); });
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  process.env.APP_URL = `http://localhost:${srv.address().port}`;
  const R = require('./journey-runner.js'), H = require('./helpers.js');
  H.oqlScalar = () => 'SO-1001';   // seed value stand-in (no database here); everything else is the real runner
  const { browser, page } = await H.launchBrowser();
  await page.goto(process.env.APP_URL + '/');
  const j = { id: 'J-ORD-01', title: 'Ship order {{order}}', persona: 'Clerk', requirement: [],
    seeds: [{ name: 'order', sql: 'SELECT 1' }],
    steps: [ { name: 'Open {{order}}', actions: [], ui: { ready: '.mx-name-ready', textPresent: ['{{order}}'] } },
             { name: 'Ship {{order}} ({{ghost}})', actions: [{ do: 'click', widget: 'btnShip', label: 'Ship {{order}}' }], ui: { ready: '.mx-name-ready' } } ] };
  await R.runJourney(page, j);
  fs.writeFileSync(process.argv[2], JSON.stringify({ capturedAt: new Date().toISOString(), configuredUser: 'u', actualUser: 'u', usedFallback: false,
    baseUrl: process.env.APP_URL, device: 'desktop', positiveControl: false, results: R.results, walks: R.walks }, null, 2));
  fs.writeFileSync(process.argv[3], JSON.stringify(j, null, 2));
  await browser.close(); srv.close();
})().catch(e => { console.error(e); process.exit(1); });
