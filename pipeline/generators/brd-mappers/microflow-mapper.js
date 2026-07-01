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

function mapMicroflows(logics) {
  return logics.map(l => ({
    name:        l.name,
    kind:        KIND_LABEL[l.logicKind] || l.logicKind,
    isPublic:    l.isPublic || false,
    purpose:     inferPurpose(l.name, l.description),
    parameters: {
      in:  (l.inputParameters  || []).map(p => ({ name: p.name, type: p.type, isMandatory: p.isMandatory })),
      out: (l.outputParameters || []).map(p => ({ name: p.name, type: p.type })),
    },
    callCount:        (l.calls     || []).length,
    aggregateCount:   (l.aggregates|| []).length,
    calledActions:    (l.calls     || []).slice(0, 5).map(c => c.name || c.resolvedName || '').filter(Boolean),
    isBPTProcess:     l.logicKind === 'process',
    gaps:             l._gaps || [],
  }));
}

module.exports = { mapMicroflows };
