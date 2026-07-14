'use strict';
// Enrichment summary — the business-facing counterpart to generate-report.js. Adapted from
// pipelines/java-angular for the OutSystems pipeline's FUNCTION-centric BRD schema
// (F{NNN}.brd.json: modules/actors/useCases/dataRequirements/businessRules/integrations,
// with an index.json carrying per-function summaries) instead of java-angular's
// module-centric one. Every number is derived from the BRD JSON, never hand-typed.
// The hero block is config-driven: set config.json → "project": { "title", "description", "techTags": [] }.
const fs = require('fs');
const path = require('path');

const CONFIG = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
const KB = CONFIG.knowledgeBaseDir || path.join(__dirname, 'knowledge-base');
const BRD_DIR = path.join(KB, 'brd');
const OUT = path.join(KB, 'enrichment-summary.html');

const PROJECT = CONFIG.project || {};
const HERO_TITLE = PROJECT.title || path.basename(path.dirname(KB));
const HERO_DESC = PROJECT.description ||
  'Business-facing summary of the enriched BRDs: functions, use cases, data requirements, business rules and integrations. Set config.json → "project" to replace this placeholder description.';
const TECH_TAGS = Array.isArray(PROJECT.techTags) ? PROJECT.techTags : [];

function esc(s) {
  if (s == null) return '';
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

let index = { functions: [] };
try { index = JSON.parse(fs.readFileSync(path.join(BRD_DIR, 'index.json'), 'utf8')); } catch (e) { /* optional */ }
const summaryById = new Map((index.functions || []).map(f => [f.id, f.summary]));

const brds = fs.readdirSync(BRD_DIR)
  .filter(f => f.endsWith('.brd.json'))
  .map(f => JSON.parse(fs.readFileSync(path.join(BRD_DIR, f), 'utf8')))
  .sort((a, b) => String(a.id).localeCompare(String(b.id)));

const allModules = new Set(brds.flatMap(b => b.modules || []));
const allActors  = new Set(brds.flatMap(b => (b.actors || []).map(a => typeof a === 'string' ? a : a.name || JSON.stringify(a))));
const totalUseCases   = brds.reduce((s, b) => s + (b.useCases || []).length, 0);
const totalDataReqs   = brds.reduce((s, b) => s + (b.dataRequirements || []).length, 0);
const totalRules      = brds.reduce((s, b) => s + (b.businessRules || []).length, 0);
const totalIntegrations = brds.reduce((s, b) => s + (b.integrations || []).length, 0);
const totalOpenQuestions = brds.reduce((s, b) => s + (b.openQuestions || []).length, 0);

const functionSections = brds.map(b => {
  const useCaseCards = (b.useCases || []).map(u => `
    <div class="usecase-card">
      <div class="usecase-header">
        <span class="mono">${esc(u.id)}</span> ${esc(u.title)}
        ${u.titleZh ? `<span class="zh">${esc(u.titleZh)}</span>` : ''}
      </div>
      ${(u.actors || []).length ? `<div class="usecase-field"><strong>Actors:</strong> ${u.actors.map(esc).join(', ')}</div>` : ''}
      ${(u.preconditions || []).length ? `<div class="usecase-field"><strong>Preconditions:</strong> ${u.preconditions.map(esc).join('; ')}</div>` : ''}
      ${(u.mainFlow || []).length ? `<div class="usecase-field"><strong>Main flow:</strong><ul>${u.mainFlow.map(s => `<li>${esc(s)}</li>`).join('')}</ul></div>` : ''}
      ${(u.postconditions || []).length ? `<div class="usecase-field"><strong>Postconditions:</strong> ${u.postconditions.map(esc).join('; ')}</div>` : ''}
      ${(u.screens || []).length ? `<div class="usecase-field"><strong>Screens:</strong> <span class="mono">${u.screens.map(esc).join(', ')}</span></div>` : ''}
    </div>`).join('');

  const ruleRows = (b.businessRules || []).map(r => `
    <tr>
      <td class="mono">${esc(r.id)}</td>
      <td><strong>${esc(r.title)}</strong><br>${esc(r.description)}</td>
      <td>${esc(r.enforcedBy || '—')}</td>
    </tr>`).join('');

  const dataRows = (b.dataRequirements || []).map(d => `
    <tr>
      <td class="mono">${esc(d.id)}</td>
      <td>${esc(d.title)}</td>
      <td class="mono">${esc(d.entity)}</td>
      <td class="mono">${(d.keyFields || []).map(esc).join(', ') || '—'}</td>
    </tr>`).join('');

  const integrationRows = (b.integrations || []).map(i => `
    <tr>
      <td class="mono">${esc(i.id)}</td>
      <td>${esc(i.system)}</td>
      <td>${esc(i.direction)}</td>
      <td>${esc(i.description)}</td>
    </tr>`).join('');

  const openQuestions = (b.openQuestions || []).map(q => `<li>${esc(q.question || q)}</li>`).join('');
  const summary = summaryById.get(b.id);

  return `
  <section class="module-section">
    <h2><span class="mono">${esc(b.id)}</span> ${esc(b.title)} ${b.titleZh ? `<span class="zh">${esc(b.titleZh)}</span>` : ''}</h2>
    ${summary ? `<p class="summary">${esc(summary)}</p>` : ''}
    <div class="chips">${(b.modules || []).map(m => `<span class="chip">${esc(m)}</span>`).join('')}</div>
    <div class="stat-row">
      <div class="stat"><div class="val">${(b.useCases || []).length}</div><div class="lbl">Use cases</div></div>
      <div class="stat"><div class="val">${(b.dataRequirements || []).length}</div><div class="lbl">Data reqs</div></div>
      <div class="stat"><div class="val">${(b.businessRules || []).length}</div><div class="lbl">Business rules</div></div>
      <div class="stat"><div class="val">${(b.integrations || []).length}</div><div class="lbl">Integrations</div></div>
    </div>

    <h3>Use cases</h3>
    ${useCaseCards || '<p class="empty">None</p>'}

    <h3>Business rules</h3>
    <table><thead><tr><th>ID</th><th>Rule</th><th>Enforced by</th></tr></thead>
    <tbody>${ruleRows || '<tr><td colspan="3" class="empty">None</td></tr>'}</tbody></table>

    <h3>Data requirements</h3>
    <table><thead><tr><th>ID</th><th>Title</th><th>Entity</th><th>Key fields</th></tr></thead>
    <tbody>${dataRows || '<tr><td colspan="4" class="empty">None</td></tr>'}</tbody></table>

    ${integrationRows ? `
    <h3>Integrations</h3>
    <table><thead><tr><th>ID</th><th>System</th><th>Direction</th><th>Description</th></tr></thead>
    <tbody>${integrationRows}</tbody></table>` : ''}

    ${openQuestions ? `
    <h3>Open questions for this function</h3>
    <ul class="open-questions">${openQuestions}</ul>` : ''}
  </section>`;
}).join('\n');

const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>${esc(HERO_TITLE)} — Enrichment Summary</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f8fafc; color: #1e293b; margin: 0; padding: 0 0 60px; }
  .hero { background: #1e293b; color: #f1f5f9; padding: 40px 32px; }
  .hero h1 { margin: 0 0 8px; font-size: 26px; }
  .hero p { color: #94a3b8; margin: 4px 0; max-width: 760px; line-height: 1.5; }
  .tech-tags { margin-top: 14px; }
  .tech-tags span { background: #334155; color: #e2e8f0; padding: 3px 10px; border-radius: 12px; font-size: 12px; margin-right: 6px; }
  .container { max-width: 980px; margin: 0 auto; padding: 32px; }
  h2 { font-size: 19px; margin: 0 0 6px; }
  h3 { font-size: 14px; color: #475569; text-transform: uppercase; letter-spacing: .03em; margin: 22px 0 10px; }
  .summary { color: #475569; margin: 0 0 10px; }
  .zh { color: #94a3b8; font-weight: 400; font-size: 0.85em; margin-left: 8px; }
  .chips { margin-bottom: 8px; }
  .chip { background: #eef2f7; border: 1px solid #e2e8f0; color: #334155; font-family: 'SF Mono', Consolas, monospace; font-size: 11px; padding: 2px 8px; border-radius: 10px; margin-right: 6px; }
  .stat-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 12px; margin: 24px 0 36px; }
  .stat-card { background: #fff; border: 1px solid #e2e8f0; border-radius: 10px; padding: 16px; text-align: center; }
  .stat-card .val { font-size: 26px; font-weight: 700; color: #1d4ed8; }
  .stat-card .lbl { font-size: 12px; color: #64748b; }
  .module-section { background: #fff; border: 1px solid #e2e8f0; border-radius: 12px; padding: 24px 28px; margin-bottom: 24px; }
  .stat-row { display: flex; gap: 24px; margin: 12px 0 6px; }
  .stat-row .stat { text-align: center; }
  .stat-row .val { font-size: 22px; font-weight: 700; color: #1d4ed8; }
  .stat-row .lbl { font-size: 11px; color: #64748b; text-transform: uppercase; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; margin-bottom: 8px; }
  th { background: #f1f5f9; text-align: left; padding: 8px 10px; font-size: 11px; color: #64748b; text-transform: uppercase; }
  td { padding: 7px 10px; border-top: 1px solid #f1f5f9; vertical-align: top; }
  .mono { font-family: 'SF Mono', Consolas, monospace; font-size: 12px; }
  .empty { color: #94a3b8; font-style: italic; }
  .usecase-card { border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px 16px; margin-bottom: 10px; }
  .usecase-header { font-weight: 600; margin-bottom: 8px; }
  .usecase-field { font-size: 13px; color: #334155; margin: 4px 0; }
  .usecase-field ul { margin: 4px 0 0 20px; padding: 0; }
  .usecase-field li { margin-bottom: 2px; }
  .open-questions li { margin-bottom: 8px; line-height: 1.5; }
  .open-questions { background: #fffbeb; border: 1px solid #fde68a; border-radius: 8px; padding: 14px 14px 14px 32px; }
</style>
</head>
<body>

<div class="hero">
  <h1>${esc(HERO_TITLE)} — Enrichment Summary</h1>
  <p>${esc(HERO_DESC)}</p>
  ${TECH_TAGS.length ? `<div class="tech-tags">${TECH_TAGS.map(t => `<span>${esc(t)}</span>`).join('')}</div>` : ''}
</div>

<div class="container">
  <div class="stat-grid">
    <div class="stat-card"><div class="val">${brds.length}</div><div class="lbl">Functions</div></div>
    <div class="stat-card"><div class="val">${allModules.size}</div><div class="lbl">Source modules</div></div>
    <div class="stat-card"><div class="val">${allActors.size}</div><div class="lbl">Actors</div></div>
    <div class="stat-card"><div class="val">${totalUseCases}</div><div class="lbl">Use cases</div></div>
    <div class="stat-card"><div class="val">${totalDataReqs}</div><div class="lbl">Data requirements</div></div>
    <div class="stat-card"><div class="val">${totalRules}</div><div class="lbl">Business rules</div></div>
    <div class="stat-card"><div class="val">${totalIntegrations}</div><div class="lbl">Integrations</div></div>
    ${totalOpenQuestions ? `<div class="stat-card"><div class="val">${totalOpenQuestions}</div><div class="lbl">Open questions</div></div>` : ''}
  </div>

  ${functionSections}
</div>

</body>
</html>`;

fs.writeFileSync(OUT, html, 'utf8');
console.log(`Enrichment summary written → ${OUT}`);
