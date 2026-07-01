'use strict';

function mapIntegrations(serviceApis, extEntities) {
  const integrations = [];

  for (const api of serviceApis) {
    integrations.push({
      name:        api.name,
      direction:   'inbound',
      kind:        'PublishedRESTOperation',
      description: api.description || '',
      isPublic:    api.isPublic || false,
      parameters: {
        in:  (api.inputParameters  || []).map(p => ({ name: p.name, type: p.type })),
        out: (api.outputParameters || []).map(p => ({ name: p.name, type: p.type })),
      },
      gaps: api._gaps || [],
    });
  }

  for (const ext of extEntities) {
    integrations.push({
      name:        ext.name,
      direction:   'outbound',
      kind:        'ExternalEntity',
      description: ext.description || '',
      physicalTable: ext.physicalTableName || '',
      columns:     (ext.columns || []).map(c => ({ name: c.name, type: c.type })),
      gaps:        ext._gaps || [],
    });
  }

  return integrations;
}

module.exports = { mapIntegrations };
