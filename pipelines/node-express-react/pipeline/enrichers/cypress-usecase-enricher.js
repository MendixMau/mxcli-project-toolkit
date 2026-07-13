'use strict';

/**
 * Cypress use-case enricher.
 * Reads Cypress test specs and uses them to enrich BRD use cases with:
 * - Real actor flows extracted from test steps
 * - Main flow sequence from cy. commands
 * - Pre/postconditions inferred from setup + assertions
 * - Endpoint coverage mapping
 *
 * Merges enriched data back into BRD JSON files.
 */

const fs   = require('fs');
const path = require('path');

const sourceDir        = process.argv[2];
const knowledgeBaseDir = process.argv[3] || path.join(__dirname, '..', 'knowledge-base');

const cypressDir = path.join(sourceDir, 'cypress', 'tests', 'ui');
const brdDir = path.join(knowledgeBaseDir, 'brd');

if (!fs.existsSync(cypressDir)) {
  console.error('Cypress tests directory not found');
  process.exit(1);
}

if (!fs.existsSync(brdDir)) {
  console.error('BRD directory not found');
  process.exit(1);
}

let enrichedCount = 0;

// ── Parse a Cypress spec and extract test scenarios ────────────────────────
function parseSpec(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const scenarios = [];

  // Extract describe() blocks
  const describeRegex = /describe\s*\(\s*["'`]([^"'`]+)["'`].*?\);/gs;
  let dm;
  while ((dm = describeRegex.exec(content)) !== null) {
    const describeBody = dm[0];
    const describeName = dm[1];

    // Extract it() blocks within describe
    const itRegex = /it\s*\(\s*["'`]([^"'`]+)["'`]\s*,\s*function\s*\(\s*\)\s*{([^}]+(?:{[^}]*}[^}]*)*(?:}[^}]*)*)/g;
    let im;
    while ((im = itRegex.exec(describeBody)) !== null) {
      const testName = im[1];
      const testBody = im[2] || '';

      // Extract key Cypress commands
      const mainFlow = [];
      const endpoints = [];
      const actors = [];

      // cy.intercept("METHOD", "/path")
      const interceptRegex = /cy\.intercept\s*\(\s*["'`]([A-Z]+)["'`]\s*,\s*["'`]([^"'`]+)["'`]/g;
      let om;
      while ((om = interceptRegex.exec(testBody)) !== null) {
        endpoints.push(`${om[1]} ${om[2]}`);
      }

      // cy.loginByXstate / cy.login → User is authenticated
      if (/cy\.(login|loginByXstate)/.test(testBody)) {
        mainFlow.push('User logs in');
        actors.push('Authenticated User');
      }

      // cy.getBySelLike("new-transaction").click()
      if (/new-transaction.*\.click/.test(testBody)) {
        mainFlow.push('User navigates to new transaction form');
      }
      if (/user-list-search-input.*\.type/.test(testBody)) {
        mainFlow.push('User searches for recipient');
      }
      if (/amount-input.*\.type/.test(testBody)) {
        mainFlow.push('User enters transaction amount');
      }
      if (/description-input.*\.type/.test(testBody)) {
        mainFlow.push('User enters transaction description');
      }
      if (/submit-payment.*\.click/.test(testBody)) {
        mainFlow.push('User submits payment');
      }
      if (/submit-request.*\.click/.test(testBody)) {
        mainFlow.push('User submits payment request');
      }

      // cy.get("alert-bar-success")
      if (/alert-bar-success/.test(testBody)) {
        mainFlow.push('Success confirmation displayed');
      }

      // Extract database operations
      if (/cy\.database\s*\(\s*["'`]filter["'`]/.test(testBody)) {
        mainFlow.push('Database is queried for verification');
      }
      if (/cy\.database\s*\(\s*["'`]find["'`]/.test(testBody)) {
        mainFlow.push('Database state is verified');
      }

      scenarios.push({
        testName,
        describeName,
        mainFlow: mainFlow.length ? mainFlow : ['User performs action', 'System processes request'],
        endpoints,
        actors: actors.length ? actors : ['User'],
      });
    }
  }

  return scenarios;
}

// ── Match scenarios to BRD use cases ──────────────────────────────────────
function enrich() {
  const specFiles = fs.readdirSync(cypressDir)
    .filter(f => f.endsWith('.spec.ts'));

  for (const specFile of specFiles) {
    const scenarios = parseSpec(path.join(cypressDir, specFile));
    console.log(`  ${specFile}: ${scenarios.length} scenarios`);

    for (const scenario of scenarios) {
      // Try to match to a BRD file by domain
      // e.g., "New Transaction" → transaction.brd.json
      const domain = scenario.describeName
        .toLowerCase()
        .replace(/\s+/g, '-')
        .replace(/transaction/i, 'transaction')
        .replace(/bank\s*account/i, 'bankaccount')
        .replace(/notification/i, 'notification')
        .replace(/auth/i, 'user');

      const brdFile = path.join(brdDir, `${domain}.brd.json`);

      if (fs.existsSync(brdFile)) {
        try {
          const brd = JSON.parse(fs.readFileSync(brdFile, 'utf8'));

          // Enrich existing UCs in this BRD with scenario data
          if (brd.useCases && brd.useCases.length) {
            for (const uc of brd.useCases) {
              if (uc.status === 'code-inferred' && uc.reviewStatus === 'pending') {
                // Match by title similarity or endpoint
                const titleMatch = scenario.testName.toLowerCase().includes(uc.title.toLowerCase().split(' ')[0]);
                const endpointMatch = scenario.endpoints.some(e => {
                  if (uc.endpoint && (uc.endpoint.path || uc.endpoint)) {
                    const ucPath = uc.endpoint.path || uc.endpoint;
                    return e.includes(ucPath.split('/')[1] || '');
                  }
                  return false;
                });

                if (titleMatch || endpointMatch) {
                  // Enrich with test data
                  uc.mainFlow = [
                    ...scenario.mainFlow,
                    ...(uc.mainFlow || []).filter(f => !f.includes('User') && !f.includes('Express')),
                  ];
                  if (!uc.actors || uc.actors.some(a => a.includes('TODO'))) {
                    uc.actors = scenario.actors.length ? scenario.actors : uc.actors;
                  }
                  // Mark as partially enriched
                  uc.reviewStatus = 'test-verified';
                  enrichedCount++;
                  break; // Move to next UC
                }
              }
            }
          }

          // Write back
          fs.writeFileSync(brdFile, JSON.stringify(brd, null, 2), 'utf8');
        } catch (e) {
          console.warn(`  Error enriching ${brdFile}: ${e.message}`);
        }
      }
    }
  }
}

console.log('Enriching BRD use cases from Cypress tests...');
enrich();
console.log(`✓ Enriched ${enrichedCount} use cases from Cypress test scenarios.`);
