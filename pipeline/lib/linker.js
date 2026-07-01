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
    const tables      = byType['table']        || [];
    const classes     = byType['cs-class']     || [];
    const jsModules   = byType['js-module']    || [];
    const logics      = byType['logic']        || [];
    const screens     = byType['screen']       || [];
    const roles       = byType['role']         || [];
    const timers      = byType['timer']        || [];
    const staticEnts  = byType['staticEntity'] || [];

    // Index helpers for O(1) lookup
    const logicByUniqueId  = new Map(logics.map(l => [l.uniqueId, l]));
    const entityByName     = new Map([...entities, ...staticEnts].map(e => [e.name.toLowerCase(), e]));
    const roleByUniqueId   = new Map(roles.map(r => [r.uniqueId, r]));

    // ── Cross-source rules (require CS / DB — degrade gracefully when missing) ──

    // Rule 1: XML Entity → DB Table (ossys_{entityName} naming)
    // Only report gaps when DB data is available — avoids polluting report when source is missing.
    for (const entity of entities) {
      const expectedTable = `ossys_${entity.name}`;
      const match = tables.find(t => t.name.toLowerCase() === expectedTable.toLowerCase());
      if (match) {
        map[entity.linkId].linkedTo.push({ id: match.linkId, confidence: 'high', matchedBy: 'ossys-name-pattern' });
      } else {
        map[entity.linkId].gaps.push('no-db-table-found');
      }
    }

    // Rule 2: XML Logic → C# Class (name substring match)
    for (const logic of logics) {
      const match = classes.find(c =>
        c.name.toLowerCase().includes(logic.name.toLowerCase()) ||
        logic.name.toLowerCase().includes(c.name.toLowerCase())
      );
      if (match) {
        map[logic.linkId].linkedTo.push({ id: match.linkId, confidence: 'high', matchedBy: 'name-substring' });
      }
    }

    // Rule 3: XML Screen → JS Module (name match)
    for (const screen of screens) {
      const match = jsModules.find(m =>
        m.name.toLowerCase().includes(screen.name.toLowerCase()) ||
        screen.name.toLowerCase().includes(m.name.toLowerCase())
      );
      if (match) {
        map[screen.linkId].linkedTo.push({ id: match.linkId, confidence: 'high', matchedBy: 'name-match' });
      }
    }

    // Rule 4: XML Entity → C# class (medium confidence, name substring)
    for (const entity of entities) {
      const match = classes.find(c =>
        c.name.toLowerCase().includes(entity.name.toLowerCase())
      );
      if (match && !map[entity.linkId].linkedTo.some(l => l.id === match.linkId)) {
        map[entity.linkId].linkedTo.push({ id: match.linkId, confidence: 'medium', matchedBy: 'name-substring' });
      }
    }

    // ── XML-only rules (work without CS / DB) ──

    // Rule X1: Entity FK attribute → referenced Entity (by name)
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

    // Rule X2: Logic ExecuteAction → target Logic (by uniqueId key)
    for (const logic of logics) {
      for (const call of (logic.calls || [])) {
        const target = logicByUniqueId.get(call.target);
        if (target) {
          map[logic.linkId].linkedTo.push({
            id: target.linkId, confidence: 'high', matchedBy: 'execute-action-key',
            via: call.name,
          });
        }
      }
    }

    // Rule X3: Screen Permission → Role (by uniqueId key)
    for (const screen of screens) {
      for (const perm of (screen.permissions || [])) {
        const target = roleByUniqueId.get(perm.roleKey);
        if (target) {
          map[screen.linkId].linkedTo.push({
            id: target.linkId, confidence: 'high', matchedBy: 'screen-permission-role',
          });
        }
      }
    }

    // Rule X4: Timer → Logic (by actionRef uniqueId key)
    for (const timer of timers) {
      if (!timer.actionRef) continue;
      const target = logicByUniqueId.get(timer.actionRef);
      if (target) {
        map[timer.linkId].linkedTo.push({
          id: target.linkId, confidence: 'high', matchedBy: 'timer-action-key',
        });
      } else {
        map[timer.linkId].gaps.push('timer-action-unresolved');
      }
    }

    // Rule X5: Screen clientActions → Logic (screen initialization logic)
    for (const screen of screens) {
      for (const ca of (screen.clientActions || [])) {
        const target = logicByUniqueId.get(ca.key);
        if (target) {
          map[screen.linkId].linkedTo.push({
            id: target.linkId, confidence: 'high', matchedBy: 'screen-client-action',
            via: ca.name,
          });
        }
      }
    }

    // Rule X6: ServiceAPI → Logic (same-module action by name match for same-module actions)
    const serviceApis = byType['serviceApi'] || [];
    for (const api of serviceApis) {
      const match = logics.find(l => l.module === api.module && l.name === api.name);
      if (match) {
        map[api.linkId].linkedTo.push({
          id: match.linkId, confidence: 'high', matchedBy: 'service-api-action-name',
        });
      }
    }

    return map;
  }
}

module.exports = { Linker };
