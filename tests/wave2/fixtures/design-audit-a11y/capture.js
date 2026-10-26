// Capture axe-core's own result over a page, for test-design-audit-a11y-evidence.sh (#561).
//   NODE_PATH=<dir with axe-core and playwright> node capture.js page-datagrid.html axe-run-4.10.2.json
// Keeps what design-audit.js checkA11y() reads: violations with every node's target and full html.
const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const [pageFile, out] = process.argv.slice(2);
  const b = await chromium.launch(); const p = await b.newPage();
  await p.setContent(fs.readFileSync(pageFile, 'utf8'));
  await p.evaluate(fs.readFileSync(require.resolve('axe-core/axe.min.js'), 'utf8'));
  const res = await p.evaluate(async () => await axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa'] } }));
  const keep = r => ({ id: r.id, impact: r.impact, help: r.help, helpUrl: r.helpUrl,
    nodes: r.nodes.map(n => ({ target: n.target, html: n.html, impact: n.impact, failureSummary: n.failureSummary })) });
  fs.writeFileSync(out, JSON.stringify({ capturedWith: 'axe-core ' + require('axe-core/package.json').version + ' via Playwright chromium',
    violations: res.violations.map(keep), passes: res.passes.map(r => ({ id: r.id })), incomplete: res.incomplete.map(r => ({ id: r.id })) }, null, 1));
  await b.close();
})();
