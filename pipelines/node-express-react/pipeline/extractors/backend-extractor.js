'use strict';

/**
 * Backend extractor for Node/Express + TypeScript.
 * Reads two source shapes:
 *   1. src/models/*.ts   — TypeScript interfaces / enums → entity + staticEntity items
 *   2. backend/*-routes.ts — Express router files → logic items (one per route handler)
 *
 * Does NOT use an AST parser — the RWA source is small and cleanly structured, so regex
 * scanning is sufficient and avoids a tree-sitter dependency for this stack.
 * If the source grows or becomes messier, replace the regex passes with ts-morph.
 *
 * Output: { source: 'backend', items: [...], errors: [...], meta: {...} }
 * Written to: <knowledgeBaseDir>/extracted/backend.json
 */

const fs   = require('fs');
const path = require('path');

const sourceDir      = process.argv[2];
const knowledgeBaseDir = process.argv[3] || path.join(__dirname, '..', 'knowledge-base');

if (!sourceDir) {
  console.error('Usage: node backend-extractor.js <projectSourceDir> [knowledgeBaseDir]');
  process.exit(1);
}

const outputDir  = path.join(knowledgeBaseDir, 'extracted');
const outputFile = path.join(outputDir, 'backend.json');
fs.mkdirSync(outputDir, { recursive: true });

const startTime = Date.now();
const errors    = [];
const items     = [];
let   fileCount = 0;

// ── Helpers ──────────────────────────────────────────────────────────────────

function readFile(filePath) {
  try { return fs.readFileSync(filePath, 'utf8'); }
  catch (e) { errors.push({ file: filePath, error: e.message }); return null; }
}

function slug(name) {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '-');
}

// ── 1. Model extraction (src/models/*.ts) ────────────────────────────────────
// Extracts TypeScript interfaces → entity items, enums → staticEntity items.

const modelsDir = path.join(sourceDir, 'src', 'models');
if (!fs.existsSync(modelsDir)) {
  errors.push({ file: modelsDir, error: 'models directory not found' });
} else {
  const modelFiles = fs.readdirSync(modelsDir).filter(f => f.endsWith('.ts') && f !== 'index.ts');
  for (const file of modelFiles) {
    const filePath = path.join(modelsDir, file);
    const content  = readFile(filePath);
    if (!content) continue;
    fileCount++;

    const moduleName = path.basename(file, '.ts');

    // Extract enums → staticEntity
    const enumRegex = /export\s+enum\s+(\w+)\s*\{([^}]+)\}/g;
    let em;
    while ((em = enumRegex.exec(content)) !== null) {
      const enumName = em[1];
      const body     = em[2];
      const values   = body.split(',')
        .map(v => v.trim().split(/\s*=\s*/)[0].trim())
        .filter(v => v && !v.startsWith('//'));

      items.push({
        type:        'staticEntity',
        name:        enumName,
        module:      moduleName,
        linkId:      `staticEntity:${moduleName}:${enumName}`,
        isPublic:    true,
        description: `Enumeration extracted from ${file}`,
        records:     values.map(v => ({ name: v, label: v })),
        _gaps:       [],
      });
    }

    // Extract interfaces → entity
    const ifaceRegex = /export\s+interface\s+(\w+)\s*(?:extends[^{]*)?\{([^}]+)\}/gs;
    let im;
    while ((im = ifaceRegex.exec(content)) !== null) {
      const ifaceName = im[1];
      // Skip payload/utility types (not persistent entities)
      if (/Payload|Response|Query|Scenario|Pagination|Range|Value|Piece/.test(ifaceName)) continue;

      const body  = im[2];
      const attrs = [];

      const fieldRegex = /^\s*(\w+)\??:\s*([^;\n]+)/gm;
      let fm;
      while ((fm = fieldRegex.exec(body)) !== null) {
        const fieldName = fm[1];
        const fieldType = fm[2].trim().replace(/;$/, '').trim();

        if (['id', 'uuid'].includes(fieldName)) continue; // auto-generated keys

        const isFK       = /Id$/.test(fieldName) || fieldName === 'source';
        const refEntity  = isFK ? fieldName.replace(/Id$/, '') : null;

        // Map enum references — if the type matches a known enum name, tag it
        const isMandatory = !fm[0].includes('?');

        attrs.push({
          name:            fieldName,
          type:            fieldType,
          isMandatory,
          isForeignKey:    isFK,
          referencedEntity: refEntity ? capitalize(refEntity) : null,
          isAutoNumber:    false,
          deleteRule:      isFK ? 'SetNone' : '',
        });
      }

      items.push({
        type:         'entity',
        name:         ifaceName,
        module:       moduleName,
        linkId:       `entity:${moduleName}:${ifaceName}`,
        isPersistent: true,
        isPublic:     true,
        description:  `Persistent entity extracted from ${file}`,
        attributes:   attrs,
        indexes:      [],
        _gaps:        [],
      });
    }
  }
}

// ── 2. Route extraction (backend/*-routes.ts) ────────────────────────────────
// Extracts Express router.get/post/patch/delete calls → logic items.

const backendDir = path.join(sourceDir, 'backend');
if (!fs.existsSync(backendDir)) {
  errors.push({ file: backendDir, error: 'backend directory not found' });
} else {
  const routeFiles = fs.readdirSync(backendDir)
    .filter(f => f.endsWith('-routes.ts'));

  for (const file of routeFiles) {
    const filePath   = path.join(backendDir, file);
    const content    = readFile(filePath);
    if (!content) continue;
    fileCount++;

    // Derive module name from filename: "transaction-routes.ts" → "transaction"
    const moduleName = file.replace('-routes.ts', '').replace(/-([a-z])/g, (_, c) => c.toUpperCase());

    // Collect imported model names (used for NR2 linker rule)
    const importedModels = [];
    const importRegex = /import\s+[^'"]*from\s+['"]\.\.\/src\/models[^'"]*['"]/g;
    const namedImport = /import\s+\{([^}]+)\}/g;
    let   imp;
    while ((imp = namedImport.exec(content)) !== null) {
      imp[1].split(',').map(s => s.trim()).filter(Boolean).forEach(n => importedModels.push(n));
    }

    // Extract route handlers: router.METHOD('path', [...middleware,] handler)
    const routeRegex = /router\.(get|post|patch|put|delete)\s*\(\s*['"`]([^'"`]+)['"`]/gi;
    let   rm;
    while ((rm = routeRegex.exec(content)) !== null) {
      const httpMethod = rm[1].toUpperCase();
      const routePath  = rm[2];

      // Derive a readable name from method + path
      const pathParts  = routePath.split('/').filter(p => p && !p.startsWith(':'));
      const actionVerb = { GET: 'get', POST: 'create', PATCH: 'update', PUT: 'update', DELETE: 'delete' }[httpMethod] || 'handle';
      const name       = `${actionVerb}_${moduleName}_${pathParts.join('_')}`.replace(/[^a-zA-Z0-9_]/g, '_').replace(/_+/g, '_');

      items.push({
        type:            'logic',
        name,
        module:          moduleName,
        linkId:          `logic:${moduleName}:${httpMethod}:${slug(routePath)}`,
        logicKind:       'action',
        description:     `${httpMethod} ${routePath}`,
        httpEndpoint:    { method: httpMethod, path: routePath },
        referencedModels: importedModels,
        calls:           [],
        _gaps:           [],
      });
    }
  }
}

// ── Write output ─────────────────────────────────────────────────────────────

function capitalize(s) { return s ? s[0].toUpperCase() + s.slice(1) : s; }

const result = {
  source: 'backend',
  items,
  errors,
  meta: { fileCount, duration: Date.now() - startTime },
};

fs.writeFileSync(outputFile, JSON.stringify(result, null, 2), 'utf8');
console.log(`backend-extractor: ${items.length} items from ${fileCount} files → ${outputFile}`);
if (errors.length) {
  console.warn(`  Errors: ${errors.length}`);
  errors.forEach(e => console.warn(`    ${e.file}: ${e.error}`));
}
