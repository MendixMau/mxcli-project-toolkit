'use strict';

function mapTimer(item) {
  return [
    `-- SCHEDULED EVENT: ${item.module}.${item.name}`,
    `-- Schedule: ${item.schedule || 'unset'}`,
    `-- ActionRef: ${item.actionRef || 'unset'}`,
    item.description ? `-- Description: ${item.description}` : null,
    '-- TODO: CREATE SCHEDULED EVENT not yet supported in MDL; create manually in Mendix Studio',
    '',
  ].filter(l => l !== null).join('\n') + '\n';
}

module.exports = { mapTimer };
