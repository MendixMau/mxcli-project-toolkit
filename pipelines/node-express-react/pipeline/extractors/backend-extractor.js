'use strict';

/**
 * Backend extractor for Node/Express + TypeScript.
 * Reads three source shapes:
 *   1. model files      — TypeScript interfaces, type aliases and enums → entity + staticEntity
 *   2. route files      — Express router.METHOD(...) calls → logic items (one per handler)
 *   3. SQL migrations   — CREATE TABLE DDL → entity items (the most reliable of the three:
 *                         a schema states nullability, keys and FKs that TS types only imply)
 *
 * Does NOT use an AST parser — regex scanning is sufficient for the small, cleanly structured
 * sources this pipeline targets. If a source grows or becomes messier, replace the regex
 * passes with ts-morph.
 *
 * LAYOUT IS CONFIGURED, NOT ASSUMED (2026-08-31). The directories below used to be
 * hardcoded to the Cypress-RWA shape (`src/models`, `backend/*-routes.ts`). A second real
 * source (`api/src/shared/db/types.ts` + `api/src/api/routes/*.ts`) matched the
 * stack and not the layout, so the extractor found nothing and said so only as a directory
 * -not-found error — the silent-miss failure this pipeline's README warns about. Layout now
 * comes from config.json's `layout` block; the defaults ARE the RWA shape, so an existing
 * project's run is unchanged. Point a new source at its own paths instead of forking a copy.
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

// ── Layout config ────────────────────────────────────────────────────────────
// Defaults preserve the original RWA behaviour exactly; config.json overrides them.
const DEFAULT_LAYOUT = {
  modelDirs:        ['src/models'],   // every .ts in these dirs (index.ts skipped)
  modelFiles:       [],               // explicit files, for sources with one types module
  routeDirs:        ['backend'],
  routeFilePattern: '-routes\\.ts$',  // regex against the filename
  routeModuleStrip: '-routes',        // stripped from the basename to name the module
  sqlDirs:          [],               // CREATE TABLE migrations, e.g. ['api/db/migrations']
  serverFiles:      [],               // files whose app.use('<prefix>', xRouter) mounts routes
  skipEntityPattern: 'Payload|Response|Query|Scenario|Pagination|Range|Value|Piece',
};

// PIPELINE_CONFIG lets a project keep its own config file (with its real paths) outside this
// clone — the repo rule is that real local paths are never committed here, and a project that
// has to edit the toolkit's config.json to run an extraction cannot obey it.
function loadLayout() {
  const configPath = process.env.PIPELINE_CONFIG || path.join(__dirname, '..', 'config.json');
  try {
    const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    return { ...DEFAULT_LAYOUT, ...(cfg.layout || {}) };
  } catch {
    return { ...DEFAULT_LAYOUT };
  }
}
const layout = loadLayout();

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

// ── 1. Model extraction (layout.modelDirs / layout.modelFiles) ───────────────
// Extracts TypeScript interfaces AND type aliases → entity items, enums → staticEntity items.

const modelPaths = [];
for (const dir of layout.modelDirs) {
  const abs = path.join(sourceDir, dir);
  if (!fs.existsSync(abs)) { errors.push({ file: abs, error: 'models directory not found' }); continue; }
  for (const f of fs.readdirSync(abs)) {
    if (f.endsWith('.ts') && f !== 'index.ts') modelPaths.push(path.join(abs, f));
  }
}
for (const rel of layout.modelFiles) {
  const abs = path.join(sourceDir, rel);
  if (!fs.existsSync(abs)) { errors.push({ file: abs, error: 'model file not found' }); continue; }
  modelPaths.push(abs);
}
{
  const skipEntity = new RegExp(layout.skipEntityPattern);
  for (const filePath of modelPaths) {
    const file     = path.basename(filePath);
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

    // Extract interfaces AND type aliases → entity.
    // `export type X = { … }` is as common as `export interface X { … }` in Express/TS
    // sources and used to be invisible here: the second source declares all four entities that
    // way, so the extractor read its types module and produced zero entities.
    const ifaceRegex = /export\s+(?:interface\s+(\w+)\s*(?:extends[^{]*)?|type\s+(\w+)\s*=\s*)\{([^}]+)\}/gs;
    let im;
    while ((im = ifaceRegex.exec(content)) !== null) {
      const ifaceName = im[1] || im[2];
      // Skip payload/utility types (not persistent entities)
      if (skipEntity.test(ifaceName)) continue;

      const body  = im[3];
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

// ── 2a. Router mount prefixes (layout.serverFiles) ───────────────────────────
// A router file's own paths are relative to where the app mounts it. One source's viewers
// router declares '/' and '/:viewerId'; mounted at '/api/dashboards/:dashboardId/viewers'
// those are two real endpoints, and without the prefix they extract as a nameless '/'.
// Maps the exported router identifier → its mount path.
const mountPrefixes = new Map();
for (const rel of layout.serverFiles) {
  const abs = path.join(sourceDir, rel);
  if (!fs.existsSync(abs)) { errors.push({ file: abs, error: 'server file not found' }); continue; }
  const content = readFile(abs);
  if (!content) continue;
  fileCount++;
  const useRegex = /app\.use\s*\(\s*['"`]([^'"`]+)['"`]\s*,\s*(\w+)\s*\)/g;
  let um;
  while ((um = useRegex.exec(content)) !== null) mountPrefixes.set(um[2], um[1]);
}

function joinRoute(prefix, routePath) {
  if (!prefix) return routePath;
  const tail = routePath === '/' ? '' : routePath;
  return `${prefix}${tail}`.replace(/\/{2,}/g, '/');
}

// ── 2b. Route extraction (layout.routeDirs) ──────────────────────────────────
// Extracts Express router.get/post/patch/delete calls → logic items.

const routePaths = [];
for (const dir of layout.routeDirs) {
  const abs = path.join(sourceDir, dir);
  if (!fs.existsSync(abs)) { errors.push({ file: abs, error: 'routes directory not found' }); continue; }
  const re = new RegExp(layout.routeFilePattern);
  for (const f of fs.readdirSync(abs)) if (re.test(f)) routePaths.push(path.join(abs, f));
}
{
  for (const filePath of routePaths) {
    const file       = path.basename(filePath);
    const content    = readFile(filePath);
    if (!content) continue;
    fileCount++;

    // Derive module name from filename: "transaction-routes.ts" → "transaction",
    // "viewers.ts" → "viewers" when routeModuleStrip does not appear.
    const moduleName = path.basename(file, '.ts')
      .replace(layout.routeModuleStrip, '')
      .replace(/-([a-z])/g, (_, c) => c.toUpperCase());

    // This file's own mount prefix, if the server file named its router export.
    let filePrefix = '';
    for (const [routerName, prefix] of mountPrefixes) {
      if (new RegExp(`export\\s+const\\s+${routerName}\\b`).test(content)) { filePrefix = prefix; break; }
    }

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
      const routePath  = joinRoute(filePrefix, rm[2]);

      // Derive a readable name from method + path
      const pathParts  = routePath.split('/').filter(p => p && !p.startsWith(':') && p !== 'api');
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

// ── 3. SQL schema extraction (layout.sqlDirs) ────────────────────────────────
// CREATE TABLE DDL → entity items. A schema is the most reliable domain source in this
// stack: it states NOT NULL, UNIQUE, PRIMARY KEY and the foreign keys that a TypeScript
// type only implies through a naming convention. Emitted with source 'sql' on each item so
// the merger's dedupe keeps the schema-derived attributes visible next to the TS-derived
// ones rather than silently preferring whichever loaded first.

const SQL_TYPE_MAP = {
  text: 'String', varchar: 'String', char: 'String', uuid: 'String',
  int: 'Integer', integer: 'Integer', smallint: 'Integer', bigint: 'Long', serial: 'AutoNumber',
  numeric: 'Decimal', decimal: 'Decimal', real: 'Decimal', 'double': 'Decimal',
  bool: 'Boolean', boolean: 'Boolean',
  timestamp: 'DateTime', timestamptz: 'DateTime', date: 'DateTime', time: 'DateTime',
  json: 'String', jsonb: 'String', bytea: 'Binary',
};

function pascal(s) {
  return String(s).split(/[_\s]+/).filter(Boolean)
    .map(p => p[0].toUpperCase() + p.slice(1)).join('');
}
function singular(s) {
  if (/ies$/.test(s)) return s.replace(/ies$/, 'y');
  if (/sses$/.test(s)) return s.replace(/es$/, '');
  if (/s$/.test(s) && !/ss$/.test(s)) return s.replace(/s$/, '');
  return s;
}

const sqlEntitiesByTable = new Map();   // table → item, so later migrations amend earlier ones
const droppedTables = new Set();

for (const dir of layout.sqlDirs) {
  const abs = path.join(sourceDir, dir);
  if (!fs.existsSync(abs)) { errors.push({ file: abs, error: 'sql directory not found' }); continue; }
  const sqlFiles = fs.readdirSync(abs).filter(f => f.endsWith('.sql')).sort();   // applied in order

  for (const file of sqlFiles) {
    const content = readFile(path.join(abs, file));
    if (!content) continue;
    fileCount++;

    // DROP TABLE — a migration that retires a table is a statement about the target model.
    const dropRegex = /DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?["`]?(\w+)["`]?/gi;
    let dm;
    while ((dm = dropRegex.exec(content)) !== null) {
      droppedTables.add(dm[1].toLowerCase());
      sqlEntitiesByTable.delete(dm[1].toLowerCase());
    }

    // CREATE TABLE <name> ( <body> );
    const tableRegex = /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?["`]?(\w+)["`]?\s*\(([\s\S]*?)\n\)\s*;/gi;
    let tm;
    while ((tm = tableRegex.exec(content)) !== null) {
      const table = tm[1].toLowerCase();
      if (droppedTables.has(table)) continue;
      if (/^(schema_migrations|_prisma_migrations)$/.test(table)) continue;   // infrastructure

      const entityName = pascal(singular(table));
      const attrs = [];

      for (const rawLine of tm[2].split('\n')) {
        const line = rawLine.trim().replace(/,$/, '');
        if (!line || line.startsWith('--')) continue;
        if (/^(PRIMARY|UNIQUE|FOREIGN|CONSTRAINT|CHECK)\b/i.test(line)) continue;  // table-level

        const cm = line.match(/^["`]?(\w+)["`]?\s+([A-Za-z]+)/);
        if (!cm) continue;
        const column = cm[1];
        const sqlType = cm[2].toLowerCase();
        if (column.toLowerCase() === 'id') continue;   // Mendix supplies the identity

        const fkMatch = line.match(/REFERENCES\s+["`]?(\w+)["`]?/i);
        attrs.push({
          name:             column,
          type:             SQL_TYPE_MAP[sqlType] || 'String',
          sqlType,
          isMandatory:      /NOT\s+NULL/i.test(line),
          isUnique:         /\bUNIQUE\b/i.test(line),
          hasDefault:       /\bDEFAULT\b/i.test(line),
          isForeignKey:     Boolean(fkMatch),
          referencedEntity: fkMatch ? pascal(singular(fkMatch[1].toLowerCase())) : null,
          isAutoNumber:     sqlType === 'serial',
          deleteRule:       /ON\s+DELETE\s+CASCADE/i.test(line) ? 'DeleteMeAndReferences'
                            : (fkMatch ? 'SetNone' : ''),
        });
      }

      sqlEntitiesByTable.set(table, {
        type:         'entity',
        name:         entityName,
        module:       'schema',
        linkId:       `entity:schema:${entityName}`,
        isPersistent: true,
        isPublic:     true,
        description:  `Persistent entity extracted from SQL table "${table}" (${file})`,
        sourceTable:  table,
        extractedFrom: 'sql',
        attributes:   attrs,
        indexes:      [],
        _gaps:        [],
      });
    }

    // ALTER TABLE <t> ADD COLUMN [IF NOT EXISTS] <col> <type> …
    const alterRegex = /ALTER\s+TABLE\s+["`]?(\w+)["`]?\s+ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?["`]?(\w+)["`]?\s+([A-Za-z]+)([^;,]*)/gi;
    let am2;
    while ((am2 = alterRegex.exec(content)) !== null) {
      const entity = sqlEntitiesByTable.get(am2[1].toLowerCase());
      if (!entity) continue;
      if (entity.attributes.some(a => a.name === am2[2])) continue;
      const sqlType = am2[3].toLowerCase();
      entity.attributes.push({
        name: am2[2], type: SQL_TYPE_MAP[sqlType] || 'String', sqlType,
        isMandatory: /NOT\s+NULL/i.test(am2[4]), isUnique: false,
        hasDefault: /\bDEFAULT\b/i.test(am2[4]),
        isForeignKey: false, referencedEntity: null, isAutoNumber: false, deleteRule: '',
      });
    }
  }
}
// ── 3b. Reconcile the two entity readings ────────────────────────────────────
// A source with both TS types and SQL migrations describes each entity TWICE, and emitting
// both puts two "User" entities in the knowledge base — which reads downstream as two real
// entities, not one seen from two angles. Reconcile instead, taking what each reading is
// actually authoritative for: the schema for constraints (NOT NULL, UNIQUE, FK, delete
// rule), the TypeScript type for the attribute NAMES a developer wrote (createdAt, not
// created_at) and for any field the schema does not carry. Both origins stay recorded so a
// reviewer can see which half came from where.
function normalizeAttr(name) { return name.toLowerCase().replace(/[^a-z0-9]/g, ''); }

for (const sqlEntity of sqlEntitiesByTable.values()) {
  const tsIndex = items.findIndex(i => i.type === 'entity' && i.name === sqlEntity.name && i.extractedFrom !== 'sql');
  if (tsIndex === -1) { items.push(sqlEntity); continue; }

  const tsEntity = items[tsIndex];
  const tsByNorm = new Map(tsEntity.attributes.map(a => [normalizeAttr(a.name), a]));
  const merged = [];

  for (const sqlAttr of sqlEntity.attributes) {
    const tsAttr = tsByNorm.get(normalizeAttr(sqlAttr.name));
    merged.push({
      ...sqlAttr,
      name:       tsAttr ? tsAttr.name : sqlAttr.name,     // developer-facing name wins
      columnName: sqlAttr.name,
      tsType:     tsAttr ? tsAttr.type : null,
      origin:     tsAttr ? 'sql+ts' : 'sql-only',
    });
    if (tsAttr) tsByNorm.delete(normalizeAttr(sqlAttr.name));
  }
  // Anything the TS type declares that no column backs — computed/derived, and a real finding.
  for (const leftover of tsByNorm.values()) {
    merged.push({ ...leftover, columnName: null, origin: 'ts-only' });
  }

  items[tsIndex] = {
    ...sqlEntity,
    module:        tsEntity.module,
    linkId:        tsEntity.linkId,
    extractedFrom: 'sql+ts',
    description:   `${sqlEntity.description}; names reconciled with ${tsEntity.module}.ts`,
    attributes:    merged,
    _gaps:         merged.some(a => a.origin === 'ts-only') ? ['ts-field-without-column'] : [],
  };
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
