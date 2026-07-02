'use strict';
const fs   = require('fs');
const path = require('path');

const CONFIG = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
const KB  = CONFIG.knowledgeBaseDir || path.join(__dirname, 'knowledge-base');
const OUT = path.join(KB, 'extraction-report.html');

function readJson(name) {
  try { return JSON.parse(fs.readFileSync(path.join(KB, name), 'utf8')); }
  catch (_) { return []; }
}

// ── Load KB ──────────────────────────────────────────────────────────────────
const entities    = readJson('entities.json');
const statics     = readJson('staticEntities.json');
const logics      = readJson('logics.json');
const screens     = readJson('screens.json');
const webBlocks   = readJson('webBlocks.json');
const structures  = readJson('structures.json');
const timers      = readJson('timers.json');
const serviceApis = readJson('serviceApis.json');
const extEntities = readJson('extEntities.json');
const webFlows    = readJson('webFlows.json');
const roles       = readJson('roles.json');

// ── Load BRD JSONs ────────────────────────────────────────────────────────────
const BRD_DIR = path.join(KB, 'brd');
const brdByModule = {};
if (fs.existsSync(BRD_DIR)) {
  for (const f of fs.readdirSync(BRD_DIR).filter(n => n.endsWith('.brd.json'))) {
    try {
      const brd = JSON.parse(fs.readFileSync(path.join(BRD_DIR, f), 'utf8'));
      brdByModule[brd.module] = brd;
    } catch(_) {}
  }
}

// ── Group by module ───────────────────────────────────────────────────────────
const modules = {};
function bucket(items, category) {
  for (const item of items) {
    const m = item.module || item.inferredModule || '(unknown)';
    if (!modules[m]) modules[m] = {
      entities: [], statics: [], logics: [], screens: [], webBlocks: [],
      structures: [], timers: [], serviceApis: [], extEntities: [], webFlows: [], roles: [],
      gapCount: 0, linkCount: 0,
    };
    modules[m][category].push(item);
    modules[m].gapCount  += (item._gaps  || []).length;
    modules[m].linkCount += (item._links || []).length;
  }
}
bucket(entities,    'entities');
bucket(statics,     'statics');
bucket(logics,      'logics');
bucket(screens,     'screens');
bucket(webBlocks,   'webBlocks');
bucket(structures,  'structures');
bucket(timers,      'timers');
bucket(serviceApis, 'serviceApis');
bucket(extEntities, 'extEntities');
bucket(webFlows,    'webFlows');
bucket(roles,       'roles');

const moduleNames = Object.keys(modules).sort();

// ── Stats ─────────────────────────────────────────────────────────────────────
const totalItems   = entities.length + statics.length + logics.length + screens.length +
                     webBlocks.length + structures.length + timers.length +
                     serviceApis.length + extEntities.length;
const totalGaps    = [...Object.values(modules)].reduce((s, m) => s + m.gapCount,  0);
const totalLinks   = [...Object.values(modules)].reduce((s, m) => s + m.linkCount, 0);
const coveragePct  = totalGaps === 0 ? 100 :
  Math.round((totalLinks / (totalLinks + totalGaps)) * 100);

// ── BRD stats ─────────────────────────────────────────────────────────────────
const brdModules   = Object.values(brdByModule);
const totalBrdFiles      = brdModules.length;
const totalUseCaseScaffolds = brdModules.reduce((s, b) => s + (b.summary ? b.summary.useCaseCount || 0 : 0), 0);
const totalBrdOpenGaps   = brdModules.reduce((s, b) => s + (b.summary ? b.summary.openGapCount  || 0 : 0), 0);

function confidence(mod) {
  if (mod.gapCount === 0)  return 'high';
  if (mod.gapCount <= 3)   return 'medium';
  return 'low';
}
function confColor(c) {
  return c === 'high' ? '#22c55e' : c === 'medium' ? '#f59e0b' : '#ef4444';
}
function confBadge(c) {
  const col = confColor(c);
  return `<span style="background:${col};color:#fff;padding:2px 8px;border-radius:12px;font-size:11px;font-weight:600">${c}</span>`;
}
function logicKindLabel(k) {
  return { action:'Microflow', clientAction:'Nanoflow', screenAction:'Nanoflow',
           dataAction:'DataAction', process:'BPT Process', dataScreenAction:'DataScreenAction' }[k] || k;
}
function esc(s) {
  if (s == null) return '';
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── Module cards JSON (embedded in page for JS filtering) ─────────────────────
const moduleData = moduleNames.map(name => {
  const m   = modules[name];
  const brd = brdByModule[name] || null;
  const c   = brd ? (brd.confidence || confidence(m)) : confidence(m);
  return {
    name,
    confidence: c,
    hasBrd:     !!brd,
    brd:        brd,
    gapCount:   m.gapCount,
    linkCount:  m.linkCount,
    counts: {
      entities:    m.entities.length,
      statics:     m.statics.length,
      logics:      m.logics.length,
      screens:     m.screens.length,
      webBlocks:   m.webBlocks.length,
      structures:  m.structures.length,
      timers:      m.timers.length,
      serviceApis: m.serviceApis.length,
    },
    entities:    m.entities.map(e => ({
      name: e.name, attrs: e.attributes ? e.attributes.length : 0,
      isPublic: e.isPublic, gaps: e._gaps || []
    })),
    logics: m.logics.map(l => ({
      name: l.name, kind: logicKindLabel(l.logicKind),
      isPublic: l.isPublic,
      calls: (l.calls || []).length,
      gaps: l._gaps || []
    })),
    screens: m.screens.map(s => ({
      name: s.name, hasListUI: s.widgetSummary?.hasListUI,
      hasFormUI: s.widgetSummary?.hasFormUI,
      gaps: s._gaps || []
    })),
    statics:     m.statics.map(s    => ({ name: s.name, records: (s.records||[]).length })),
    timers:      m.timers.map(t     => ({ name: t.name, schedule: t.schedule })),
    serviceApis: m.serviceApis.map(a=> ({ name: a.name, isPublic: a.isPublic })),
  };
});

// ── Heatmap rows (sorted by gap count desc) ───────────────────────────────────
const heatmapRows = [...moduleData]
  .sort((a, b) => b.gapCount - a.gapCount)
  .slice(0, 30)
  .map(m => {
    const bar = Math.round((m.gapCount / Math.max(...moduleData.map(x => x.gapCount), 1)) * 100);
    return `<tr onclick="showModule('${esc(m.name)}')" style="cursor:pointer">
      <td>${esc(m.name)}</td>
      <td>${confBadge(m.confidence)}</td>
      <td>${m.counts.entities}</td>
      <td>${m.counts.logics}</td>
      <td>${m.counts.screens}</td>
      <td>
        <div style="background:#e5e7eb;border-radius:4px;height:14px;width:120px;display:inline-block;vertical-align:middle">
          <div style="background:${confColor(m.confidence)};height:14px;border-radius:4px;width:${bar}%"></div>
        </div>
        <span style="margin-left:6px">${m.gapCount}</span>
      </td>
    </tr>`;
  }).join('\n');

// ── Module confidence overview table rows ─────────────────────────────────────
const moduleOverviewRows = moduleData.map(m => {
  const brdCell = m.hasBrd
    ? '<span style="background:#dcfce7;color:#166534;padding:2px 8px;border-radius:12px;font-size:11px;font-weight:600">✓ generated</span>'
    : '—';
  return `<tr onclick="showModule('${esc(m.name)}')" style="cursor:pointer">
    <td class="mono">${esc(m.name)}</td>
    <td>${confBadge(m.confidence)}</td>
    <td>${m.counts.entities}</td>
    <td>${m.counts.logics}</td>
    <td>${m.counts.screens}</td>
    <td style="color:${m.gapCount>0?'#b91c1c':'#166534'}">${m.gapCount}</td>
    <td>${m.linkCount}</td>
    <td>${brdCell}</td>
  </tr>`;
}).join('\n');

// ── Sidebar nav items ─────────────────────────────────────────────────────────
const navItems = moduleNames.map(n => {
  const m   = modules[n];
  const brd = brdByModule[n];
  const c   = brd ? (brd.confidence || confidence(m)) : confidence(m);
  const dot = c === 'high' ? '🟢' : c === 'medium' ? '🟡' : '🔴';
  const badge = m.gapCount > 0 ? m.gapCount + ' gaps' : '✓';
  return `<div class="nav-item module-nav" id="nav-${esc(n)}" onclick="showModule('${esc(n)}')">${dot} ${esc(n)}<span class="nav-badge">${badge}</span></div>`;
}).join('\n');

// ── HTML ──────────────────────────────────────────────────────────────────────
const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>OS Extraction Report</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f8fafc; color: #1e293b; }
  a { color: #3b82f6; }
  h1 { font-size: 22px; font-weight: 700; }
  h2 { font-size: 16px; font-weight: 600; margin-bottom: 10px; }
  h3 { font-size: 13px; font-weight: 600; color: #64748b; text-transform: uppercase; letter-spacing: .04em; margin-bottom: 6px; }

  /* Layout */
  .sidebar { position: fixed; top: 0; left: 0; width: 240px; height: 100vh; background: #1e293b; color: #e2e8f0; overflow-y: auto; padding: 0; }
  .sidebar-header { padding: 20px 16px 12px; border-bottom: 1px solid #334155; }
  .sidebar-header h1 { color: #f1f5f9; font-size: 15px; }
  .sidebar-header p  { color: #94a3b8; font-size: 11px; margin-top: 4px; }
  .sidebar-search { padding: 10px 12px; }
  .sidebar-search input { width: 100%; padding: 6px 10px; border-radius: 6px; border: none; background: #334155; color: #f1f5f9; font-size: 12px; }
  .sidebar-search input::placeholder { color: #64748b; }
  .nav-item { padding: 7px 16px; font-size: 12px; cursor: pointer; border-left: 3px solid transparent; color: #94a3b8; }
  .nav-item:hover { background: #334155; color: #f1f5f9; }
  .nav-item.active { background: #1d4ed8; color: #fff; border-left-color: #60a5fa; }
  .nav-section { padding: 8px 16px 2px; font-size: 10px; font-weight: 700; color: #475569; text-transform: uppercase; letter-spacing: .06em; }
  .nav-badge { float: right; background: #334155; color: #94a3b8; font-size: 10px; padding: 1px 6px; border-radius: 10px; }
  .nav-item.active .nav-badge { background: rgba(255,255,255,.2); color: #fff; }

  /* Main */
  .main { margin-left: 240px; padding: 28px 32px; max-width: 1100px; }
  .page { display: none; }
  .page.active { display: block; }

  /* Stat cards */
  .stat-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 12px; margin-bottom: 28px; }
  .stat-card { background: #fff; border: 1px solid #e2e8f0; border-radius: 10px; padding: 16px; }
  .stat-card .val { font-size: 28px; font-weight: 700; color: #1d4ed8; }
  .stat-card .lbl { font-size: 12px; color: #64748b; margin-top: 2px; }

  /* Tables */
  table { width: 100%; border-collapse: collapse; font-size: 13px; background: #fff; border-radius: 8px; overflow: hidden; border: 1px solid #e2e8f0; }
  th { background: #f1f5f9; text-align: left; padding: 9px 12px; font-size: 11px; font-weight: 600; color: #64748b; text-transform: uppercase; letter-spacing: .04em; }
  td { padding: 8px 12px; border-top: 1px solid #f1f5f9; vertical-align: top; }
  tr:hover td { background: #f8fafc; }
  .mono { font-family: 'SF Mono', Consolas, monospace; font-size: 12px; }

  /* Module detail */
  .module-header { background: #fff; border: 1px solid #e2e8f0; border-radius: 10px; padding: 20px 24px; margin-bottom: 20px; }
  .module-header h2 { font-size: 18px; margin-bottom: 6px; }
  .module-pills { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 10px; }
  .pill { background: #f1f5f9; border-radius: 20px; padding: 4px 12px; font-size: 12px; color: #475569; }
  .pill strong { color: #1e293b; }
  .section-block { background: #fff; border: 1px solid #e2e8f0; border-radius: 10px; padding: 18px 20px; margin-bottom: 14px; }
  .brd-section-block { background: #fff; border: 2px solid #bfdbfe; border-radius: 10px; padding: 18px 20px; margin-bottom: 14px; }
  .gap-tag { background: #fee2e2; color: #b91c1c; font-size: 11px; padding: 2px 6px; border-radius: 4px; margin-left: 6px; }
  .tag { background: #eff6ff; color: #1d4ed8; font-size: 11px; padding: 2px 6px; border-radius: 4px; margin-left: 4px; }
  .tag-green { background: #dcfce7; color: #166534; }
  .tag-gray  { background: #f1f5f9; color: #475569; }
  .tag-yellow { background: #fef9c3; color: #854d0e; }
  .empty { color: #94a3b8; font-size: 13px; font-style: italic; padding: 10px 0; }
  .back-btn { font-size: 13px; color: #3b82f6; cursor: pointer; margin-bottom: 16px; display: inline-block; }
  .back-btn:hover { text-decoration: underline; }
  .raw-divider { text-align: center; color: #94a3b8; font-size: 12px; letter-spacing: .08em; margin: 22px 0 18px; border-top: 1px solid #e2e8f0; padding-top: 10px; }
  .brd-header-label { display: inline-block; background: #eff6ff; color: #1d4ed8; font-size: 11px; font-weight: 700; padding: 2px 8px; border-radius: 8px; text-transform: uppercase; letter-spacing: .06em; margin-bottom: 10px; }
</style>
</head>
<body>

<!-- Sidebar -->
<div class="sidebar">
  <div class="sidebar-header">
    <h1>OS Extraction Report</h1>
    <p>${moduleNames.length} modules &middot; ${totalItems.toLocaleString()} items</p>
  </div>
  <div class="sidebar-search">
    <input type="text" id="moduleSearch" placeholder="Search modules..." oninput="filterNav(this.value)">
  </div>
  <div class="nav-section">Overview</div>
  <div class="nav-item active" onclick="showPage('dashboard')">Dashboard</div>
  <div class="nav-item" onclick="showPage('heatmap')">Gap Heatmap</div>
  <div class="nav-section">Modules</div>
  <div id="navModules">
    ${navItems}
  </div>
</div>

<!-- Main -->
<div class="main">

  <!-- Dashboard -->
  <div class="page active" id="page-dashboard">
    <h2 style="margin-bottom:20px">Extraction Dashboard</h2>
    <div class="stat-grid">
      <div class="stat-card"><div class="val">${moduleNames.length}</div><div class="lbl">Modules</div></div>
      <div class="stat-card"><div class="val">${entities.length + statics.length}</div><div class="lbl">Entities</div></div>
      <div class="stat-card"><div class="val">${logics.length}</div><div class="lbl">Logic items</div></div>
      <div class="stat-card"><div class="val">${screens.length}</div><div class="lbl">Screens</div></div>
      <div class="stat-card"><div class="val">${webBlocks.length}</div><div class="lbl">Web Blocks</div></div>
      <div class="stat-card"><div class="val">${structures.length}</div><div class="lbl">Structures</div></div>
      <div class="stat-card"><div class="val">${timers.length}</div><div class="lbl">Timers</div></div>
      <div class="stat-card"><div class="val">${serviceApis.length}</div><div class="lbl">Service APIs</div></div>
      <div class="stat-card"><div class="val">${coveragePct}%</div><div class="lbl">Link coverage</div></div>
      <div class="stat-card"><div class="val">${totalGaps}</div><div class="lbl">Open gaps</div></div>
      <div class="stat-card"><div class="val">${totalBrdFiles}</div><div class="lbl">BRD Coverage</div></div>
    </div>

    <h2 style="margin-bottom:12px">Construct Breakdown</h2>
    <table style="margin-bottom:28px">
      <thead><tr><th>Type</th><th>Count</th><th>Mendix equivalent</th></tr></thead>
      <tbody>
        <tr><td>Entity</td><td>${entities.length}</td><td>Persistent Entity</td></tr>
        <tr><td>Static Entity</td><td>${statics.length}</td><td>Enumeration</td></tr>
        <tr><td>Structure</td><td>${structures.length}</td><td>Non-persistent Entity</td></tr>
        <tr><td>Server Action / BPT</td><td>${logics.filter(l=>l.logicKind==='action'||l.logicKind==='process').length}</td><td>Microflow / Workflow</td></tr>
        <tr><td>Client / Screen Action</td><td>${logics.filter(l=>l.logicKind==='clientAction'||l.logicKind==='screenAction').length}</td><td>Nanoflow</td></tr>
        <tr><td>Web Screen</td><td>${screens.length}</td><td>Page</td></tr>
        <tr><td>Web Block</td><td>${webBlocks.length}</td><td>Building Block / Snippet</td></tr>
        <tr><td>Timer</td><td>${timers.length}</td><td>Scheduled Event</td></tr>
        <tr><td>Service Action (exposed)</td><td>${serviceApis.length}</td><td>Published REST operation</td></tr>
      </tbody>
    </table>

    <h2 style="margin-bottom:12px">BRD Generation</h2>
    <table style="margin-bottom:28px">
      <thead><tr><th>Metric</th><th>Value</th></tr></thead>
      <tbody>
        <tr><td>Total BRD files generated</td><td><strong>${totalBrdFiles}</strong></td></tr>
        <tr><td>Total use case scaffolds</td><td><strong>${totalUseCaseScaffolds}</strong></td></tr>
        <tr><td>Total open gaps (from BRDs)</td><td><strong style="color:${totalBrdOpenGaps>0?'#b91c1c':'#166534'}">${totalBrdOpenGaps}</strong></td></tr>
      </tbody>
    </table>

    <h2 style="margin-bottom:12px">Module Confidence Overview</h2>
    <table>
      <thead><tr><th>Module</th><th>Confidence</th><th>Entities</th><th>Logics</th><th>Screens</th><th>Gaps</th><th>Links</th><th>BRD</th></tr></thead>
      <tbody>
        ${moduleOverviewRows}
      </tbody>
    </table>
  </div>

  <!-- Heatmap -->
  <div class="page" id="page-heatmap">
    <h2 style="margin-bottom:6px">Gap Heatmap</h2>
    <p style="color:#64748b;font-size:13px;margin-bottom:20px">Top 30 modules by unresolved gap count. Click a row to inspect the module.</p>
    <table>
      <thead><tr><th>Module</th><th>Confidence</th><th>Entities</th><th>Logics</th><th>Screens</th><th>Gaps</th></tr></thead>
      <tbody>${heatmapRows}</tbody>
    </table>
  </div>

  <!-- Module detail (dynamic) -->
  <div class="page" id="page-module">
    <span class="back-btn" onclick="showPage('dashboard')">← Back to Dashboard</span>
    <div id="module-detail"></div>
  </div>

</div>

<script>
const DATA = ${JSON.stringify(moduleData)};
const byName = {};
DATA.forEach(m => byName[m.name] = m);

function esc(s) {
  if (s == null) return '';
  return String(s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function showPage(id) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  document.getElementById('page-' + id).classList.add('active');
  const navEl = document.getElementById('nav-' + id);
  if (navEl) navEl.classList.add('active');
}

function showModule(name) {
  const m = byName[name];
  if (!m) return;

  // Nav highlight
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  const navEl = document.getElementById('nav-' + name);
  if (navEl) navEl.classList.add('active');

  // Confidence
  const confCol = m.confidence === 'high' ? '#22c55e' : m.confidence === 'medium' ? '#f59e0b' : '#ef4444';
  const confBadgeHtml = '<span style="background:' + confCol + ';color:#fff;padding:2px 8px;border-radius:12px;font-size:12px;font-weight:600">' + esc(m.confidence) + '</span>';

  let html = '<div class="module-header">';
  html += '<h2>' + esc(name) + ' &nbsp;' + confBadgeHtml;
  if (m.hasBrd) html += ' &nbsp;<span style="background:#eff6ff;color:#1d4ed8;padding:2px 8px;border-radius:12px;font-size:12px;font-weight:600">BRD ✓</span>';
  html += '</h2>';
  html += '<div style="color:#64748b;font-size:13px;margin-top:4px">' + m.gapCount + ' gaps &nbsp;&middot;&nbsp; ' + m.linkCount + ' cross-references</div>';
  html += '<div class="module-pills">';
  if (m.counts.entities)    html += '<div class="pill"><strong>' + m.counts.entities    + '</strong> entities</div>';
  if (m.counts.statics)     html += '<div class="pill"><strong>' + m.counts.statics     + '</strong> enumerations</div>';
  if (m.counts.logics)      html += '<div class="pill"><strong>' + m.counts.logics      + '</strong> logic items</div>';
  if (m.counts.screens)     html += '<div class="pill"><strong>' + m.counts.screens     + '</strong> screens</div>';
  if (m.counts.webBlocks)   html += '<div class="pill"><strong>' + m.counts.webBlocks   + '</strong> web blocks</div>';
  if (m.counts.structures)  html += '<div class="pill"><strong>' + m.counts.structures  + '</strong> structures</div>';
  if (m.counts.timers)      html += '<div class="pill"><strong>' + m.counts.timers      + '</strong> timers</div>';
  if (m.counts.serviceApis) html += '<div class="pill"><strong>' + m.counts.serviceApis + '</strong> service APIs</div>';
  html += '</div></div>';

  // ── BRD Summary Section ────────────────────────────────────────────────────
  if (m.hasBrd && m.brd) {
    const brd = m.brd;
    const sum = brd.summary || {};

    html += '<div class="brd-section-block">';
    html += '<div class="brd-header-label">BRD Summary</div>';

    // Summary pills from brd.summary
    html += '<div class="module-pills" style="margin-bottom:14px">';
    const pillDefs = [
      ['entityCount',      'entities'],
      ['microflowCount',   'microflows'],
      ['pageCount',        'pages'],
      ['useCaseCount',     'use cases'],
      ['integrationCount', 'integrations'],
      ['timerCount',       'timers'],
      ['openGapCount',     'open gaps'],
    ];
    pillDefs.forEach(([key, label]) => {
      if (sum[key] != null) {
        const isGap = key === 'openGapCount';
        const style = isGap && sum[key] > 0 ? 'background:#fee2e2;color:#b91c1c' : '';
        html += '<div class="pill" style="' + style + '"><strong>' + sum[key] + '</strong> ' + label + '</div>';
      }
    });
    html += '</div>';

    // ── Business Process Overview (code-inferred, confirmed/corrected in Phase 5) ──
    if (brd.appType || (brd.useCases && brd.useCases.length)) {
      html += '<h3 style="margin-top:14px;margin-bottom:8px">Business Process Overview</h3>';
      if (brd.appType) {
        const at = brd.appType;
        const atCol = at.confidence === 'high' ? '#22c55e' : at.confidence === 'medium' ? '#f59e0b' : '#94a3b8';
        html += '<div style="margin-bottom:10px">';
        html += '<span style="background:' + atCol + ';color:#fff;padding:2px 8px;border-radius:12px;font-size:12px;font-weight:600">' + esc(at.label) + '</span> ';
        html += '<span style="color:#64748b;font-size:12px">' + esc((at.signals || []).join('; ')) + '</span>';
        html += '</div>';
      }
      if (brd.useCases && brd.useCases.length) {
        html += '<table style="margin-bottom:16px"><thead><tr><th>ID</th><th>Screen</th><th>Main Flow (code-inferred)</th><th>Open Questions</th><th>Status</th></tr></thead><tbody>';
        brd.useCases.forEach(uc => {
          const flow = Array.isArray(uc.mainFlow) ? uc.mainFlow.map(s => esc(s)).join('<br>') : '—';
          const oq   = Array.isArray(uc.openQuestions) && uc.openQuestions.length
                        ? uc.openQuestions.map(q => esc(q)).join('<br>') : '—';
          const status = uc.status || 'code-inferred';
          const statusStyle = status === 'doc-confirmed'
            ? 'background:#dcfce7;color:#15803d'
            : status === 'doc-conflict'
              ? 'background:#fee2e2;color:#b91c1c'
              : 'background:#eff6ff;color:#1d4ed8';
          html += '<tr><td class="mono">' + esc(uc.id || '—') + '</td>';
          html += '<td>' + esc(uc.screen || '—') + '</td>';
          html += '<td style="font-size:12px;color:#475569">' + flow + '</td>';
          html += '<td style="font-size:12px;color:#475569">' + oq + '</td>';
          html += '<td><span style="' + statusStyle + ';padding:2px 8px;border-radius:12px;font-size:11px;font-weight:600">' + esc(status) + '</span></td></tr>';
        });
        html += '</tbody></table>';
      }
    }

    // Domain Entities
    if (brd.domainEntities && brd.domainEntities.length) {
      html += '<h3 style="margin-top:14px;margin-bottom:8px">Domain Entities</h3>';
      html += '<table style="margin-bottom:16px"><thead><tr><th>Name</th><th>Mendix Type</th><th>Attributes</th><th>Key FKs</th><th>Gaps</th></tr></thead><tbody>';
      brd.domainEntities.forEach(e => {
        const attrs  = Array.isArray(e.attributes) ? e.attributes.join(', ') : (e.attributes || '—');
        const fks    = Array.isArray(e.keyFKs) ? e.keyFKs.join(', ') : (e.keyFKs || '—');
        const gaps   = Array.isArray(e.gaps) ? e.gaps.map(g => '<span class="gap-tag">' + esc(g) + '</span>').join('') : '—';
        html += '<tr><td class="mono">' + esc(e.name) + '</td>';
        html += '<td>' + esc(e.mendixType || e.type || '—') + '</td>';
        html += '<td style="font-size:11px;color:#475569">' + esc(attrs) + '</td>';
        html += '<td style="font-size:11px;color:#475569">' + esc(fks) + '</td>';
        html += '<td>' + (gaps || '—') + '</td></tr>';
      });
      html += '</tbody></table>';
    }

    // Microflows & Nanoflows
    if (brd.microflows && brd.microflows.length) {
      html += '<h3 style="margin-top:14px;margin-bottom:8px">Microflows &amp; Nanoflows</h3>';
      html += '<table style="margin-bottom:16px"><thead><tr><th>Name</th><th>Kind</th><th>Purpose</th><th>Calls</th><th>Public</th><th>Gaps</th></tr></thead><tbody>';
      brd.microflows.forEach(mf => {
        const purpose = mf.purpose ? (mf.purpose.length > 80 ? mf.purpose.slice(0, 80) + '…' : mf.purpose) : '—';
        const calls   = Array.isArray(mf.calls) ? mf.calls.length : (mf.calls || '—');
        const gaps    = Array.isArray(mf.gaps) ? mf.gaps.map(g => '<span class="gap-tag">' + esc(g) + '</span>').join('') : '—';
        html += '<tr><td class="mono">' + esc(mf.name) + '</td>';
        html += '<td><span class="tag tag-gray">' + esc(mf.kind || mf.logicKind || '—') + '</span></td>';
        html += '<td style="color:#475569;font-size:12px">' + esc(purpose) + '</td>';
        html += '<td>' + esc(String(calls)) + '</td>';
        html += '<td>' + (mf.isPublic ? '<span class="tag tag-green">public</span>' : '—') + '</td>';
        html += '<td>' + (gaps || '—') + '</td></tr>';
      });
      html += '</tbody></table>';
    }

    // Pages
    if (brd.pages && brd.pages.length) {
      html += '<h3 style="margin-top:14px;margin-bottom:8px">Pages</h3>';
      html += '<table style="margin-bottom:16px"><thead><tr><th>Name</th><th>UI Pattern</th><th>Input Params</th><th>Linked Logics</th><th>Gaps</th></tr></thead><tbody>';
      brd.pages.forEach(pg => {
        const params  = Array.isArray(pg.inputParams)   ? pg.inputParams.join(', ')   : (pg.inputParams   || '—');
        const logics2 = Array.isArray(pg.linkedLogics)  ? pg.linkedLogics.join(', ')  : (pg.linkedLogics  || '—');
        const gaps    = Array.isArray(pg.gaps) ? pg.gaps.map(g => '<span class="gap-tag">' + esc(g) + '</span>').join('') : '—';
        html += '<tr><td class="mono">' + esc(pg.name) + '</td>';
        html += '<td><span class="tag tag-gray">' + esc(pg.uiPattern || '—') + '</span></td>';
        html += '<td style="font-size:12px;color:#475569">' + esc(params) + '</td>';
        html += '<td style="font-size:12px;color:#475569">' + esc(logics2) + '</td>';
        html += '<td>' + (gaps || '—') + '</td></tr>';
      });
      html += '</tbody></table>';
    }

    // Integrations
    if (brd.integrations && brd.integrations.length) {
      html += '<h3 style="margin-top:14px;margin-bottom:8px">Integrations</h3>';
      html += '<table style="margin-bottom:16px"><thead><tr><th>Name</th><th>Direction</th><th>Kind</th><th>Parameters</th></tr></thead><tbody>';
      brd.integrations.forEach(intg => {
        const params = Array.isArray(intg.parameters) ? intg.parameters.join(', ') : (intg.parameters || '—');
        html += '<tr><td class="mono">' + esc(intg.name) + '</td>';
        html += '<td>' + esc(intg.direction || '—') + '</td>';
        html += '<td><span class="tag tag-gray">' + esc(intg.kind || intg.type || '—') + '</span></td>';
        html += '<td style="font-size:12px;color:#475569">' + esc(params) + '</td></tr>';
      });
      html += '</tbody></table>';
    }

    // Timers (scheduled events from BRD)
    if (brd.timers && brd.timers.length) {
      html += '<h3 style="margin-top:14px;margin-bottom:8px">Scheduled Events</h3>';
      html += '<table style="margin-bottom:16px"><thead><tr><th>Name</th><th>Schedule</th><th>Description</th></tr></thead><tbody>';
      brd.timers.forEach(t => {
        html += '<tr><td class="mono">' + esc(t.name) + '</td>';
        html += '<td>' + esc(t.schedule || '—') + '</td>';
        html += '<td style="color:#475569;font-size:12px">' + esc(t.description || '—') + '</td></tr>';
      });
      html += '</tbody></table>';
    }

    html += '</div>';

    // Divider before raw KB sections
    html += '<div class="raw-divider">── Raw Extraction Data ──</div>';
  }

  // ── Raw KB sections ────────────────────────────────────────────────────────

  // Entities
  if (m.entities.length) {
    html += '<div class="section-block">';
    html += '<h3>Entities → Mendix Persistent Entities</h3>';
    html += '<table><thead><tr><th>Name</th><th>Attributes</th><th>Public</th><th>Gaps</th></tr></thead><tbody>';
    m.entities.forEach(e => {
      const gaps = e.gaps.map(g => '<span class="gap-tag">' + esc(g) + '</span>').join('');
      html += '<tr><td class="mono">' + esc(e.name) + '</td><td>' + e.attrs + '</td>';
      html += '<td>' + (e.isPublic ? '<span class="tag tag-green">public</span>' : '') + '</td>';
      html += '<td>' + (gaps || '—') + '</td></tr>';
    });
    html += '</tbody></table></div>';
  }

  // Logics
  if (m.logics.length) {
    html += '<div class="section-block">';
    html += '<h3>Logic → Mendix Microflows / Nanoflows</h3>';
    html += '<table><thead><tr><th>Name</th><th>Kind</th><th>Calls</th><th>Public</th><th>Gaps</th></tr></thead><tbody>';
    m.logics.forEach(l => {
      const gaps = l.gaps.map(g => '<span class="gap-tag">' + esc(g) + '</span>').join('');
      html += '<tr><td class="mono">' + esc(l.name) + '</td>';
      html += '<td><span class="tag tag-gray">' + esc(l.kind) + '</span></td>';
      html += '<td>' + l.calls + '</td>';
      html += '<td>' + (l.isPublic ? '<span class="tag tag-green">public</span>' : '') + '</td>';
      html += '<td>' + (gaps || '—') + '</td></tr>';
    });
    html += '</tbody></table></div>';
  }

  // Screens
  if (m.screens.length) {
    html += '<div class="section-block">';
    html += '<h3>Screens → Mendix Pages</h3>';
    html += '<table><thead><tr><th>Name</th><th>List UI</th><th>Form UI</th><th>Gaps</th></tr></thead><tbody>';
    m.screens.forEach(s => {
      const gaps = s.gaps.map(g => '<span class="gap-tag">' + esc(g) + '</span>').join('');
      html += '<tr><td class="mono">' + esc(s.name) + '</td>';
      html += '<td>' + (s.hasListUI ? '<span class="tag">ListView</span>' : '—') + '</td>';
      html += '<td>' + (s.hasFormUI ? '<span class="tag">DataView</span>'  : '—') + '</td>';
      html += '<td>' + (gaps || '—') + '</td></tr>';
    });
    html += '</tbody></table></div>';
  }

  // Statics / Enumerations
  if (m.statics.length) {
    html += '<div class="section-block">';
    html += '<h3>Static Entities → Mendix Enumerations</h3>';
    html += '<table><thead><tr><th>Name</th><th>Values</th></tr></thead><tbody>';
    m.statics.forEach(s => {
      html += '<tr><td class="mono">' + esc(s.name) + '</td><td>' + s.records + ' records</td></tr>';
    });
    html += '</tbody></table></div>';
  }

  // Timers
  if (m.timers.length) {
    html += '<div class="section-block">';
    html += '<h3>Timers → Mendix Scheduled Events</h3>';
    html += '<table><thead><tr><th>Name</th><th>Schedule</th></tr></thead><tbody>';
    m.timers.forEach(t => {
      html += '<tr><td class="mono">' + esc(t.name) + '</td><td>' + esc(t.schedule || '—') + '</td></tr>';
    });
    html += '</tbody></table></div>';
  }

  // Service APIs
  if (m.serviceApis.length) {
    html += '<div class="section-block">';
    html += '<h3>Service Actions → Mendix Published REST Operations</h3>';
    html += '<table><thead><tr><th>Name</th><th>Public</th></tr></thead><tbody>';
    m.serviceApis.forEach(a => {
      html += '<tr><td class="mono">' + esc(a.name) + '</td>';
      html += '<td>' + (a.isPublic ? '<span class="tag tag-green">public</span>' : '') + '</td></tr>';
    });
    html += '</tbody></table></div>';
  }

  if (!m.entities.length && !m.logics.length && !m.screens.length && !m.statics.length && !m.timers.length && !m.serviceApis.length) {
    html += '<div class="section-block"><p class="empty">No extractable business artifacts in this module (likely infrastructure or theme).</p></div>';
  }

  document.getElementById('module-detail').innerHTML = html;
  showPage('module');
  window.scrollTo(0, 0);
}

function filterNav(q) {
  const lower = q.toLowerCase();
  document.querySelectorAll('.module-nav').forEach(el => {
    const name = el.id.replace('nav-', '');
    el.style.display = name.toLowerCase().includes(lower) ? '' : 'none';
  });
}
</script>
</body>
</html>`;

fs.writeFileSync(OUT, html, 'utf8');
console.log(`Report written → ${OUT}`);
