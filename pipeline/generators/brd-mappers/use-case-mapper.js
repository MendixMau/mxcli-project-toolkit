'use strict';

function mapUseCases(screens) {
  // Scaffold only — narrative fields are intentional TODOs for business review.
  // Groups screens into use case stubs based on screen name patterns.
  return screens.map((s, i) => {
    const id = `UC${String(i + 1).padStart(3, '0')}`;
    const linkedLogics = (s._links || [])
      .filter(l => l.id.includes(':logic:'))
      .map(l => l.via || l.id);

    return {
      id,
      title:          s.name.replace(/_/g, ' '),
      screen:         s.name,
      uiPattern:      (s.widgetSummary || {}).hasListUI
                        ? 'list' : (s.widgetSummary || {}).hasFormUI
                        ? 'form' : 'detail',
      linkedLogics,
      inputParameters: (s.inputParameters || []).map(p => p.name),
      // ── Narrative stubs — must be reviewed with business ──
      actors:          ['TODO: identify actors'],
      preconditions:   ['TODO: define preconditions'],
      mainFlow:        ['TODO: describe user interaction steps'],
      postconditions:  ['TODO: define postconditions'],
      reviewStatus:    'pending',
    };
  });
}

module.exports = { mapUseCases };
