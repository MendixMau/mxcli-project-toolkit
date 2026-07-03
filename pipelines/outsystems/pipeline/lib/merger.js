'use strict';

const fs   = require('fs');
const path = require('path');
const { Linker }      = require('./linker');
const { KeyResolver } = require('./key-resolver');

class Merger {
  constructor({ extractedDir, outputDir, blueprintDir, logger }) {
    this.extractedDir = extractedDir;
    this.outputDir    = outputDir;
    this.blueprintDir = blueprintDir || null;
    this.logger       = logger || console;
  }

  async run() {
    const all    = this._loadAll();
    const deduped = this._deduplicate(all);

    // ── Secondary enrichment (requires all items loaded) ──
    if (this.blueprintDir) {
      this.logger.log('  [merge] Building global key index...');
      const resolver = new KeyResolver(this.blueprintDir).build();
      this._enrichWithKeyResolver(deduped, resolver);
      this.logger.log('  [merge] Key resolution complete.');
    }

    const crossRef = new Linker().link(deduped);
    this._emit(deduped, crossRef);
    this._writeGapsReport(crossRef, deduped);
    this._writeCoverageReport(all, deduped);
    this._writeSummary(deduped, crossRef);
    this.logger.log(`Merge complete. Total unique items: ${deduped.length}`);
  }

  /** Enrich logic.calls with sourceModule/resolvedName, and aggregates with entityName. */
  _enrichWithKeyResolver(items, resolver) {
    // Build entity uniqueId → name map from extracted items (covers same-module entities)
    const entityByUniqueId = new Map();
    for (const item of items) {
      if ((item.type === 'entity' || item.type === 'staticEntity' || item.type === 'ext-entity') && item.uniqueId) {
        entityByUniqueId.set(item.uniqueId, item.name);
      }
    }

    let callsResolved = 0, callsTotal = 0;
    let aggResolved = 0, aggTotal = 0;

    for (const item of items) {
      if (item.type !== 'logic') continue;

      // Resolve cross-module calls (ActionReference:) and same-module calls (Action:)
      for (const call of (item.calls || [])) {
        callsTotal++;
        if (!call.target) continue;
        if (call.target.startsWith('ActionReference:')) {
          const resolved = resolver.resolveActionRef(call.target);
          if (resolved) {
            call.sourceModule = resolved.sourceModule;
            call.resolvedName = resolved.name || call.name;
            callsResolved++;
          }
        } else if (call.target.startsWith('Action:')) {
          // Direct same-module call — no cross-module lookup needed
          call.sourceModule = item.module;
          call.resolvedName = call.name;
          callsResolved++;
        }
      }

      // Resolve aggregate entitySource → entityName
      // entitySource may be "Entity:xxx" (same/other module) or "EntityReference:xxx" (cross-module ref)
      const resolveEntitySrc = (key) => {
        if (!key) return null;
        let name = entityByUniqueId.get(key);
        if (name) return name;
        if (key.startsWith('EntityReference:')) {
          // Look up in actionRefMap which also contains EntityReference entries
          const r = resolver.actionRefMap.get(key);
          return r?.name || null;
        }
        const r = resolver.resolveEntityKey(key);
        return r?.entityName || null;
      };

      for (const agg of (item.aggregates || [])) {
        if (!agg.entitySource) continue;
        aggTotal++;
        const name = resolveEntitySrc(agg.entitySource);
        if (name) { agg.entityName = name; aggResolved++; }
      }

      // Also resolve aggregate entitySource in flowGraph nodes
      for (const node of (item.flowGraph?.nodes || [])) {
        if (node.nodeType !== 'Aggregate' || !node.entitySource) continue;
        const name = resolveEntitySrc(node.entitySource);
        if (name) node.entityName = name;
      }
    }

    // Resolve screen widget dataSources → boundEntities
    // Build: module → list of {aggName, entityName} across all logics in that module
    const aggsByModule = new Map();
    for (const item of items) {
      if (item.type !== 'logic' || !item.module) continue;
      const list = aggsByModule.get(item.module) || [];
      for (const agg of (item.aggregates || [])) {
        if (agg.name && agg.entityName) list.push({ aggName: agg.name, entityName: agg.entityName });
      }
      aggsByModule.set(item.module, list);
    }

    for (const item of items) {
      if (item.type !== 'screen' || !item.widgetSummary?.dataSources?.length) continue;
      const boundEntities = new Set();
      const moduleAggs = aggsByModule.get(item.module) || [];
      for (const ds of item.widgetSummary.dataSources) {
        // ds like "GetGroups.List" → aggName = "GetGroups"
        const aggName = ds.split('.')[0];
        const match = moduleAggs.find(a => a.aggName === aggName);
        if (match?.entityName) boundEntities.add(match.entityName);
      }
      if (boundEntities.size) item.widgetSummary.boundEntities = [...boundEntities];
    }

    this.logger.log(`  [merge] Calls resolved: ${callsResolved}/${callsTotal} | Aggregates resolved: ${aggResolved}/${aggTotal}`);

    // ── Widget tree key resolution ──
    let widgetTreeScreens = 0, navResolved = 0, slotResolved = 0, slotTotal = 0, blockResolved = 0;
    for (const item of items) {
      if (item.type !== 'screen' || !item.widgetTree) continue;
      widgetTreeScreens++;
      this._resolveWidgetTree(item.widgetTree, resolver, item.module,
        { navResolved: 0, slotResolved: 0, slotTotal: 0, blockResolved: 0 },
        (counts) => { navResolved += counts.navResolved; slotResolved += counts.slotResolved;
                      slotTotal += counts.slotTotal; blockResolved += counts.blockResolved; });
    }
    this.logger.log(`  [merge] Widget trees: ${widgetTreeScreens} screens | nav resolved: ${navResolved} | slots: ${slotResolved}/${slotTotal} | blocks: ${blockResolved}`);
  }

  /** Recursively walk a widgetTree array and resolve keys in-place. */
  _resolveWidgetTree(nodes, resolver, module, counts, onDone) {
    if (!Array.isArray(nodes)) return;
    for (const node of nodes) {
      if (!node || typeof node !== 'object') continue;

      // Resolve navigation destination (WebScreen:key → name)
      if (node.destinationKey && node.destinationKey.startsWith('WebScreen:')) {
        const r = resolver.resolveScreen(node.destinationKey);
        if (r) { node.destinationName = r.screenName; counts.navResolved++; }
      }
      // Resolve rowNavigation
      if (node.rowNavigation?.destinationKey?.startsWith('WebScreen:')) {
        const r = resolver.resolveScreen(node.rowNavigation.destinationKey);
        if (r) { node.rowNavigation.destinationName = r.screenName; counts.navResolved++; }
      }
      // Resolve WebBlock name
      if (node.sourceWebBlockKey && !node.sourceWebBlockName) {
        const r = resolver.resolveWebBlock(node.sourceWebBlockKey);
        if (r) { node.sourceWebBlockName = r.name; counts.blockResolved++; }
      }
      // Resolve Placeholder slot name
      if (node.widgetType === 'PlaceholderArgument' && node.placeholderKey) {
        counts.slotTotal++;
        if (!node.slotName) {
          const r = resolver.resolvePlaceholder(node.placeholderKey);
          if (r) {
            node.slotName  = r.slotName;
            node.inLayout  = r.webBlockName;
            counts.slotResolved++;
          }
          // Positional fallback: infer from sibling index if still unnamed
          // (handled after full sibling scan — see positional pass below)
        } else {
          counts.slotResolved++;
        }
      }
      // Positional slot-name fallback: for PlaceholderArgument with no resolved name,
      // infer from its position among siblings (set by parent BuildingBlock resolution).
      // This pass assigns Atlas-style positional names after all children are processed.

      // Recurse into children
      if (node.children) {
        this._resolveWidgetTree(node.children, resolver, module, counts, null);
        // After recursing, apply positional names to any still-unnamed SlotContent children
        const slots = node.children.filter(c => c.widgetType === 'PlaceholderArgument');
        if (slots.some(s => !s.slotName)) {
          const layoutName = node.sourceWebBlockName || '';
          slots.forEach((slot, i) => {
            if (!slot.slotName) {
              slot.slotName       = resolver.inferSlotNameByPosition(i, layoutName);
              slot.slotNameSource = 'positional';
            }
          });
        }
      }
      // Recurse into cells (TableRecords DataRow)
      if (node.cells) {
        for (const cell of node.cells) {
          if (cell.children) this._resolveWidgetTree(cell.children, resolver, module, counts, null);
        }
      }
    }
    if (onDone) onDone(counts);
  }

  _loadAll() {
    const sources = ['xml','cs','js','db','excel','docs','ext-entities'];
    const items = [];
    for (const src of sources) {
      const f = path.join(this.extractedDir, `${src}.json`);
      if (!fs.existsSync(f)) { this.logger.log(`  [merge] Skipping missing: ${f}`); continue; }
      try {
        const data = JSON.parse(fs.readFileSync(f, 'utf8'));
        items.push(...(data.items || []));
      } catch (e) {
        this.logger.error(`  [merge] Failed to load ${f}: ${e.message}`);
      }
    }
    return items;
  }

  _deduplicate(items) {
    const seen = new Set();
    return items.filter(item => {
      const key = item.uniqueId ? `uid:${item.uniqueId}` : item.linkId;
      if (!key || seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }

  _emit(items, crossRef) {
    const out = this.outputDir;
    fs.mkdirSync(out, { recursive: true });

    const byType = (type) => items.filter(i => i.type === type).map(i => ({
      ...i,
      _links: crossRef[i.linkId]?.linkedTo || [],
      _gaps:  crossRef[i.linkId]?.gaps     || [],
    }));

    const write = (name, data) =>
      fs.writeFileSync(path.join(out, name), JSON.stringify(data, null, 2), 'utf8');

    write('structures.json',         byType('structure'));
    write('entities.json',          byType('entity'));
    write('staticEntities.json',    byType('staticEntity'));
    write('logics.json',            byType('logic'));
    write('screens.json',           byType('screen'));
    write('webBlocks.json',         byType('webBlock'));
    write('dataScreenActions.json', byType('dataScreenAction'));
    write('webFlows.json',       byType('webFlow'));
    write('workflows.json',      byType('workflow'));
    write('serviceApis.json',    byType('serviceApi'));
    write('exceptions.json',     byType('exception'));
    write('timers.json',         byType('timer'));
    write('roles.json',          byType('role'));
    write('extEntities.json',    byType('ext-entity'));
    write('requirements.json',   [...byType('excel-sheet'), ...byType('docx'), ...byType('pdf'), ...byType('pptx')]);
    write('mendix-mapping.json', items.filter(i => i.linkId?.includes('mendix')));
    write('cross-reference-map.json', crossRef);
  }

  _writeGapsReport(crossRef, items) {
    const byLinkId = Object.fromEntries(items.map(i => [i.linkId, i]));
    const lines = ['# Gaps Report\n\nConstructs with missing cross-references or low-confidence links.\n'];
    for (const [id, { linkedTo, gaps }] of Object.entries(crossRef)) {
      if (!gaps.length && !linkedTo.some(l => l.confidence === 'low')) continue;
      const item = byLinkId[id];
      lines.push(`## ${id}`);
      if (item?.name) lines.push(`**Name:** ${item.name}  `);
      if (gaps.length)   lines.push(`**Gaps:** ${gaps.join(', ')}  `);
      const lowConf = linkedTo.filter(l => l.confidence === 'low');
      if (lowConf.length) lines.push(`**Low-confidence links:** ${lowConf.map(l => l.id).join(', ')}  `);
      lines.push('');
    }
    const reportsDir = path.join(this.outputDir, 'reports');
    fs.mkdirSync(reportsDir, { recursive: true });
    fs.writeFileSync(path.join(reportsDir, 'gaps-report.md'), lines.join('\n'), 'utf8');
  }

  _writeCoverageReport(raw, deduped) {
    const total = raw.length;
    const unique = deduped.length;
    const byType = {};
    for (const i of deduped) byType[i.type] = (byType[i.type] || 0) + 1;
    const lines = [
      '# Coverage Report\n',
      `- **Total raw items:** ${total}`,
      `- **Unique items after deduplication:** ${unique}`,
      `- **Duplication rate:** ${total ? Math.round((1 - unique / total) * 100) : 0}%\n`,
      '## By Type\n',
      '| Type | Count |',
      '|------|-------|',
      ...Object.entries(byType).map(([t, n]) => `| ${t} | ${n} |`),
    ];
    const reportsDir = path.join(this.outputDir, 'reports');
    fs.mkdirSync(reportsDir, { recursive: true });
    fs.writeFileSync(path.join(reportsDir, 'coverage-report.md'), lines.join('\n'), 'utf8');
  }

  _writeSummary(items, crossRef) {
    const counts = {};
    for (const i of items) counts[i.type] = (counts[i.type] || 0) + 1;
    const totalLinks = Object.values(crossRef).reduce((s, v) => s + v.linkedTo.length, 0);
    const totalGaps  = Object.values(crossRef).reduce((s, v) => s + v.gaps.length, 0);
    const lines = [
      '# Knowledge Base Summary\n',
      '## Construct Counts\n',
      '| Type | Count |', '|------|-------|',
      ...Object.entries(counts).map(([t, n]) => `| ${t} | ${n} |`),
      '',
      '## Cross-Reference Summary\n',
      `- Total cross-references established: **${totalLinks}**`,
      `- Total gaps (missing links): **${totalGaps}**`,
      '',
      '> Review `reports/gaps-report.md` for constructs requiring human confirmation.',
    ];
    const reportsDir = path.join(this.outputDir, 'reports');
    fs.mkdirSync(reportsDir, { recursive: true });
    fs.writeFileSync(path.join(reportsDir, 'summary.md'), lines.join('\n'), 'utf8');
    fs.writeFileSync(path.join(this.outputDir, 'summary.md'), lines.join('\n'), 'utf8');
  }
}

if (require.main === module) {
  const config = JSON.parse(require('fs').readFileSync('config.json', 'utf8'));
  const kbDir  = config.knowledgeBaseDir || require('path').join(__dirname, '..', 'knowledge-base');
  const merger = new Merger({
    extractedDir: require('path').join(kbDir, 'extracted'),
    outputDir:    kbDir,
    blueprintDir: config.blueprintDir,
    logger:       console,
  });
  merger.run().catch(e => { console.error(e); process.exit(1); });
}

module.exports = { Merger };
