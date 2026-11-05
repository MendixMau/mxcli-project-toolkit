'use strict';
const fs = require('fs');
const path = require('path');
const Parser = require('tree-sitter');
const Java = require('tree-sitter-java');

// ── Setup ──────────────────────────────────────────────────────────────────
const sourceDir = process.argv[2];
if (!sourceDir) {
  console.error('Usage: node java-extractor.js <javaSourceDir>');
  process.exit(1);
}
// argv[3] lets run.js point this at a per-project output dir (config.json's knowledgeBaseDir) so
// this tool never accumulates project-specific data of its own; falls back to a local
// knowledge-base/ for standalone/manual invocation outside the orchestrated pipeline.
const knowledgeBaseDir = process.argv[3] || path.join(__dirname, '..', 'knowledge-base');
// argv[4] is an optional source tag, set by run.js when config.json declares multiple `sources` —
// each source's extraction lands in its own extracted/java-<tag>.json so a combined run doesn't
// clobber the others; merger.js globs java*.json so all of them get merged (and linked) together.
const sourceTag = process.argv[4];
const outputFile = path.join(knowledgeBaseDir, 'extracted', sourceTag ? `java-${sourceTag}.json` : 'java.json');
const startTime = Date.now();

const parser = new Parser();
parser.setLanguage(Java);

const errors = [];

// ── File discovery ───────────────────────────────────────────────────────────
function walkDir(dir) {
  let results = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) results = results.concat(walkDir(full));
    else if (entry.name.endsWith('.java')) results.push(full);
  }
  return results;
}

// ── AST helpers ────────────────────────────────────────────────────────────
function findChildOfType(node, type) {
  return node.namedChildren.find(n => n.type === type) || null;
}

// Parses a `modifiers` node into a list of { name, args: {k:v}, value: <positional string|null> }.
// value covers single-argument annotations like @GetMapping("/items");
// args covers key=value annotations like @Column(nullable = false, unique = true).
function annotationsOf(modifiersNode) {
  if (!modifiersNode) return [];
  const out = [];
  for (const child of modifiersNode.namedChildren) {
    if (child.type === 'marker_annotation') {
      out.push({ name: child.childForFieldName('name').text, args: {}, value: null, argNodes: {}, valueNode: null });
    } else if (child.type === 'annotation') {
      const name = child.childForFieldName('name').text;
      const argsList = child.childForFieldName('arguments');
      const args = {};
      // argNodes/valueNode keep the AST of each value so a caller can evaluate constant
      // expressions (`value = API_LOCATIONS + "/{pKey}"`) instead of reading flattened text.
      const argNodes = {};
      let positional = null;
      let valueNode = null;
      if (argsList) {
        for (const arg of argsList.namedChildren) {
          if (arg.type === 'element_value_pair') {
            const key = arg.childForFieldName('key').text;
            args[key] = arg.childForFieldName('value').text.replace(/^"|"$/g, '');
            argNodes[key] = arg.childForFieldName('value');
          } else if (arg.type !== 'comment') {
            positional = arg.text.replace(/^"|"$/g, '');
            valueNode = arg;
          }
        }
      }
      out.push({ name, args, value: positional, argNodes, valueNode });
    }
  }
  return out;
}

function findAnnotation(annotations, name) {
  return annotations.find(a => a.name === name) || null;
}

function packageOf(tree) {
  const pkgNode = findChildOfType(tree.rootNode, 'package_declaration');
  return pkgNode ? pkgNode.namedChildren[0].text : '';
}

// com.ims.server.item -> "item" (module = last package segment)
function moduleFromPackage(pkg) {
  const parts = pkg.split('.');
  // When MODULE_BASE_PACKAGE is set (e.g. "org.openwms"), the module is the first
  // segment AFTER that base — so org.openwms.common.location.impl -> "common",
  // org.openwms.tms.impl.state -> "tms". This matches the common Java convention of
  // <base>.<module>.<subpackages>. Unset -> legacy behavior (leaf segment).
  const base = process.env.MODULE_BASE_PACKAGE;
  if (base && pkg.startsWith(base + '.')) {
    return pkg.slice(base.length + 1).split('.')[0] || '(unknown)';
  }
  return parts[parts.length - 1] || '(unknown)';
}

// Recursively collects every method_invocation, method_reference, and throw_statement
// inside a method body. This captures raw structural facts (what gets called, what gets
// thrown) — it does NOT attempt to label *why* (e.g. "this is a cascade delete"); that
// synthesis belongs to a mapper or human review reading these facts, per
// mxcli-project-toolkit/skills/migration-pipeline.md's extractor-vs-mapper split.
function walkBody(node, calls, throwsList) {
  if (node.type === 'method_invocation') {
    const objNode = node.childForFieldName('object');
    const nameNode = node.childForFieldName('name');
    // Only prefix with the receiver when it's a simple identifier/field/this — if the
    // receiver is itself a call chain (e.g. `repo.findAll().stream()`), using its full text
    // would embed the whole nested chain as one giant string. Fall back to the bare method
    // name in that case; the chain's other links are still captured as their own nodes.
    const simpleReceiver = objNode && ['identifier', 'field_access', 'this'].includes(objNode.type);
    calls.push(simpleReceiver ? `${objNode.text}.${nameNode.text}` : nameNode.text);
  } else if (node.type === 'method_reference') {
    calls.push(node.text);
  } else if (node.type === 'throw_statement') {
    const inner = node.namedChildren[0];
    if (inner && inner.type === 'object_creation_expression') {
      const typeNode = inner.childForFieldName('type');
      if (typeNode) throwsList.push(typeNode.text);
    }
  }
  for (const child of node.namedChildren) walkBody(child, calls, throwsList);
}

// ── Entity extraction (@Entity classes, and plain @Data DTOs treated as non-persistent) ──
function extractEntity(classNode, className, module, file, isPersistent) {
  const body = classNode.childForFieldName('body');
  const attributes = [];

  for (const member of body.namedChildren) {
    if (member.type !== 'field_declaration') continue;
    const modifiers = findChildOfType(member, 'modifiers');
    const anns = annotationsOf(modifiers);
    const typeNode = member.childForFieldName('type');
    const declarator = member.childForFieldName('declarator');
    if (!typeNode || !declarator) continue;
    const fieldType = typeNode.text;
    const fieldName = declarator.childForFieldName('name').text;

    const relation = ['ManyToOne', 'OneToOne', 'OneToMany', 'ManyToMany']
      .map(r => findAnnotation(anns, r)).find(Boolean);

    if (relation && (relation === findAnnotation(anns, 'ManyToOne') || relation === findAnnotation(anns, 'OneToOne'))) {
      // Owning FK side — represent as a synthetic "<Entity> Identifier" attribute so the
      // existing (unmodified) type-converter.js/domain-entity-mapper.js handle it exactly
      // like an OS "EntityName Identifier" attribute, no mapper changes needed.
      const joinCol = findAnnotation(anns, 'JoinColumn');
      const isMandatory = joinCol ? joinCol.args.nullable === 'false' : false;
      attributes.push({
        name: fieldName,
        type: `${fieldType} Identifier`,
        isMandatory,
        isAutoNumber: false,
        isForeignKey: true,
        referencedEntity: fieldType,
        deleteRule: '', // no declarative JPA cascade found; cascade-in-code (if any) is a
                         // service-layer business rule, not a schema fact — see logic items.
        length: '',
      });
      continue;
    }
    if (relation) {
      // OneToMany/ManyToMany inverse side — no column lives on this entity, skip as an attribute.
      continue;
    }

    const isAutoNumber = !!findAnnotation(anns, 'GeneratedValue');
    const colAnn = findAnnotation(anns, 'Column');
    const isMandatory = colAnn ? colAnn.args.nullable === 'false' : false;
    const isUnique = colAnn ? colAnn.args.unique === 'true' : false;

    attributes.push({
      name: fieldName,
      type: fieldType,
      isMandatory,
      isAutoNumber,
      isForeignKey: false,
      referencedEntity: '',
      deleteRule: '',
      length: '',
      isUnique,
    });
  }

  return {
    type: 'entity',
    linkId: `java:entity:${module}:${className}`,
    uniqueId: `java:${module}.${className}`,
    name: className,
    label: className,
    description: '',
    module,
    isStatic: false,
    isPublic: true,
    isMultitenant: false,
    isPersistent,
    deleteRule: '',
    attributes,
    indexes: [],
    _source: file,
    sourceRef: path.relative(path.join(sourceDir, '..', '..', '..', '..'), file),
    _gaps: [],
    _links: [],
  };
}

// sourceRef: path relative to the repo root four levels above src/main/java — same convention
// extractEntity() uses, so every item kind carries a comparable reference.
function sourceRefOf(file) {
  return path.relative(path.join(sourceDir, '..', '..', '..', '..'), file);
}

function baseTypeName(typeText) {
  // `TransportationService<TransportOrder>` -> `TransportationService`; `a.b.Foo` -> `Foo`
  const noGenerics = (typeText || '').replace(/<.*$/s, '').trim();
  return noGenerics.split('.').pop();
}

// ── String-constant table (paths are rarely literals in real Spring code) ──────────────────
// Real incident (issue #637, OpenWMS): every mapping read `@GetMapping(value = API_LOCATIONS +
// "/{pKey}")` with API_LOCATIONS = "/" + API_VERSION + "/locations" in a separate *ApiConstants
// class. Flattened annotation text made those paths unusable, so we evaluate the expression
// against every `String NAME = <expr>` declared anywhere in this source tree.
const CONSTS = new Map();       // "Class.NAME" -> { node, ctx }
const CONSTS_BY_NAME = new Map(); // "NAME" -> ["Class.NAME", ...]

function collectConstants(classNode, ctx) {
  const body = classNode.childForFieldName('body');
  if (!body) return;
  const className = classNode.childForFieldName('name').text;
  for (const member of body.namedChildren) {
    if (member.type !== 'field_declaration' && member.type !== 'constant_declaration') continue;
    const typeNode = member.childForFieldName('type');
    if (!typeNode || typeNode.text !== 'String') continue;
    for (const decl of member.namedChildren) {
      if (decl.type !== 'variable_declarator') continue;
      const nameNode = decl.childForFieldName('name');
      const valueNode = decl.childForFieldName('value');
      if (!nameNode || !valueNode) continue;
      const key = `${className}.${nameNode.text}`;
      CONSTS.set(key, { node: valueNode, ctx: { ...ctx, className } });
      const list = CONSTS_BY_NAME.get(nameNode.text) || [];
      list.push(key);
      CONSTS_BY_NAME.set(nameNode.text, list);
    }
  }
}

function staticImportsOf(tree) {
  const map = new Map();   // simple NAME -> declaring class simple name
  const wildcards = [];    // class simple names imported with `import static a.b.C.*;`
  for (const node of tree.rootNode.namedChildren) {
    if (node.type !== 'import_declaration') continue;
    const m = /^import\s+static\s+([\w.]+)\.(\w+|\*)\s*;/.exec(node.text);
    if (!m) continue;
    const cls = m[1].split('.').pop();
    if (m[2] === '*') wildcards.push(cls); else map.set(m[2], cls);
  }
  return { map, wildcards };
}

function lookupConstant(name, ctx, depth) {
  const candidates = [`${ctx.className}.${name}`];
  if (ctx.imports && ctx.imports.map.has(name)) candidates.push(`${ctx.imports.map.get(name)}.${name}`);
  for (const w of (ctx.imports ? ctx.imports.wildcards : [])) candidates.push(`${w}.${name}`);
  for (const st of (CLASS_INDEX.get(ctx.className)?.superTypes || [])) candidates.push(`${st}.${name}`);
  for (const key of candidates) if (CONSTS.has(key)) return evalString(CONSTS.get(key).node, CONSTS.get(key).ctx, depth + 1);
  const global = CONSTS_BY_NAME.get(name) || [];
  if (global.length) {
    // Several classes may declare the same NAME; only trust it when they all agree.
    const values = [...new Set(global.map(k => evalString(CONSTS.get(k).node, CONSTS.get(k).ctx, depth + 1)))];
    if (values.length === 1) return values[0];
  }
  return null;
}

// Returns a string, an array of strings (for `{"/a", "/b"}`), or null when not resolvable.
function evalString(node, ctx, depth = 0) {
  if (!node || depth > 20) return null;
  switch (node.type) {
    case 'string_literal':
      return node.text.replace(/^"|"$/g, '').replace(/\\"/g, '"');
    case 'parenthesized_expression':
      return evalString(node.namedChildren[0], ctx, depth);
    case 'binary_expression': {
      const op = node.childForFieldName('operator');
      if (op && op.text !== '+') return null;
      const l = evalString(node.childForFieldName('left'), ctx, depth);
      const r = evalString(node.childForFieldName('right'), ctx, depth);
      return (typeof l === 'string' && typeof r === 'string') ? l + r : null;
    }
    case 'identifier':
      return lookupConstant(node.text, ctx, depth);
    case 'field_access': {
      const cls = node.childForFieldName('object').text.split('.').pop();
      const field = node.childForFieldName('field').text;
      const key = `${cls}.${field}`;
      if (CONSTS.has(key)) return evalString(CONSTS.get(key).node, CONSTS.get(key).ctx, depth + 1);
      return lookupConstant(field, { ...ctx, className: cls }, depth);
    }
    case 'element_value_array_initializer': {
      const vals = node.namedChildren.filter(n => n.type !== 'comment').map(n => evalString(n, ctx, depth));
      return vals.every(v => typeof v === 'string') ? vals : null;
    }
    default:
      return null;
  }
}

function joinPath(base, sub) {
  const joined = `/${base || ''}/${sub || ''}`.replace(/\/+/g, '/');
  return joined.length > 1 ? joined.replace(/\/$/, '') : '/';
}

// ── Controller endpoint extraction: one record per mapping annotation (and per path when the
// annotation lists several). A list, not a methodName map — overloaded handlers
// (`changeState(pKey…)` / `changeState(locationId…)`) are two endpoints, not one. ──
const MAPPING_VERBS = { GetMapping: 'GET', PostMapping: 'POST', PutMapping: 'PUT', DeleteMapping: 'DELETE', PatchMapping: 'PATCH' };

function mappingPaths(ann, ctx) {
  const node = ann.argNodes.value || ann.argNodes.path || ann.valueNode;
  if (!node) return { paths: [''], resolved: true, raw: '' };
  const v = evalString(node, ctx);
  if (v === null) return { paths: [node.text], resolved: false, raw: node.text };
  return { paths: Array.isArray(v) ? (v.length ? v : ['']) : [v], resolved: true, raw: node.text };
}

function mappingParams(ann, ctx) {
  const node = ann.argNodes.params;
  if (!node) return null;
  const v = evalString(node, ctx);
  if (v === null) return [node.text];
  return Array.isArray(v) ? v : [v];
}

function extractControllerEndpoints(classNode, ctx) {
  const classAnns = annotationsOf(findChildOfType(classNode, 'modifiers'));
  const classMapping = findAnnotation(classAnns, 'RequestMapping');
  const base = classMapping ? mappingPaths(classMapping, ctx) : { paths: [''], resolved: true };

  const body = classNode.childForFieldName('body');
  const endpoints = [];
  let annotationCount = 0;
  for (const member of body.namedChildren) {
    if (member.type !== 'method_declaration') continue;
    const mAnns = annotationsOf(findChildOfType(member, 'modifiers'));
    for (const ann of mAnns) {
      let verb = MAPPING_VERBS[ann.name];
      if (!verb && ann.name === 'RequestMapping') {
        // Method-level @RequestMapping(method = RequestMethod.GET); no method= means any verb.
        const m = /(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)/.exec(ann.args.method || '');
        verb = m ? m[1] : 'ANY';
      }
      if (!verb) continue;
      annotationCount++;
      const sub = mappingPaths(ann, ctx);
      const params = mappingParams(ann, ctx);
      for (const b of base.paths) {
        for (const s of sub.paths) {
          const ep = { method: verb, path: joinPath(b, s) };
          if (params) ep.params = params;
          if (!(base.resolved && sub.resolved)) ep.pathResolved = false;
          endpoints.push({ methodNode: member, methodName: member.childForFieldName('name').text,
                           endpoint: ep, line: member.startPosition.row + 1 });
        }
      }
    }
  }
  return { endpoints, annotationCount };
}

function fieldTypesOf(classNode) {
  const types = new Map(); // field name -> base type name
  const body = classNode.childForFieldName('body');
  for (const member of (body ? body.namedChildren : [])) {
    if (member.type !== 'field_declaration') continue;
    const typeNode = member.childForFieldName('type');
    for (const decl of member.namedChildren) {
      if (decl.type !== 'variable_declarator') continue;
      types.set(decl.childForFieldName('name').text, baseTypeName(typeNode && typeNode.text));
    }
  }
  return types;
}

function superTypesOf(classNode) {
  const out = [];
  for (const field of ['superclass', 'interfaces']) {
    const n = classNode.childForFieldName(field);
    if (!n) continue;
    // type_list children / a single type; strip generics and qualifiers
    const text = n.text.replace(/^(extends|implements)\s+/, '');
    for (const t of text.split(/,(?![^<]*>)/)) if (t.trim()) out.push(baseTypeName(t));
  }
  // interface_declaration uses an `extends_interfaces` child rather than a field
  const ext = findChildOfType(classNode, 'extends_interfaces');
  if (ext) for (const t of ext.text.replace(/^extends\s+/, '').split(/,(?![^<]*>)/)) if (t.trim()) out.push(baseTypeName(t));
  return out;
}

// ── Logic-item builder shared by service and controller methods. `seen` disambiguates
// overloads within one class: the first keeps the plain id (unchanged for every existing KB),
// later ones get a ~2, ~3 suffix instead of being silently dropped by merger dedup. ──
function logicItemFor(member, className, module, file, seen) {
  const name = member.childForFieldName('name').text;
  const returnTypeNode = member.childForFieldName('type');
  const returnType = returnTypeNode ? returnTypeNode.text : 'void';

  const params = [];
  const paramsNode = member.childForFieldName('parameters');
  if (paramsNode) {
    for (const p of paramsNode.namedChildren) {
      if (p.type !== 'formal_parameter') continue;
      params.push({ name: p.childForFieldName('name').text, type: p.childForFieldName('type').text });
    }
  }

  const calls = [];
  const throwsList = [];
  const bodyNode = member.childForFieldName('body');
  if (bodyNode) walkBody(bodyNode, calls, throwsList);
  const uniqueCalls = [...new Set(calls)].map(n => ({ name: n }));

  const n = (seen.get(name) || 0) + 1;
  seen.set(name, n);
  const idName = n === 1 ? name : `${name}~${n}`;

  return {
    type: 'logic',
    logicKind: 'action', // Spring service/controller logic is always server-side, so it
                          // reuses the OS 'action' vocabulary (-> Microflow) per
                          // migration-pipeline.md's "Reuse the logicKind vocabulary" rule.
    linkId: `java:logic:${module}:${className}.${idName}`,
    uniqueId: `java:${module}.${className}.${idName}`,
    name,
    label: name,
    description: '',
    module,
    isPublic: true,
    httpEndpoint: null, // attached in a second pass once controller endpoints are known
    inputParameters: params.map(p => ({ name: p.name, type: p.type, isMandatory: true })),
    outputParameters: (returnType && returnType !== 'void') ? [{ name: 'Result', type: returnType }] : [],
    calls: uniqueCalls,
    aggregates: [],
    throwsExceptions: [...new Set(throwsList)],
    _source: file,
    sourceRef: sourceRefOf(file),
    _gaps: [],
    _links: [],
  };
}

// ── Service method extraction: every method (public + private helpers alike) becomes its
// own logic item, mirroring how the OS pipeline treats SUB_ helper microflows as first-class
// items. A caller's `calls[]` will reference a helper by name; the reviewer/mapper follows
// the chain rather than the extractor inlining it. ──
function extractServiceMethods(classNode, className, module, file) {
  const body = classNode.childForFieldName('body');
  const seen = new Map();
  return body.namedChildren
    .filter(m => m.type === 'method_declaration')
    .map(m => logicItemFor(m, className, module, file, seen));
}

// ── Enum extraction (Java enum → Mendix Enumeration / KB staticEntity) ──
// Emits records:[{name,label}] per constant — the shape domain-entity-mapper.js reads.
// Carries _source/sourceRef like every other item kind (issue #639: without them
// capability-grouper.js fell back to the raw leaf package, so enums produced api/events BRDs).
// A nested enum is qualified by its outer type(s): LocationCommand.Type and
// TransportUnitCommand.Type were both a bare `Type`, and merger dedup kept only one of the
// enums sharing a leaf package. `name` stays a legal Mendix identifier (Outer_Type).
function extractEnum(enumNode, enumName, module, file, outerNames) {
  const body = enumNode.childForFieldName('body');
  const records = [];
  if (body) {
    for (const member of body.namedChildren) {
      if (member.type !== 'enum_constant') continue;
      const nameNode = member.childForFieldName('name');
      if (nameNode) records.push({ name: nameNode.text, label: nameNode.text });
    }
  }
  const qualified = [...outerNames, enumName];
  const name = qualified.join('_');
  const item = {
    type: 'staticEntity',
    linkId: `java:staticEntity:${module}:${name}`,
    uniqueId: `java:${module}.${name}`,
    name,
    label: qualified.join('.'),
    description: '',
    module,
    isStatic: true,
    isPublic: true,
    records,
    _source: file,
    sourceRef: sourceRefOf(file),
    _gaps: [],
    _links: [],
  };
  if (outerNames.length) item.outerType = outerNames.join('.');
  return item;
}

// ── Independent endpoint count (the validator's "different mechanism" rule from
// extractor-quality-loop.md): a comment-stripped regex over each controller file's raw text,
// never the AST. Every mapping annotation on a method of a *Controller-stereotyped class is
// expected to land as an endpoint; any shortfall is reported, never dropped. ──
function regexEndpointCount(text) {
  const code = text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  if (!/@\w*Controller\b/.test(code)) return null;
  const firstType = code.search(/\b(class|interface|enum|record)\s+\w+/);
  let count = 0;
  const re = /@(Get|Post|Put|Delete|Patch|Request)Mapping\b/g;
  let m;
  while ((m = re.exec(code))) {
    if (m[1] === 'Request' && firstType >= 0 && m.index < firstType) continue; // class-level base path
    count++;
  }
  return count;
}

// ── Pass 0: parse every file once; index classes and string constants ──
const files = walkDir(sourceDir);
const parsed = [];
const CLASS_INDEX = new Map(); // simple class name -> { superTypes, isService, isInterface }

for (const file of files) {
  let tree, text;
  try {
    text = fs.readFileSync(file, 'utf8');
    tree = parser.parse(text);
  } catch (e) {
    errors.push({ file, error: e.message });
    continue;
  }
  const ctx = { imports: staticImportsOf(tree) };
  parsed.push({ file, tree, text, ctx });
  (function index(node) {
    if (node.type === 'class_declaration' || node.type === 'interface_declaration') {
      const name = node.childForFieldName('name').text;
      const anns = annotationsOf(findChildOfType(node, 'modifiers'));
      CLASS_INDEX.set(name, {
        superTypes: superTypesOf(node),
        isInterface: node.type === 'interface_declaration',
        isService: anns.some(a => a.name.endsWith('Service')),
      });
      collectConstants(node, ctx);
    }
    for (const c of node.namedChildren) index(c);
  })(tree.rootNode);
}

// ── Pass 1: classify each class by annotation ──
const entityItems = [];
const staticItems = [];
const rawLogicItems = [];
const classOfLogic = new Map();     // linkId -> declaring class simple name
const controllerEndpoints = [];     // { endpoint, methodName, methodNode, className, module, file, fields }
const endpointCoverage = [];        // per controller file: { file, expected, captured }

for (const { file, tree, text, ctx } of parsed) {
  const module = moduleFromPackage(packageOf(tree));
  const classNodes = [];
  const enumNodes = [];
  (function collect(node, outer) {
    let nextOuter = outer;
    if (node.type === 'class_declaration' || node.type === 'interface_declaration' || node.type === 'enum_declaration' || node.type === 'record_declaration') {
      const nm = node.childForFieldName('name');
      if (node.type === 'enum_declaration') enumNodes.push({ node, outer });
      else if (node.type !== 'record_declaration') classNodes.push(node);
      if (nm) nextOuter = [...outer, nm.text];
    }
    for (const c of node.namedChildren) collect(c, nextOuter);
  })(tree.rootNode, []);

  for (const { node: enumNode, outer } of enumNodes) {
    try {
      const enumName = enumNode.childForFieldName('name').text;
      staticItems.push(extractEnum(enumNode, enumName, module, file, outer));
    } catch (e) {
      errors.push({ file, error: `enum: ${e.message}` });
    }
  }

  let capturedInFile = 0;
  let fileHasController = false;
  for (const classNode of classNodes) {
    const isInterface = classNode.type === 'interface_declaration';
    const className = classNode.childForFieldName('name').text;
    const anns = annotationsOf(findChildOfType(classNode, 'modifiers'));

    const isEntity = !!findAnnotation(anns, 'Entity');
    // Match framework meta-stereotypes by suffix, not just vanilla Spring: OpenWMS/Ameba
    // use @MeasuredRestController and @TxService. Suffix matching also future-proofs against
    // other custom stereotypes (e.g. @CachedService) without further edits.
    const isController = !isInterface && anns.some(a => a.name.endsWith('Controller'));
    const isService = anns.some(a => a.name.endsWith('Service'));
    const isPlainDataDto = !isInterface && !isEntity && !isController && !isService && !!findAnnotation(anns, 'Data');

    try {
      if (isEntity) {
        entityItems.push(extractEntity(classNode, className, module, file, true));
      } else if (isController) {
        fileHasController = true;
        const { endpoints, annotationCount } = extractControllerEndpoints(classNode, { ...ctx, className });
        capturedInFile += annotationCount;
        const fields = fieldTypesOf(classNode);
        for (const ep of endpoints) controllerEndpoints.push({ ...ep, className, module, file, fields });
      } else if (isService && !isInterface) {
        for (const item of extractServiceMethods(classNode, className, module, file)) {
          rawLogicItems.push(item);
          classOfLogic.set(item.linkId, className);
        }
      } else if (isPlainDataDto) {
        // Non-persistent computed DTO (e.g. ItemSummary) — tagged isPersistent:false.
        // Note: today's domain-entity-mapper.js treats every entities.json item as
        // mendixType 'PersistentEntity' regardless of this flag (it doesn't read
        // isPersistent) — a known, accepted looseness for this POC rather than building a
        // dedicated non-persistent-entity mapper right now.
        entityItems.push(extractEntity(classNode, className, module, file, false));
      }
      // Plain interfaces (Repository, Service contracts) intentionally produce no item —
      // their methods are only meaningful as call targets, already captured by name in
      // rawLogicItems[].calls.
    } catch (e) {
      errors.push({ file, error: `${className}: ${e.message}` });
    }
  }

  const expected = regexEndpointCount(text);
  if (expected !== null || fileHasController) {
    endpointCoverage.push({ file: sourceRefOf(file), expected: expected || 0, captured: capturedInFile });
  }
}

// ── Pass 2: every endpoint lands somewhere — never dropped silently (issue #637).
// (a) Legacy delegate-name convention, unchanged: a service method in the SAME module with the
//     SAME name as the controller method carries the httpEndpoint (the pilot's shape).
// (b) Otherwise the controller method itself becomes the logic item carrying the endpoint, and
//     `delegatesTo` names the service methods it calls through its injected fields, resolved by
//     type (field type == service class, or an interface the service class implements) — so a
//     controller in package `location` reaching LocationServiceImpl in `impl` still links.
const logicByClassAndName = new Map(); // "Class.method" -> [items]
for (const item of rawLogicItems) {
  const key = `${classOfLogic.get(item.linkId)}.${item.name}`;
  (logicByClassAndName.get(key) || logicByClassAndName.set(key, []).get(key)).push(item);
}
const serviceClassesFor = (typeName) => {
  const out = [];
  for (const [name, info] of CLASS_INDEX) {
    if (!info.isService || info.isInterface) continue;
    if (name === typeName || info.superTypes.includes(typeName)) out.push(name);
  }
  return out;
};

const controllerItems = [];
const seenByController = new Map();
for (const ep of controllerEndpoints) {
  const legacy = rawLogicItems.find(i => i.module === ep.module && i.name === ep.methodName && !i.httpEndpoint);
  if (legacy) { legacy.httpEndpoint = ep.endpoint; continue; }

  const seen = seenByController.get(ep.className) || seenByController.set(ep.className, new Map()).get(ep.className);
  const item = logicItemFor(ep.methodNode, ep.className, ep.module, ep.file, seen);
  item.httpEndpoint = ep.endpoint;
  item.layer = 'controller';
  const delegates = [];
  for (const { name: call } of item.calls) {
    const m = /^(?:this\.)?(\w+)\.(\w+)$/.exec(call);
    if (!m || !ep.fields.has(m[1])) continue;
    for (const cls of serviceClassesFor(ep.fields.get(m[1]))) {
      for (const target of (logicByClassAndName.get(`${cls}.${m[2]}`) || [])) delegates.push(target.linkId);
    }
  }
  item.delegatesTo = [...new Set(delegates)];
  if (!item.delegatesTo.length) item._gaps.push('endpoint-delegate-unresolved');
  if (ep.endpoint.pathResolved === false) item._gaps.push(`endpoint-path-unresolved:${ep.endpoint.path}`);
  controllerItems.push(item);
}
for (const item of rawLogicItems) {
  if (item.httpEndpoint && item.httpEndpoint.pathResolved === false) item._gaps.push(`endpoint-path-unresolved:${item.httpEndpoint.path}`);
}
const logicItems = [...rawLogicItems, ...controllerItems];

// ── Emit ──────────────────────────────────────────────────────────────────
const expectedEndpoints = endpointCoverage.reduce((s, f) => s + f.expected, 0);
const capturedEndpoints = endpointCoverage.reduce((s, f) => s + Math.min(f.captured, f.expected), 0);
const result = {
  source: 'java',
  items: [...entityItems, ...staticItems, ...logicItems],
  errors,
  meta: {
    fileCount: files.length,
    duration: Date.now() - startTime,
    // Read by merger.js: uncaptured mapping annotations are written to the gaps report and
    // counted in summary.md's total, so "0 gaps" can never coexist with missed endpoints.
    endpointCoverage: {
      method: 'regex count of @*Mapping on methods of *Controller classes (comments stripped)',
      expected: expectedEndpoints,
      captured: capturedEndpoints,
      endpointRecords: controllerEndpoints.length,
      pathUnresolved: controllerEndpoints.filter(e => e.endpoint.pathResolved === false).length,
      files: endpointCoverage.filter(f => f.expected !== f.captured),
    },
  },
};

fs.mkdirSync(path.dirname(outputFile), { recursive: true });
fs.writeFileSync(outputFile, JSON.stringify(result, null, 2), 'utf8');
console.log(`Extracted ${entityItems.length} entities + ${staticItems.length} enums + ${logicItems.length} logic items from ${files.length} files (${errors.length} errors); ` +
  `endpoints ${capturedEndpoints}/${expectedEndpoints} mapping annotations captured`);
