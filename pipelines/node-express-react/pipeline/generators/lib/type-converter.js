'use strict';

// TypeScript/JavaScript type name → Mendix attribute type.
// Stack-specific table for Node/Express/React (TypeScript interfaces + Mongoose-style types).
const TYPE_MAP = {
  'string':   'String(unlimited)',
  'String':   'String(unlimited)',
  'number':   'Decimal',
  'Number':   'Decimal',
  'boolean':  'Boolean',
  'Boolean':  'Boolean',
  'Date':     'DateTime',
  'ObjectId': 'String(36)',   // stored as UUID/string in Mendix
  'Buffer':   'Binary',
};

function convertType(tsType, length) {
  if (!tsType) return 'String(unlimited)';
  if (TYPE_MAP[tsType]) {
    const base = TYPE_MAP[tsType];
    if (base === 'String(unlimited)' && length && length !== '') return `String(${length})`;
    return base;
  }
  // Enum references — will be resolved as Enumeration in domain-entity-mapper
  if (/^[A-Z]/.test(tsType)) return `Enumeration /* ${tsType} */`;
  return 'String(unlimited)';
}

module.exports = { convertType };
