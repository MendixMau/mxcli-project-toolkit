'use strict';
const fs = require('fs');
const path = require('path');
const Parser = require('tree-sitter');
const TypeScript = require('tree-sitter-typescript').typescript;

// ── Setup ──────────────────────────────────────────────────────────────────
const sourceDir = process.argv[2]; // e.g. .../client/src/app
if (!sourceDir) {
  console.error('Usage: node angular-extractor.js <angularSourceDir>');
  process.exit(1);
}
// argv[3] lets run.js point this at a per-project output dir (config.json's knowledgeBaseDir) so
// this tool never accumulates project-specific data of its own; falls back to a local
// knowledge-base/ for standalone/manual invocation outside the orchestrated pipeline.
const knowledgeBaseDir = process.argv[3] || path.join(__dirname, '..', 'knowledge-base');
// argv[4] is an optional source tag, set by run.js when config.json declares multiple `sources` —
// each source's extraction lands in its own extracted/angular-<tag>.json so a combined run doesn't
// clobber the others; merger.js globs angular*.json so all of them get merged (and linked) together.
const sourceTag = process.argv[4];
const outputFile = path.join(knowledgeBaseDir, 'extracted', sourceTag ? `angular-${sourceTag}.json` : 'angular.json');
const startTime = Date.now();

const parser = new Parser();
parser.setLanguage(TypeScript);

const errors = [];

// ── File discovery ───────────────────────────────────────────────────────────
function walkDir(dir) {
  let results = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) results = results.concat(walkDir(full));
    else results.push(full);
  }
  return results;
}

const allFiles = walkDir(sourceDir);
// Only components under public/ are real business screens — shared/ holds framework UI
// (navbar, 404 page, sidenav) that we skip, same "never migrate framework modules" rule
// migration-pipeline.md applies to OS AppCommon_* modules.
const componentFiles = allFiles.filter(f => f.endsWith('.component.ts') && !f.endsWith('.spec.ts') && f.includes(`${path.sep}public${path.sep}`));
const routingFiles = allFiles.filter(f => f.endsWith('routing.module.ts'));
const serviceFiles = allFiles.filter(f => f.endsWith('.service.ts') && !f.endsWith('.spec.ts'));

// ── AST helpers ────────────────────────────────────────────────────────────
function findChildOfType(node, type) {
  return node.namedChildren.find(n => n.type === type) || null;
}
function findAllOfType(node, type, acc = []) {
  if (node.type === type) acc.push(node);
  for (const c of node.namedChildren) findAllOfType(c, type, acc);
  return acc;
}

// Parses a decorator's `(...)` object-literal argument into a plain object of string values.
// Good enough for @Component({ selector: '...', templateUrl: '...', styleUrls: [...] }) —
// array/nested values are returned as raw source text.
function decoratorArgsObject(decoratorNode) {
  const call = findChildOfType(decoratorNode, 'call_expression');
  if (!call) return {};
  const args = call.childForFieldName('arguments');
  const obj = args && args.namedChildren.find(n => n.type === 'object');
  if (!obj) return {};
  const out = {};
  for (const pair of obj.namedChildren) {
    if (pair.type !== 'pair') continue;
    const key = pair.childForFieldName('key').text;
    const valueNode = pair.childForFieldName('value');
    out[key] = valueNode.type === 'string'
      ? valueNode.text.replace(/^['"]|['"]$/g, '')
      : valueNode.text;
  }
  return out;
}

function decoratorName(decoratorNode) {
  const call = findChildOfType(decoratorNode, 'call_expression');
  const fn = call && call.childForFieldName('function');
  return fn ? fn.text : null;
}

const LIFECYCLE_HOOKS = new Set(['ngOnInit', 'ngOnDestroy', 'ngOnChanges', 'ngAfterViewInit', 'constructor']);

// URLs here are frequently built as 'literal1' + this.item.id + 'literal2' rather than one
// string literal, so reconstructing just the first fragment would silently truncate e.g.
// '/api/items/{id}/itemActions' down to '/api/items'. This flattens a '+' concatenation chain
// (and template-literal ${...} interpolation) into one string, substituting '*' for any
// non-literal segment so the shape ("there's a variable path segment here") survives even
// though the concrete value doesn't.
function reconstructConcatenatedString(node) {
  if (node.type === 'string') return node.text.replace(/^['"]|['"]$/g, '');
  if (node.type === 'template_string') return node.text.replace(/^`|`$/g, '').replace(/\$\{[^}]*\}/g, '*');
  if (node.type === 'binary_expression' && node.children.some(c => c.type === '+')) {
    return reconstructConcatenatedString(node.childForFieldName('left')) +
           reconstructConcatenatedString(node.childForFieldName('right'));
  }
  return '*';
}

// Scrapes reconstructed strings that look like backend API paths out of a component's source,
// e.g. 'http://localhost:4201/api/items/' + id + '/itemActions' -> '/api/items/*/itemActions'.
// This is what lets linker.js match a screen to the Java logic item whose httpEndpoint.path
// corresponds — without it, Screen<->Logic cross-referencing has no shared key to join on.
// Takes any node (whole-file rootNode, or a single method body) so it can be scoped tightly
// enough to pair a path with the specific service call made in the same method — see
// buildServiceVerbMap()/below, where per-method scoping is what lets us know the HTTP verb.
function scanApiPaths(scopeNode) {
  const paths = new Set();
  const candidates = [
    ...findAllOfType(scopeNode, 'string'),
    ...findAllOfType(scopeNode, 'template_string'),
    ...findAllOfType(scopeNode, 'binary_expression')
      .filter(n => n.parent?.type !== 'binary_expression' && n.children.some(c => c.type === '+')),
  ];
  for (const node of candidates) {
    // Skip fragments that are themselves part of a larger '+' chain — those are covered by
    // reconstructing from the outermost binary_expression above, not fragment-by-fragment.
    if (node.type !== 'binary_expression' && node.parent?.type === 'binary_expression') continue;
    const reconstructed = reconstructConcatenatedString(node);
    const m = reconstructed.match(/\/api\/[a-zA-Z0-9\/_*-]*/);
    if (m) paths.add(m[0].replace(/\/$/, ''));
  }
  return [...paths];
}

// Parses every *.service.ts file into { serviceMethodName: 'GET'|'POST'|'PUT'|'DELETE' } by
// finding which this.http.<verb>(...) call each method's body makes. Lets a component's call
// to e.g. `this.itemService.deleteItem(url)` be resolved to a real HTTP verb, instead of every
// screen touching a given path shape matching every logic item with that same path shape
// regardless of GET/PUT/DELETE.
const HTTP_VERB_METHODS = { get: 'GET', post: 'POST', put: 'PUT', delete: 'DELETE', patch: 'PATCH' };
function buildServiceVerbMap() {
  const verbByMethod = {};
  for (const file of serviceFiles) {
    let tree;
    try { tree = parser.parse(fs.readFileSync(file, 'utf8')); } catch (e) { continue; }
    for (const method of findAllOfType(tree.rootNode, 'method_definition')) {
      const name = method.childForFieldName('name')?.text;
      const body = method.childForFieldName('body');
      if (!name || !body) continue;
      const httpCall = findAllOfType(body, 'call_expression').find(c => {
        const fn = c.childForFieldName('function');
        return fn?.type === 'member_expression' &&
          fn.childForFieldName('object')?.text === 'this.http' &&
          HTTP_VERB_METHODS[fn.childForFieldName('property')?.text];
      });
      if (httpCall) {
        const verbMethodName = httpCall.childForFieldName('function').childForFieldName('property').text;
        verbByMethod[name] = HTTP_VERB_METHODS[verbMethodName];
      }
    }
  }
  return verbByMethod;
}
const serviceVerbByMethod = buildServiceVerbMap();

// Within one component method body: find api-path-like reconstructed strings AND any call to a
// known service method: `this.itemService.deleteItem(...)`. If exactly one of each appears
// (true for every method in this codebase — one URL built, one service call made with it),
// pair them into {path, method}. Otherwise fall back to path-only (no verb determinable).
function scanApiCallsInMethod(methodBody) {
  const paths = scanApiPaths(methodBody);
  const verbCalls = findAllOfType(methodBody, 'call_expression')
    .map(c => c.childForFieldName('function'))
    .filter(fn => fn?.type === 'member_expression')
    .map(fn => serviceVerbByMethod[fn.childForFieldName('property')?.text])
    .filter(Boolean);
  if (paths.length === 1 && verbCalls.length === 1) {
    return { apiCalls: [{ path: paths[0], method: verbCalls[0] }], apiPaths: [] };
  }
  return { apiCalls: [], apiPaths: paths };
}

// Component-name-to-backend-module heuristic. Angular here has no per-domain NgModule
// boundary (one flat app.module.ts), so screens are bucketed by matching the same domain
// vocabulary the backend modules use ('item' / 'itemAction' / 'itemSummary') — this is what
// makes a screen and its backend logic land in the same per-module BRD file.
function moduleForComponent(className) {
  const lower = className.toLowerCase();
  if (lower.includes('summary')) return 'itemSummary';
  if (lower.includes('action')) return 'itemAction';
  return 'item';
}

// Pattern-based template scan (not a full HTML parser, per the earlier scoping decision —
// Angular template binding syntax is easier to regex than to properly AST-parse without a
// dedicated template parser).
const EMPTY_TEMPLATE_INFO = { hasListUI: false, hasFormUI: false, widgetTypes: [], hasConditionalStyling: false };

function scanTemplate(componentFile, templateUrl) {
  if (!templateUrl) return EMPTY_TEMPLATE_INFO;
  const templatePath = path.join(path.dirname(componentFile), templateUrl.replace(/^\.\//, ''));
  if (!fs.existsSync(templatePath)) return EMPTY_TEMPLATE_INFO;
  const html = fs.readFileSync(templatePath, 'utf8');
  const hasListUI = /mat-table|\*ngFor/.test(html);
  const hasFormUI = /\[formGroup\]|<form[\s>]/.test(html);
  const widgetTypes = [...new Set((html.match(/<(mat-[a-z-]+)/g) || []).map(t => t.slice(1)))];
  // Data-driven styling ([ngClass], [class.x]="condition") is the one styling pattern that can
  // hide a real business rule (e.g. a status color-code) the same way logic hides in Java
  // service methods — unlike static CSS, which is never worth extracting (Mendix has its own
  // theming system; Angular Material CSS isn't a migration target at all). Flagged here so a
  // reviewer knows exactly which screens to eyeball during Phase 4 enrichment, rather than
  // captured-and-buried the way the OS pipeline's widget Visible-property handling is (it
  // reaches Phase 6 MDL generation but is never surfaced in the BRD or HTML report).
  const hasConditionalStyling = /\[ngClass\]|\[class\./.test(html);
  return { hasListUI, hasFormUI, widgetTypes, hasConditionalStyling };
}

// ── Pass 1: route map — { ComponentClassName: { path } } ──
const routedComponents = {};
for (const file of routingFiles) {
  let tree;
  try { tree = parser.parse(fs.readFileSync(file, 'utf8')); }
  catch (e) { errors.push({ file, error: e.message }); continue; }

  for (const obj of findAllOfType(tree.rootNode, 'object')) {
    const pairs = obj.namedChildren.filter(n => n.type === 'pair');
    const pathPair = pairs.find(p => p.childForFieldName('key').text === 'path');
    const compPair = pairs.find(p => p.childForFieldName('key').text === 'component');
    if (pathPair && compPair) {
      const compName = compPair.childForFieldName('value').text;
      const routePath = pathPair.childForFieldName('value').text.replace(/^['"]|['"]$/g, '');
      routedComponents[compName] = { path: routePath };
    }
  }
}

// ── Pass 2: dialog-launch call sites — { OpenedComponentName: [OpenerComponentName, ...] } ──
// Detects `<anything>.open(SomeComponent, {...})` — deliberately loose (doesn't require
// proving the receiver is specifically MatDialog) since that's a reliable enough signal in
// practice and avoids brittle service-injection-type tracing for a POC.
const dialogLaunches = {}; // openedComponent -> Set(openerComponent)

function classNameOfFile(tree) {
  for (const exp of findAllOfType(tree.rootNode, 'export_statement')) {
    const decl = exp.childForFieldName('declaration');
    if (decl && decl.type === 'class_declaration') return decl.childForFieldName('name').text;
  }
  return null;
}

for (const file of componentFiles) {
  let tree;
  try { tree = parser.parse(fs.readFileSync(file, 'utf8')); }
  catch (e) { continue; }
  const openerName = classNameOfFile(tree);
  if (!openerName) continue;

  for (const call of findAllOfType(tree.rootNode, 'call_expression')) {
    const fn = call.childForFieldName('function');
    if (!fn || fn.type !== 'member_expression' || fn.childForFieldName('property').text !== 'open') continue;
    const args = call.childForFieldName('arguments');
    const firstArg = args && args.namedChildren[0];
    if (firstArg && firstArg.type === 'identifier' && /Component$/.test(firstArg.text)) {
      const opened = firstArg.text;
      (dialogLaunches[opened] = dialogLaunches[opened] || new Set()).add(openerName);
    }
  }
}

// ── Pass 3: extract each component as a screen item ──
const screenItems = [];

for (const file of componentFiles) {
  let tree;
  try {
    tree = parser.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    errors.push({ file, error: e.message });
    continue;
  }

  try {
    const exportStmt = findAllOfType(tree.rootNode, 'export_statement')
      .find(n => n.childForFieldName('declaration')?.type === 'class_declaration' && n.childForFieldName('decorator'));
    if (!exportStmt) continue; // no @Component-decorated exported class in this file

    const decorator = exportStmt.childForFieldName('decorator');
    if (decoratorName(decorator) !== 'Component') continue;

    const meta = decoratorArgsObject(decorator);
    const classNode = exportStmt.childForFieldName('declaration');
    const className = classNode.childForFieldName('name').text;
    const classBody = classNode.childForFieldName('body');

    const inputParameters = [];
    const clientActions = [];
    const apiCalls = [];
    const apiPathsFallback = [];

    for (const member of classBody.namedChildren) {
      if (member.type === 'public_field_definition') {
        const fieldDecorator = member.childForFieldName('decorator');
        if (fieldDecorator && decoratorName(fieldDecorator) === 'Input') {
          const typeAnn = member.childForFieldName('type');
          inputParameters.push({ name: member.childForFieldName('name').text, type: typeAnn ? typeAnn.text.replace(/^:\s*/, '') : 'any', isMandatory: true });
        }
      } else if (member.type === 'method_definition') {
        const name = member.childForFieldName('name').text;
        if (name === 'constructor') {
          const params = member.childForFieldName('parameters');
          for (const p of (params ? params.namedChildren : [])) {
            if (p.type !== 'required_parameter') continue;
            const pDecorator = findChildOfType(p, 'decorator');
            if (pDecorator && decoratorName(pDecorator) === 'Inject') {
              const typeAnn = p.childForFieldName('type');
              inputParameters.push({ name: 'dialogData', type: typeAnn ? typeAnn.text.replace(/^:\s*/, '') : 'object', isMandatory: true });
            }
          }
        } else if (!LIFECYCLE_HOOKS.has(name)) {
          clientActions.push({ name });
        }
        const methodBody = member.childForFieldName('body');
        if (methodBody) {
          const { apiCalls: mCalls, apiPaths: mPaths } = scanApiCallsInMethod(methodBody);
          apiCalls.push(...mCalls);
          apiPathsFallback.push(...mPaths);
        }
      }
    }

    const templateInfo = scanTemplate(file, meta.templateUrl);
    const screenKind = routedComponents[className] ? 'route'
      : dialogLaunches[className] ? 'dialog'
      : 'embedded';

    screenItems.push({
      type: 'screen',
      screenKind: 'webScreen',
      linkId: `angular:screen:${className}`,
      uniqueId: `angular:${className}`,
      name: className,
      label: className,
      description: '',
      module: moduleForComponent(className),
      isPublic: true,
      title: className.replace(/Component$/, '').replace(/([a-z])([A-Z])/g, '$1 $2'),
      inputParameters,
      localVariables: [],
      clientActions,
      permissions: [],
      widgetSummary: {
        widgetTypes: templateInfo.widgetTypes,
        dataSources: [],
        hasListUI: templateInfo.hasListUI,
        hasFormUI: templateInfo.hasFormUI,
        hasConditionalStyling: templateInfo.hasConditionalStyling,
      },
      // Additive, not read by today's page-mapper/use-case-mapper — kept for the linker/report
      // and for whenever a screenKind-aware enhancement is worth adding.
      angularScreenKind: screenKind,
      launchedFrom: dialogLaunches[className] ? [...dialogLaunches[className]] : [],
      selector: meta.selector || '',
      routePath: routedComponents[className] ? routedComponents[className].path : null,
      apiCalls,                 // [{path, method}] — verb-resolved, use this for linking when non-empty
      apiPaths: apiPathsFallback, // paths with no resolvable verb (multiple candidates in one method, etc.)
      _templatePath: meta.templateUrl ? path.join(path.dirname(file), meta.templateUrl.replace(/^\.\//, '')) : null,
      _source: file,
      sourceRef: path.relative(path.join(sourceDir, '..', '..', '..'), file),
      _gaps: [],
      _links: [],
    });
  } catch (e) {
    errors.push({ file, error: e.message });
  }
}

// ── Pass 4: component composition — which components does each template embed as a
// custom element (e.g. ItemsComponent's template contains <app-item-list>)? Closes the gap
// for pure-composition screens that have no API call of their own but delegate to children
// that do — without this, e.g. ItemsComponent would wrongly look like a dead-end screen. ──
const selectorToComponent = new Map(screenItems.map(s => [s.selector, s.name]).filter(([sel]) => sel));
for (const screen of screenItems) {
  screen.composesComponents = [];
  if (!screen._templatePath || !fs.existsSync(screen._templatePath)) continue;
  const html = fs.readFileSync(screen._templatePath, 'utf8');
  for (const tag of new Set((html.match(/<(app-[a-z-]+)/g) || []).map(t => t.slice(1)))) {
    const composed = selectorToComponent.get(tag);
    if (composed && composed !== screen.name) screen.composesComponents.push(composed);
  }
  delete screen._templatePath;
}

// ── Emit ──────────────────────────────────────────────────────────────────
const result = {
  source: 'angular',
  items: screenItems,
  errors,
  meta: { fileCount: componentFiles.length, duration: Date.now() - startTime },
};

fs.mkdirSync(path.dirname(outputFile), { recursive: true });
fs.writeFileSync(outputFile, JSON.stringify(result, null, 2), 'utf8');
console.log(`Extracted ${screenItems.length} screens from ${componentFiles.length} component files (${errors.length} errors)`);
console.log(`  routed: ${screenItems.filter(s => s.angularScreenKind === 'route').length}, dialog: ${screenItems.filter(s => s.angularScreenKind === 'dialog').length}, embedded: ${screenItems.filter(s => s.angularScreenKind === 'embedded').length}`);
