'use strict';

function mapExtEntity(item) {
  const mod = item.inferredModule || 'SAPIntegration';
  const entityFqn = `${mod}.${item.name}`;
  const attrs = item.attributes || [];

  const lines = [
    `-- SAP Extension Entity (non-persistent, sourced via Database Connector)`,
    `-- Physical table: ${item.physicalTable || '(unknown — check SAP schema)'}`,
    `CREATE ENTITY ${entityFqn} (`,
  ];
  attrs.forEach((a, i) => {
    const comma = i < attrs.length - 1 ? ',' : '';
    lines.push(`  ${a.physicalName}: String(unlimited)${comma}`);
  });
  if (attrs.length === 0) lines.push('  -- no attributes extracted');
  lines.push(')\nPERSISTABLE: false;\n');

  // SELECT SQL — only if physical table is known
  const table = item.physicalTable;
  const selectCols = attrs.map(a => a.physicalName).join(', ');

  lines.push(`CREATE MICROFLOW ${mod}.${item.name}_GetAll (`);
  lines.push(`  $ConnectionString: String(unlimited)`);
  lines.push(`)`);
  lines.push(`RETURNS List of ${entityFqn}`);
  lines.push(`BEGIN`);
  if (table) {
    lines.push(`  CALL MICROFLOW DatabaseConnector.ExecuteQueryResult (`);
    lines.push(`    SQL: 'SELECT ${selectCols} FROM ${table}',`);
    lines.push(`    ConnectionString: $ConnectionString,`);
    lines.push(`    ResultEntity: ${entityFqn}`);
    lines.push(`  );`);
  } else {
    lines.push(`  -- TODO: physicalTable not resolved; fill in SAP table name and column list`);
    lines.push(`  CALL MICROFLOW DatabaseConnector.ExecuteQueryResult (`);
    lines.push(`    SQL: 'SELECT ${selectCols || '*'} FROM <SAP_TABLE>',`);
    lines.push(`    ConnectionString: $ConnectionString,`);
    lines.push(`    ResultEntity: ${entityFqn}`);
    lines.push(`  );`);
  }
  lines.push(`END;\n`);

  return lines.join('\n') + '\n';
}

module.exports = { mapExtEntity };
