'use strict';

const KIND_LABEL = {
  action:           'Microflow',
  clientAction:     'Nanoflow',
  screenAction:     'Nanoflow',
  dataAction:       'DataAction',
  process:          'BPTProcess',
  dataScreenAction: 'DataScreenAction',
};

function inferPurpose(name, description) {
  if (description && description.trim().length > 3) return description.trim();
  const n = name || '';
  if (/^GET_|^Get[A-Z]/i.test(n))           return `Retrieve ${n.replace(/^GET_|^Get/i, '').replace(/_/g, ' ')}`;
  if (/^ACT_Save|^Save|^Update|^PUT/i.test(n)) return `Save / update ${n.replace(/^ACT_Save|^Save|^Update|^PUT/i, '').replace(/_/g, ' ')}`;
  if (/^ACT_Create|^Create|^POST/i.test(n))    return `Create ${n.replace(/^ACT_Create|^Create|^POST/i, '').replace(/_/g, ' ')}`;
  if (/^ACT_Delete|^Delete|^DEL/i.test(n))     return `Delete ${n.replace(/^ACT_Delete|^Delete|^DEL/i, '').replace(/_/g, ' ')}`;
  if (/^VAL_|^Validate|^Check/i.test(n))       return `Validate ${n.replace(/^VAL_|^Validate|^Check/i, '').replace(/_/g, ' ')}`;
  if (/^CAL_|^Calculate/i.test(n))             return `Calculate ${n.replace(/^CAL_|^Calculate/i, '').replace(/_/g, ' ')}`;
  if (/^SUB_|^sub/i.test(n))                   return `Sub-routine: ${n.replace(/^SUB_|^sub/i, '').replace(/_/g, ' ')}`;
  if (/Reject|Remand|Approve|Submit/i.test(n)) return `Workflow action: ${n.replace(/_/g, ' ')}`;
  return `Logic: ${n.replace(/_/g, ' ')}`;
}

// Mechanical, evidence-based detection of behavioral facts that a domain-model-only or
// signature-only read would miss. Deliberately generic (works for any Java/Spring source, not
// hand-tuned to one pilot app) — anything more specific than this belongs in human/Claude
// review, not baked into the mapper as a hardcoded pattern. Every entry must cite evidence.
function detectHiddenRules(l) {
  const rules = [];
  const callNames = (l.calls || []).map(c => c.name || '');

  for (const exc of (l.throwsExceptions || [])) {
    rules.push({
      rule: `May throw ${exc} — review the guarding condition to confirm when this triggers.`,
      evidence: l.sourceRef || l._source || '',
      risk: 'medium',
    });
  }

  // PUT handler that falls back to creating a record when not found = upsert-on-PUT, not the
  // "404 if missing" behavior a REST client would typically assume from a PUT endpoint.
  if (l.httpEndpoint?.method === 'PUT' && callNames.includes('orElseGet')) {
    rules.push({
      rule: 'PUT endpoint upserts: creates a new record if the target id is not found, rather than returning 404.',
      evidence: l.sourceRef || l._source || '',
      risk: 'high',
    });
  }

  // Two or more distinct repository delete-shaped calls in one method body = cascade-delete
  // implemented in application code, not a declarative DB/ORM cascade.
  const deleteCalls = [...new Set(callNames.filter(n => /Repository\.delete/i.test(n)))];
  if (deleteCalls.length > 1) {
    rules.push({
      rule: `Deletes across multiple repositories in one operation (${deleteCalls.join(', ')}) — cascade behavior is implemented in code, not a declarative DB/ORM cascade.`,
      evidence: l.sourceRef || l._source || '',
      risk: 'high',
    });
  }

  return rules;
}

function mapMicroflows(logics) {
  return logics.map(l => ({
    name:        l.name,
    kind:        KIND_LABEL[l.logicKind] || l.logicKind,
    isPublic:    l.isPublic || false,
    purpose:     inferPurpose(l.name, l.description),
    httpEndpoint: l.httpEndpoint || null,
    parameters: {
      in:  (l.inputParameters  || []).map(p => ({ name: p.name, type: p.type, isMandatory: p.isMandatory })),
      out: (l.outputParameters || []).map(p => ({ name: p.name, type: p.type })),
    },
    callCount:        (l.calls     || []).length,
    aggregateCount:   (l.aggregates|| []).length,
    calledActions:    (l.calls     || []).slice(0, 5).map(c => c.name || c.resolvedName || '').filter(Boolean),
    isBPTProcess:     l.logicKind === 'process',
    hiddenRules:      detectHiddenRules(l),
    gaps:             l._gaps || [],
  }));
}

module.exports = { mapMicroflows };
