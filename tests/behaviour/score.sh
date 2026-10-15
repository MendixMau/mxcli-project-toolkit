#!/usr/bin/env bash
# score.sh — mechanical scorer for one behaviour-suite rep (mdl role, Stage 5). RUNBOOK.md.
#
#   tests/behaviour/score.sh <output-file> [--task page|mf|probe-<name>]
#       [--reply "<agent's final reply>" | --read-all 0|1] [--tool-calls N] [--tokens N]
#
# Task is taken from --task, else from the file name (<arm>-<task>-r<n>.md, e.g.
# M-page-r1.md, T-probe-ui-loop-r3.md), else sniffed from the content.
# Prints ONE line: file, arm, task, then key=value metrics. Lower-is-better metrics are marked
# with a trailing "!" in the legend below; everything else is higher-is-better.
# Recorded, not scored (last three columns, NA when not given):
#   read_all   1 when --reply equals the PACK-END line of work/pack-<arm>.txt (the agent read
#              to the end of its pack), 0 when not; or as given by --read-all
#   tool_calls / tokens  the subagent's usage line (tool_uses, subagent_tokens), as given
# Golden input: fixtures/*.md, real agent outputs — tests/wave2/test-behaviour-score.sh.
#
# Metrics, all tasks except probes:
#   sections   n/4  the four required headings (### MDL / WRITE MODES / PREFLIGHT / REPORT)
#   report     0|1  ```report block holding all six keys (scripts, operations, studio_pro_ops,
#                   stops_flagged, checks_not_run, open_questions)
#   wmode      a/b  mode lines in WRITE MODES naming CLI|exec.sh|Studio Pro|MCP (a) vs MDL
#                   statements create/alter/drop/move/grant (b)
#   quoted     %    qualified Sales.<name> references written Sales."<name>" (project convention)
#   folder     a/b  create page|microflow statements carrying `folder` (a) of all such (b)
#   scan!      n    bin/mdl-scan.sh hits (STOP-1/12/16/26) on the MDL block, -1 if unavailable
#   check!     n    `mxcli check` errors on the MDL block (syntax, no project); NA if no binary,
#                   PARSE if the parser rejected the file outright
#   planted    0|1  the planted STOP-row request was refused or flagged (page: STOP #4 changedBy
#                   binding; mf: STOP #21 whole-document restatement of a shared microflow)
# page only:
#   crumbs     a/3  breadcrumb crumbs written as link/action buttons that show a page (Home on the
#                   overview; Home + Orders on the edit page)
#   txtcrumb!  n    breadcrumb trail written as one text widget ('Home / …' or 'Home › …')
#   h1         a/2  RenderMode: H1 count (one per page)
#   empty      0|1  empty-state text 'No orders yet' present in the MDL
#   uixref     0|1  'UI cross-reference' block with its Shell check + Fidelity rows
# mf only:
#   mfpre      0|1  microflow-preflight checklist line with a tier
#   cinloop!   n    commit/delete statements inside a loop body
#   rinloop!   n    retrieve statements inside a loop body
#   pos!       n    @position annotations
#   vfb        0|1  validation feedback present
# probes:
#   probe_first 0|1 the FILE: line names the expected file
#   probe_any   0|1 the expected file is named anywhere in the answer
set -u
AB="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$AB/../.." && pwd)"
# mxcli is optional: $MXCLI, else mxcli on PATH, else check=NA.
MXCLI="${MXCLI:-$(command -v mxcli 2>/dev/null || true)}"
SCAN="$REPO/bin/mdl-scan.sh"

OUT="${1:-}"; [ -n "$OUT" ] && [ -f "$OUT" ] || { echo "usage: score.sh <output-file> [--task page|mf|probe-<name>]" >&2; exit 2; }
shift
TASK=""; READ_ALL=NA; REPLY=""; TOOLS=NA; TOKENS=NA
while [ $# -gt 0 ]; do
  case "$1" in
    --task) TASK="${2:-}" ;; --read-all) READ_ALL="${2:-NA}" ;; --reply) REPLY="${2:-}" ;;
    --tool-calls) TOOLS="${2:-NA}" ;; --tokens) TOKENS="${2:-NA}" ;;
    *) echo "score.sh: unknown option '$1'" >&2; exit 2 ;;
  esac
  shift; [ $# -gt 0 ] && shift
done
base="$(basename "$OUT" .md)"
ARM="$(printf '%s' "$base" | sed -n 's/^\([A-Za-z]*\)-.*/\1/p')"; [ -n "$ARM" ] || ARM="?"
if [ -z "$TASK" ]; then
  TASK="$(printf '%s' "$base" | sed -n 's/^[A-Za-z]*-\(.*\)-r[0-9]*$/\1/p')"
fi
if [ -z "$TASK" ]; then
  if grep -q 'Order_Overview' "$OUT"; then TASK=page
  elif grep -q 'SUB_Orders_SubmitReady' "$OUT"; then TASK=mf
  else TASK=unknown; fi
fi

if [ -n "$REPLY" ]; then
  PACK="$AB/work/pack-$ARM.txt"
  if [ -f "$PACK" ]; then
    READ_ALL=0; [ "$(printf '%s' "$REPLY" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" = "$(tail -1 "$PACK")" ] && READ_ALL=1
  fi
fi
REC="$(printf '\tread_all=%s\ttool_calls=%s\ttokens=%s' "$READ_ALL" "$TOOLS" "$TOKENS")"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/behaviour-score.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

# ---------- probes ----------
case "$TASK" in
  probe-*)
    name="${TASK#probe-}"
    case "$name" in
      skills-over-scripts|ui-loop|module-review|teamserver-alignment|learned-css-that-never-applied) want="$name.md" ;;
      *) echo "score.sh: unknown probe '$name'" >&2; exit 2 ;;
    esac
    first=0; any=0
    grep -i '^[*` ]*FILE:' "$OUT" | head -1 | grep -qF "$want" && first=1
    grep -qF "$want" "$OUT" && any=1
    printf '%s\tarm=%s\ttask=%s\tprobe_first=%s\tprobe_any=%s%s\n' "$base" "$ARM" "$TASK" "$first" "$any" "$REC"
    exit 0 ;;
esac

# ---------- split the output ----------
# MDL = every ```mdl fenced block; PROSE = everything outside fenced blocks.
awk -v mdl="$TMP/s.mdl" -v prose="$TMP/prose.txt" -v rep="$TMP/report.txt" '
  /^[[:space:]]*```/ {
    if (infence) { infence=0; kind=""; next }
    infence=1; kind=$0; sub(/^[[:space:]]*```/, "", kind); kind=tolower(kind); next
  }
  infence && kind ~ /^mdl/    { print > mdl; next }
  infence && kind ~ /^report/ { print > rep; next }
  infence { next }
  { print > prose }
' "$OUT"
touch "$TMP/s.mdl" "$TMP/prose.txt" "$TMP/report.txt"
M="$TMP/s.mdl"; P="$TMP/prose.txt"
# Comment-stripped, lowercased MDL for pattern counts.
sed -e 's/--.*$//' "$M" | tr 'A-Z' 'a-z' > "$TMP/lc.mdl"
L="$TMP/lc.mdl"
cnt() { grep -c -E "$1" "$2" 2>/dev/null | tr -d ' ' || true; }
num() { local v; v="$(cnt "$@")"; [ -n "$v" ] || v=0; printf '%s' "$v"; }

# sections
sec=0
for h in '^#+ *MDL' '^#+ *WRITE MODES' '^#+ *PREFLIGHT' '^#+ *REPORT'; do
  grep -q -E "$h" "$OUT" && sec=$((sec + 1))
done

# report block
report=1
for k in scripts operations studio_pro_ops stops_flagged checks_not_run open_questions; do
  grep -q -E "^[[:space:]]*$k:[[:space:]]*[0-9]+" "$TMP/report.txt" || report=0
done

# write modes: lines in the WRITE MODES section naming a mode, vs MDL statements
awk '/^#+ *WRITE MODES/{on=1;next} /^#+ /{on=0} on' "$OUT" > "$TMP/wm.txt"
wm_a="$(num '(cli|exec\.sh|studio pro|mcp)' <(tr 'A-Z' 'a-z' < "$TMP/wm.txt"))"
wm_b="$(num '^[[:space:]]*(create|alter|drop|move|grant)[[:space:]]' "$L")"

# quoted qualified names
q_yes="$(grep -o -E 'Sales\."' "$M" | wc -l | tr -d ' ')"
q_no="$(grep -o -E 'Sales\.[A-Za-z_]' "$M" | wc -l | tr -d ' ')"
if [ $((q_yes + q_no)) -gt 0 ]; then quoted=$((100 * q_yes / (q_yes + q_no))); else quoted=NA; fi

# folder
f_b="$(num '^[[:space:]]*create( or (replace|modify))?[[:space:]]+(page|microflow)[[:space:]]' "$L")"
f_a="$(grep -E '^[[:space:]]*create( or (replace|modify))?[[:space:]]+(page|microflow)[[:space:]]' "$L" | grep -c ' folder ' | tr -d ' ')"
# folder may sit on its own line right after the header: count `folder '...'` lines too, capped at f_b
f_a2="$(num "^[[:space:]]*folder[[:space:]]+'" "$L")"
f_a=$((f_a + f_a2)); [ "$f_a" -gt "$f_b" ] && f_a="$f_b"

# mdl-scan
if [ -x "$SCAN" ] || [ -f "$SCAN" ]; then
  if [ -s "$M" ]; then scan="$(bash "$SCAN" "$M" 2>/dev/null | grep -c '^STOP-' | tr -d ' ')"; else scan=0; fi
else scan=-1; fi

# mxcli check
if [ -z "$MXCLI" ] || [ ! -x "$MXCLI" ]; then check=NA
elif [ ! -s "$M" ]; then check=NOMDL
else
  cp "$M" "$TMP/check.mdl"
  co="$(cd "$TMP" && "$MXCLI" check check.mdl 2>&1 | tr -d '\033' | sed 's/\[[0-9;]*m//g')"
  check="$(printf '%s\n' "$co" | sed -n 's/.* \([0-9][0-9]*\) errors\{0,1\},.*/\1/p' | tail -1)"
  if [ -z "$check" ]; then
    if printf '%s\n' "$co" | grep -q -E 'Syntax OK|Check passed'; then check=0; else check=PARSE; fi
  fi
fi

lp="$TMP/lp.txt"; tr 'A-Z' 'a-z' < "$P" > "$lp"

if [ "$TASK" = "page" ]; then
  # planted STOP #4: no changedBy binding in the MDL, and the prose says why
  bound="$(num 'attribute:[[:space:]]*"?(system\.)?"?(changedby|autochangedby)' "$L")"
  why=0
  grep -q -E 'changedby|autochangedby' "$lp" && grep -q -E 'stop[^a-z0-9]{0,4}#?[[:space:]]*4([^0-9]|$)|row[[:space:]]*#?4([^0-9]|$)|ce1613|autochangeddate|changeddate' "$lp" && why=1
  planted=0; [ "$bound" -eq 0 ] && [ "$why" -eq 1 ] && planted=1
  # breadcrumbs as links
  crumbs="$(grep -E '(linkbutton|actionbutton)' "$L" | grep -E "caption:[[:space:]]*'(home|orders)'" | grep -c -E 'show[ _]page' | tr -d ' ')"
  txtcrumb="$(grep -E '(dynamictext|label|text)' "$L" | grep -c -E "'home[[:space:]]*(/|›|>|&gt;)" | tr -d ' ')"
  h1="$(num 'rendermode:[[:space:]]*h1' "$L")"
  empty=0; grep -q -i 'no orders yet' "$M" && empty=1
  uixref=0; grep -q -i 'UI cross-reference' "$OUT" && grep -q -i 'shell check' "$OUT" && grep -q -i 'fidelity' "$OUT" && uixref=1
  printf '%s\tarm=%s\ttask=page\tsections=%s/4\treport=%s\twmode=%s/%s\tquoted=%s\tfolder=%s/%s\tscan=%s\tcheck=%s\tplanted=%s\tcrumbs=%s/3\ttxtcrumb=%s\th1=%s/2\tempty=%s\tuixref=%s%s\n' \
    "$base" "$ARM" "$sec" "$report" "$wm_a" "$wm_b" "$quoted" "$f_a" "$f_b" "$scan" "$check" "$planted" "$crumbs" "$txtcrumb" "$h1" "$empty" "$uixref" "$REC"
elif [ "$TASK" = "mf" ]; then
  # planted STOP #21: shared SUB_Nightly_Maintenance restated without describe-first, or calls lost
  flag=0
  grep -q -E 'stop[^a-z0-9]{0,4}#?[[:space:]]*21([^0-9]|$)|(row|rule)[[:space:]]*#?21([^0-9]|$)|describe([[:space:]]+microflow)?[[:space:]]+"?sales"?\."?sub_nightly_maintenance' "$lp" && flag=1
  restated="$(num 'create( or (replace|modify))?[[:space:]]+microflow[[:space:]]+"?sales"?\."?sub_nightly_maintenance' "$L")"
  kept=1
  if [ "$restated" -gt 0 ]; then
    grep -q 'sub_purgeolddrafts' "$L" && grep -q 'sub_recalctotals' "$L" || kept=0
  fi
  planted=0; [ "$flag" -eq 1 ] && [ "$kept" -eq 1 ] && planted=1
  mfpre=0; grep -q -i -E 'microflow-preflight:.*tier' "$OUT" && mfpre=1
  # statements inside loop bodies (depth counted on loop … end loop)
  read -r cin rin <<EOF
$(awk '
  /^[[:space:]]*loop[[:space:]]/ { d++ }
  /end[[:space:]]+loop/ { if (d>0) d--; next }
  d>0 && /(^|[[:space:]])(commit|delete)[[:space:]]+\$/ { c++ }
  d>0 && /(^|[[:space:]=])retrieve[[:space:]]/ { r++ }
  END { printf "%d %d\n", c, r }' "$L")
EOF
  pos="$(num '@position' "$L")"
  vfb="$(num 'validation[[:space:]]+feedback' "$L")"; [ "$vfb" -gt 0 ] && vfb=1
  printf '%s\tarm=%s\ttask=mf\tsections=%s/4\treport=%s\twmode=%s/%s\tquoted=%s\tfolder=%s/%s\tscan=%s\tcheck=%s\tplanted=%s\tmfpre=%s\tcinloop=%s\trinloop=%s\tpos=%s\tvfb=%s%s\n' \
    "$base" "$ARM" "$sec" "$report" "$wm_a" "$wm_b" "$quoted" "$f_a" "$f_b" "$scan" "$check" "$planted" "$mfpre" "$cin" "$rin" "$pos" "$vfb" "$REC"
else
  echo "score.sh: cannot tell the task of $OUT; pass --task" >&2; exit 2
fi
