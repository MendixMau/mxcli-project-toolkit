'use strict';
const { convertType } = require('../lib/type-converter');

const HTML_ENTITIES = { '&quot;': '"', '&amp;': '&', '&lt;': '<', '&gt;': '>', '&#xA;': '\n', '&#x9;': '\t' };
function decodeHtml(s) {
  return s.replace(/&quot;|&amp;|&lt;|&gt;|&#xA;|&#x9;/g, m => HTML_ENTITIES[m] || m);
}

function formatDefault(osType, rawDefault) {
  if (!rawDefault || rawDefault === '') return null;
  const decoded = decodeHtml(rawDefault);
  if (osType === 'Boolean') return decoded === 'True' ? 'true' : 'false';
  if (decoded === '""' || decoded === "''") return '""';
  if (decoded.startsWith('"') && decoded.endsWith('"')) return decoded;
  return decoded;
}

function mapStructure(item, structureIndex) {
  const attrLines = (item.attributes || []).map(a => {
    if (a.type === 'Binary Data') {
      // NPEs cannot extend System.FileDocument — annotate for manual migration
      return `  -- TODO: ${a.name} (Binary Data) → replace with System.FileDocument entity reference via association`;
    }
    const mxType = convertType(a.type, a.length || '', structureIndex);
    const dflt   = formatDefault(a.type, a.defaultValue);
    const dfltClause = dflt !== null ? ` DEFAULT ${dflt}` : '';
    return `  ${a.name}: ${mxType}${dfltClause}`;
  });

  // Filter out Binary TODO lines when computing comma-separated list
  const realAttrs = attrLines.filter(l => !l.trimStart().startsWith('--'));
  const commentAttrs = attrLines.filter(l => l.trimStart().startsWith('--'));
  const attrBlock = [
    ...commentAttrs,
    ...realAttrs.map((l, i) => i < realAttrs.length - 1 ? l + ',' : l),
  ].join('\n');

  const attrs = attrBlock;

  const lines = [];
  if (item.description) {
    const desc = decodeHtml(item.description).replace(/[\r\n]+/g, ' ').trim();
    if (desc) lines.push(`-- ${desc}`);
  }
  lines.push(`CREATE NON-PERSISTENT ENTITY ${item.module}.${item.name} (`);
  if (attrs) lines.push(attrs);
  lines.push(');\n');
  return lines.join('\n');
}

module.exports = { mapStructure };
