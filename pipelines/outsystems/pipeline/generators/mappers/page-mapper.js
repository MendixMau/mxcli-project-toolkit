'use strict';
const { convertType } = require('../lib/type-converter');
const { translateWidgets } = require('../lib/widget-translator');

function mapPage(item, layout = 'Atlas_Core.Atlas_Default') {
  const params = (item.inputParameters || [])
    .map(p => `    $${p.name}: ${convertType(p.type, p.length || '')}`)
    .join(',\n');
  const paramsBlock = params ? `  Params: {\n${params}\n  }` : '';

  const title = (item.title || item.name).replace(/^"|"$/g, '').replace(/&quot;/g, '');

  const attrs = [
    `  Title: '${title}'`,
    `  Layout: ${layout}`,
    paramsBlock,
  ].filter(Boolean).join(',\n');

  const body = translateWidgets(item.widgetTree || [], 1);

  return [
    `CREATE PAGE ${item.module}.${item.name} (`,
    attrs,
    ') {',
    body.trimEnd() || '  -- empty page',
    '};\n',
  ].join('\n');
}

module.exports = { mapPage };
