'use strict';

const TYPE_MAP = {
  'Integer': 'Integer',
  'Long Integer': 'Long',
  'Decimal': 'Decimal',
  'Boolean': 'Boolean',
  'DateTime': 'DateTime',
  'Date Time': 'DateTime',      // OutSystems sometimes emits with space
  'Date': 'Date',
  'Time': 'Time',
  'Binary Data': 'Binary',
  'Currency': 'Decimal',
  'Email': 'String(200)',
  'Phone Number': 'String(20)',
  'Object': 'Object',
};

function convertType(osType, length, structureIndex) {
  if (!osType) return 'String(unlimited)';
  if (TYPE_MAP[osType]) return TYPE_MAP[osType];

  if (osType === 'Text') {
    return (length && length !== '') ? `String(${length})` : 'String(unlimited)';
  }

  // Entity identifier types: "EntityName Identifier" → Long
  if (osType.endsWith(' Identifier')) {
    const entityName = osType.slice(0, -' Identifier'.length);
    return `Long /* ${entityName} ID */`;
  }

  // Structure / StructureReference / ListType — resolve via index if available
  if (osType.startsWith('Structure:') || osType.startsWith('StructureReference:') || osType.startsWith('ListType:')) {
    if (structureIndex && structureIndex[osType]) {
      const { name, module, isList } = structureIndex[osType];
      const fqn = module ? `${module}.${name}` : name;
      return isList ? `List of ${fqn}` : fqn;
    }
    // Fallback when index missing or key not found
    if (osType.startsWith('ListType:')) return 'List /* unresolved */';
    return 'Object /* unresolved Structure */';
  }

  // EntityReference keys
  if (osType.startsWith('EntityReference:')) {
    return 'Long /* EntityReference */';
  }

  return 'String(unlimited)';
}

module.exports = { convertType };
