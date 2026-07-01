'use strict';
const { convertType } = require('../lib/type-converter');
const { translateFlow } = require('../lib/flow-translator');

const NANOFLOW_KINDS = new Set(['clientAction', 'screenAction']);

function mapMicroflow(item, structureIndex, parentIndex, dsaIndex, paramIndex) {
  const keyword = NANOFLOW_KINDS.has(item.logicKind) ? 'NANOFLOW' : 'MICROFLOW';

  // Qualify name with parent WebBlock/Screen for client/screen actions to avoid duplicates
  let logicName = item.name;
  if (NANOFLOW_KINDS.has(item.logicKind) && parentIndex) {
    const parentName = parentIndex[item.uniqueId];
    if (parentName) logicName = `${parentName}_${item.name}`;
  }

  const params = (item.inputParameters || [])
    .map(p => `  $${p.name}: ${convertType(p.type, p.length || '', structureIndex)}`)
    .join(',\n');
  const paramBlock = params ? `(\n${params}\n)` : '()';

  const outputs = item.outputParameters || [];
  const returnsClause = outputs.length > 0
    ? `\nRETURNS ${convertType(outputs[0].type, outputs[0].length || '', structureIndex)} AS $${outputs[0].name}`
    : '';

  const body = translateFlow(item, structureIndex, dsaIndex, paramIndex);
  const comment = item.logicKind === 'process' ? '  -- BPT process\n' : '';

  return [
    `CREATE ${keyword} ${item.module}.${logicName} ${paramBlock}${returnsClause}`,
    'BEGIN',
    comment + body.trimEnd(),
    'END;\n',
  ].join('\n');
}

module.exports = { mapMicroflow };
