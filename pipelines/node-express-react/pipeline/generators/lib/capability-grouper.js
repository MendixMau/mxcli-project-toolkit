'use strict';
// Capability grouping — rolls technical-layer package names up into business capabilities
// before BRD generation, so BRDs land at business-function granularity instead of one per
// Java package (real incident: 19 BRDs for ~6 capabilities, half of them named impl/spi/api).
//
// This is a PROPOSAL mechanism, not an architecture decision: the heuristic runs by default
// (solo run never stalls), the mapping is written to brd/grouping-proposal.md, and CAC-2
// (checkpoint-brd.md) asks the user to confirm or correct it. Corrections go into
// config.json → "brdGrouping": { "<rawModule>": "<capability>", ... } and Phase 3 re-runs.
// Mendix module boundaries remain a Stage 3 decision (modularize-domain.md) — this only
// fixes the granularity of the requirements documents.

// Package segments that are technical layers, never business capabilities.
// Deliberately conservative — when in doubt leave a name out and let the human correct
// via config.brdGrouping at the checkpoint.
const TECH_LAYERS = new Set([
  'impl', 'api', 'spi', 'app',
  'commands', 'command', 'events', 'event', 'handler', 'handlers',
  'config', 'configuration', 'util', 'utils', 'internal',
  'jpa', 'persistence', 'repository', 'repositories',
  'dto', 'dtos', 'model', 'models',
  'service', 'services', 'controller', 'controllers', 'rest', 'web',
]);

// Namespace roots that can never be a capability (reverse walk rarely reaches them,
// but a shallow package like org.acme.impl shouldn't resolve to "acme"... it should —
// acme is the app. Only the TLD-style roots are excluded.)
const NAMESPACE_ROOTS = new Set(['org', 'com', 'net', 'io', 'edu', 'de', 'nl', 'src', 'main', 'java']);

/**
 * Derive the business capability for one KB item from its source path.
 * Returns null when there's no usable path evidence.
 */
function capabilityFromSource(sourcePath) {
  if (!sourcePath || typeof sourcePath !== 'string') return null;
  const norm = sourcePath.replace(/\\/g, '/');
  // Prefer the java package part when present; otherwise use the whole path.
  const idx = norm.lastIndexOf('/java/');
  const rel = idx >= 0 ? norm.slice(idx + 6) : norm;
  const segs = rel.split('/').filter(Boolean);
  segs.pop(); // drop the filename
  for (let i = segs.length - 1; i >= 0; i--) {
    const s = segs[i].toLowerCase();
    if (TECH_LAYERS.has(s)) continue;
    if (NAMESPACE_ROOTS.has(s)) break;
    return segs[i];
  }
  return null;
}

/**
 * Majority capability per raw module, computed only from items that carry path evidence.
 * Used as the fallback for evidence-less items (e.g. KB types without a _source field).
 */
function buildEvidenceMajority(allItems) {
  const votes = {};
  for (const item of allItems) {
    const raw = item.module || item.inferredModule || '(unknown)';
    const src = item._source || item.sourceFile || item.source;
    const cap = capabilityFromSource(Array.isArray(src) ? src[0] : src);
    if (!cap) continue;
    votes[raw] = votes[raw] || {};
    votes[raw][cap] = (votes[raw][cap] || 0) + 1;
  }
  const majority = {};
  for (const [raw, caps] of Object.entries(votes)) {
    majority[raw] = Object.entries(caps).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0][0];
  }
  return majority;
}

/**
 * Resolve the capability for ONE item. Per-item, because the KB's `module` field is the
 * leaf package name only — the same raw name (e.g. `impl`) legitimately belongs to several
 * different domains, so a single rawModule->capability vote would collapse them wrongly.
 *
 * Order: explicit config override (by raw name) → this item's own path evidence →
 * majority of its raw module's evidenced items → raw name.
 */
function capabilityForItem(item, brdGrouping = {}, evidenceMajority = {}) {
  const raw = item.module || item.inferredModule || '(unknown)';
  if (brdGrouping[raw]) return brdGrouping[raw];
  const src = item._source || item.sourceFile || item.source;
  const cap = capabilityFromSource(Array.isArray(src) ? src[0] : src);
  return cap || evidenceMajority[raw] || raw;
}

/**
 * Build the proposal statistics: rawModule -> { capability: itemCount }, for human review.
 * A raw module fanning out into several capabilities is expected and correct (leaf package
 * names repeat across domains).
 */
function buildGroupingReport(allItems, brdGrouping = {}, evidenceMajority = {}) {
  const report = {};
  for (const item of allItems) {
    const raw = item.module || item.inferredModule || '(unknown)';
    const cap = capabilityForItem(item, brdGrouping, evidenceMajority);
    report[raw] = report[raw] || {};
    report[raw][cap] = (report[raw][cap] || 0) + 1;
  }
  return report;
}

/**
 * Render the human-facing proposal doc (markdown) for CAC-2 review.
 * `report` is buildGroupingReport()'s output: raw -> { capability: count }.
 */
function renderProposal(report) {
  const capabilities = new Set();
  let regrouped = 0;
  for (const [raw, caps] of Object.entries(report)) {
    for (const cap of Object.keys(caps)) {
      capabilities.add(cap);
      if (cap !== raw) regrouped++;
    }
  }
  const lines = [
    '# BRD Capability Grouping — Proposal (confirm at checkpoint-brd / CAC-2)',
    '',
    'The BRD mapper rolled technical-layer packages up into business capabilities using each',
    "item's own source-path evidence. **This is a proposal**: confirm or correct it at the BRD",
    'checkpoint. Corrections go in `config.json` → `"brdGrouping": { "<rawModule>": "<capability>" }`',
    '(overrides win over path evidence), then re-run Phase 3. Mendix module boundaries are still',
    'decided at Stage 3 (`modularize-domain.md`).',
    '',
    `**Result: ${Object.keys(report).length} raw package name(s) → ${capabilities.size} capability BRD(s).**`,
    '',
    '| Raw module (package) | → Capability BRD(s) | Items |',
    '|---|---|---|',
  ];
  for (const raw of Object.keys(report).sort()) {
    const caps = Object.entries(report[raw]).sort((a, b) => b[1] - a[1]);
    const capStr = caps.map(([c, n]) => (c === raw ? `*(unchanged: ${n})*` : `**${c}** (${n})`)).join(', ');
    const total = caps.reduce((s, [, n]) => s + n, 0);
    lines.push(`| ${raw} | ${capStr} | ${total} |`);
  }
  lines.push('', regrouped
    ? 'A raw package fanning out into several capabilities is normal — leaf package names repeat across domains. If a grouping is wrong, override it in config — don\'t hand-edit the BRDs.'
    : 'No grouping was applied (no technical-layer packages detected, or no path evidence).');
  return lines.join('\n') + '\n';
}

module.exports = { capabilityForItem, buildGroupingReport, buildEvidenceMajority, capabilityFromSource, renderProposal, TECH_LAYERS };
