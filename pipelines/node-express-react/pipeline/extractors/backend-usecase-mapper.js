'use strict';

/**
 * Backend use-case mapper for Express routes.
 * Reads backend/*-routes.ts and infers use cases from HTTP endpoints.
 * Outputs use-case scaffolds with code-inferred status.
 *
 * Usage: node backend-usecase-mapper.js <projectSourceDir> <knowledgeBaseDir>
 */

const fs   = require('fs');
const path = require('path');

const sourceDir        = process.argv[2];
const knowledgeBaseDir = process.argv[3] || path.join(__dirname, '..', 'knowledge-base');

if (!sourceDir) {
  console.error('Usage: node backend-usecase-mapper.js <projectSourceDir> [knowledgeBaseDir]');
  process.exit(1);
}

const backendDir = path.join(sourceDir, 'backend');
const items = [];
const errors = [];

function slug(name) {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '-');
}

function inferUcTitle(method, routePath, handlerName) {
  // POST /transactions → "User creates transaction"
  // GET /transactions/:id → "User views transaction detail"
  // PATCH /transactions/:id → "User updates transaction"
  // DELETE /transactions/:id → "User deletes transaction"
  // POST /transactions/:id/like → "User likes transaction"

  const entity = routePath.split('/')[1] || 'resource'; // e.g., 'transactions'
  const singular = entity.replace(/s$/, ''); // transactions → transaction
  const action = routePath.split('/')[3]; // e.g., 'like' from /transactions/:id/like

  const verbMap = {
    'GET':    (e, a) => a ? `User views ${a} on ${e}` : `User views ${e} list`,
    'POST':   (e, a) => a ? `User ${a}s ${e}` : `User creates ${e}`,
    'PATCH':  (e, a) => `User updates ${e}`,
    'PUT':    (e, a) => `User updates ${e}`,
    'DELETE': (e, a) => `User deletes ${e}`,
  };

  const builder = verbMap[method] || (() => `User performs ${method} on ${singular}`);
  return builder(singular, action);
}

function inferActor(routePath) {
  // /users/* → Admin or User (depends on context)
  // /transactions/* → Customer/User
  // /bankaccounts/* → Account Owner
  if (routePath.includes('/users')) return 'Admin or User';
  if (routePath.includes('/admin')) return 'Admin';
  return 'User/Customer';
}

function extractRouteHandlers(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const handlers = [];

  // Match patterns like:
  // router.get('/path', (req, res) => { ... });
  // router.post('/transactions/:id/like', validateRequest(...), (req, res) => { ... });
  const routeRegex = /router\.(get|post|patch|put|delete)\s*\(\s*[`'"]([^`'"]+)[`'"]/gi;
  let m;
  while ((m = routeRegex.exec(content)) !== null) {
    const method = m[1].toUpperCase();
    const path = m[2];
    handlers.push({ method, path });
  }

  return handlers;
}

// ── Scan backend/*-routes.ts ──────────────────────────────────────────────
if (!fs.existsSync(backendDir)) {
  errors.push({ file: backendDir, error: 'backend directory not found' });
} else {
  const routeFiles = fs.readdirSync(backendDir)
    .filter(f => f.endsWith('-routes.ts') && !f.startsWith('gql-'));

  for (const file of routeFiles) {
    const filePath = path.join(backendDir, file);
    try {
      const handlers = extractRouteHandlers(filePath);
      const module = file.replace('-routes.ts', ''); // user, transaction, bankaccount, etc.

      for (let i = 0; i < handlers.length; i++) {
        const { method, path: routePath } = handlers[i];
        const ucId = `UC-${module.toUpperCase()}-${String(i + 1).padStart(2, '0')}`;
        const title = inferUcTitle(method, routePath, file);
        const actor = inferActor(routePath);

        items.push({
          type: 'useCase',
          id: ucId,
          title,
          module,
          linkId: `usecase:${module}:${slug(title)}`,
          endpoint: { method, path: routePath },
          actors: [actor],
          preconditions: [
            'User is authenticated (via /auth)',
            `Endpoint exists: ${method} ${routePath}`
          ],
          mainFlow: [
            `User invokes ${method} ${routePath}`,
            'Express handler processes request',
            'Response returned to frontend'
          ],
          postconditions: [
            'Response state updated in frontend',
            routePath.includes('POST') || routePath.includes('PATCH') || routePath.includes('DELETE')
              ? 'Database may be modified (via lowdb)'
              : 'No database modification'
          ],
          openQuestions: [
            'What validation rules apply to request payload?',
            'What error cases should be handled?',
            'Is this endpoint public or role-restricted?',
            'Are there side effects (e.g., notifications, emails)?'
          ],
          gaps: [],
          status: 'code-inferred',
          reviewStatus: 'pending',
          source: `Express route from ${file}`,
        });
      }
    } catch (e) {
      errors.push({ file: filePath, error: e.message });
    }
  }
}

// ── Write output ──────────────────────────────────────────────────────────
const result = {
  source: 'backend-usecase-mapper',
  items,
  errors,
  meta: {
    fileCount: fs.readdirSync(backendDir).filter(f => f.endsWith('-routes.ts')).length,
    itemCount: items.length,
    timestamp: new Date().toISOString(),
  },
};

const outputDir = path.join(knowledgeBaseDir, 'extracted');
fs.mkdirSync(outputDir, { recursive: true });
const outputFile = path.join(outputDir, 'backend-usecases.json');

fs.writeFileSync(outputFile, JSON.stringify(result, null, 2), 'utf8');
console.log(`backend-usecase-mapper: ${items.length} use cases → ${outputFile}`);
if (errors.length) {
  console.warn(`  Errors: ${errors.length}`);
  errors.forEach(e => console.warn(`    ${e.file}: ${e.error}`));
}
