'use strict';

/**
 * Frontend extractor for React/TypeScript.
 * Reads src/containers/*.tsx → screen items (one per container/page component).
 * Also scans src/graphql/query.ts and src/graphql/mutation.ts for API call shapes.
 *
 * Output: { source: 'frontend', items: [...], errors: [...], meta: {...} }
 * Written to: <knowledgeBaseDir>/extracted/frontend.json
 */

const fs   = require('fs');
const path = require('path');

const sourceDir        = process.argv[2];
const knowledgeBaseDir = process.argv[3] || path.join(__dirname, '..', 'knowledge-base');

if (!sourceDir) {
  console.error('Usage: node frontend-extractor.js <projectSourceDir> [knowledgeBaseDir]');
  process.exit(1);
}

const outputDir  = path.join(knowledgeBaseDir, 'extracted');
const outputFile = path.join(outputDir, 'frontend.json');
fs.mkdirSync(outputDir, { recursive: true });

const startTime = Date.now();
const errors    = [];
const items     = [];
let   fileCount = 0;

function readFile(filePath) {
  try { return fs.readFileSync(filePath, 'utf8'); }
  catch (e) { errors.push({ file: filePath, error: e.message }); return null; }
}

function slug(name) {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '-');
}

// ── 1. GraphQL operations scan ────────────────────────────────────────────────
// Collect named queries/mutations from graphql/*.ts → used to annotate screen items.

const gqlApiCalls = new Map(); // operationName → { method, path }

const gqlDir = path.join(sourceDir, 'src', 'graphql');
if (fs.existsSync(gqlDir)) {
  for (const file of fs.readdirSync(gqlDir).filter(f => f.endsWith('.ts'))) {
    const content = readFile(path.join(gqlDir, file));
    if (!content) continue;
    fileCount++;

    // Extract gql operation names: query GetTransactions { ... } or mutation CreateTransaction { ... }
    const opRegex = /\b(query|mutation|subscription)\s+(\w+)/g;
    let om;
    while ((om = opRegex.exec(content)) !== null) {
      const opType = om[1];
      const opName = om[2];
      // Map common GraphQL operation patterns to REST-like paths for linker compatibility
      const method = opType === 'query' ? 'GET' : 'POST';
      // Infer path from operation name: GetTransactions → /transactions, CreateTransaction → /transactions
      const entityPart = opName.replace(/^(Get|Create|Update|Delete|List|Fetch)/, '').toLowerCase();
      gqlApiCalls.set(opName, { method, path: `/${entityPart}s`.replace(/ss$/, 's') });
    }
  }
}

// Also scan src/utils/apolloClient.ts for the base URL
const apolloFile = path.join(sourceDir, 'src', 'utils', 'apolloClient.ts');
if (fs.existsSync(apolloFile)) { readFile(apolloFile); fileCount++; } // just count it

// ── 2. REST calls from containers ─────────────────────────────────────────────
// Scan axios calls: axios.get('/api/transactions'), axios.post('/api/users'), etc.

function extractAxiosCalls(content) {
  const calls = [];
  const axiosRegex = /axios\.(get|post|patch|put|delete)\s*\(\s*[`'"]([^`'"]+)[`'"]/gi;
  let am;
  while ((am = axiosRegex.exec(content)) !== null) {
    calls.push({ method: am[1].toUpperCase(), path: am[2].replace(/\${[^}]+}/g, ':param') });
  }
  return calls;
}

// ── 3. Container extraction (src/containers/*.tsx) ───────────────────────────

const containersDir = path.join(sourceDir, 'src', 'containers');
if (!fs.existsSync(containersDir)) {
  errors.push({ file: containersDir, error: 'containers directory not found — skipping frontend screens' });
} else {
  const containerFiles = fs.readdirSync(containersDir)
    .filter(f => f.endsWith('.tsx') || f.endsWith('.ts'));

  for (const file of containerFiles) {
    if (file.endsWith('.cy.tsx')) continue; // skip Cypress component tests

    const filePath = path.join(containersDir, file);
    const content  = readFile(filePath);
    if (!content) continue;
    fileCount++;

    const screenName = path.basename(file, path.extname(file)); // e.g. TransactionsContainer
    const module     = 'frontend';

    // Collect API calls (axios REST)
    const apiCalls = extractAxiosCalls(content);

    // Collect referenced GraphQL operations (useQuery/useMutation hook calls)
    const gqlOpRegex = /use(?:Query|Mutation|Subscription)\s*\(\s*(\w+)/g;
    let gm;
    while ((gm = gqlOpRegex.exec(content)) !== null) {
      const opName = gm[1];
      if (gqlApiCalls.has(opName)) {
        apiCalls.push(gqlApiCalls.get(opName));
      }
    }

    // Collect composed child components (JSX usage: <TransactionDetail ... />)
    const composesComponents = [];
    const jsxRegex = /<([A-Z][A-Za-z]+)[\s/>]/g;
    let jx;
    while ((jx = jsxRegex.exec(content)) !== null) {
      const comp = jx[1];
      if (comp !== screenName && !composesComponents.includes(comp)) {
        composesComponents.push(comp);
      }
    }

    // Infer screen kind from name
    let screenKind = 'page';
    if (/Modal|Dialog|Aside/.test(screenName))  screenKind = 'modal';
    if (/Section|Part|Item/.test(screenName))   screenKind = 'embedded';

    // Infer entity binding from name pattern: TransactionDetailContainer → Transaction
    const entityMatch = screenName.match(/^([A-Z][a-z]+)/);
    const boundEntity = entityMatch ? entityMatch[1] : null;

    items.push({
      type:               'screen',
      name:               screenName,
      module,
      linkId:             `screen:${module}:${slug(screenName)}`,
      screenKind,
      boundEntity,
      apiCalls,
      composesComponents,
      widgetSummary: {
        dataSources:    boundEntity ? [`${boundEntity}List`] : [],
        boundEntities:  boundEntity ? [boundEntity] : [],
      },
      description: `React container extracted from ${file}`,
      _gaps: apiCalls.length === 0 && composesComponents.length === 0
        ? ['no-api-calls-found']
        : [],
    });
  }
}

// ── Write output ──────────────────────────────────────────────────────────────

const result = {
  source: 'frontend',
  items,
  errors,
  meta: { fileCount, duration: Date.now() - startTime },
};

fs.writeFileSync(outputFile, JSON.stringify(result, null, 2), 'utf8');
console.log(`frontend-extractor: ${items.length} items from ${fileCount} files → ${outputFile}`);
if (errors.length) {
  console.warn(`  Errors: ${errors.length}`);
  errors.forEach(e => console.warn(`    ${e.file}: ${e.error}`));
}
