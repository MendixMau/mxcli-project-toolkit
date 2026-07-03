'use strict';

// Prefix patterns for genuine user-triggered business actions (save/submit/approve/etc).
// Deliberately excludes lifecycle hooks (OnInitialize, OnReady, ToggleX, AsyncX, ScreenState*)
// and internal section-refresh helpers (UpdateXData) common in OS client actions — including
// those would bury the real business actions in noise.
const BUSINESS_ACTION_RE = /^(Save|Create|Delete|Remove|Submit|Approve|Reject|Cancel|Confirm|Register|Apply|Remand)/i;
const WORKFLOW_ACTION_RE = /^(Approve|Reject|Remand|Submit)/i;
const SAVE_ACTION_RE     = /^(Save|Create|Register|Apply)/i;
const MAX_FLOW_STEPS = 8;

function findNavEdges(node, out) {
  if (!node || typeof node !== 'object') return out;
  if (Array.isArray(node)) {
    for (const n of node) findNavEdges(n, out);
    return out;
  }
  if (node.destinationName) {
    out.push({ destinationName: node.destinationName, via: node.widgetType || 'Link' });
  }
  if (node.rowNavigation && node.rowNavigation.destinationName) {
    out.push({ destinationName: node.rowNavigation.destinationName, via: 'row click' });
  }
  if (Array.isArray(node.children)) findNavEdges(node.children, out);
  return out;
}

function uniqueBy(arr, keyFn) {
  const seen = new Set();
  return arr.filter(item => {
    const k = keyFn(item);
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

// Actors are only ever asserted when a screen-permission-role link already exists —
// never guessed from screen name or content.
function inferActors(links) {
  const roleLinks = links.filter(l => l.matchedBy === 'screen-permission-role');
  if (!roleLinks.length) return ['TODO: identify actors'];
  return uniqueBy(roleLinks, l => l.id).map(l => l.id.split(':')[2] || l.id);
}

function buildFlow(screen, navEdges, actionLinks) {
  const businessActions = actionLinks.filter(l => BUSINESS_ACTION_RE.test(l.via || ''));
  const uniqueEdges = uniqueBy(navEdges, e => e.destinationName);

  const steps = [
    ...businessActions.slice(0, MAX_FLOW_STEPS).map(a => `User triggers "${a.via}" on ${screen.name}`),
    ...uniqueEdges.slice(0, MAX_FLOW_STEPS).map(e => `User navigates from ${screen.name} to ${e.destinationName}`),
  ];

  if (!steps.length) {
    return {
      mainFlow: ['TODO: describe user interaction steps'],
      gaps: [],
      openQuestions: [
        'No navigation or recognizable business action detected on this screen — ' +
        'confirm this is a display-only / read-only page',
      ],
    };
  }

  const openQuestions = [
    ...businessActions.filter(a => WORKFLOW_ACTION_RE.test(a.via || '')).map(a =>
      `What conditions determine the outcome of "${a.via}" on ${screen.name} (approve vs. reject vs. remand)?`),
    ...businessActions.filter(a => SAVE_ACTION_RE.test(a.via || '')).map(a =>
      `What validation rules must pass before "${a.via}" succeeds on ${screen.name}?`),
  ];

  const gaps = [];
  if (actionLinks.length + navEdges.length > businessActions.length + MAX_FLOW_STEPS) {
    gaps.push('additional-actions-not-surfaced');
  }

  return { mainFlow: steps, gaps, openQuestions };
}

function mapUseCases(screens) {
  return screens.map((s, i) => {
    const id = `UC${String(i + 1).padStart(3, '0')}`;
    const links = s._links || [];
    const actionLinks = links
      .filter(l => l.id.includes(':logic:'))
      .map(l => ({ via: l.via || l.id }));
    const navEdges = findNavEdges(s.widgetTree, []);
    const { mainFlow, gaps, openQuestions } = buildFlow(s, navEdges, actionLinks);
    const actors = inferActors(links);

    return {
      id,
      title:          s.name.replace(/_/g, ' '),
      screen:         s.name,
      uiPattern:      (s.widgetSummary || {}).hasListUI
                        ? 'list' : (s.widgetSummary || {}).hasFormUI
                        ? 'form' : 'detail',
      linkedLogics:   actionLinks.map(a => a.via),
      inputParameters: (s.inputParameters || []).map(p => p.name),
      // ── Code-inferred narrative — confirm/correct against documented business intent ──
      actors,
      preconditions:  actors[0] === 'TODO: identify actors'
                        ? ['TODO: define preconditions']
                        : [`User must have role: ${actors.join(', ')}`],
      mainFlow,
      postconditions: ['TODO: define postconditions'],
      openQuestions,
      gaps,
      status:         'code-inferred',
      reviewStatus:   'pending',
    };
  });
}

// Rough app/module type classification from data the other mappers already compute.
// Always returns the signals that led to the label — never a bare assertion.
function classifyAppType(pages, microflows, integrations) {
  const bptCount = microflows.filter(m => m.isBPTProcess).length;
  const workflowActionCount = microflows.filter(m => WORKFLOW_ACTION_RE.test(m.name || '')).length;
  const integrationCount = integrations.length;
  const listFormCount = pages.filter(p => ['list', 'form', 'list+form'].includes(p.uiPattern)).length;

  if (bptCount > 0 || workflowActionCount >= 3) {
    return {
      label: 'Approval Workflow',
      confidence: bptCount > 0 ? 'high' : 'medium',
      signals: [`${bptCount} BPT process(es), ${workflowActionCount} approval/workflow-named action(s)`],
    };
  }
  if (integrationCount >= 3) {
    return {
      label: 'Integration-heavy',
      confidence: integrationCount >= 5 ? 'high' : 'medium',
      signals: [`${integrationCount} external integration(s) (services + external entities)`],
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
