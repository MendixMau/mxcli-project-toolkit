#!/usr/bin/env bash
# grade.sh — run 2, real artifacts. Markers come from the real USI theme module and brand guide
# and appear NOWHERE in either arm's project files (verified before the run).
# Negation-aware (run 1 defect): "NO company brain is wired" must not score as a hit.
W="$(cd "$(dirname "$0")" && pwd)"
printf '%-13s %-7s %-7s %-7s %-7s %-9s %-8s %s\n' ARM MODULE PRIMARY BTNSTYL PALETTE DEVIATION ATLAS VERDICT
for f in "$W"/out/*.md; do
  [ -f "$f" ] || continue
  n="$(basename "$f" .md)"
  b="$(tr 'A-Z' 'a-z' < "$f")"
  bn="$(sed -E 's/(no|not|never|without|absent|missing|neither) [^.;]*//g' <<<"$b")"
  m_mod=0;  grep -q 'usi_theme_module\|usi theme module' <<<"$bn" && m_mod=1
  m_pri=0;  grep -q '#0c4c8a\|0c4c8a' <<<"$b" && m_pri=1
  m_btn=0;  grep -q 'usi-blue\|usi-red\|usi blue\|usi red' <<<"$b" && m_btn=1
  m_pal=0;  c=0; for h in '#e60012' '#ed6d0f' '#437242' '#24276c'; do grep -q "$h" <<<"$b" && c=$((c+1)); done; [ $c -ge 2 ] && m_pal=1
  # deviation understood: mentions the corporate blue AND does not adopt it as the primary
  m_dev=0
  if grep -q '002662' <<<"$b"; then
    grep -qE 'logo|print|corporate|not the (theme|ui|screen) primary|do not|deviat' <<<"$b" && m_dev=1
  fi
  # fell back to stock Atlas as THE answer
  ds="$(awk '/^## Design system/{f=1;next} /^## /{f=0} f' "$f" | tr 'A-Z' 'a-z')"
  dsn="$(sed -E 's/(no|not|never|without|rather than|instead of) [^.;,]*//g' <<<"$ds")"
  m_atl=0; grep -qE 'atlas (ui )?(defaults|core)|stock atlas|atlas_default' <<<"$dsn" && m_atl=1
  if [ "$m_mod" -eq 1 ] && [ "$m_pri" -eq 1 ]; then v=RETRIEVED
  elif [ "$m_mod" -eq 1 ]; then v=PARTIAL
  else v=MISSED; fi
  printf '%-13s %-7s %-7s %-7s %-7s %-9s %-8s %s\n' "$n" "$m_mod" "$m_pri" "$m_btn" "$m_pal" "$m_dev" "$m_atl" "$v"
done
cat <<'NOTE'

MODULE=named USI_Theme_Module  PRIMARY=#0C4C8A  BTNSTYL=usi-blue/usi-red design property
PALETTE=>=2 of the other real theme hexes  DEVIATION=cited #002662 as logo/print, not the UI primary
ATLAS=proposed stock Atlas as the answer.  RETRIEVED = module + primary colour.
NOTE
