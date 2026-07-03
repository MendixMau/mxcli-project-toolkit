'use strict';

const { XMLParser } = require('fast-xml-parser');
const fs   = require('fs');
const path = require('path');

const PARSER_OPTIONS = {
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
  isArray: () => false,
  processEntities: false,
};

/**
 * Builds two global indexes by scanning all XML blueprint files:
 *
 * 1. actionRefMap:    ActionReference:xxx → { sourceModule, name }
 *    Also covers EntityReference, WebBlockReference (same pattern).
 *
 * 2. entityKeyMap:    "Entity:xxx" → { entityName, sourceModule }
 *
 * 3. placeholderMap:  "Placeholder:xxx" → { slotName, webBlockName }
 *    From all WebBlock.Placeholder definitions across all modules.
 *
 * 4. webBlockMap:     "WebBlock:xxx" | "WebBlockReference:xxx" → { name, sourceModule }
 *    From all WebBlock definitions + Reference section WebBlockReference entries.
 *
 * 5. screenKeyMap:    "WebScreen:xxx" → { screenName, module }
 *    From all WebScreen definitions — enables widget navigation resolution.
 */

// Atlas UI framework layout → slot names (standard, not in blueprint XMLs)
const ATLAS_SLOT_MAP = {
  // Traditional Web layouts (OutSystemsUI / RichWidgets)
  'MainFlow':            ['Menu','Breadcrumbs','Title','MainContent'],
  'Layout_Side_Menu':   ['Menu','Breadcrumbs','Title','MainContent','SideContent'],
  'Layout_TopMenu':     ['Menu','Breadcrumbs','Title','MainContent'],
  'Layout_Popup':       ['MainContent','Footer'],
  'Layout_Blank':       ['MainContent'],
  'Layout_Login':       ['MainContent'],
  'Layout_NoMenu':      ['Breadcrumbs','Title','MainContent'],
  // Positional fallback (ordered by typical layout position)
  '_positional':        ['Navigation','Breadcrumbs','Title','MainContent','Footer','SideContent','Actions'],
};

class KeyResolver {
  constructor(blueprintDir) {
    this.blueprintDir   = blueprintDir;
    this.actionRefMap   = new Map();
    this.entityKeyMap   = new Map();
    this.placeholderMap = new Map();  // Placeholder:key → { slotName, webBlockName }
    this.webBlockMap    = new Map();  // WebBlock:key → { name, sourceModule }
    this.screenKeyMap   = new Map();  // WebScreen:key → { screenName, module }
  }

  build() {
    const files = fs.readdirSync(this.blueprintDir)
      .filter(f => f.endsWith('.xml'))
      .map(f => path.join(this.blueprintDir, f));

    for (const filePath of files) {
      try {
        this._processFile(filePath);
      } catch (e) {
        // skip unparseable files silently
      }
    }
    return this;
  }

  _processFile(filePath) {
    const raw    = fs.readFileSync(filePath, 'utf8');
    const parsed = new XMLParser(PARSER_OPTIONS).parse(raw);
    const root   = parsed && Object.values(parsed)[0];
    if (!root) return;

    const moduleName = root['@_Name'] || path.basename(filePath, '.xml');

    // ── 1. Entity key map ──
    this._walkForEntities(root, moduleName);

    // ── 3. WebBlock + Placeholder maps ──
    this._walkForWebBlocks(root, moduleName);

    // ── 5. Screen key map ──
    this._walkForScreens(root, moduleName);

    // ── 2. ActionReference + WebBlockReference maps (from References section) ──
    const refs = root.References;
    if (!refs) return;
    const refList = refs.Reference;
    if (!refList) return;
    const allRefs = Array.isArray(refList) ? refList : [refList];

    for (const ref of allRefs) {
      const sourceModule = ref['@_Name'] || '';
      this._extractActionRefs(ref.Actions,    sourceModule);
      this._extractActionRefs(ref.WebFlows,   sourceModule);
      this._extractActionRefs(ref.Entities,   sourceModule);
      // WebBlockReference (layout blocks from other modules)
      this._extractActionRefs(ref.Screens,    sourceModule);
      this._extractActionRefs(ref,            sourceModule); // catch any direct children
    }
  }

  _walkForWebBlocks(obj, moduleName) {
    if (!obj || typeof obj !== 'object') return;
    if (Array.isArray(obj)) { for (const v of obj) this._walkForWebBlocks(v, moduleName); return; }
    for (const [k, v] of Object.entries(obj)) {
      if (k === 'WebBlock' && v && typeof v === 'object') {
        const blocks = Array.isArray(v) ? v : [v];
        for (const wb of blocks) {
          const key  = wb['@_Key'] || '';
          const name = wb['@_Name'] || '';
          if (key) {
            this.webBlockMap.set(key, { name, sourceModule: moduleName });
            // Collect its Placeholder slots
            this._collectPlaceholders(wb, name);
          }
          this._walkForWebBlocks(wb, moduleName);
        }
        continue;
      }
      if (v && typeof v === 'object') this._walkForWebBlocks(v, moduleName);
    }
  }

  _collectPlaceholders(webBlockObj, webBlockName) {
    if (!webBlockObj || typeof webBlockObj !== 'object') return;
    if (Array.isArray(webBlockObj)) { for (const v of webBlockObj) this._collectPlaceholders(v, webBlockName); return; }
    for (const [k, v] of Object.entries(webBlockObj)) {
      if (k === 'Placeholder' && v && typeof v === 'object') {
        const phs = Array.isArray(v) ? v : [v];
        for (const ph of phs) {
          const key  = ph['@_Key'] || '';
          const name = ph['@_Name'] || '';
          if (key) this.placeholderMap.set(key, { slotName: name, webBlockName });
        }
        continue;
      }
      if (v && typeof v === 'object') this._collectPlaceholders(v, webBlockName);
    }
  }

  _walkForScreens(obj, moduleName) {
    if (!obj || typeof obj !== 'object') return;
    if (Array.isArray(obj)) { for (const v of obj) this._walkForScreens(v, moduleName); return; }
    for (const [k, v] of Object.entries(obj)) {
      if (k === 'WebScreen' && v && typeof v === 'object') {
        const screens = Array.isArray(v) ? v : [v];
        for (const ws of screens) {
          const key  = ws['@_Key'] || '';
          const name = ws['@_Name'] || '';
          if (key) this.screenKeyMap.set(key, { screenName: name, module: moduleName });
        }
        continue;
      }
      if (v && typeof v === 'object') this._walkForScreens(v, moduleName);
    }
  }

  _extractActionRefs(container, sourceModule) {
    if (!container || typeof container !== 'object') return;
    // ActionReference can be direct child or nested in any child
    this._walkForActionRefs(container, sourceModule);
  }

  _walkForActionRefs(obj, sourceModule) {
    if (!obj || typeof obj !== 'object') return;
    if (Array.isArray(obj)) {
      for (const v of obj) this._walkForActionRefs(v, sourceModule);
      return;
    }
    for (const [k, v] of Object.entries(obj)) {
      if (k === 'ActionReference' || k === 'EntityReference' || k === 'ScreenReference') {
        const items = Array.isArray(v) ? v : [v];
        for (const item of items) {
          const key  = item['@_Key'] || '';
          const name = item['@_Name'] || '';
          if (key) this.actionRefMap.set(key, { sourceModule, name });
        }
      }
      if (v && typeof v === 'object') this._walkForActionRefs(v, sourceModule);
    }
  }

  _walkForEntities(obj, moduleName) {
    if (!obj || typeof obj !== 'object') return;
    if (Array.isArray(obj)) {
      for (const v of obj) this._walkForEntities(v, moduleName);
      return;
    }
    for (const [k, v] of Object.entries(obj)) {
      if ((k === 'Entity' || k === 'StaticEntity') && v && typeof v === 'object') {
        const items = Array.isArray(v) ? v : [v];
        for (const item of items) {
          const key  = item['@_Key'] || '';
          const name = item['@_Name'] || '';
          if (key) this.entityKeyMap.set(key, { entityName: name, sourceModule: moduleName });
        }
      }
      if (v && typeof v === 'object') this._walkForEntities(v, moduleName);
    }
  }

  /** Resolve an ActionReference key to { sourceModule, name } */
  resolveActionRef(key) {
    return this.actionRefMap.get(key) || null;
  }

  /** Resolve an Entity key (with or without "Entity:" prefix) to { entityName, sourceModule } */
  resolveEntityKey(key) {
    if (this.entityKeyMap.has(key)) return this.entityKeyMap.get(key);
    const stripped = key.startsWith('Entity:') ? key.slice(7) : key;
    return this.entityKeyMap.get(stripped) || this.entityKeyMap.get('Entity:' + stripped) || null;
  }

  /** Resolve a Placeholder key to { slotName, webBlockName } */
  resolvePlaceholder(key) {
    return this.placeholderMap.get(key) || null;
  }

  /** Resolve a WebBlock key (WebBlock:xxx or WebBlockReference:xxx) to { name, sourceModule } */
  resolveWebBlock(key) {
    if (this.webBlockMap.has(key)) return this.webBlockMap.get(key);
    // Also check actionRefMap for WebBlockReference entries
    const ref = this.actionRefMap.get(key);
    if (ref) return { name: ref.name, sourceModule: ref.sourceModule };
    return null;
  }

  /** Resolve a WebScreen key to { screenName, module } */
  resolveScreen(key) {
    return this.screenKeyMap.get(key) || null;
  }

  /**
   * Infer slot name by position when Placeholder key is unresolvable
   * (Atlas/external framework layouts use standard positional slot order)
   */
  inferSlotNameByPosition(index, layoutBlockName) {
    const slots = ATLAS_SLOT_MAP[layoutBlockName] || ATLAS_SLOT_MAP['_positional'];
    return slots[index] || `Slot_${index + 1}`;
  }
}

module.exports = { KeyResolver };
