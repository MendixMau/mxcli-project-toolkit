'use strict';

class Linker {
  link(allItems) {
    const byType     = {};
    for (const item of allItems) {
      (byType[item.type] = byType[item.type] || []).push(item);
    }

    const map = {};
    for (const item of allItems) {
      map[item.linkId] = { linkedTo: [], gaps: [] };
    }

    const entities    = byType['entity']       || [];
    const logics      = byType['logic']        || [];
    const screens     = byType['screen']       || [];
    const staticEnts  = byType['staticEntity'] || [];

    // Index helpers for O(1) lookup
    const entityByName   = new Map([...entities, ...staticEnts].map(e => [e.name.toLowerCase(), e]));
    const screenByName    = new Map(screens.map(s => [s.name, s]));
    const logicsByModule  = new Map();
    for (const l of logics) (logicsByModule.get(l.module) || logicsByModule.set(l.module, []).get(l.module)).push(l);

    // Compares a Java httpEndpoint path template ("/api/items/{itemId}/itemActions") against
    // an Angular-reconstructed path ("/api/items/*/itemActions") segment-by-segment. Either
    // side may have a placeholder segment (Java's {name}, Angular's *) at the same position —
    // since both represent "a real ID goes here at runtime", any placeholder-vs-anything pair
    // matches. Literal segments must match exactly.
    function pathsMatch(a, b) {
      const segsA = a.split('/').filter(Boolean);
      const segsB = b.split('/').filter(Boolean);
      if (segsA.length !== segsB.length) return false;
      return segsA.every((segA, i) => {
        const segB = segsB[i];
        const isPlaceholder = s => s === '*' || /^\{.*\}$/.test(s);
        return isPlaceholder(segA) || isPlaceholder(segB) || segA === segB;
      });
    }

    // Rule J1: Entity FK attribute → referenced Entity (by name). Fully stack-agnostic —
    // works because java-extractor.js represents JPA associations as synthetic
    // "<Entity> Identifier"-typed attributes, same shape OS uses for its own FK attributes.
    for (const entity of [...entities, ...staticEnts]) {
      for (const attr of (entity.attributes || [])) {
        if (!attr.isForeignKey || !attr.referencedEntity) continue;
        const target = entityByName.get(attr.referencedEntity.toLowerCase());
        if (target) {
          map[entity.linkId].linkedTo.push({
            id: target.linkId, confidence: 'high', matchedBy: 'fk-identifier-name',
            via: attr.name,
          });
        } else {
          map[entity.linkId].gaps.push(`fk-unresolved:${attr.referencedEntity}`);
        }
      }
    }

    // Rule J2: Logic → Entity (repository-call naming convention: "itemRepository.findById"
    // implies the Item entity, "itemActionRepository.save" implies ItemAction, etc.)
    for (const logic of logics) {
      const linkedEntityNames = new Set();
      for (const call of (logic.calls || [])) {
        const m = /^([a-zA-Z]+)Repository\./.exec(call.name || '');
        if (!m) continue;
        const entityGuess = m[1]; // e.g. "item" or "itemAction"
        const target = entityByName.get(entityGuess.toLowerCase());
        if (target && !linkedEntityNames.has(target.name)) {
          linkedEntityNames.add(target.name);
          map[logic.linkId].linkedTo.push({
            id: target.linkId, confidence: 'high', matchedBy: 'repository-call-name', via: call.name,
          });
        }
      }
    }

    // Rule J3: Logic → Logic (same-module call-name match — mirrors OS's ExecuteAction rule,
    // but our calls[] are raw name strings rather than resolved uniqueId keys, so we match by
    // name within the same module instead. This is what makes e.g. deleteItem's call to
    // deleteItemWithRelatedItemActions traceable as a real cross-reference, not just text.)
    for (const logic of logics) {
      const sameModule = logicsByModule.get(logic.module) || [];
      for (const call of (logic.calls || [])) {
        const target = sameModule.find(l => l.name === call.name && l.linkId !== logic.linkId);
        if (target) {
          map[logic.linkId].linkedTo.push({
            id: target.linkId, confidence: 'high', matchedBy: 'same-module-call-name', via: call.name,
          });
        }
      }
    }

    // Rule J4: Screen → Logic. Prefers verb-resolved apiCalls (matches method AND path shape,
    // so ItemDeleteComponent links only to the DELETE logic, not also GET/PUT on the same
    // path) and falls back to bare apiPaths (path shape only, any verb) when the extractor
    // couldn't pair a verb — see angular-extractor.js's scanApiCallsInMethod().
    for (const screen of screens) {
      let matched = false;
      for (const { path: apiPath, method } of (screen.apiCalls || [])) {
        for (const logic of logics) {
          if (!logic.httpEndpoint || logic.httpEndpoint.method !== method) continue;
          if (pathsMatch(logic.httpEndpoint.path, apiPath)) {
            matched = true;
            map[screen.linkId].linkedTo.push({
              id: logic.linkId, confidence: 'high', matchedBy: 'api-call-match',
              via: `${logic.httpEndpoint.method} ${apiPath}`,
            });
          }
        }
      }
      for (const apiPath of (screen.apiPaths || [])) {
        for (const logic of logics) {
          if (!logic.httpEndpoint) continue;
          if (pathsMatch(logic.httpEndpoint.path, apiPath)) {
            matched = true;
            map[screen.linkId].linkedTo.push({
              id: logic.linkId, confidence: 'medium', matchedBy: 'api-path-match-no-verb',
              via: `${logic.httpEndpoint.method} ${apiPath}`,
            });
          }
        }
      }
      // A screen with no direct API call is only a real gap if it also doesn't delegate to a
      // composed child component that does — a pure layout/composition wrapper (e.g.
      // ItemsComponent composing ItemListComponent) is not missing anything.
      if (!matched && !(screen.composesComponents || []).length && screen.angularScreenKind !== 'embedded') {
        map[screen.linkId].gaps.push('no-api-path-found');
      }
    }

    // Rule J5: Screen → Screen (dialog launch relationships, both directions)
    for (const screen of screens) {
      for (const openerName of (screen.launchedFrom || [])) {
        const opener = screenByName.get(openerName);
        if (opener) {
          map[screen.linkId].linkedTo.push({ id: opener.linkId, confidence: 'high', matchedBy: 'dialog-launched-from', via: openerName });
          map[opener.linkId].linkedTo.push({ id: screen.linkId, confidence: 'high', matchedBy: 'dialog-opens', via: screen.name });
        }
      }
    }

    // Rule J6: Screen → Screen (template composition — parent embeds child as a custom element)
    for (const screen of screens) {
      for (const childName of (screen.composesComponents || [])) {
        const child = screenByName.get(childName);
        if (child) {
          map[screen.linkId].linkedTo.push({ id: child.linkId, confidence: 'high', matchedBy: 'composes-component', via: childName });
        }
      }
    }

    return map;
  }
}

module.exports = { Linker };
