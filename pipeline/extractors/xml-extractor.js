'use strict';

const { XMLParser } = require('fast-xml-parser');
const path = require('path');
const { BaseExtractor, ExtractionResult } = require('../lib/interfaces');

const ARRAY_TAGS = new Set([
  'Entity', 'Attribute', 'Structure', 'RecordType', 'Reference',
  'WebScreen', 'WebFlow', 'WebBlock',
  'Action', 'ScreenAction', 'EntityActions',
  'StaticRecord', 'StaticRecordAttributeValue',
  'InputParameter', 'OutputParameter', 'ImplicitParameter',
  'LocalVariable',
  'Role', 'SQL', 'Timer', 'Process', 'Theme',
  'SiteProperty', 'SessionVariable', 'Resource', 'Image', 'Folder',
  'ExecuteAction', 'Aggregate',
  'ServiceAction', 'UserException',
  'Index', 'IndexAttribute',
  'ClientAction', 'Permission',
  'Filter', 'Join',
  'DataAction', 'DataScreenAction',
]);

const PARSER_OPTIONS = {
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
  isArray: (name) => ARRAY_TAGS.has(name),
  numberParseOptions: { leadingZeros: false, hex: false, eNotation: false },
  processEntities: false,
};

const KEY = (n) => n['@_Key'] || n['@_uniqueId'];
const NAME = (n) => n['@_Name'] || n['@_name'];
const LABEL = (n) => n['@_Label'] || n['@_label'];
const DESC = (n) => DECODE(n['@_Description'] || n['@_description'] || '');
const DATATYPE = (n) => n['@_DataType'] || n['@_Type'] || n['@_dataType'] || n['@_type'] || '';
const YESNO = (v) => v === 'Yes' || v === 'true' || v === true;
// ── Widget tree constants ─────────────────────────────────────────────────
const WIDGET_SKIP_KEYS = new Set([
  'OnClick','OnChange','OnNotify','OnRender','OnInitialize','OnReady',
  'OnDestroy','OnAfterFetch','Arguments','ExtendedProperties','StyleSheet',
  'Connectors','Connector','ConnectorTrue','ConnectorFalse',
  'HeaderRow',  // handled explicitly in TableRecords extraction
]);

const WIDGET_MX_MAP = {
  TableRecords:'ListView',  ListRecords:'ListView',   Table:'DataGrid',
  EditRecord:'DataView',    Form:'DataView',
  Expression:'DynamicText', Text:'StaticText',
  Input:'TextBox',          TextArea:'TextArea',
  Button:'ActionButton',    Link:'LinkButton',
  Container:'LayoutContainer', WebBlockWidget:'BuildingBlock',
  IfWidget:'ConditionalContainer', Placeholder:'LayoutSlot',
  PlaceholderArgument:'SlotContent',
  Image:'ImageWidget',      Checkbox:'CheckBox',
  RadioButton:'RadioButton',Dropdown:'DropDown',
  DateTimePicker:'DatePicker', Upload:'FileManager',
  RichText:'RichText',      Label:'Label',
  Icon:'Icon',              Badge:'Badge',
};

const DECODE = (s) => (s || '').toString()
  .replace(/&amp;/g, '&')
  .replace(/&lt;/g, '<')
  .replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"')
  .replace(/&apos;/g, "'")
  .replace(/&#xA;/g, '\n')
  .replace(/&#x9;/g, '\t')
  .replace(/&#(\d+);/g, (_, c) => String.fromCharCode(Number(c)));

class XmlExtractor extends BaseExtractor {
  get supportedExtensions() { return ['.xml']; }

  async run(filePaths, _options = {}) {
    const start = Date.now();
    const seen   = new Set();
    const items  = [];
    const errors = [];

    for (const filePath of filePaths) {
      try {
        const raw  = this.fileReader.readTextSync(filePath);
        const data = new XMLParser(PARSER_OPTIONS).parse(raw);
        const ctx  = this._buildContext(data, filePath);
        this._extract(data, ctx, seen, items);
      } catch (err) {
        this.logger.error(`[xml-extractor] Failed: ${filePath} — ${err.message}`);
        errors.push({ file: filePath, error: err.message });
      }
    }

    return new ExtractionResult({
      source: 'xml',
      items,
      errors,
      meta: { fileCount: filePaths.length, itemCount: items.length, duration: Date.now() - start }
    });
  }

  _buildContext(data, sourceFile) {
    const espace = data && data.ESpace;
    const moduleName = (espace && (espace['@_Name'] || espace['@_name']))
      || path.basename(sourceFile, path.extname(sourceFile));
    const attrLabels = {};
    this._collectAttributeLabels(data, attrLabels);
    // Build per-module maps for widget tree resolution
    const placeholderNames = {};   // Placeholder:key → slot name
    const webBlockNames    = {};   // WebBlock:key    → block name
    this._collectWebBlockMaps(data, placeholderNames, webBlockNames);
    return { sourceFile, moduleName, attrLabels, placeholderNames, webBlockNames };
  }

  _collectWebBlockMaps(obj, phMap, wbMap) {
    if (!obj || typeof obj !== 'object') return;
    if (Array.isArray(obj)) { for (const v of obj) this._collectWebBlockMaps(v, phMap, wbMap); return; }
    for (const [k, v] of Object.entries(obj)) {
      if (k === 'WebBlock' && v && typeof v === 'object') {
        const blocks = Array.isArray(v) ? v : [v];
        for (const wb of blocks) {
          const key = KEY(wb); const name = NAME(wb);
          if (key) wbMap[key] = name;
          this._collectWebBlockMaps(wb, phMap, wbMap);
        }
        continue;
      }
      if (k === 'Placeholder' && v && typeof v === 'object') {
        const phs = Array.isArray(v) ? v : [v];
        for (const ph of phs) {
          const key = KEY(ph); const name = NAME(ph) || ph['@_Placeholder'] || '';
          if (key) phMap[key] = name;
        }
        continue;
      }
      if (v && typeof v === 'object') this._collectWebBlockMaps(v, phMap, wbMap);
    }
  }

  _collectAttributeLabels(obj, out) {
    if (!obj || typeof obj !== 'object') return;
    if (Array.isArray(obj)) {
      for (const item of obj) this._collectAttributeLabels(item, out);
      return;
    }
    for (const [key, val] of Object.entries(obj)) {
      if ((key === 'Attribute' || key === 'AttributeReference') && Array.isArray(val)) {
        for (const a of val) {
          const k = KEY(a);
          const label = LABEL(a);
          if (k && label) out[k] = label;
        }
      }
      if (val && typeof val === 'object') this._collectAttributeLabels(val, out);
    }
  }

  _extract(obj, ctx, seen, items) {
    if (!obj || typeof obj !== 'object') return;

    const handlers = {
      Entity:           (n) => this._extractEntity(n, ctx),
      Structure:        (n) => this._extractStructure(n, ctx),
      RecordType:       (n) => this._extractStructure(n, ctx),
      Reference:        (n) => this._extractReference(n, ctx),
      WebScreen:        (n) => this._extractWebScreen(n, ctx),
      WebFlow:          (n) => this._extractWebFlow(n, ctx),
      WebBlock:         (n) => this._extractWebBlock(n, ctx),
      Action:           (n) => this._extractAction(n, 'action', ctx),
      ScreenAction:     (n) => this._extractAction(n, 'screenAction', ctx),
      Process:          (n) => this._extractAction(n, 'process', ctx),
      Role:             (n) => this._extractRole(n, ctx),
      SQL:              (n) => this._extractSql(n, ctx),
      Timer:            (n) => this._extractTimer(n, ctx),
      SiteProperty:     (n) => this._extractSiteProperty(n, ctx),
      SessionVariable:  (n) => this._extractSessionVariable(n, ctx),
      Theme:            (n) => this._extractTheme(n, ctx),
      ServiceAction:    (n) => this._extractServiceAction(n, ctx),
      UserException:    (n) => this._extractException(n, ctx),
      ClientAction:       (n) => this._extractAction(n, 'clientAction', ctx),
      DataAction:         (n) => this._extractAction(n, 'dataAction', ctx),
      DataScreenAction:   (n) => this._extractDataScreenAction(n, ctx),
    };

    for (const [key, fn] of Object.entries(handlers)) {
      if (Array.isArray(obj[key])) {
        for (const node of obj[key]) {
          const item = fn(node);
          if (!item) continue;
          if (item.uniqueId && seen.has(item.uniqueId)) continue;
          if (item.uniqueId) seen.add(item.uniqueId);
          items.push(item);
        }
      }
    }

    for (const val of Object.values(obj)) {
      if (val && typeof val === 'object') this._extract(val, ctx, seen, items);
    }
  }

  _resolveLabel(node, ctx) {
    const raw = LABEL(node);
    if (!raw) return '';
    if (typeof raw === 'string' && raw.startsWith('Attribute:') && ctx.attrLabels[raw]) {
      return ctx.attrLabels[raw];
    }
    return raw;
  }

  _extractEntity(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    const isStatic = YESNO(node['@_IsStaticEntity']);
    const type     = isStatic ? 'staticEntity' : 'entity';
    const resolvedLabel = this._resolveLabel(node, ctx);
    const description   = DESC(node);
    const item = {
      type,
      linkId:        `xml:${type}:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      label:         resolvedLabel || description || name,
      description,
      module:        ctx.moduleName,
      isStatic,
      isPublic:      YESNO(node['@_Public']) || YESNO(node['@_isPublic']),
      isMultitenant: YESNO(node['@_IsMultitenant']),
      deleteRule:    node['@_DeleteRule'] || node['@_deleteRule'] || '',
      attributes:    ((node.Attributes && node.Attributes.Attribute) || node.Attribute || []).map(a => this._extractAttribute(a)),
      exposeReadOnly: YESNO(node['@_ExposeReadOnly']),
      indexes:       ((node.Indexes && node.Indexes.Index) || []).map(idx => ({
        name:       NAME(idx),
        key:        KEY(idx),
        isUnique:   YESNO(idx['@_IsUnique']),
        attributes: ((idx.Attributes && idx.Attributes.IndexAttribute) || idx.IndexAttribute || [])
          .map(ia => ({ attributeKey: ia['@_Attribute'] || '' })),
      })),
      _source: ctx.sourceFile,
    };
    if (isStatic) {
      item.records = ((node.StaticRecords && node.StaticRecords.StaticRecord) || node.StaticRecord || []).map(r => ({
        uniqueId: KEY(r),
        name: NAME(r),
        label: LABEL(r) || NAME(r),
        order: r['@_Order'] || '',
        values: ((r.StaticRecordAttributeValues && r.StaticRecordAttributeValues.StaticRecordAttributeValue) || r.StaticRecordAttributeValue || []).map(v => ({
          attributeKey: v['@_AttributeKey'] || '',
          value: v['@_Value'] || (typeof v === 'object' && v['#text']) || '',
        })),
      }));
    }
    return item;
  }

  _extractAttribute(a) {
    const dataType = DATATYPE(a);
    const isFk     = dataType.endsWith('Identifier') && dataType !== 'Tenant Identifier';
    return {
      uniqueId:         KEY(a),
      name:             NAME(a),
      label:            LABEL(a) || NAME(a),
      type:             dataType,
      isMandatory:      YESNO(a['@_IsMandatory']),
      isAutoNumber:     YESNO(a['@_IsAutoNumber']),
      defaultValue:     a['@_DefaultValue'] || a['@_defaultValue'] || '',
      length:           a['@_Length'] || '',
      decimals:         a['@_Decimals'] || '',
      isForeignKey:     isFk,
      referencedEntity: isFk ? dataType.replace(/\s+Identifier$/, '').trim() : '',
      deleteRule:       a['@_DeleteRule'] || '',
    };
  }

  _extractStructure(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    return {
      type:       'structure',
      linkId:     `xml:structure:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      label:      LABEL(node) || name,
      description: DESC(node),
      module:     ctx.moduleName,
      attributes: ((node.Attributes && node.Attributes.Attribute) || node.Attribute || []).map(a => this._extractAttribute(a)),
      _source:    ctx.sourceFile,
    };
  }

  _extractReference(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    return {
      type:         'reference',
      linkId:       `xml:reference:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      description:  DESC(node),
      module:       ctx.moduleName,
      referenceKey: node['@_ReferenceKey'] || '',
      _source:      ctx.sourceFile,
    };
  }

  _extractWebScreen(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    return {
      type:       'screen',
      screenKind: 'webScreen',
      linkId:     `xml:screen:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      label:      LABEL(node) || name,
      description: DESC(node),
      module:     ctx.moduleName,
      isPublic:   YESNO(node['@_Public']),
      title:      node['@_Title'] || '',
      inputParameters: ((node.InputParameters && node.InputParameters.InputParameter) || [])
        .map(p => this._extractParameter(p, 'In')),
      localVariables: ((node.LocalVariables && node.LocalVariables.LocalVariable) || [])
        .map(v => ({ name: NAME(v), type: DATATYPE(v), defaultValue: v['@_DefaultValue'] || '' })),
      onInitializeRef: (node.OnInitialize && node.OnInitialize['@_Key']) || '',
      clientActions: ((node.ClientActions && node.ClientActions.ClientAction) || [])
        .map(a => ({ name: NAME(a), key: KEY(a) })),
      permissions: ((node.Permissions && node.Permissions.Permission) || [])
        .map(p => ({ roleKey: p['@_Role'] || '', key: KEY(p) })),
      widgetSummary: this._extractWidgetSummary(node.Widgets),
      widgetTree:    this._extractWidgetTree(node.Widgets, ctx),
      _source:    ctx.sourceFile,
    };
  }

  _extractWebFlow(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    const nodes    = node.Nodes || {};
    return {
      type:       'webFlow',
      linkId:     `xml:webFlow:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      label:      LABEL(node) || name,
      description: DESC(node),
      module:     ctx.moduleName,
      screens:    ((Array.isArray(nodes.WebScreen) ? nodes.WebScreen : (nodes.WebScreen ? [nodes.WebScreen] : [])))
        .map(s => ({ key: KEY(s), name: NAME(s) })),
      webBlocks:  ((Array.isArray(nodes.WebBlock) ? nodes.WebBlock : (nodes.WebBlock ? [nodes.WebBlock] : [])))
        .map(b => ({ key: KEY(b), name: NAME(b) })),
      _source:    ctx.sourceFile,
    };
  }

  _extractWebBlock(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    return {
      type:       'webBlock',
      linkId:     `xml:webBlock:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      label:      LABEL(node) || name,
      description: DESC(node),
      module:     ctx.moduleName,
      inputParameters: ((node.InputParameters && node.InputParameters.InputParameter) || [])
        .map(p => this._extractParameter(p, 'In')),
      _source:    ctx.sourceFile,
    };
  }

  _extractDataScreenAction(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    const outputParams = ((node.OutputParameters && node.OutputParameters.OutputParameter) || [])
      .map(p => this._extractParameter(p, 'Out'));
    return {
      type:       'dataScreenAction',
      linkId:     `xml:dataScreenAction:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      module:     ctx.moduleName,
      fetch:      node['@_Fetch'] || '',
      outputParameters: outputParams,
      _source:    ctx.sourceFile,
    };
  }

  _extractAction(node, kind, ctx) {
    const uniqueId  = KEY(node);
    const name      = NAME(node);
    const flowGraph = this._extractFlowGraph(node);
    const calls     = flowGraph.nodes
      .filter(n => n.nodeType === 'ExecuteAction')
      .map(n => ({ uniqueId: n.nodeId, name: n.name || '', target: n.actionRef || '' }));
    const aggregates = flowGraph.nodes
      .filter(n => n.nodeType === 'Aggregate')
      .map(n => ({ uniqueId: n.nodeId, name: n.name || '', maxRecords: n.maxRecords || '',
                   entitySource: n.entitySource || '', joins: n.joins || [], filters: n.filters || [] }));
    const item = {
      type:        'logic',
      logicKind:   kind,
      linkId:      `xml:logic:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      label:       LABEL(node) || name,
      description: DESC(node),
      module:      ctx.moduleName,
      isPublic:    YESNO(node['@_Public']),
      inputParameters:    ((node.InputParameters  && node.InputParameters.InputParameter)   || node.InputParameter   || []).map(p => this._extractParameter(p, 'In')),
      outputParameters:   ((node.OutputParameters && node.OutputParameters.OutputParameter) || node.OutputParameter  || []).map(p => this._extractParameter(p, 'Out')),
      implicitParameters: ((node.ImplicitParameters && node.ImplicitParameters.ImplicitParameter) || node.ImplicitParameter || []).map(p => this._extractParameter(p, 'Implicit')),
      localVariables: ((node.LocalVariables && node.LocalVariables.LocalVariable) || [])
        .map(v => ({ name: NAME(v), type: DATATYPE(v), defaultValue: v['@_DefaultValue'] || '' })),
      calls,
      aggregates,
      flowGraph,
      _source:     ctx.sourceFile,
    };
    if (kind === 'process') {
      item.processGraph = this._extractProcessGraph(node);
    }
    return item;
  }

  _extractFlowGraph(actionNode) {
    const nodesObj = actionNode.Nodes || {};
    const nodes    = [];

    const NODE_HANDLERS = {
      Start:             (n) => ({ nodeType: 'Start' }),
      End:               (n) => ({ nodeType: 'End' }),
      Comment:           (n) => ({ nodeType: 'Comment', label: n['@_Label'] || '' }),
      If:                (n) => ({ nodeType: 'If', condition: DECODE(n['@_Condition']) }),
      Assign:            (n) => ({ nodeType: 'Assign', assignments: this._extractAssignments(n) }),
      ForEach:           (n) => ({ nodeType: 'ForEach', recordList: n['@_RecordList'] || '' }),
      ExecuteAction:     (n) => ({ nodeType: 'ExecuteAction', name: NAME(n) || '', actionRef: n['@_Action'] || n['@_action'] || '', args: this._extractArgs(n) }),
      Aggregate:         (n) => ({ nodeType: 'Aggregate', name: NAME(n) || '', maxRecords: n['@_MaxRecords'] || '', ...this._extractAggregateDetail(n) }),
      SQL:               (n) => ({ nodeType: 'SQL', name: NAME(n) || '', sqlText: DECODE(n['@_SQLStatement']) }),
      ExcelToRecordList: (n) => ({ nodeType: 'ExcelToRecordList', name: NAME(n) || '' }),
      CreateEntity:      (n) => ({ nodeType: 'CreateEntity', entity: n['@_Entity'] || '' }),
      Update:            (n) => ({ nodeType: 'Update', entity: n['@_Entity'] || '' }),
      DeleteEntity:      (n) => ({ nodeType: 'DeleteEntity' }),
      Delete:            (n) => ({ nodeType: 'Delete' }),
      Commit:            (n) => ({ nodeType: 'Commit' }),
      CommitTransaction: (n) => ({ nodeType: 'CommitTransaction' }),
      Rollback:          (n) => ({ nodeType: 'Rollback' }),
      ExceptionHandler:  (n) => ({ nodeType: 'ExceptionHandler', exceptionType: n['@_ExceptionType'] || '' }),
      RaiseException:    (n) => ({ nodeType: 'RaiseException', exceptionType: n['@_ExceptionType'] || '' }),
      Message:           (n) => ({ nodeType: 'Message', message: DECODE(n['@_Message']) }),
      Destination:       (n) => ({ nodeType: 'Destination', screen: n['@_Screen'] || '' }),
      SendEmail:         (n) => ({ nodeType: 'SendEmail', name: NAME(n) || '' }),
      WebServiceCall:    (n) => ({ nodeType: 'WebServiceCall', name: NAME(n) || '' }),
      ConsumedAPIMethod: (n) => ({ nodeType: 'ConsumedAPIMethod', name: NAME(n) || '' }),
      JSONDeserialize:   (n) => ({ nodeType: 'JSONDeserialize', name: NAME(n) || '' }),
      JSONSerialize:     (n) => ({ nodeType: 'JSONSerialize', name: NAME(n) || '' }),
    };

    for (const [nodeType, handler] of Object.entries(NODE_HANDLERS)) {
      const raw = nodesObj[nodeType];
      if (!raw) continue;
      const list = Array.isArray(raw) ? raw : [raw];
      for (const n of list) {
        const nodeId = KEY(n);
        if (!nodeId) continue;
        nodes.push({ nodeId, ...handler(n), edges: this._extractEdges(n) });
      }
    }

    return { nodes };
  }

  _extractEdges(node) {
    const conn = node.Connectors;
    if (!conn) return [];
    const edges = [];
    const addEdge = (c, label) => { if (c && c['@_Target']) edges.push({ target: c['@_Target'], label }); };
    if (conn.Connector) {
      const cs = Array.isArray(conn.Connector) ? conn.Connector : [conn.Connector];
      for (const c of cs) addEdge(c, '');
    }
    if (conn.ConnectorTrue)   addEdge(conn.ConnectorTrue,   'true');
    if (conn.ConnectorFalse)  addEdge(conn.ConnectorFalse,  'false');
    if (conn.ConnectorCycle)  addEdge(conn.ConnectorCycle,  'cycle');
    return edges;
  }

  _extractArgs(node) {
    const raw = node.Arguments && node.Arguments.Argument;
    if (!raw) return [];
    const list = Array.isArray(raw) ? raw : [raw];
    return list.map(a => ({
      paramKey:     a['@_Parameter']    || '',
      value:        DECODE(a['@_Value']) || '',
      requiredType: a['@_RequiredType'] || '',
    }));
  }

  _extractAssignments(node) {
    const raw = node.Assignments && node.Assignments.Assignment;
    if (!raw) return [];
    const list = Array.isArray(raw) ? raw : [raw];
    return list.map(a => ({
      key:        KEY(a) || '',
      variable:   DECODE(a['@_Variable'])   || '',
      expression: DECODE(a['@_Value'])      || '',
    }));
  }

  _extractAggregateDetail(node) {
    const table = node.Table && node.Table.DataTable;
    if (!table) return { entitySource: '', joins: [], filters: [] };
    const ops       = table.TableOperations || {};
    const addSource = ops.AddSource;
    const entitySource = addSource ? (addSource['@_Source'] || '') : '';
    const joinRaw   = ops.Join;
    const joins     = joinRaw
      ? (Array.isArray(joinRaw) ? joinRaw : [joinRaw]).map(j => ({ source: j['@_Source'] || '', joinType: j['@_JoinType'] || '' }))
      : [];
    const filterRaw = table.Filters && table.Filters.Filter;
    const filters   = filterRaw
      ? (Array.isArray(filterRaw) ? filterRaw : [filterRaw]).map(f => DECODE(f['@_Condition']))
      : [];
    return { entitySource, joins, filters };
  }

  _extractParameter(p, direction) {
    return {
      uniqueId:    KEY(p),
      name:        NAME(p),
      type:        DATATYPE(p),
      isMandatory: YESNO(p['@_IsMandatory']),
      direction,
    };
  }

  _extractRole(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    return {
      type:        'role',
      linkId:      `xml:role:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      description: DESC(node),
      module:      ctx.moduleName,
      _source:     ctx.sourceFile,
    };
  }

  _extractSql(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    const sqlText  = DECODE(node['@_SQLStatement']) || '';
    return {
      type:        'sql',
      linkId:      `xml:sql:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      description: DESC(node),
      module:      ctx.moduleName,
      sqlText,
      inputParameters:  ((node.InputParameters && node.InputParameters.InputParameter) || node.InputParameter  || []).map(p => this._extractParameter(p, 'In')),
      outputParameters: ((node.OutputParameters && node.OutputParameters.OutputParameter) || node.OutputParameter || []).map(p => this._extractParameter(p, 'Out')),
      _source:     ctx.sourceFile,
    };
  }

  _extractTimer(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    return {
      type:        'timer',
      linkId:      `xml:timer:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      description: DESC(node),
      module:      ctx.moduleName,
      schedule:    node['@_Schedule'] || '',
      actionRef:   node['@_Action']   || '',
      timeout:     node['@_Timeout']  || '',
      priority:    node['@_Priority'] || '',
      _source:     ctx.sourceFile,
    };
  }

  _extractSiteProperty(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    return {
      type:         'siteProperty',
      linkId:       `xml:siteProperty:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      dataType:     DATATYPE(node),
      defaultValue: node['@_DefaultValue'] || '',
      description:  DESC(node),
      module:       ctx.moduleName,
      _source:      ctx.sourceFile,
    };
  }

  _extractSessionVariable(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    return {
      type:         'sessionVariable',
      linkId:       `xml:sessionVariable:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      dataType:     DATATYPE(node),
      defaultValue: node['@_DefaultValue'] || '',
      module:       ctx.moduleName,
      _source:      ctx.sourceFile,
    };
  }

  _extractTheme(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    return {
      type:        'theme',
      linkId:      `xml:theme:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      description: DESC(node),
      module:      ctx.moduleName,
      _source:     ctx.sourceFile,
    };
  }

  _extractProcessGraph(processNode) {
    const nodesObj = processNode.Nodes || {};
    const nodes    = [];

    const ACTIVITY_HANDLERS = {
      Start:             (n) => ({ activityType: 'Start' }),
      End:               (n) => ({ activityType: 'End' }),
      AutomaticActivity: (n) => ({
        activityType: 'AutomaticActivity',
        name:         n['@_Name'] || n['@_Label'] || '',
        actionRef:    this._extractActivityActionRef(n),
      }),
      HumanActivity:     (n) => ({
        activityType: 'HumanActivity',
        name:         n['@_Name'] || n['@_Label'] || '',
        screen:       n['@_Screen'] || '',
        actionRef:    this._extractActivityActionRef(n),
      }),
      ConditionalStart:  (n) => ({
        activityType: 'ConditionalStart',
        name:         n['@_Name'] || n['@_Label'] || '',
        condition:    DECODE(n['@_Condition']),
      }),
      Wait:              (n) => ({
        activityType: 'Wait',
        name:         n['@_Name'] || n['@_Label'] || '',
      }),
    };

    for (const [actType, handler] of Object.entries(ACTIVITY_HANDLERS)) {
      const raw = nodesObj[actType];
      if (!raw) continue;
      const list = Array.isArray(raw) ? raw : [raw];
      for (const n of list) {
        const nodeId = KEY(n);
        if (!nodeId) continue;
        nodes.push({ nodeId, ...handler(n), edges: this._extractEdges(n) });
      }
    }
    return { nodes };
  }

  _extractActivityActionRef(activityNode) {
    const actionFlow = activityNode.ActionFlow;
    if (!actionFlow) return '';
    const actAct = actionFlow.ActivityAction;
    if (!actAct) return '';
    const execNodes = actAct.Nodes;
    if (!execNodes) return '';
    const exec = execNodes.ExecuteAction;
    const firstExec = Array.isArray(exec) ? exec[0] : exec;
    return firstExec ? (firstExec['@_Action'] || '') : '';
  }

  // ── Widget Tree ──────────────────────────────────────────────────────────

  _extractWidgetTree(widgetsNode, ctx) {
    if (!widgetsNode || typeof widgetsNode !== 'object') return null;
    return this._walkWidgetContainer(widgetsNode, ctx, 0);
  }

  _walkWidgetContainer(container, ctx, depth) {
    if (depth > 12 || !container || typeof container !== 'object') return [];
    const children = [];
    const skipKeys = WIDGET_SKIP_KEYS;

    for (const [key, val] of Object.entries(container)) {
      if (key.startsWith('@_') || skipKeys.has(key)) continue;
      if (!val || typeof val !== 'object') continue;

      // PlaceholderArgument needs special handling (it IS a widget slot)
      if (key === 'PlaceholderArgument') {
        const items = Array.isArray(val) ? val : [val];
        for (const item of items) {
          const slotNode = this._buildSlotNode(item, ctx, depth);
          if (slotNode) children.push(slotNode);
        }
        continue;
      }

      // IfWidget Branches → IfBranch children
      if (key === 'Branches') {
        const branches = this._extractBranches(val, ctx, depth);
        children.push(...branches);
        continue;
      }

      // DataRow → Row → Cells → Cell (table row cells)
      if (key === 'DataRow') {
        const row = val.Row || val;
        const cellNode = this._extractTableRow(row, ctx, depth);
        if (cellNode) children.push(cellNode);
        continue;
      }

      // Skip structural containers (Cells, Row, HeaderRow) — recurse into them
      if (['Cells','Row','HeaderRow'].includes(key)) {
        const inner = this._walkWidgetContainer(val, ctx, depth + 1);
        children.push(...inner);
        continue;
      }

      // Regular widget types
      const items = Array.isArray(val) ? val : [val];
      for (const item of items) {
        if (!item || typeof item !== 'object') continue;
        const node = this._buildWidgetNode(key, item, ctx, depth);
        if (node) children.push(node);
      }
    }
    return children;
  }

  _buildWidgetNode(widgetType, item, ctx, depth) {
    const key      = KEY(item) || '';
    const name     = NAME(item) || '';
    const mxType   = WIDGET_MX_MAP[widgetType] || widgetType;
    const node     = { widgetType, mxType, key, name };

    // Style / visibility (common attrs)
    const style   = item['@_Style'] || '';
    const visible = DECODE(item['@_Visible'] || '');
    const enabled = DECODE(item['@_Enabled'] || '');
    if (style)   node.style   = style;
    if (visible && visible !== 'True') node.visibilityCondition = visible;
    if (enabled && enabled !== 'True') node.enabledCondition    = enabled;

    // ── Type-specific semantic extraction ──
    switch (widgetType) {

      case 'TableRecords':
      case 'ListRecords': {
        node.dataSource = DECODE(item['@_SourceRecordList'] || '');
        node.limit      = parseInt(item['@_LineCount'] || '0') || undefined;
        node.emptyMessage = DECODE(item['@_EmptyMessage'] || '');
        // Column headers from HeaderRow
        const hRow   = item.HeaderRow?.HeaderRow || item.HeaderRow;
        const hCells = hRow?.Cells?.Cell;
        const hcList = Array.isArray(hCells) ? hCells : (hCells ? [hCells] : []);
        node.columns = hcList
          .map(c => ({ header: DECODE(c.Widgets?.Text?.['@_Text'] || '') }))
          .filter(c => c.header);
        // Row navigation from DataRow > Cells > Link
        const dataRow  = item.DataRow?.Row;
        const navLinks = this._findNavLinks(dataRow, ctx);
        if (navLinks.length) node.rowNavigation = navLinks[0];
        break;
      }

      case 'Expression': {
        const rawExpr   = item['@_Expression'] || '';
        node.expression = DECODE(rawExpr);
        node.binding    = this._parseExpressionBinding(rawExpr);
        break;
      }

      case 'Input':
      case 'TextArea': {
        node.variable    = DECODE(item['@_Variable'] || '');
        node.inputType   = item['@_InputType'] || 'Text';
        node.mandatory   = item['@_Mandatory'] === 'True';
        node.maxLength   = parseInt(item['@_MaxLength'] || '0') || undefined;
        node.binding     = this._parseExpressionBinding(item['@_Variable'] || '');
        break;
      }

      case 'Link': {
        const onClick  = item.OnClick?.OnClick || {};
        node.destinationKey    = onClick['@_Destination'] || '';
        node.navigationMethod  = onClick['@_Method'] || '';
        node.navigationArgs    = this._extractOnClickArgs(onClick);
        node.visibilityCondition = DECODE(item['@_Visible'] || '') || undefined;
        break;
      }

      case 'Button': {
        const onClick  = item.OnClick?.OnClick || {};
        node.caption   = DECODE(item['@_Label'] || name);
        node.destinationKey  = onClick['@_Destination'] || '';
        node.navigationArgs  = this._extractOnClickArgs(onClick);
        node.style     = style || item['@_ButtonStyle'] || '';
        break;
      }

      case 'Text': {
        node.text = DECODE(item['@_Text'] || '');
        break;
      }

      case 'WebBlockWidget': {
        node.sourceWebBlockKey = item['@_SourceWebBlock'] || '';
        // Resolve name from ctx maps (same-module blocks)
        node.sourceWebBlockName = ctx.webBlockNames?.[node.sourceWebBlockKey] || '';
        break;
      }

      case 'IfWidget': {
        node.condition = DECODE(item['@_Condition'] || '');
        break;
      }

      case 'Image': {
        node.imageKey = item['@_Image'] || '';
        node.url      = DECODE(item['@_URL'] || '');
        break;
      }

      case 'Dropdown': {
        node.variable      = DECODE(item['@_Variable'] || '');
        node.sourceList    = DECODE(item['@_SourceList'] || '');
        node.sourceAttr    = item['@_SourceAttribute'] || '';
        node.binding       = this._parseExpressionBinding(item['@_Variable'] || '');
        break;
      }

      case 'Checkbox':
      case 'RadioButton': {
        node.variable   = DECODE(item['@_Variable'] || '');
        node.binding    = this._parseExpressionBinding(item['@_Variable'] || '');
        break;
      }

      case 'Container': {
        node.width  = item['@_Width'] || '';
        node.align  = item['@_Align'] || '';
        break;
      }
    }

    // ── Recurse into child Widgets ──
    const childContainers = [item.Widgets, item.PlaceholderArguments];
    const childNodes      = [];
    for (const cc of childContainers) {
      if (cc) childNodes.push(...this._walkWidgetContainer(cc, ctx, depth + 1));
    }
    // Branches for IfWidget
    if (item.Branches) childNodes.push(...this._extractBranches(item.Branches, ctx, depth + 1));
    // DataRow cells
    if (item.DataRow?.Row) {
      const cr = this._extractTableRow(item.DataRow.Row, ctx, depth + 1);
      if (cr) childNodes.push(cr);
    }

    if (childNodes.length) node.children = childNodes;
    return node;
  }

  _buildSlotNode(item, ctx, depth) {
    const phKey  = item['@_Placeholder'] || '';
    const slotName = ctx.placeholderNames?.[phKey] || '';
    const node = {
      widgetType: 'PlaceholderArgument',
      mxType:     'SlotContent',
      key:        KEY(item) || '',
      placeholderKey:  phKey,
      slotName,           // resolved from same-module; cross-module resolved in merger
    };
    const children = this._walkWidgetContainer(item.Widgets || item, ctx, depth + 1);
    if (children.length) node.children = children;
    return node;
  }

  _extractBranches(branchesObj, ctx, depth) {
    const branches = branchesObj?.IfBranch || branchesObj;
    const list     = Array.isArray(branches) ? branches : (branches ? [branches] : []);
    return list.map((b, i) => ({
      widgetType: 'IfBranch',
      mxType:     'ConditionalBranch',
      key:        KEY(b) || '',
      branchIndex: i,
      children:   this._walkWidgetContainer(b.Widgets || {}, ctx, depth + 1),
    }));
  }

  _extractTableRow(rowObj, ctx, depth) {
    if (!rowObj) return null;
    const cells = rowObj.Cells?.Cell;
    const cellList = Array.isArray(cells) ? cells : (cells ? [cells] : []);
    const cellNodes = cellList.map((cell, i) => {
      const cellChildren = this._walkWidgetContainer(cell.Widgets || {}, ctx, depth + 2);
      return { widgetType:'Cell', mxType:'TableCell', index: i, children: cellChildren };
    }).filter(c => c.children?.length);
    if (!cellNodes.length) return null;
    return { widgetType:'DataRow', mxType:'TableRow', cells: cellNodes };
  }

  _findNavLinks(rowObj, ctx) {
    if (!rowObj) return [];
    const links = [];
    const collectLinks = (obj) => {
      if (!obj || typeof obj !== 'object') return;
      if (Array.isArray(obj)) { for (const v of obj) collectLinks(v); return; }
      for (const [k, v] of Object.entries(obj)) {
        if (k === 'Link' && v) {
          const items = Array.isArray(v) ? v : [v];
          for (const l of items) {
            const oc = l.OnClick?.OnClick || {};
            const dest = oc['@_Destination'] || '';
            if (dest.startsWith('WebScreen:')) {
              links.push({
                destinationKey: dest,
                destinationName: '', // resolved in merger
                parameters: this._extractOnClickArgs(oc),
              });
            }
          }
        }
        if (v && typeof v === 'object') collectLinks(v);
      }
    };
    collectLinks(rowObj);
    return links;
  }

  _extractOnClickArgs(onClickObj) {
    const args = onClickObj?.Arguments?.Argument;
    if (!args) return [];
    const list = Array.isArray(args) ? args : [args];
    return list.map(a => ({
      parameterKey: a['@_Parameter'] || '',
      value:        DECODE(a['@_Value'] || ''),
      binding:      this._parseExpressionBinding(a['@_Value'] || ''),
    }));
  }

  _parseExpressionBinding(rawExpr) {
    if (!rawExpr) return null;
    const expr = DECODE(rawExpr);
    // X.List.Current.Entity.Attr
    const m1 = expr.match(/(\w+)\.List\.Current\.(\w+)\.(\w+)/);
    if (m1) return { type:'entity', source: m1[1], entity: m1[2], attribute: m1[3] };
    // Session.VarName
    const m2 = expr.match(/^Session\.(\w+)/);
    if (m2) return { type:'session', variable: m2[1] };
    // LocalVar.Attr or simple Entity.Attr
    const m3 = expr.match(/^(\w+)\.(\w+)$/);
    if (m3) return { type:'attribute', entity: m3[1], attribute: m3[2] };
    // Constant string
    if (expr.startsWith('"') && expr.endsWith('"')) return { type:'constant', value: expr.slice(1,-1) };
    // Otherwise: complex expression
    return { type:'expression', raw: expr.slice(0, 100) };
  }

  _extractWidgetSummary(widgetsNode) {
    if (!widgetsNode) return { widgetTypes: [], dataSources: [], hasListUI: false, hasFormUI: false };

    const widgetTypes = new Set();
    const dataSources = new Set();

    const LIST_TYPES = new Set(['ListRecords', 'TableRecords', 'List', 'Table']);
    const FORM_TYPES = new Set(['EditRecord', 'Form', 'TableEditor']);

    const walk = (obj) => {
      if (!obj || typeof obj !== 'object') return;
      if (Array.isArray(obj)) { for (const v of obj) walk(v); return; }
      for (const [k, v] of Object.entries(obj)) {
        if (k.startsWith('@_')) {
          if (k === '@_SourceRecordList' || k === '@_SourceRecord' || k === '@_Source') {
            const val = String(v);
            if (val && !val.startsWith('Entity:') && val.includes('.')) dataSources.add(val);
          }
        } else if (v && typeof v === 'object') {
          widgetTypes.add(k);
          walk(v);
        }
      }
    };
    walk(widgetsNode);

    const types = [...widgetTypes].filter(t => !t.startsWith('@_'));
    return {
      widgetTypes: types,
      dataSources: [...dataSources],
      hasListUI:  types.some(t => LIST_TYPES.has(t)),
      hasFormUI:  types.some(t => FORM_TYPES.has(t)),
    };
  }

  _extractServiceAction(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    return {
      type:        'serviceApi',
      linkId:      `xml:serviceApi:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      description: DESC(node),
      module:      ctx.moduleName,
      isPublic:    YESNO(node['@_Public']),
      inputParameters:  ((node.InputParameters && node.InputParameters.InputParameter) || [])
        .map(p => this._extractParameter(p, 'In')),
      outputParameters: ((node.OutputParameters && node.OutputParameters.OutputParameter) || [])
        .map(p => this._extractParameter(p, 'Out')),
      _source:     ctx.sourceFile,
    };
  }

  _extractException(node, ctx) {
    const uniqueId = KEY(node);
    const name     = NAME(node);
    return {
      type:    'exception',
      linkId:  `xml:exception:${name}:${uniqueId || ''}`,
      uniqueId,
      name,
      module:  ctx.moduleName,
      _source: ctx.sourceFile,
    };
  }
}

if (require.main === module) {
  const { FileReader } = require('../lib/file-reader');
  const fs  = require('fs');
  const [,, dir] = process.argv;
  const reader    = new FileReader();
  const extractor = new XmlExtractor({ fileReader: reader, logger: console });
  (async () => {
    const files  = await reader.glob(dir, '*.xml');
    console.error(`Extracting from ${files.length} XML files...`);
    const result = await extractor.run(files, {});
    fs.mkdirSync('knowledge-base/extracted', { recursive: true });
    fs.writeFileSync('knowledge-base/extracted/xml.json', JSON.stringify(result, null, 2));
    console.error(`Done. Items: ${result.items.length}, Errors: ${result.errors.length}`);
  })();
}

module.exports = { XmlExtractor };
