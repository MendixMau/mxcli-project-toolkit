'use strict';
const fs   = require('fs');
const path = require('path');

const { mapDomainEntities } = require('./domain-entity-mapper');
const { mapMicroflows }     = require('./microflow-mapper');
const { mapPages }          = require('./page-mapper');
const { mapUseCases, classifyAppType } = require('./use-case-mapper');
const { mapIntegrations }   = require('./integration-mapper');
const { capabilityForItem, buildGroupingReport, buildEvidenceMajority, renderProposal } = require('../lib/capability-grouper');

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (_) { return []; }
}

function confidence(gapCount) {
  if (gapCount === 0) return 'high';
  if (gapCount <= 3)  return 'medium';
  return 'low';
}

async function generate(kbDir, outDir, opts = {}) {
  fs.mkdirSync(outDir, { recursive: true });

  const entities    = readJson(path.join(kbDir, 'entities.json'));
  const statics     = readJson(path.join(kbDir, 'staticEntities.json'));
  const logics      = readJson(path.join(kbDir, 'logics.json'));
  const screens     = readJson(path.join(kbDir, 'screens.json'));
  const webBlocks   = readJson(path.join(kbDir, 'webBlocks.json'));
  const serviceApis = readJson(path.join(kbDir, 'serviceApis.json'));
  const extEntities = readJson(path.join(kbDir, 'extEntities.json'));
  const timers      = readJson(path.join(kbDir, 'timers.json'));

  // Roll technical-layer packages up into business capabilities before bucketing.
  // Per-item (path evidence), because the same leaf package name (impl, api…) legitimately
  // belongs to several domains. opts.brdGrouping = explicit config overrides by raw name.
  // Proposal doc goes to outDir for CAC-2 review — see capability-grouper.js.
  const brdGrouping = opts.brdGrouping || {};
  const allItems = [...entities, ...statics, ...logics, ...screens,
                    ...webBlocks, ...serviceApis, ...extEntities, ...timers];
  const evidenceMajority = buildEvidenceMajority(allItems);
  fs.writeFileSync(path.join(outDir, 'grouping-proposal.md'),
    renderProposal(buildGroupingReport(allItems, brdGrouping, evidenceMajority)), 'utf8');

  // Bucket by module (post-grouping capability name)
  const modules = {};
  function bucket(items, key) {
    for (const item of items) {
      const m = capabilityForItem(item, brdGrouping, evidenceMajority);
      if (!modules[m]) modules[m] = {
        entities: [], statics: [], logics: [], screens: [],
        webBlocks: [], serviceApis: [], extEntities: [], timers: [],
      };
      modules[m][key].push(item);
    }
  }
  bucket(entities,    'entities');
  bucket(statics,     'statics');
  bucket(logics,      'logics');
  bucket(screens,     'screens');
  bucket(webBlocks,   'webBlocks');
  bucket(serviceApis, 'serviceApis');
  bucket(extEntities, 'extEntities');
  bucket(timers,      'timers');

  const warnings = [];
  let modulesGenerated = 0;

  for (const [modName, arts] of Object.entries(modules)) {
    if (opts.moduleFilter && !opts.moduleFilter.has(modName)) continue;

    try {
      const domainEntities = mapDomainEntities(arts.entities, arts.statics);
      const microflows     = mapMicroflows(arts.logics);
      const { pages, webBlocks: blocks } = mapPages(arts.screens, arts.webBlocks);
      const useCases       = mapUseCases(arts.screens);
      const integrations   = mapIntegrations(arts.serviceApis, arts.extEntities);
      const appType        = classifyAppType(pages, microflows, integrations);

      const allGaps = [
        ...domainEntities.flatMap(e => e.gaps),
        ...microflows.flatMap(m => m.gaps),
        ...pages.flatMap(p => p.gaps),
        ...useCases.flatMap(u => u.gaps),
        ...integrations.flatMap(i => i.gaps),
      ];

      const brd = {
        module:      modName,
        generatedAt: new Date().toISOString(),
        confidence:  confidence(allGaps.length),
        appType,
        summary: {
          entityCount:      domainEntities.filter(e => e.mendixType === 'PersistentEntity').length,
          enumerationCount: domainEntities.filter(e => e.mendixType === 'Enumeration').length,
          microflowCount:   microflows.filter(m => m.kind === 'Microflow').length,
          nanoflowCount:    microflows.filter(m => m.kind === 'Nanoflow').length,
          bptProcessCount:  microflows.filter(m => m.isBPTProcess).length,
          pageCount:        pages.length,
          webBlockCount:    blocks.length,
          useCaseCount:     useCases.length,
          integrationCount: integrations.length,
          timerCount:       arts.timers.length,
          openGapCount:     allGaps.length,
        },
        domainEntities,
        microflows,
        pages,
        webBlocks: blocks,
        useCases,
        integrations,
        timers: arts.timers.map(t => ({
          name:        t.name,
          description: t.description || '',
          schedule:    t.schedule    || '',
          timeout:     t.timeout     || '',
          priority:    t.priority    || '',
          gaps:        t._gaps       || [],
        })),
        openGaps: [...new Set(allGaps)],
      };

      // Guard against clobbering Phase 4/5 enrichment: re-running Phase 3 (e.g. after a source
      // change, or just to regenerate reports) used to silently overwrite reviewed useCase
      // narrative and openQuestions with fresh 'pending' scaffolds. If the existing file has
      // any human enrichment or doc-KB reconciliation (brd-validation.md check #6), write the
      // fresh scaffold alongside it instead of over it.
      const outFile = path.join(outDir, `${modName}.brd.json`);
      let targetFile = outFile;
      if (fs.existsSync(outFile)) {
        try {
          const existing = JSON.parse(fs.readFileSync(outFile, 'utf8'));
          const isEnriched = (existing.useCases || []).some(u =>
            u.reviewStatus === 'reviewed' ||
            u.status === 'doc-confirmed' ||
            u.status === 'doc-conflict' ||
            (u.openQuestions || []).some(q => q && q.status === 'Resolved')
          ) || (existing.openQuestions || []).length > 0;
          if (isEnriched) {
            targetFile = path.join(outDir, `${modName}.brd.scaffold.json`);
            warnings.push({ module: modName, issue: `${modName}.brd.json already has Phase 4/5 enrichment — fresh scaffold written to ${modName}.brd.scaffold.json instead of overwriting it. Diff and merge manually if the source changed.` });
          }
        } catch (_) { /* existing file unreadable — fall through and overwrite */ }
      }

      fs.writeFileSync(targetFile, JSON.stringify(brd, null, 2), 'utf8');
      modulesGenerated++;
    } catch (e) {
      warnings.push({ module: modName, issue: e.message });
    }
  }

  const report = { modulesGenerated, warnings };
  fs.writeFileSync(path.join(outDir, 'generation-report.json'), JSON.stringify(report, null, 2));
  return report;
}

module.exports = { generate };
