'use strict';
const fs = require('fs');
const path = require('path');

const MODULE_RE = /<eSpace[^>]*Name="([^"]+)"/;
const STRUCT_RE = /<Structure\s[^>]*Key="(Structure:[^"]+)"[^>]*Name="([^"]+)"/g;
const STRUCT_REF_RE = /<StructureReference\s([^>]+)>/g;
const ATTR_RE = (name) => new RegExp(`${name}="([^"]+)"`);
const LIST_TYPE_RE = /<ListType\s[^>]*Key="(ListType:[^"]+)"[^>]*ElementType="(Structure:[^"]+)"/g;
const CLIENT_ACTION_RE = /<ClientAction\s[^>]*Key="(ClientAction:[^"]+)"/g;
const PARENT_RE = /<(?:WebBlock|WebScreen)\s[^>]*Key="(?:WebBlock|WebScreen):[^"]*"[^>]*Name="([^"]+)"/;
const INPUT_PARAM_RE = /<InputParameter\s[^>]*Key="(InputParameter:[^"]+)"[^>]*Name="([^"]+)"/g;

function buildStructureIndex(blueprintDir) {
  if (!blueprintDir || !fs.existsSync(blueprintDir)) return {};

  const structureIndex = {};
  const parentIndex = {}; // ClientAction:key → parent WebBlock/Screen name
  const files = fs.readdirSync(blueprintDir).filter(f => f.endsWith('.xml'));

  for (const file of files) {
    const xml = fs.readFileSync(path.join(blueprintDir, file), 'utf8');
    const mod = (xml.match(MODULE_RE) || ['', ''])[1] || path.basename(file, '.xml');

    for (const m of xml.matchAll(STRUCT_RE)) {
      structureIndex[m[1]] = { name: m[2], module: mod };
    }
    for (const m of xml.matchAll(STRUCT_REF_RE)) {
      const attrs = m[1];
      const key = ATTR_RE('Key').exec(attrs)?.[1];
      const name = ATTR_RE('Name').exec(attrs)?.[1];
      const originalKey = ATTR_RE('OriginalKey').exec(attrs)?.[1] || null;
      if (key && name) {
        structureIndex[key] = { name, module: mod, _originalKey: originalKey };
      }
    }
    for (const m of xml.matchAll(LIST_TYPE_RE)) {
      structureIndex[m[1]] = { _elementType: m[2], module: mod };
    }

    // Build ClientAction → parent WebBlock/Screen name map
    // Split XML by WebBlock/WebScreen boundaries
    const sections = xml.split(/(?=<WebBlock\s|<WebScreen\s)/);
    for (const section of sections) {
      const parentMatch = section.match(PARENT_RE);
      if (!parentMatch) continue;
      const parentName = parentMatch[1];
      for (const m of section.matchAll(CLIENT_ACTION_RE)) {
        parentIndex[m[1]] = parentName;
      }
    }
  }

  // Resolve StructureReference: use OriginalKey → Structure:OriginalKey to get true defining module
  for (const [k, v] of Object.entries(structureIndex)) {
    if (k.startsWith('StructureReference:') && v._originalKey) {
      const structKey = `Structure:${v._originalKey}`;
      const original = structureIndex[structKey];
      if (original) {
        structureIndex[k] = { name: v.name, module: original.module };
      } else {
        // OriginalKey not found (defined outside these 114 XMLs) — keep local name, drop _originalKey
        structureIndex[k] = { name: v.name, module: v.module };
      }
    }
  }

  // Resolve ListType → store element name+module with isList flag
  for (const [k, v] of Object.entries(structureIndex)) {
    if (v._elementType) {
      const elem = structureIndex[v._elementType];
      structureIndex[k] = elem
        ? { name: elem.name, module: elem.module, isList: true }
        : { name: 'unresolved', module: '', isList: true };
    }
  }

  return { structureIndex, parentIndex };
}

// Build DataScreenAction index: {module → {dsaName → {outputParamName → type}}}
function buildDataScreenActionIndex(dataScreenActions, structureIndex) {
  const index = {}; // module → { dsaName → { paramName → resolvedType } }
  for (const dsa of (dataScreenActions || [])) {
    const mod = dsa.module;
    if (!index[mod]) index[mod] = {};
    const params = {};
    for (const p of (dsa.outputParameters || [])) {
      const entry = structureIndex[p.type];
      if (entry) {
        params[p.name] = entry.isList
          ? { kind: 'list', name: entry.name, module: entry.module }
          : { kind: 'struct', name: entry.name, module: entry.module };
      } else {
        params[p.name] = { kind: 'scalar', type: p.type };
      }
    }
    index[mod][dsa.name] = params;
  }
  return index;
}

// Build InputParameter key → name index from all blueprint XMLs.
// Needed to resolve ExecuteAction argument paramKeys to human-readable parameter names.
function buildParamIndex(blueprintDir) {
  if (!blueprintDir || !fs.existsSync(blueprintDir)) return {};
  const paramIndex = {};
  const files = fs.readdirSync(blueprintDir).filter(f => f.endsWith('.xml'));
  for (const file of files) {
    const xml = fs.readFileSync(path.join(blueprintDir, file), 'utf8');
    for (const m of xml.matchAll(INPUT_PARAM_RE)) {
      paramIndex[m[1]] = m[2]; // InputParameter:xxx → "ParamName"
    }
  }
  return paramIndex;
}

module.exports = { buildStructureIndex, buildDataScreenActionIndex, buildParamIndex };
