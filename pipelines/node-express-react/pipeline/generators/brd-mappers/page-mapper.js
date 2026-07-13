'use strict';

function inferUiPattern(screen) {
  const ws = screen.widgetSummary || {};
  if (ws.hasListUI && ws.hasFormUI) return 'list+form';
  if (ws.hasListUI)                  return 'list';
  if (ws.hasFormUI)                  return 'form';
  return 'detail';
}

function mapPages(screens, webBlocks) {
  const pages = screens.map(s => ({
    name:       s.name,
    title:      (s.title || s.name).replace(/^"|"$/g, '').replace(/&quot;/g, ''),
    isPublic:   s.isPublic || false,
    uiPattern:  inferUiPattern(s),
    description: s.description || '',
    inputParameters: (s.inputParameters || []).map(p => ({
      name: p.name, type: p.type, isMandatory: p.isMandatory,
    })),
    clientActions: (s.clientActions || []).map(a => a.name).filter(Boolean),
    widgetTypes:   (s.widgetSummary || {}).widgetTypes || [],
    dataSources:   (s.widgetSummary || {}).dataSources || [],
    // Data-driven styling ([ngClass]/[class.x]) is the one styling pattern that can hide a
    // real business rule (e.g. a status color-code) — surfaced here, unlike the OS pipeline's
    // equivalent (widget Visible-property expressions), which is captured at extraction time
    // but never reaches the BRD or HTML report, only Phase 6 MDL generation.
    hasConditionalStyling: (s.widgetSummary || {}).hasConditionalStyling || false,
    linkedLogics:  (s._links || []).filter(l => l.id.includes(':logic:')).map(l => ({
      id: l.id, confidence: l.confidence, via: l.via,
    })),
    gaps: s._gaps || [],
  }));

  const blocks = webBlocks.map(b => ({
    name:        b.name,
    isBlock:     true,
    description: b.description || '',
    inputParameters: (b.inputParameters || []).map(p => ({
      name: p.name, type: p.type,
    })),
    gaps: b._gaps || [],
  }));

  return { pages, webBlocks: blocks };
}

module.exports = { mapPages };
