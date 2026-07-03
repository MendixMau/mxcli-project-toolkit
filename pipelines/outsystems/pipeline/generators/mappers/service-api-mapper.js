'use strict';
const { convertType } = require('../lib/type-converter');

function mapServiceApi(item) {
  const inputs = (item.inputParameters || [])
    .map(p => `    ${p.name}: ${convertType(p.type, p.length || '')}`)
    .join(',\n');
  const outputs = (item.outputParameters || [])
    .map(p => `    ${p.name}: ${convertType(p.type, p.length || '')}`)
    .join(',\n');

  const lines = [
    `-- PUBLISHED REST SERVICE: ${item.module}.${item.name}`,
    `-- TODO: HTTP method and URL path not available in KB; fill in manually`,
    `CREATE PUBLISHED REST SERVICE ${item.module}.${item.name} {`,
  ];
  if (inputs) {
    lines.push(`  -- Input parameters:`);
    lines.push(`  -- ${inputs.replace(/\n/g, '\n  -- ')}`);
  }
  if (outputs) {
    lines.push(`  -- Output parameters:`);
    lines.push(`  -- ${outputs.replace(/\n/g, '\n  -- ')}`);
  }
  lines.push(`  -- ENDPOINT: <method> /<path> CALLS ${item.module}.${item.name};`);
  lines.push('};\n');
  return lines.join('\n');
}

module.exports = { mapServiceApi };
