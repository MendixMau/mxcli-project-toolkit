'use strict';

/**
 * Frontend extractor for React/TypeScript.
 * Reads the configured screen directories → screen items (one per page/component).
 * Also scans src/graphql/query.ts and src/graphql/mutation.ts for API call shapes.
 *
 * LAYOUT IS CONFIGURED, NOT ASSUMED (2026-08-31) — see the same note in
 * backend-extractor.js. `src/containers` is the RWA shape and remains the default; a source
 * that keeps screens in `web/src/pages` + `web/src/components` sets config.json's
 * `layout.screenDirs` rather than forking this file. Directories are walked recursively,
 * because pages routinely nest one level (`pages/user/UserApp.tsx`).
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

// ── 1b. Typed API-client scan (layout.apiClientFiles) ────────────────────────
// A React app that centralises its calls in a typed client module (`api.listDashboards(id)`
// → `request('/api/users/${id}/dashboards')`) has NO axios call anywhere in a screen, so the
// axios pass below reports every screen as `no-api-calls-found` and the linker cannot join a
// single screen to an endpoint. Field case: Puffin, 10 of 10 screens with zero API calls
// while the client module held all 13. This pass maps client method → {method, path}; the
// screen pass then resolves `client.method(` usages through it, exactly as it already does
// for GraphQL operations.
const clientApiCalls = new Map();   // methodName → { method, path }

function loadFrontendLayout() {
  try {
    const cfg = JSON.parse(fs.readFileSync(process.env.PIPELINE_CONFIG || path.join(__dirname, '..', 'config.json'), 'utf8'));
    return cfg.layout || {};
  } catch { return {}; }
}
const feLayout = loadFrontendLayout();

for (const rel of (feLayout.apiClientFiles || [])) {
  const abs = path.join(sourceDir, rel);
  if (!fs.existsSync(abs)) { errors.push({ file: abs, error: 'api client file not found' }); continue; }
  const content = readFile(abs);
  if (!content) continue;
  fileCount++;

  // methodName: (args) => request<T>(`/api/...`, { method: 'POST' })  — and fetch(`${base}/api/...`)
  // The body window is generous on purpose: a one-line `=> request('/path')` and a
  // block-bodied `async () => { … 40 lines of status handling … }` are both normal in a
  // hand-written client, and a short window silently drops the second kind (Puffin's
  // fetchMe and fetchVersionContent, the two methods with their own error handling).
  const methodRegex = /(\w+)\s*:\s*(?:async\s*)?\([^)]*\)\s*(?::[^=]+)?=>\s*([\s\S]{0,2000}?)(?=\n\s{2}(?:\/\*|\w+\s*:)|\n\};)/g;
  let mm;
  while ((mm = methodRegex.exec(content)) !== null) {
    const methodName = mm[1];
    const body       = mm[2];
    const pathMatch  = body.match(/[`'"]((?:\$\{[^}]*\})?\/[^`'"]*)[`'"]/);
    if (!pathMatch) continue;
    const httpMatch  = body.match(/method:\s*['"](\w+)['"]/);
    const urlPath    = pathMatch[1]
      .replace(/\$\{[^}]*base[^}]*\}/gi, '')          // strip the base-URL interpolation
      .replace(/\$\{[^}]+\}/g, ':param');             // remaining interpolations are params
    if (!urlPath.startsWith('/')) continue;
    clientApiCalls.set(methodName, { method: (httpMatch ? httpMatch[1] : 'GET').toUpperCase(), path: urlPath });
  }
}

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

// ── 3. Screen extraction (layout.screenDirs) ─────────────────────────────────

const DEFAULT_SCREEN_DIRS = ['src/containers'];
function loadScreenDirs() {
  try {
    const cfg = JSON.parse(fs.readFileSync(process.env.PIPELINE_CONFIG || path.join(__dirname, '..', 'config.json'), 'utf8'));
    return (cfg.layout && cfg.layout.screenDirs) || DEFAULT_SCREEN_DIRS;
  } catch { return DEFAULT_SCREEN_DIRS; }
}

function walkTsx(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walkTsx(full, out);
    else if (/\.(tsx|ts)$/.test(entry.name) && !entry.name.endsWith('.cy.tsx') && !entry.name.endsWith('.d.ts')) out.push(full);
  }
  return out;
}

const screenPaths = [];
for (const rel of loadScreenDirs()) {
  const abs = path.join(sourceDir, rel);
  if (!fs.existsSync(abs)) { errors.push({ file: abs, error: 'screen directory not found — skipping' }); continue; }
  walkTsx(abs, screenPaths);
}
{
  for (const filePath of screenPaths) {
    const file     = path.basename(filePath);
    const content  = readFile(filePath);
    if (!content) continue;
    fileCount++;

    const screenName = path.basename(file, path.extname(file)); // e.g. TransactionsContainer
    const module     = 'frontend';

    // Collect API calls (axios REST)
    const apiCalls = extractAxiosCalls(content);

    // Collect typed-client calls: api.listDashboards(…), userApi.fetchMe(…)
    const clientCallRegex = /\b\w*[Aa]pi\.(\w+)\s*\(/g;
    let cm;
    while ((cm = clientCallRegex.exec(content)) !== null) {
      const hit = clientApiCalls.get(cm[1]);
      if (hit && !apiCalls.some(c => c.method === hit.method && c.path === hit.path)) apiCalls.push(hit);
    }

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
