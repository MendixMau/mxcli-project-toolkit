#!/usr/bin/env bash
# grade.sh — mechanical scoring of the company-brain retrieval eval.
# Markers exist ONLY in the company brain; none appear in either arm's project files.
# Any hit is therefore proof the session reached the brain, not a lucky guess.
W="$(cd "$(dirname "$0")" && pwd)"
printf '%-13s %-9s %-9s %-9s %-9s %-9s %s\n' ARM RETRIEVED SNIPPET TOKENS MANIFEST SELFBUILT VERDICT
for f in "$W"/out/*.md; do
  [ -f "$f" ] || continue
  n="$(basename "$f" .md)"
  b="$(tr 'A-Z' 'a-z' < "$f")"
  ds="$(awk '/^## Design system/{f=1;next} /^## /{f=0} f' "$f" | tr 'A-Z' 'a-z')"
  m_name=0;  grep -q 'usidesignsystem' <<<"$b" && m_name=1   # name needs no negation guard: no control arm can invent it
  m_snip=0;  grep -q 'snippet_usipageheader\|snippet_usidatatable' <<<"$b" && m_snip=1
  m_tok=0;   grep -q 'usi-brand-primary\|usi-brand-ink\|usi-surface' <<<"$b" && m_tok=1
  # Negation-blind markers are worthless: a control session that says "NO company brain is wired"
  # scored a hit on the first run. Strip negated clauses before matching (found 2026-09-19).
  bn="$(sed -E 's/(no|not|never|without|absent|missing|neither) [^.;]*//g' <<<"$b")"
  dsn="$(sed -E 's/(no|not|never|without|rather than|instead of|neither) [^.;,]*//g' <<<"$ds")"
  m_man=0;   grep -q 'usi\.usidesignsystem\.md\|components/usi' <<<"$bn" && m_man=1
  # self-built: proposes creating a design system / ds.css / design-system.html as THE answer
  m_self=0
  grep -qE 'design/ds\.css|design-system\.html|build (a|the) design system|create (a|the) design system|design-artifacts' <<<"$dsn" && m_self=1
  if [ "$m_name" -eq 1 ] && [ "$m_snip" -eq 1 ]; then v=RETRIEVED
  elif [ "$m_name" -eq 1 ]; then v=PARTIAL
  else v=MISSED; fi
  printf '%-13s %-9s %-9s %-9s %-9s %-9s %s\n' "$n" "$m_name" "$m_snip" "$m_tok" "$m_man" "$m_self" "$v"
done
echo
echo "Markers are USIDesignSystem, SNIPPET_USIPageHeader/USIDataTable, --usi-brand-* tokens."
echo "They appear in the company brain only. RETRIEVED = named the module AND a snippet."
