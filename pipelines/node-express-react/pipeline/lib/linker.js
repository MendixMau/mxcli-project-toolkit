'use strict';

/**
 * Linker for Node/Express/React stack.
 * Rules adapted from java-angular linker.js — same engine, different cross-reference patterns:
 *   NR1: Entity FK → referenced Entity (by referencedEntity name on FK attributes)
 *   NR2: Logic → Entity (Express route handler references model by variable name/import)
 *   NR3: Logic → Logic (same-module function call by name)
 *   NR4: Screen → Logic (React container's GraphQL/REST calls → Express route handler)
 *   NR5: Screen → Screen (React component composition)
 */
class Linker {
  link(allItems) {
    const byType = {};
    for (const item of allItems) {
      (byType[item.type] = byType[item.type] || []).push(item);
    }

    const map = {};
    for (const item of allItems) {
      map[item.linkId] = { linkedTo: [], gaps: [] };
    }

    const entities   = byType['entity']       || [];
    const staticEnts = byType['staticEntity'] || [];
    const logics     = byType['logic']        || [];
    const screens    = byType['screen']       || [];

    const entityByName  = new Map([...entities, ...staticEnts].map(e => [e.name.toLowerCase(), e]));
    const screenByName  = new Map(screens.map(s => [s.name, s]));
    const logicsByModule = new Map();
    for (const l of logics) {
      (logicsByModule.get(l.module) || logicsByModule.set(l.module, []).get(l.module)).push(l);
    }

    // Compare Express path template ("/transactions/:transactionId") against
    // a React client path ("/transactions/*") — placeholder segments match anything.
    function pathsMatch(a, b) {
      const segsA = a.split('/').filter(Boolean);
      const segsB = b.split('/').filter(Boolean);
      if (segsA.length !== segsB.length) return false;
      return segsA.every((segA, i) => {
        const segB = segsB[i];
        const isPlaceholder = s => s === '*' || s.startsWith(':');
        return isPlaceholder(segA) || isPlaceholder(segB) || segA === segB;
      });
    }

    // NR1: Entity FK → referenced Entity
    for (const entity of [...entities, ...staticEnts]) {
      for (const attr of (entity.attributes || [])) {
        if (!attr.isForeignKey || !attr.referencedEntity) continue;
        const target = entityByName.get(attr.referencedEntity.toLowerCase());
        if (target) {
          map[entity.linkId].linkedTo.push({
            id: target.linkId, confidence: 'high', matchedBy: 'fk-ref-name', via: attr.name,
          });
        } else {
          map[entity.linkId].gaps.push(`fk-unresolved:${attr.referencedEntity}`);
        }
      }
    }

    // NR2: Logic → Entity (Express route handlers import Mongoose models by name)
    for (const logic of logics) {
      for (const modelName of (logic.referencedModels || [])) {
        const target = entityByName.get(modelName.toLowerCase());
        if (target) {
          map[logic.linkId].linkedTo.push({
            id: target.linkId, confidence: 'high', matchedBy: 'model-import', via: modelName,
          });
        }
      }
    }

    // NR3: Logic → Logic (same-module call by name)
    for (const logic of logics) {
      const sameModule = logicsByModule.get(logic.module) || [];
      for (const call of (logic.calls || [])) {
        const target = sameModule.find(l => l.name === call.name && l.linkId !== logic.linkId);
        if (target) {
          map[logic.linkId].linkedTo.push({
            id: target.linkId, confidence: 'high', matchedBy: 'same-module-call', via: call.name,
          });
        }
      }
    }

    // NR4: Screen → Logic (React container GraphQL mutation/query or REST call → route handler)
    for (const screen of screens) {
      let matched = false;
      for (const { path: apiPath, method } of (screen.apiCalls || [])) {
        for (const logic of logics) {
          if (!logic.httpEndpoint) continue;
          if (logic.httpEndpoint.method && logic.httpEndpoint.method !== method) continue;
          if (pathsMatch(logic.httpEndpoint.path, apiPath)) {
            matched = true;
            map[screen.linkId].linkedTo.push({
              id: logic.linkId, confidence: 'high', matchedBy: 'api-call-match',
              via: `${method} ${apiPath}`,
            });
          }
        }
      }
      if (!matched && !(screen.composesComponents || []).length) {
        map[screen.linkId].gaps.push('no-api-path-found');
      }
    }

    // NR5: Screen → Screen (React component composition)
    for (const screen of screens) {
      for (const childName of (screen.composesComponents || [])) {
        const child = screenByName.get(childName);
        if (child) {
          map[screen.linkId].linkedTo.push({
            id: child.linkId, confidence: 'high', matchedBy: 'composes-component', via: childName,
          });
        }
      }
    }

    return map;
  }
}

module.exports = { Linker };
