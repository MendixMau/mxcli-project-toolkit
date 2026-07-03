'use strict';
const fs = require('fs');
const path = require('path');

const { mapEnumeration } = require('./mappers/enumeration-mapper');
const { mapEntity } = require('./mappers/entity-mapper');
const { mapMicroflow } = require('./mappers/microflow-mapper');
const { mapPage } = require('./mappers/page-mapper');
const { mapTimer } = require('./mappers/timer-mapper');
const { mapServiceApi } = require('./mappers/service-api-mapper');
const { mapExtEntity } = require('./mappers/ext-entity-mapper');
const { mapStructure } = require('./mappers/structure-mapper');
const { buildStructureIndex, buildDataScreenActionIndex, buildParamIndex } = require('./lib/structure-index');

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (_) { return []; }
}

async function generate(kbDir, outDir, opts = {}) {
  fs.mkdirSync(outDir, { recursive: true });

  const { structureIndex = {}, parentIndex = {} } = opts.blueprintDir ? buildStructureIndex(opts.blueprintDir) : {};
  const paramIndex = opts.blueprintDir ? buildParamIndex(opts.blueprintDir) : {};

  // Enrich structureIndex with attribute lists from xml.json (needed for Pattern A expansion)
  const xmlExtracted = readJson(path.join(kbDir, 'extracted', 'xml.json'));
  const xmlItems = xmlExtracted.items || xmlExtracted || [];
  // Build Structure:key → attrs map
  const structAttrsById = {};
  for (const item of xmlItems) {
    if (item.type === 'structure' && item.uniqueId) {
      structAttrsById[item.uniqueId] = (item.attributes || []).map(a => a.name).filter(Boolean);
    }
  }
  // Apply attrs to direct Structure: entries
  for (const [k, v] of Object.entries(structureIndex)) {
    if (k.startsWith('Structure:') && structAttrsById[k]) {
      v._attrs = structAttrsById[k];
    }
  }
  // Propagate attrs to StructureReference: entries via name+module lookup
  const attrsByNameModule = {};
  for (const [k, v] of Object.entries(structureIndex)) {
    if (k.startsWith('Structure:') && v._attrs) {
      attrsByNameModule[`${v.module}.${v.name}`] = v._attrs;
    }
  }
  for (const [k, v] of Object.entries(structureIndex)) {
    if (k.startsWith('StructureReference:') && !v._attrs) {
      const key = `${v.module}.${v.name}`;
      if (attrsByNameModule[key]) v._attrs = attrsByNameModule[key];
    }
  }

  const allDataScreenActions = readJson(path.join(kbDir, 'dataScreenActions.json'));
  const dsaIndex = buildDataScreenActionIndex(allDataScreenActions, structureIndex);

  const allEntities    = readJson(path.join(kbDir, 'entities.json'));
  const allStatics     = readJson(path.join(kbDir, 'staticEntities.json'));
  const allLogics      = readJson(path.join(kbDir, 'logics.json'));
  const allScreens     = readJson(path.join(kbDir, 'screens.json'));
  const allTimers      = readJson(path.join(kbDir, 'timers.json'));
  const allServiceApis = readJson(path.join(kbDir, 'serviceApis.json'));
  const allExtEntities = readJson(path.join(kbDir, 'extEntities.json'));

  // Deduplicate structures: drop unnamed, keep first occurrence per (module, name)
  const rawStructures = readJson(path.join(kbDir, 'structures.json'));
  const seenStructKey = new Set();
  const allStructures = rawStructures.filter(s => {
    if (!s.name) return false;
    const k = `${s.module}::${s.name}`;
    if (seenStructKey.has(k)) return false;
    seenStructKey.add(k);
    return true;
  });

  const modules = {};
  function bucket(item, category) {
    const m = item.module || item.inferredModule;
    if (!modules[m]) modules[m] = { statics: [], entities: [], structures: [], logics: [], screens: [], timers: [], serviceApis: [], extEntities: [] };
    modules[m][category].push(item);
  }
  for (const x of allStatics)      bucket(x, 'statics');
  for (const x of allEntities)     bucket(x, 'entities');
  for (const x of allStructures)   bucket(x, 'structures');
  for (const x of allLogics)       bucket(x, 'logics');
  for (const x of allScreens)      bucket(x, 'screens');
  for (const x of allTimers)       bucket(x, 'timers');
  for (const x of allServiceApis)  bucket(x, 'serviceApis');
  for (const x of allExtEntities)  bucket(x, 'extEntities');

  const warnings = [];
  let artifactsTranslated = 0;

  for (const [modName, artifacts] of Object.entries(modules)) {
    if (opts.moduleFilter && !opts.moduleFilter.has(modName)) continue;
    const sections = [`CREATE MODULE ${modName};\n`];

    for (const item of artifacts.statics) {
      try { sections.push(mapEnumeration(item)); artifactsTranslated++; }
      catch (e) { warnings.push({ module: modName, artifact: item.name, issue: e.message }); }
    }
    for (const item of artifacts.entities) {
      try { sections.push(mapEntity(item, allEntities)); artifactsTranslated++; }
      catch (e) { warnings.push({ module: modName, artifact: item.name, issue: e.message }); }
    }
    for (const item of (artifacts.structures || [])) {
      try { sections.push(mapStructure(item, structureIndex)); artifactsTranslated++; }
      catch (e) { warnings.push({ module: modName, artifact: item.name, issue: e.message }); }
    }
    for (const item of artifacts.logics) {
      try { sections.push(mapMicroflow(item, structureIndex, parentIndex, dsaIndex, paramIndex)); artifactsTranslated++; }
      catch (e) { warnings.push({ module: modName, artifact: item.name, issue: e.message }); }
    }
    for (const item of artifacts.screens) {
      try { sections.push(mapPage(item, opts.layout)); artifactsTranslated++; }
      catch (e) { warnings.push({ module: modName, artifact: item.name, issue: e.message }); }
    }
    for (const item of artifacts.serviceApis) {
      try { sections.push(mapServiceApi(item)); artifactsTranslated++; }
      catch (e) { warnings.push({ module: modName, artifact: item.name, issue: e.message }); }
    }
    for (const item of artifacts.timers) {
      try { sections.push(mapTimer(item)); artifactsTranslated++; }
      catch (e) { warnings.push({ module: modName, artifact: item.name, issue: e.message }); }
    }
    for (const item of (artifacts.extEntities || [])) {
      try { sections.push(mapExtEntity(item)); artifactsTranslated++; }
      catch (e) { warnings.push({ module: modName, artifact: item.name, issue: e.message }); }
    }

    fs.writeFileSync(path.join(outDir, `${modName}.mdl`), sections.join('\n'));
  }

  const report = { modulesGenerated: Object.keys(modules).length, artifactsTranslated, warnings, errors: [] };
  fs.writeFileSync(path.join(outDir, 'generation-report.json'), JSON.stringify(report, null, 2));

  return report;
}

module.exports = { generate };
