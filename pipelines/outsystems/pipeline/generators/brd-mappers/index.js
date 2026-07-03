'use strict';
const fs   = require('fs');
const path = require('path');

const { mapDomainEntities } = require('./domain-entity-mapper');
const { mapMicroflows }     = require('./microflow-mapper');
const { mapPages }          = require('./page-mapper');
const { mapUseCases, classifyAppType } = require('./use-case-mapper');
const { mapIntegrations }   = require('./integration-mapper');

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (_) { return []; }
}

function confidence(gapCount) {
  if (gapCount === 0) return 'high';
  if (gapCount <= 3)  return 'medium';
  return 'low';
}

// A BRD carries Phase 4/5 enrichment once a use case has been reviewed, or an open question
// has been answered against the document KB — re-running Phase 3 must not silently clobber
// that. Detect it and redirect the fresh scaffold instead of overwriting.
function hasEnrichment(existingBrd) {
  if (!existingBrd) return false;
  const useCases = existingBrd.useCases || [];
  return useCases.some(uc =>
    uc.reviewStatus === 'reviewed' ||
    uc.status === 'doc-confirmed' ||
    uc.status === 'doc-conflict' ||
    (uc.openQuestions || []).some(q => q && q.status === 'Resolved')
  );
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

  // Bucket by module
  const modules = {};
  function bucket(items, key) {
    for (const item of items) {
      const m = item.module || item.inferredModule || '(unknown)';
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

      const brdPath = path.join(outDir, `${modName}.brd.json`);
      const existing = fs.existsSync(brdPath) ? readJson(brdPath) : null;
      const targetPath = hasEnrichment(existing)
        ? path.join(outDir, `${modName}.brd.scaffold.json`)
        : brdPath;
      if (targetPath !== brdPath) {
        warnings.push({
          module: modName,
          issue: `${modName}.brd.json already has reviewed/doc-confirmed content — ` +
                 `fresh scaffold written to ${modName}.brd.scaffold.json instead of overwriting it`,
        });
      }

      fs.writeFileSync(targetPath, JSON.stringify(brd, null, 2), 'utf8');
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
