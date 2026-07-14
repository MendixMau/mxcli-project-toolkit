'use strict';
// Phase 4 enrichment summary — the business-facing counterpart to generate-report.js (which is
// the raw extraction/gap dashboard). Reads the enriched BRD JSON so every number here is
// derived from actual data, never hand-typed. Ported from pipelines/java-angular (same
// module-centric BRD schema). The hero block is config-driven, never hardcoded: set
// config.json → "project": { "title", "description", "techTags": [] }.
const fs = require('fs');
const path = require('path');

const CONFIG = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
const KB = CONFIG.knowledgeBaseDir || path.join(__dirname, 'knowledge-base');
const BRD_DIR = path.join(KB, 'brd');
const OUT = path.join(KB, 'enrichment-summary.html');

const PROJECT = CONFIG.project || {};
const HERO_TITLE = PROJECT.title || path.basename(path.dirname(KB));
const HERO_DESC = PROJECT.description ||
  'Business-facing summary of the enriched BRDs: modules, entities, use cases, hidden rules and open questions. Set config.json → "project" to replace this placeholder description.';
const TECH_TAGS = Array.isArray(PROJECT.techTags) ? PROJECT.techTags : [];

function esc(s) {
  if (s == null) return '';
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// Real enriched BRDs may omit any of these arrays — default them so one sparse module
// doesn't kill the whole report.
const ents = b => b.domainEntities || [];
const mfs  = b => b.microflows || [];
const pgs  = b => b.pages || [];
const ucs  = b => b.useCases || [];

const brds = fs.readdirSync(BRD_DIR)
  .filter(f => f.endsWith('.brd.json'))
  .map(f => JSON.parse(fs.readFileSync(path.join(BRD_DIR, f), 'utf8')))
  .sort((a, b) => a.module.localeCompare(b.module));

const totalEntities   = brds.reduce((s, b) => s + ents(b).length, 0);
const totalMicroflows = brds.reduce((s, b) => s + mfs(b).length, 0);
const totalPages      = brds.reduce((s, b) => s + pgs(b).length, 0);
const totalUseCases   = brds.reduce((s, b) => s + ucs(b).length, 0);
const reviewedUseCases = brds.reduce((s, b) => s + ucs(b).filter(u => u.reviewStatus === 'reviewed').length, 0);
const totalOpenQuestions = brds.reduce((s, b) => s + (b.openQuestions || []).length, 0);
const totalHiddenRules = brds.reduce((s, b) => s + mfs(b).reduce((n, m) => n + (m.hiddenRules || []).length, 0), 0);

function confColor(c) { return c === 'high' ? '#22c55e' : c === 'medium' ? '#f59e0b' : '#ef4444'; }
function confBadge(c) { return `<span style="background:${confColor(c)};color:#fff;padding:2px 10px;border-radius:12px;font-size:12px;font-weight:600">${esc(c)}</span>`; }

const moduleSections = brds.map(b => {
  const entityRows = ents(b).map(e => `
    <tr>
      <td class="mono">${esc(e.name)}</td>
      <td>${esc(e.mendixType)}</td>
      <td>${e.attributeCount}</td>
      <td>${(e.associations || []).map(a => esc(a.to)).join(', ') || '—'}</td>
      <td>${(e.businessRules || []).length}</td>
    </tr>`).join('');

  const hiddenRules = mfs(b).flatMap(m => (m.hiddenRules || []).map(hr => ({ ...hr, microflow: m.name })));
  const hiddenRulesRows = hiddenRules.map(hr => `
    <tr>
      <td class="mono">${esc(hr.microflow)}</td>
      <td>${esc(hr.rule)}</td>
      <td><span class="risk-${hr.risk}">${esc(hr.risk)}</span></td>
    </tr>`).join('');

  const pageByName = new Map(pgs(b).map(p => [p.name, p]));
  const useCaseCards = ucs(b).map(u => `
    <div class="usecase-card">
      <div class="usecase-header">
        <span class="mono">${esc(u.id)}</span> ${esc(u.title)}
        ${u.reviewStatus === 'reviewed' ? '<span class="tag-green">reviewed</span>' : '<span class="tag-yellow">pending review</span>'}
        ${pageByName.get(u.screen)?.hasConditionalStyling ? '<span class="tag-yellow">conditional styling — check for hidden rule</span>' : ''}
      </div>
      ${(u.actors || []).length ? `<div class="usecase-field"><strong>Actors:</strong> ${(u.actors || []).map(esc).join(', ')}</div>` : ''}
      ${(u.preconditions || []).length ? `<div class="usecase-field"><strong>Preconditions:</strong> ${(u.preconditions || []).map(esc).join('; ')}</div>` : ''}
      ${(u.mainFlow || []).length ? `<div class="usecase-field"><strong>Main flow:</strong><ul>${(u.mainFlow || []).map(s => `<li>${esc(s)}</li>`).join('')}</ul></div>` : ''}
      ${(u.postconditions || []).length ? `<div class="usecase-field"><strong>Postconditions:</strong> ${(u.postconditions || []).map(esc).join('; ')}</div>` : ''}
    </div>`).join('');

  const openQuestions = (b.openQuestions || []).map(q => `<li>${esc(q.question)}</li>`).join('');

  return `
  <section class="module-section">
    <h2>Module: ${esc(b.module)} ${confBadge(b.confidence)}</h2>
    <div class="stat-row">
      <div class="stat"><div class="val">${ents(b).length}</div><div class="lbl">Entities</div></div>
      <div class="stat"><div class="val">${mfs(b).length}</div><div class="lbl">Functions</div></div>
      <div class="stat"><div class="val">${pgs(b).length}</div><div class="lbl">Pages</div></div>
      <div class="stat"><div class="val">${ucs(b).length}</div><div class="lbl">Use cases</div></div>
    </div>

    <h3>Domain entities</h3>
    <table><thead><tr><th>Name</th><th>Type</th><th>Attributes</th><th>Associations</th><th>Business rules</th></tr></thead>
    <tbody>${entityRows || '<tr><td colspan="5" class="empty">None</td></tr>'}</tbody></table>

    ${hiddenRules.length ? `
    <h3>Hidden business rules found (not visible from the domain model alone)</h3>
    <table><thead><tr><th>Function</th><th>Rule</th><th>Risk</th></tr></thead>
    <tbody>${hiddenRulesRows}</tbody></table>` : ''}

    <h3>Use cases</h3>
    ${useCaseCards || '<p class="empty">None</p>'}

    ${openQuestions ? `
    <h3>Open questions for this module</h3>
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
  h2 { font-size: 19px; margin: 0 0 14px; }
  h3 { font-size: 14px; color: #475569; text-transform: uppercase; letter-spacing: .03em; margin: 22px 0 10px; }
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
  .tag-green { background: #dcfce7; color: #166534; font-size: 11px; padding: 2px 8px; border-radius: 10px; margin-left: 8px; }
  .tag-yellow { background: #fef9c3; color: #854d0e; font-size: 11px; padding: 2px 8px; border-radius: 10px; margin-left: 8px; }
  .risk-high { color: #b91c1c; font-weight: 600; }
  .risk-medium { color: #b45309; font-weight: 600; }
  .risk-low { color: #64748b; }
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
    <div class="stat-card"><div class="val">${brds.length}</div><div class="lbl">Modules</div></div>
    <div class="stat-card"><div class="val">${totalEntities}</div><div class="lbl">Domain entities</div></div>
    <div class="stat-card"><div class="val">${totalMicroflows}</div><div class="lbl">Functions</div></div>
    <div class="stat-card"><div class="val">${totalPages}</div><div class="lbl">Pages</div></div>
    <div class="stat-card"><div class="val">${reviewedUseCases}/${totalUseCases}</div><div class="lbl">Use cases reviewed</div></div>
    <div class="stat-card"><div class="val">${totalHiddenRules}</div><div class="lbl">Hidden rules found</div></div>
    <div class="stat-card"><div class="val">${totalOpenQuestions}</div><div class="lbl">Open questions</div></div>
  </div>

  ${moduleSections}
</div>

</body>
</html>`;

fs.writeFileSync(OUT, html, 'utf8');
console.log(`Enrichment summary written → ${OUT}`);
