'use strict';
const { convertType } = require('../lib/type-converter');

function mapDomainEntities(entities, staticEntities) {
  const result = [];

  for (const e of staticEntities) {
    result.push({
      name:        e.name,
      mendixType:  'Enumeration',
      isPublic:    e.isPublic || false,
      description: e.description || '',
      values:      (e.records || []).map(r => ({ name: r.name, label: r.label || r.name })),
      gaps:        e._gaps || [],
    });
  }

  for (const e of entities) {
    const attrs = e.attributes || [];
    const keyAttributes = attrs
      .filter(a => a.isMandatory || a.isForeignKey)
      .filter(a => !a.isAutoNumber)
      .map(a => ({
        name:             a.name,
        type:             convertType(a.type, a.length || ''),
        isMandatory:      a.isMandatory,
        isForeignKey:     a.isForeignKey,
        referencedEntity: a.referencedEntity || '',
        deleteRule:       a.deleteRule || '',
      }));

    const associations = attrs
      .filter(a => a.isForeignKey && a.referencedEntity)
      .map(a => ({
        to:         a.referencedEntity,
        deleteRule: a.deleteRule || '',
      }));

    result.push({
      name:           e.name,
      mendixType:     'PersistentEntity',
      isPublic:       e.isPublic || false,
      description:    e.description || '',
      attributeCount: attrs.filter(a => !a.isAutoNumber && !a.isForeignKey).length,
      keyAttributes,
      associations,
      indexes:        (e.indexes || []).map(i => ({ name: i.name, isUnique: i.isUnique })),
      gaps:           e._gaps || [],
    });
  }

  return result;
}

module.exports = { mapDomainEntities };
