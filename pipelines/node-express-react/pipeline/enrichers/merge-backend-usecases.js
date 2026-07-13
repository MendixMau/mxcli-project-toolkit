'use strict';

/**
 * Merge backend use cases (from backend-usecase-mapper) into their respective BRD files.
 * Each BRD file gets its own set of use cases extracted from its Express routes.
 *
 * Usage: node merge-backend-usecases.js <knowledgeBaseDir>
 */

const fs = require('fs');
const path = require('path');

const knowledgeBaseDir = process.argv[2];

if (!knowledgeBaseDir) {
  console.error('Usage: node merge-backend-usecases.js <knowledgeBaseDir>');
  process.exit(1);
}

const usecasesFile = path.join(knowledgeBaseDir, 'extracted', 'backend-usecases.json');
const brdDir = path.join(knowledgeBaseDir, 'brd');

if (!fs.existsSync(usecasesFile)) {
  console.error(`Backend use cases file not found: ${usecasesFile}`);
  process.exit(1);
}

const usecases = JSON.parse(fs.readFileSync(usecasesFile, 'utf8'));

let mergedCount = 0;

// Group use cases by module
const byModule = {};
for (const uc of usecases.items) {
  const mod = uc.module;
  if (!byModule[mod]) byModule[mod] = [];
  byModule[mod].push(uc);
}

// Write each module's use cases into its BRD
for (const [module, moduleUcs] of Object.entries(byModule)) {
  const brdFile = path.join(brdDir, `${module}.brd.json`);

  try {
    let brd = {};
    if (fs.existsSync(brdFile)) {
      brd = JSON.parse(fs.readFileSync(brdFile, 'utf8'));
    } else {
      brd = {
        module,
        timestamp: new Date().toISOString(),
        summary: {},
      };
    }

    // Merge use cases (don't overwrite existing, just add new)
    const existingIds = new Set((brd.useCases || []).map(u => u.id));
    const newUcs = moduleUcs.filter(u => !existingIds.has(u.id));

    brd.useCases = [...(brd.useCases || []), ...newUcs];

    // Update summary
    if (!brd.summary) brd.summary = {};
    brd.summary.useCaseCount = brd.useCases.length;

    fs.writeFileSync(brdFile, JSON.stringify(brd, null, 2), 'utf8');
    mergedCount += newUcs.length;
    console.log(`  ${module}: +${newUcs.length} use cases (total: ${brd.useCases.length})`);
  } catch (e) {
    console.error(`Error merging use cases for ${module}: ${e.message}`);
  }
}

console.log(`✓ Merged ${mergedCount} backend use cases into ${Object.keys(byModule).length} BRD files.`);
