'use strict';

const WIDGET_KEYWORDS = {
  'LayoutContainer': 'CONTAINER',
  'ConditionalContainer': 'CONTAINER',
  'ListView': 'LISTVIEW',
  'DynamicText': 'DYNAMICTEXT',
  'TextBox': 'TEXTBOX',
  'TextArea': 'TEXTAREA',
  'LinkButton': 'LINKBUTTON',
  'ActionButton': 'ACTIONBUTTON',
  'BuildingBlock': 'SNIPPETCALL',
  'DataView': 'DATAVIEW',
  'GroupBox': 'GROUPBOX',
  'Image': 'IMAGE',
};

function translateWidgets(nodes, level) {
  const lines = [];
  for (const node of nodes) {
    renderWidget(node, level, lines);
  }
  return lines.join('\n') + (lines.length > 0 ? '\n' : '');
}

function ind(level) { return '  '.repeat(level); }

function renderWidget(node, level, lines) {
  const { mxType, name, children = [] } = node;

  if (mxType === 'SlotContent') {
    for (const child of children) renderWidget(child, level, lines);
    return;
  }

  const keyword = WIDGET_KEYWORDS[mxType];
  if (!keyword) {
    lines.push(`${ind(level)}-- TODO: widget type ${mxType} not translated`);
    for (const child of children) renderWidget(child, level + 1, lines);
    return;
  }

  const widgetName = name || `_${mxType.toLowerCase()}`;
  const props = buildProps(node);
  const propsStr = props.length > 0 ? ` (${props.join(', ')})` : '';

  if (children.length > 0) {
    lines.push(`${ind(level)}${keyword} ${widgetName}${propsStr} {`);
    for (const child of children) renderWidget(child, level + 1, lines);
    lines.push(`${ind(level)}}`);
  } else {
    lines.push(`${ind(level)}${keyword} ${widgetName}${propsStr}`);
  }
}

function buildProps(node) {
  const props = [];
  if (node.caption) props.push(`Caption: '${node.caption}'`);
  if (node.expression) props.push(`Content: '${node.expression}'`);
  if (node.dataSource) props.push(`DataSource: ${node.dataSource}`);
  if (node.destinationName) props.push(`NavigateTo: ${node.destinationName}`);
  if (node.visibilityCondition) props.push(`Visible: ${node.visibilityCondition}`);
  if (node.variable) props.push(`Attribute: ${node.variable}`);
  if (node.sourceWebBlockName) props.push(`Snippet: ${node.sourceWebBlockName}`);
  return props;
}

module.exports = { translateWidgets };
