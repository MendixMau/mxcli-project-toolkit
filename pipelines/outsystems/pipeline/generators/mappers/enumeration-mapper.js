'use strict';

function mapEnumeration(item) {
  const lines = [`CREATE ENUMERATION ${item.module}.${item.name} (`];
  const records = item.records || [];
  if (records.length === 0) {
    lines.push('  -- no records');
  } else {
    records.forEach((r, i) => {
      const comma = i < records.length - 1 ? ',' : '';
      lines.push(`  ${r.name} '${r.label}'${comma}`);
    });
  }
  lines.push(');');
  return lines.join('\n') + '\n';
}

module.exports = { mapEnumeration };
