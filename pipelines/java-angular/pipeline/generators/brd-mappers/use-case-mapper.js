'use strict';

// Business-action HTTP methods vs. read-only. Mirrors os-migration-pipeline's
// BUSINESS_ACTION_RE/SAVE_ACTION_RE split, but keyed off httpEndpoint.method (what our
// linker's Rule J4 actually gives us) rather than an OS action-name prefix convention.
const WRITE_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
const MAX_FLOW_STEPS = 8;

function uniqueBy(arr, keyFn) {
  const seen = new Set();
  return arr.filter(item => {
    const k = keyFn(item);
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

// This stack's extractors never capture a role/permission model (no equivalent of OS's
// screen-permission-role link exists in java-extractor.js/angular-extractor.js) — so actors
// are always an explicit TODO, never guessed from screen name or content.
function inferActors() {
  return ['TODO: identify actors'];
}

function buildFlow(screen, links) {
  const apiLinks = links.filter(l => l.matchedBy === 'api-call-match' || l.matchedBy === 'api-path-match-no-verb');
  const compositionLinks = links.filter(l => l.matchedBy === 'composes-component');
  const dialogOpensLinks = links.filter(l => l.matchedBy === 'dialog-opens');

  const writeActions = apiLinks.filter(l => WRITE_METHODS.has((l.via || '').split(' ')[0]));
  const readActions   = apiLinks.filter(l => (l.via || '').split(' ')[0] === 'GET');
  const uniqueComposed = uniqueBy(compositionLinks, l => l.via);
  const uniqueDialogs   = uniqueBy(dialogOpensLinks, l => l.via);

  const steps = [
    ...readActions.slice(0, MAX_FLOW_STEPS).map(a => `System loads data via ${a.via} on ${screen.name}`),
    ...writeActions.slice(0, MAX_FLOW_STEPS).map(a => `User triggers an action causing ${a.via} on ${screen.name}`),
    ...uniqueComposed.slice(0, MAX_FLOW_STEPS).map(c => `${screen.name} embeds ${c.via}`),
    ...uniqueDialogs.slice(0, MAX_FLOW_STEPS).map(d => `${screen.name} opens ${d.via} as a dialog`),
  ];

  if (!steps.length) {
    return {
      mainFlow: ['TODO: describe user interaction steps'],
      gaps: [],
      openQuestions: [
        'No API call or component composition detected on this screen — confirm this is a ' +
        'display-only / read-only page',
      ],
    };
  }

  const openQuestions = writeActions.map(a => {
    const method = (a.via || '').split(' ')[0];
    return method === 'DELETE'
      ? `What confirmation/cascade behavior is expected before ${a.via} succeeds on ${screen.name}?`
      : `What validation rules must pass before ${a.via} succeeds on ${screen.name}?`;
  });

  const gaps = [];
  if (links.length > apiLinks.length + compositionLinks.length + dialogOpensLinks.length + MAX_FLOW_STEPS) {
    gaps.push('additional-links-not-surfaced');
  }

  return { mainFlow: steps, gaps, openQuestions };
}

function mapUseCases(screens) {
  return screens.map((s, i) => {
    const id = `UC${String(i + 1).padStart(3, '0')}`;
    const links = s._links || [];
    const linkedLogics = links
      .filter(l => l.id.includes(':logic:'))
      .map(l => l.via || l.id);
    const { mainFlow, gaps, openQuestions } = buildFlow(s, links);
    const actors = inferActors();

    return {
      id,
      title:          s.name.replace(/_/g, ' '),
      screen:         s.name,
      uiPattern:      (s.widgetSummary || {}).hasListUI
                        ? 'list' : (s.widgetSummary || {}).hasFormUI
                        ? 'form' : 'detail',
      linkedLogics,
      inputParameters: (s.inputParameters || []).map(p => p.name),
      // ── Code-inferred narrative — confirm/correct against documented business intent ──
      actors,
      preconditions:  ['TODO: define preconditions'],
      mainFlow,
      postconditions: ['TODO: define postconditions'],
      openQuestions,
      gaps,
      status:         'code-inferred',
      reviewStatus:   'pending',
    };
  });
}

// Rough app/module type classification from data the other mappers already compute. Drops
// os-migration-pipeline's BPT/workflow-action category — that's an OS-specific concept with no
// Java/Angular equivalent in this stack's extractors. Always returns the signals that led to
// the label — never a bare assertion.
function classifyAppType(pages, microflows, integrations) {
  const integrationCount = integrations.length;
  const listFormCount = pages.filter(p => ['list', 'form', 'list+form'].includes(p.uiPattern)).length;

  if (integrationCount >= 3) {
    return {
      label: 'Integration-heavy',
      confidence: integrationCount >= 5 ? 'high' : 'medium',
      signals: [`${integrationCount} external integration(s)`],
    };
  }
  if (pages.length > 0 && listFormCount / pages.length >= 0.6) {
    return {
      label: 'Master Data / CRUD',
      confidence: 'medium',
      signals: [`${listFormCount}/${pages.length} pages are list/form UI patterns`],
    };
  }
  return {
    label: 'Mixed',
    confidence: 'low',
    signals: [`${pages.length} pages, ${microflows.length} logic items, ${integrationCount} integrations — no dominant pattern`],
  };
}

module.exports = { mapUseCases, classifyAppType };
