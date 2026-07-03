'use strict';

// All known OutSystems (System) built-in actions.
// Value = ordered array of parameter names (as resolved from paramIndex).
const SYSTEM_ACTION_PARAMS = {
  // List operations
  ListAppend:    ['Element', 'List'],
  ListAppendAll: ['List', 'SourceList'],
  ListRemove:    ['List', 'Position'],
  ListClear:     ['List'],
  ListDuplicate: ['SourceList'],
  ListFilter:    ['SourceList', 'Condition'],
  ListSort:      ['List', 'By'],
  ListAny:       ['Condition', 'List'],
  ListAll:       ['Condition', 'List'],
  ListIndexOf:   ['List', 'Condition'],
  ListInsert:    ['Element', 'List', 'Position'],
  ListDistinct:  ['SourceList'],
  // Logging
  LogMessage:    ['ModuleName', 'Message'],
  // Transactions
  CommitTransaction: [],
  AbortTransaction:  [],
  // Auth
  Login:            ['Persistent', 'UserId'],
  LoginPassword:    ['UserId', 'Password', 'Persistent'],
  Logout:           [],
  // Misc
  Deprecated_Notify:          ['Message'],
  Deprecated_NotifyGetMessage: [],
  SetCurrentLocale:   ['Locale'],
  GenerateGuid:       [],
  TenantSwitch:       ['TenantId'],
  EspaceInvalidateCache: [],
  IntegratedSecurityGetDetails: [],
};

// Replace OutSystems Record accessor paths in an expression string.
// NodeName.Record.EntityName.Attr → $NodeName.Attr
// NodeName.Record.Field           → $NodeName.Field
function rewriteRecordExprs(expr) {
  if (!expr || !expr.includes('.Record.')) return expr;
  return expr
    .replace(/\b(\w+)\.Record\.(\w+)\.(\w+)/g, (_, node, _entity, attr) => `$${node}.${attr}`)
    .replace(/\b(\w+)\.Record\.(\w+)/g,         (_, node, field)         => `$${node}.${field}`);
}

function translateFlow(logic, structureIndex, dsaIndex, paramIndex) {
  const nodes = (logic.flowGraph && logic.flowGraph.nodes) || [];
  if (nodes.length === 0) return '  -- no flow graph\n';

  const nodeMap = {};
  for (const n of nodes) nodeMap[n.nodeId] = n;

  const callMap = {};
  for (const c of (logic.calls || [])) callMap[c.uniqueId] = c;

  // Build param type map: paramName → structureIndex entry (for Pattern A/B detection)
  const structParamTypes = {};
  for (const p of (logic.inputParameters || [])) {
    if (p.type && structureIndex && structureIndex[p.type]) {
      structParamTypes[p.name] = structureIndex[p.type];
    }
  }

  const modDsa = (dsaIndex && dsaIndex[logic.module]) || {};

  // Pre-compute which ExecuteAction call names are referenced via .Record. accessor pattern.
  // These calls must capture their return value: $NodeName = CALL MICROFLOW ...;
  const recordReturnNodes = new Set();
  for (const n of nodes) {
    if (n.nodeType !== 'Assign') continue;
    for (const a of (n.assignments || [])) {
      for (const text of [a.variable || '', a.expression || '']) {
        for (const m of text.matchAll(/\b(\w+)\.Record\./g)) {
          recordReturnNodes.add(m[1]);
        }
      }
    }
  }

  const startNode = nodes.find(n => n.nodeType === 'Start');
  if (!startNode) return '  -- no Start node found\n';

  const visited = new Set();
  const lines = [];
  const ctx = { structParamTypes, modDsa, structureIndex, paramIndex: paramIndex || {}, recordReturnNodes };
  renderNode(startNode.nodeId, nodeMap, callMap, visited, lines, 1, ctx);

  // Implicit RETURN: End node exists but unreachable (unextracted node types), or no End at all.
  const endNode = nodes.find(n => n.nodeType === 'End');
  const hasReturn = lines.some(l => l.trimStart().startsWith('RETURN'));
  const needsReturn = !hasReturn && (
    (endNode && !visited.has(endNode.nodeId)) ||
    (!endNode)
  );
  if (needsReturn) {
    lines.push('  -- implicit return');
    lines.push('  RETURN;');
  }

  return lines.join('\n') + '\n';
}

function ind(level) { return '  '.repeat(level); }

// Returns true if nodeId can reach targetId via non-cycle edges (for guard detection).
function pathReaches(nodeId, targetId, nodeMap, visited) {
  if (!nodeId || visited.has(nodeId)) return false;
  if (nodeId === targetId) return true;
  visited.add(nodeId);
  const node = nodeMap[nodeId];
  if (!node || node.nodeType === 'End') return false;
  for (const e of (node.edges || [])) {
    if (e.label !== 'cycle' && pathReaches(e.target, targetId, nodeMap, new Set(visited))) return true;
  }
  return false;
}

function renderNode(nodeId, nodeMap, callMap, visited, lines, level, ctx, stopAt = null) {
  if (!nodeId || visited.has(nodeId)) return;
  if (stopAt && nodeId === stopAt) return;   // convergence point reached — stop true branch here
  const node = nodeMap[nodeId];
  if (!node) return;
  visited.add(nodeId);

  const { structParamTypes, modDsa, structureIndex, paramIndex } = ctx;

  switch (node.nodeType) {
    case 'Start':
      followEdges(node.edges, nodeMap, callMap, visited, lines, level, ctx, stopAt);
      break;

    case 'End':
      lines.push(`${ind(level)}RETURN;`);
      break;

    case 'Assign':
      for (const a of (node.assignments || [])) {
        const expanded = expandAssignment(a, structParamTypes, modDsa, structureIndex, ind(level));
        for (const line of expanded) lines.push(line);
      }
      followEdges(node.edges, nodeMap, callMap, visited, lines, level, ctx, stopAt);
      break;

    case 'ExecuteAction':
    case 'ExecuteClientAction': {
      const call = callMap[node.nodeId];
      const mod  = call?.sourceModule;
      const name = call?.resolvedName || node.name;
      const { recordReturnNodes } = ctx;

      if (mod === '(System)' && name in SYSTEM_ACTION_PARAMS) {
        emitSystemOp(node, name, lines, ind(level), structureIndex, paramIndex);
      } else if (mod) {
        const argStr = resolveArgs(node.args, paramIndex, ind(level));
        // If this call's result is referenced via .Record. accessor, capture return value
        const captureVar = recordReturnNodes?.has(name) ? `$${name} = ` : '';
        lines.push(`${ind(level)}${captureVar}CALL MICROFLOW ${mod}.${name}(${argStr});`);
      } else {
        lines.push(`${ind(level)}CALL MICROFLOW ${name}(); -- module unresolved`);
      }
      followEdges(node.edges, nodeMap, callMap, visited, lines, level, ctx, stopAt);
      break;
    }

    case 'Aggregate': {
      const filterClause = (node.filters && node.filters.length > 0)
        ? ` WHERE ${node.filters.map(f => f.condition || f).join(' AND ')}` : '';
      const limitClause  = (node.maxRecords && node.maxRecords !== '')
        ? ` LIMIT ${node.maxRecords}` : '';
      lines.push(`${ind(level)}RETRIEVE $${node.name} FROM ${node.entityName}${filterClause}${limitClause};`);
      followEdges(node.edges, nodeMap, callMap, visited, lines, level, ctx, stopAt);
      break;
    }

    case 'If': {
      const trueEdge  = node.edges.find(e => e.label === 'true');
      const falseEdge = node.edges.find(e => e.label === 'false');
      const falseTarget = falseEdge?.target;

      // Guard pattern: true branch converges back to false branch target → flat IF, no ELSE
      const isGuard = falseTarget &&
        trueEdge?.target &&
        pathReaches(trueEdge.target, falseTarget, nodeMap, new Set([node.nodeId]));

      if (isGuard) {
        const cond = rewriteRecordExprs(node.condition || 'true');
      lines.push(`${ind(level)}IF ${cond} THEN`);
        renderNode(trueEdge.target, nodeMap, callMap, new Set(visited), lines, level + 1, ctx, falseTarget);
        lines.push(`${ind(level)}END IF;`);
        renderNode(falseTarget, nodeMap, callMap, visited, lines, level, ctx);
      } else {
        const cond = rewriteRecordExprs(node.condition || 'true');
        // Render true branch into a temp buffer to detect empty-true pattern
        const trueBuf = [];
        if (trueEdge) renderNode(trueEdge.target, nodeMap, callMap, new Set(visited), trueBuf, level + 1, ctx);
        const trueIsEmpty = trueBuf.every(l => l.trim() === '');

        if (trueIsEmpty && falseEdge) {
          // Empty true body: invert condition, render false body as the only branch
          lines.push(`${ind(level)}IF not(${cond}) THEN`);
          renderNode(falseEdge.target, nodeMap, callMap, new Set(visited), lines, level + 1, ctx);
          lines.push(`${ind(level)}END IF;`);
        } else {
          lines.push(`${ind(level)}IF ${cond} THEN`);
          lines.push(...trueBuf);
          lines.push(`${ind(level)}ELSE`);
          if (falseEdge) renderNode(falseEdge.target, nodeMap, callMap, new Set(visited), lines, level + 1, ctx);
          lines.push(`${ind(level)}END IF;`);
        }
      }
      break;
    }

    case 'ForEach': {
      // ConnectorCycle → loop body; plain Connector (label:'') → done (after loop)
      const bodyEdge = node.edges.find(e => e.label === 'cycle');
      const doneEdge = node.edges.find(e => e.label === '');
      lines.push(`${ind(level)}LOOP $item IN $${node.recordList || 'list'} BEGIN`);
      if (bodyEdge) renderNode(bodyEdge.target, nodeMap, callMap, new Set(visited), lines, level + 1, ctx);
      lines.push(`${ind(level)}END LOOP;`);
      // Continue with the done edge (nodes after the loop)
      if (doneEdge) renderNode(doneEdge.target, nodeMap, callMap, visited, lines, level, ctx);
      break;
    }

    case 'SQL':
      lines.push(`${ind(level)}-- SQL: ${(node.sqlText || '').replace(/\n/g, ' ')}`);
      followEdges(node.edges, nodeMap, callMap, visited, lines, level, ctx, stopAt);
      break;

    case 'Comment':
      lines.push(`${ind(level)}-- ${node.comment || ''}`);
      followEdges(node.edges, nodeMap, callMap, visited, lines, level, ctx, stopAt);
      break;

    case 'Destination':
      lines.push(`${ind(level)}${node.screen ? `SHOW PAGE ${node.screen};` : '-- Destination (screen not resolved)'}`);
      followEdges(node.edges, nodeMap, callMap, visited, lines, level, ctx, stopAt);
      break;

    default:
      lines.push(`${ind(level)}-- TODO: ${node.nodeType} node not translated`);
      followEdges(node.edges, nodeMap, callMap, visited, lines, level, ctx, stopAt);
      break;
  }
}

function followEdges(edges, nodeMap, callMap, visited, lines, level, ctx, stopAt = null) {
  const mainEdge = (edges || []).find(e => e.label === '') || (edges || [])[0];
  if (mainEdge) renderNode(mainEdge.target, nodeMap, callMap, visited, lines, level, ctx, stopAt);
}

// Resolve args array [{paramKey, value}] → "Name1: val1, Name2: val2"
// Falls back to positional comments when param name is unknown.
function resolveArgs(args, paramIndex, indStr) {
  if (!args || args.length === 0) return '';
  const parts = args.map(a => {
    const name = paramIndex[a.paramKey];
    const val  = rewriteRecordExprs(a.value || '');
    return name ? `${name}: ${val}` : `/* ${a.paramKey} */ ${val}`;
  });
  // Single arg → inline; multiple → one per line with indent
  if (parts.length === 1) return parts[0];
  return '\n' + parts.map(p => `${indStr}  ${p}`).join(',\n') + `\n${indStr}`;
}

// Emit native MDL for all OutSystems (System) built-in actions.
function emitSystemOp(node, actionName, lines, indStr, structureIndex, paramIndex) {
  const args = node.args || [];

  // Resolve args by param name using paramIndex, with positional fallback
  const byName = {};
  for (const a of args) {
    const pName = paramIndex[a.paramKey];
    if (pName) byName[pName] = rewriteRecordExprs(a.value || '');
  }
  if (Object.keys(byName).length === 0) {
    const order = SYSTEM_ACTION_PARAMS[actionName] || [];
    args.forEach((a, i) => { if (order[i]) byName[order[i]] = rewriteRecordExprs(a.value || ''); });
  }

  const shortId  = node.nodeId.replace(/[^a-zA-Z0-9]/g, '').slice(-4);
  const listVar  = byName['List'] || byName['SourceList'] || 'list';

  switch (actionName) {

    // ── List: append one element ────────────────────────────────────────────
    case 'ListAppend': {
      const elemVal  = byName['Element'] || '{}';
      const elemArg  = args.find(a => a.requiredType && a.requiredType.startsWith('Structure'));
      const elemType = (elemArg && structureIndex && structureIndex[elemArg.requiredType])
        ? (() => { const e = structureIndex[elemArg.requiredType]; return e.module ? `${e.module}.${e.name}` : e.name; })()
        : 'OBJECT /* TODO: replace with concrete NPE type */';
      const initPairs = elemVal && elemVal !== '{}'
        ? elemVal.replace(/^\{|\}$/g, '').trim().split(',').map(p => p.trim()).filter(Boolean).join(', ')
        : '';
      lines.push(`${indStr}$_elem_${shortId} = CREATE ${elemType}${initPairs ? ` (${initPairs})` : ''};`);
      lines.push(`${indStr}ADD $_elem_${shortId} TO $${byName['List'] || 'list'};`);
      break;
    }

    // ── List: append all items from another list ────────────────────────────
    case 'ListAppendAll':
      lines.push(`${indStr}ADD $${byName['SourceList'] || 'sourceList'} TO $${byName['List'] || 'list'};`);
      break;

    // ── List: clear ─────────────────────────────────────────────────────────
    case 'ListClear':
      lines.push(`${indStr}$${listVar} = CREATE LIST OF OBJECT; -- TODO: replace OBJECT with concrete NPE type`);
      break;

    // ── List: duplicate ─────────────────────────────────────────────────────
    case 'ListDuplicate': {
      const src = byName['SourceList'] || 'sourceList';
      lines.push(`${indStr}$_dup_${shortId} = CREATE LIST OF OBJECT; -- TODO: replace OBJECT with concrete NPE type`);
      lines.push(`${indStr}ADD $${src} TO $_dup_${shortId};`);
      break;
    }

    // ── List: positional remove → REMOVE by reference (find item first) ──────
    case 'ListRemove': {
      const rList = byName['List'] || 'list';
      const rPos  = byName['Position'] || '?';
      lines.push(`${indStr}-- ListRemove positional: find object at index ${rPos} then remove by reference`);
      lines.push(`${indStr}$_found_${shortId} = FIND($${rList}, /* TODO: condition for position ${rPos} */);`);
      lines.push(`${indStr}REMOVE $_found_${shortId} FROM $${rList};`);
      break;
    }

    // ── List: filter → native FILTER() expression ────────────────────────────
    case 'ListFilter': {
      const fSrc  = byName['SourceList'] || 'sourceList';
      const fCond = byName['Condition']  || 'true';
      lines.push(`${indStr}$_filtered_${shortId} = FILTER($${fSrc}, ${fCond});`);
      break;
    }

    // ── List: sort → native SORT() expression ────────────────────────────────
    case 'ListSort': {
      const sList = byName['List'] || 'list';
      const sBy   = byName['By']   || '/* TODO: Attr ASC|DESC */';
      lines.push(`${indStr}$_sorted_${shortId} = SORT($${sList}, ${sBy});`);
      break;
    }

    // ── List: ListAny → FILTER() + empty check ───────────────────────────────
    case 'ListAny': {
      const aList = byName['List']      || 'list';
      const aCond = byName['Condition'] || 'true';
      lines.push(`${indStr}$_any_${shortId} = FILTER($${aList}, ${aCond}) != empty;`);
      break;
    }

    // ── List: ListAll → FILTER(NOT cond) empty check ─────────────────────────
    case 'ListAll': {
      const allList = byName['List']      || 'list';
      const allCond = byName['Condition'] || 'true';
      lines.push(`${indStr}-- ListAll: true when no item fails condition`);
      lines.push(`${indStr}$_all_${shortId} = FILTER($${allList}, not(${allCond})) = empty;`);
      break;
    }

    // ── List: indexOf → FIND() returns item (not index) ──────────────────────
    case 'ListIndexOf': {
      const iList = byName['List']      || 'list';
      const iCond = byName['Condition'] || 'true';
      lines.push(`${indStr}-- ListIndexOf: MDL returns the matching item via FIND, not a numeric index`);
      lines.push(`${indStr}$_found_${shortId} = FIND($${iList}, ${iCond});`);
      break;
    }

    // ── List: insert at position (no direct MDL equivalent) ──────────────────
    case 'ListInsert': {
      const insList = byName['List']     || 'list';
      const insElem = byName['Element']  || '?';
      const insPos  = byName['Position'] || '?';
      lines.push(`${indStr}-- TODO: ListInsert has no positional equivalent in MDL`);
      lines.push(`${indStr}-- Rebuild: split $${insList} at position ${insPos}, insert ${insElem}, re-union`);
      lines.push(`${indStr}$_head_${shortId} = RANGE($${insList}, 0, ${insPos} - 1);`);
      lines.push(`${indStr}$_tail_${shortId} = RANGE($${insList}, ${insPos}, COUNT($${insList}));`);
      lines.push(`${indStr}$_ins_${shortId} = CREATE LIST OF OBJECT; -- TODO: concrete type`);
      lines.push(`${indStr}ADD $_head_${shortId} TO $_ins_${shortId};`);
      lines.push(`${indStr}ADD $${insElem} TO $_ins_${shortId};`);
      lines.push(`${indStr}ADD $_tail_${shortId} TO $_ins_${shortId};`);
      break;
    }

    // ── List: distinct (no direct MDL equivalent) ─────────────────────────────
    case 'ListDistinct': {
      const dSrc = byName['SourceList'] || 'sourceList';
      lines.push(`${indStr}-- TODO: ListDistinct has no native MDL equivalent`);
      lines.push(`${indStr}-- Option: use RETRIEVE with XPath DISTINCT, or dedup in loop`);
      lines.push(`${indStr}-- Source: $${dSrc}`);
      break;
    }

    // ── Logging ─────────────────────────────────────────────────────────────
    case 'LogMessage': {
      const node_  = byName['ModuleName'] || "'App'";
      const msg    = byName['Message']    || "''";
      lines.push(`${indStr}LOG INFO NODE ${node_} ${msg};`);
      break;
    }

    // ── Transactions ─────────────────────────────────────────────────────────
    // MDL syntax: COMMIT $var [WITH EVENTS] [REFRESH]
    // CommitTransaction commits the whole DB transaction; Mendix requires per-object COMMIT
    case 'CommitTransaction':
      lines.push(`${indStr}-- CommitTransaction: identify changed objects above and COMMIT each explicitly`);
      lines.push(`${indStr}-- COMMIT $changedObject [WITH EVENTS] [REFRESH];`);
      break;

    // MDL syntax: ROLLBACK $var [REFRESH]
    // AbortTransaction rolls back everything; MDL requires a specific object reference
    case 'AbortTransaction':
      lines.push(`${indStr}-- AbortTransaction: ROLLBACK requires a specific object — or throw exception for auto-rollback`);
      lines.push(`${indStr}-- ROLLBACK $changedObject [REFRESH];`);
      break;

    // ── Authentication ───────────────────────────────────────────────────────
    case 'Login':
      lines.push(`${indStr}-- TODO: Login(UserId: ${byName['UserId'] || '?'}, Persistent: ${byName['Persistent'] || '?'})`);
      lines.push(`${indStr}-- Mendix: use Administration.Account login microflows`);
      break;

    case 'LoginPassword':
      lines.push(`${indStr}-- TODO: LoginPassword(UserId: ${byName['UserId'] || '?'}, Password: ${byName['Password'] || '?'})`);
      lines.push(`${indStr}-- Mendix: use System.ValidatePassword + Administration.Account`);
      break;

    case 'Logout':
      lines.push(`${indStr}-- TODO: Logout — Mendix: use System.DeleteSession microflow or page logout action`);
      break;

    // ── Notifications ────────────────────────────────────────────────────────
    // MDL syntax: SHOW MESSAGE expr [TYPE Information|Warning|Error] [OBJECTS [...]]
    case 'Deprecated_Notify': {
      const msg = byName['Message'] || "''";
      lines.push(`${indStr}SHOW MESSAGE ${msg} TYPE Information;`);
      break;
    }

    case 'Deprecated_NotifyGetMessage':
      lines.push(`${indStr}-- TODO: Deprecated_NotifyGetMessage — no Mendix equivalent; use session variable or feedback widget`);
      break;

    // ── Misc ─────────────────────────────────────────────────────────────────
    case 'SetCurrentLocale':
      lines.push(`${indStr}-- TODO: SetCurrentLocale(Locale: ${byName['Locale'] || '?'}) — Mendix: set $currentSession Language`);
      break;

    case 'GenerateGuid':
      lines.push(`${indStr}-- TODO: GenerateGuid — Mendix: use Community Commons GenerateGUID() or java.util.UUID.randomUUID()`);
      break;

    case 'TenantSwitch':
      lines.push(`${indStr}-- TODO: TenantSwitch(TenantId: ${byName['TenantId'] || '?'}) — Mendix: multi-tenant architecture differs; review manually`);
      break;

    case 'EspaceInvalidateCache':
      lines.push(`${indStr}-- TODO: EspaceInvalidateCache — Mendix: no direct equivalent; review caching strategy`);
      break;

    case 'IntegratedSecurityGetDetails':
      lines.push(`${indStr}-- TODO: IntegratedSecurityGetDetails — Mendix: use $currentUser attributes`);
      break;

    default:
      lines.push(`${indStr}-- TODO: (System).${actionName}(${Object.entries(byName).map(([k, v]) => `${k}: ${v}`).join(', ')})`);
      break;
  }
}

// Expand an assignment statement, handling Mendix model-driven patterns.
function expandAssignment(a, structParamTypes, modDsa, structureIndex, indStr) {
  const varr  = a.variable   || '';
  const expr  = rewriteRecordExprs(a.expression || '');
  const parts = varr.split('.');

  // Pattern R: NodeName.Record.EntityName.Attr or NodeName.Record.Field
  // OutSystems Record accessor → CHANGE $NodeName.Attr = expr;
  if (varr.includes('.Record.')) {
    const [nodeName, , ...rest] = parts;
    // strip the EntityName segment if 4-part (Node.Record.Entity.Attr)
    const attrPath = rest.length >= 2 ? rest.slice(1).join('.') : rest.join('.');
    return [`${indStr}CHANGE $${nodeName}.${attrPath} = ${expr};`];
  }

  // Pattern A: SET X = Y where Y is a bare Structure-type param (whole-object assignment)
  if (!expr.includes('.') && structParamTypes && structParamTypes[expr] && parts.length === 1) {
    const srcType = structParamTypes[expr];
    const attrs   = (srcType._attrs || []);
    if (attrs.length > 0) {
      const out = [`${indStr}-- [EXPANDED] OutSystems: SET ${varr} = ${expr} (whole-object Structure assignment)`];
      out.push(`${indStr}-- Mendix: $${varr} must be passed as non-persistent entity parameter (type: ${srcType.module}.${srcType.name})`);
      for (const attr of attrs) {
        out.push(`${indStr}CHANGE $${varr}.${attr} = $${expr}.${attr};`);
      }
      out.push(`${indStr}REFRESH OBJECT $${varr};`);
      return out;
    }
    return [
      `${indStr}-- [MIGRATION] SET ${varr} = ${expr} — whole-object Structure assignment`,
      `${indStr}-- Add $${varr}: ${srcType.module}.${srcType.name} as input parameter; Change each attribute individually`,
      `${indStr}SET ${varr} = ${expr}; -- TODO: expand to per-attribute CHANGE`,
    ];
  }

  // Pattern B: SET DSA.OutputParam.Field = Expr
  if (parts.length === 3 && modDsa && modDsa[parts[0]] && modDsa[parts[0]][parts[1]]) {
    const dsaName   = parts[0];
    const paramName = parts[1];
    const fieldName = parts[2];
    const paramInfo = modDsa[dsaName][paramName];
    const mendixParam = `$${dsaName}_${paramName}`;
    const fqn = paramInfo.kind === 'struct' ? `${paramInfo.module}.${paramInfo.name}` : paramInfo.type;
    return [
      `${indStr}-- [DSA] ${dsaName}.${paramName} → ${fqn} (DataScreenAction output)`,
      `${indStr}-- Mendix: pass ${mendixParam}: ${fqn} as nanoflow parameter`,
      `${indStr}CHANGE ${mendixParam}.${fieldName} = ${expr};`,
    ];
  }

  return [`${indStr}SET ${varr} = ${expr};`];
}

module.exports = { translateFlow };
