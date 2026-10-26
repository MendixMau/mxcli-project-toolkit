#!/usr/bin/env bash
# score-baseline-adds.sh <name>  — mechanical score for one rep of the 2026-10-27 baseline-adds A/B
# (tasks/t511.md, t565.md, t567.md; results/2026-10-27-baseline-adds.tsv). <name> is
# <arm>-<task>-r<n>, e.g. T-565-r3. Expects, under AB_WORK (the run's scratch dir):
#   data/out/<name>.md        the agent's written answer
#   data/pack-<arm><task>.txt the pack it was given (its last line is the read-to-the-end token)
#   runs/<name>/result.json   `claude -p --output-format json` result
set -u
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; . "$TK/bin/lib/portable.sh"; require_py
NAME="$1"; ARM="${NAME%%-*}"; N="$(echo "$NAME" | cut -d- -f2)"
W="${AB_WORK:?set AB_WORK to the run scratch dir}"
DATA="$W/data"; OUT="$DATA/out/$NAME.md"; RJ="$W/runs/$NAME/result.json"
[ -f "$OUT" ] || { printf '%s\tarm=%s\ttask=t%s\tNO-OUTPUT\n' "$NAME" "$ARM" "$N"; exit 0; }
X="$(tr 'A-Z' 'a-z' < "$OUT")"
g() { printf '%s' "$X" | grep -qE "$1" && echo 1 || echo 0; }
read -r reply turns tok < <("$PY" -c '
import json,sys
j=json.load(open(sys.argv[1])); u=j.get("usage",{})
t=u.get("input_tokens",0)+u.get("cache_read_input_tokens",0)+u.get("cache_creation_input_tokens",0)+u.get("output_tokens",0)
print(repr(j.get("result","").strip()).replace(" ","_"), j.get("num_turns",0), t)' "$RJ" 2>/dev/null || echo "x 0 0")
last="$(tail -1 "$DATA/pack-$ARM$N.txt")"
ra=0; "$PY" -c 'import sys,ast; sys.exit(0 if ast.literal_eval(sys.argv[1].replace("_"," ")).strip()==sys.argv[2] else 1)' "$reply" "$last" 2>/dev/null && ra=1
case "$N" in
 565) back=$(g 'browser[- ]?back|back[- ]?button|`back`|"back"|navigate[s]? back|go(es|ing)? back|press(es|ing)? back|after back|back step|back-step')
      illegal=$(g 'illegal|560')
      fix=$(g 'rollback[^\n]{0,60}refresh')
      role=$(g 'as (the )?`?customer|least[- ]privileged|`?demo_customer')
      cites=$(g 'learned-detection-gaps')
      m="back=$back	illegal=$illegal	fix=$fix	role=$role	cites=$cites" ;;
 511) restart=$(g 'restart|new session|fresh session|start a new|reload(s|ed)? (the )?agents?|re-?open the session')
      gp=$(g 'general-purpose'); gpread=0; [ "$gp" = 1 ] && gpread=$(g 'read[^\n]{0,40}gate-agent\.md')
      ok=0; { [ "$restart" = 1 ] || [ "$gpread" = 1 ]; } && ok=1
      m="ok=$ok	restart=$restart	gpread=$gpread" ;;
 567) ret=$(g '!== ?false|returned (string|message|value)|return(s|ed)? a (string|message|defect)|return value|non-empty return|string is truthy|returns? (the )?(defect|error|failure) (string|message)')
      throw=$(g 'throw')
      runner=$(g 'journey-runner')
      cites=$(g 'testing-shape|false-green|#567')
      m="ret=$ret	throw=$throw	runner=$runner	cites=$cites" ;;
esac
printf '%s\tarm=%s\ttask=t%s\t%s\tread_all=%s\tturns=%s\ttokens=%s\n' "$NAME" "$ARM" "$N" "$m" "$ra" "$turns" "$tok"
