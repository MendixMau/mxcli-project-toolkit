'use strict';

// Java/TypeScript type name -> Mendix type. This table (not the function shape) is the
// stack-specific part per migration-pipeline.md's "Creating a New Stack Pipeline" checklist —
// the OS pipeline's equivalent file keys on OS type names ('Text', 'Long Integer', ...) instead.
const TYPE_MAP = {
  'Long': 'Long',
  'long': 'Long',
  'Integer': 'Integer',
  'int': 'Integer',
  'BigDecimal': 'Decimal',
  'Double': 'Decimal',
  'double': 'Decimal',
  'Float': 'Decimal',
  'float': 'Decimal',
  'Boolean': 'Boolean',
  'boolean': 'Boolean',
  'LocalDateTime': 'DateTime',
  'LocalDate': 'Date',
  'Instant': 'DateTime',
};

function convertType(javaType, length, structureIndex) {
  if (!javaType) return 'String(unlimited)';
  if (TYPE_MAP[javaType]) return TYPE_MAP[javaType];

  if (javaType === 'String') {
    return (length && length !== '') ? `String(${length})` : 'String(unlimited)';
  }

  // Non-persistent DTO / structure reference, resolved via a structure index if available
  // (mirrors the OS pipeline's Structure:/StructureReference:/ListType: handling).
  if (structureIndex && structureIndex[javaType]) {
    const { name, module, isList } = structureIndex[javaType];
    const fqn = module ? `${module}.${name}` : name;
    return isList ? `List of ${fqn}` : fqn;
  }

  return `Object /* unresolved Java type: ${javaType} */`;
}

module.exports = { convertType };
