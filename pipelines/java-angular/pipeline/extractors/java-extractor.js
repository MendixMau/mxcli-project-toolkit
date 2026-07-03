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
const outputFile = path.join(knowledgeBaseDir, 'extracted', 'java.json');
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
      out.push({ name: child.childForFieldName('name').text, args: {}, value: null });
    } else if (child.type === 'annotation') {
      const name = child.childForFieldName('name').text;
      const argsList = child.childForFieldName('arguments');
      const args = {};
      let positional = null;
      if (argsList) {
        for (const arg of argsList.namedChildren) {
          if (arg.type === 'element_value_pair') {
            const key = arg.childForFieldName('key').text;
            args[key] = arg.childForFieldName('value').text.replace(/^"|"$/g, '');
          } else {
            positional = arg.text.replace(/^"|"$/g, '');
          }
        }
      }
      out.push({ name, args, value: positional });
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

// ── Controller endpoint extraction: methodName -> {method, path} per module ──
const MAPPING_VERBS = { GetMapping: 'GET', PostMapping: 'POST', PutMapping: 'PUT', DeleteMapping: 'DELETE', PatchMapping: 'PATCH' };

function extractControllerEndpoints(classNode) {
  const modifiers = findChildOfType(classNode, 'modifiers');
  const classAnns = annotationsOf(modifiers);
  const classMapping = findAnnotation(classAnns, 'RequestMapping');
  const basePath = classMapping ? (classMapping.value || classMapping.args.value || classMapping.args.path || '') : '';

  const body = classNode.childForFieldName('body');
  const endpoints = {};
  for (const member of body.namedChildren) {
    if (member.type !== 'method_declaration') continue;
    const mAnns = annotationsOf(findChildOfType(member, 'modifiers'));
    for (const [annName, verb] of Object.entries(MAPPING_VERBS)) {
      const found = findAnnotation(mAnns, annName);
      if (found) {
        const subPath = found.value || found.args.value || found.args.path || '';
        endpoints[member.childForFieldName('name').text] = { method: verb, path: (basePath + subPath) || '/' };
      }
    }
  }
  return endpoints;
}

// ── Service method extraction: every method (public + private helpers alike) becomes its
// own logic item, mirroring how the OS pipeline treats SUB_ helper microflows as first-class
// items. A caller's `calls[]` will reference a helper by name; the reviewer/mapper follows
// the chain rather than the extractor inlining it. ──
function extractServiceMethods(classNode, className, module, file) {
  const body = classNode.childForFieldName('body');
  const items = [];

  for (const member of body.namedChildren) {
    if (member.type !== 'method_declaration') continue;
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

    const uniqueCalls = [...new Set(calls)].map(name => ({ name }));

    items.push({
      type: 'logic',
      logicKind: 'action', // Spring service/controller logic is always server-side, so it
                            // reuses the OS 'action' vocabulary (-> Microflow) per
                            // migration-pipeline.md's "Reuse the logicKind vocabulary" rule.
      linkId: `java:logic:${module}:${className}.${name}`,
      uniqueId: `java:${module}.${className}.${name}`,
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
      sourceRef: path.relative(path.join(sourceDir, '..', '..', '..', '..'), file),
      _gaps: [],
      _links: [],
    });
  }
  return items;
}

// ── Pass 1: parse every file and classify each top-level class by annotation ──
const files = walkDir(sourceDir);
const entityItems = [];
const rawLogicItems = [];
const endpointsByModule = {};

for (const file of files) {
  let tree;
  try {
    tree = parser.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    errors.push({ file, error: e.message });
    continue;
  }

  const module = moduleFromPackage(packageOf(tree));
  const classNodes = [];
  (function collect(node) {
    if (node.type === 'class_declaration' || node.type === 'interface_declaration') classNodes.push(node);
    for (const c of node.namedChildren) collect(c);
  })(tree.rootNode);

  for (const classNode of classNodes) {
    const isInterface = classNode.type === 'interface_declaration';
    const className = classNode.childForFieldName('name').text;
    const anns = annotationsOf(findChildOfType(classNode, 'modifiers'));

    const isEntity = !!findAnnotation(anns, 'Entity');
    const isController = !!findAnnotation(anns, 'RestController');
    const isService = !!findAnnotation(anns, 'Service');
    const isPlainDataDto = !isInterface && !isEntity && !isController && !isService && !!findAnnotation(anns, 'Data');

    try {
      if (isEntity) {
        entityItems.push(extractEntity(classNode, className, module, file, true));
      } else if (isController) {
        endpointsByModule[module] = { ...(endpointsByModule[module] || {}), ...extractControllerEndpoints(classNode) };
      } else if (isService && !isInterface) {
        rawLogicItems.push(...extractServiceMethods(classNode, className, module, file));
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
}

// ── Pass 2: attach httpEndpoint to service logic items by (module, methodName) match.
// Assumes the standard Spring delegate-controller convention: controller method name ===
// service method name. True for this pilot; document the assumption if a future source
// breaks it (e.g. controller adapts/renames before delegating). ──
const logicItems = rawLogicItems.map(item => ({
  ...item,
  httpEndpoint: (endpointsByModule[item.module] || {})[item.name] || null,
}));

// ── Emit ──────────────────────────────────────────────────────────────────
const result = {
  source: 'java',
  items: [...entityItems, ...logicItems],
  errors,
  meta: { fileCount: files.length, duration: Date.now() - startTime },
};

fs.mkdirSync(path.dirname(outputFile), { recursive: true });
fs.writeFileSync(outputFile, JSON.stringify(result, null, 2), 'utf8');
console.log(`Extracted ${entityItems.length} entities + ${logicItems.length} logic items from ${files.length} files (${errors.length} errors)`);
