#!/bin/zsh
[ -n "${BASH_VERSION:-}" ] && exec zsh "$0" "$@"  # a zsh script: `bash script.sh` re-runs it under zsh (E6-1)
# pds_oldnames.sh <ver> <mpr> [design-properties.json ...]: run `mx rename-design-properties` with the property-level
# oldNames of internal design systems hidden, then restore those files byte for byte (E7-5, E5 F16).
#
# Why: an internal design system (the platform design system module of the app, under themesource/<module>/web/) can
# map a whole property to an old name ("Margin top" <- "Spacing top"). That mapping shadows the value-level oldNames
# Atlas_Core 3.20 ships ("Spacing top::Outer small" -> the compound Spacing value), and the rename then writes values
# that do not exist: 142 CE6085 in E5 and again in E7. Without the property-level mapping the rename takes Atlas's
# value-level route and the CE6085 flood does not happen.
#
#   <ver>   mxbuild toolset for mx10.sh (9.* selects mx9.sh)
#   <mpr>   the app .mpr (relative paths resolve against the current directory; the design-properties files resolve
#           against the .mpr's directory)
#   files   default: every themesource/*/web/design-properties.json except atlas_core's that declares property-level
#           oldNames
# Meant as the fixer of design_props_guard.sh, so it runs on the guard's copy and the result is only kept when mx check
# is not worse:
#   design_props_guard.sh <app> 10.24.16 --fixed CE6087 -- $B/repair/pds_oldnames.sh 10.24.16 APP
# Exit: the rename's exit code; 3 = a file could not be restored byte for byte (the backup path is printed);
#       2 = usage error. Env: UPG_PDS_MX replaces mx10.sh / mx9.sh (same arguments; used by the controls).
here=${0:A:h:h}
[[ $# -ge 2 ]] || { sed -n '2,24p' $0 | sed 's/^# \{0,1\}//'; exit 2; }
ver=$1 mpr=${2:A}; shift 2
[[ -f $mpr ]] || { echo "pds_oldnames: no file $mpr" >&2; exit 2; }
app=${mpr:h}
files=()
if [[ $# -gt 0 ]]; then
  for f in "$@"; do [[ $f == /* ]] && files+=($f) || files+=($app/$f); done
else
  for f in $app/themesource/*/web/design-properties.json(N); do
    [[ ${f:h:h:t} == atlas_core ]] && continue
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if any("oldNames" in q for ps in d.values() if isinstance(ps, list) for q in ps if isinstance(q, dict)) else 1)' $f 2>/dev/null && files+=($f)
  done
fi
mx=$here/mx10.sh; [[ $ver == 9.* ]] && mx=$here/mx9.sh
mx=${UPG_PDS_MX:-$mx}
bak=$(mktemp -d "${TMPDIR:-/tmp}/pds-oldnames.XXXXXX")
restore() {
  local bad=0 i=0
  for f in $files; do
    i=$((i + 1)); cp -p $bak/$i.json $f && cmp -s $bak/$i.json $f || { echo "pds_oldnames: RESTORE FAILED for $f (backup $bak/$i.json)" >&2; bad=1; }
  done
  [[ $bad == 0 ]] && rm -rf $bak
  return $bad
}
i=0
for f in $files; do
  [[ -f $f ]] || { echo "pds_oldnames: no file $f" >&2; rm -rf $bak; exit 2; }
  i=$((i + 1)); cp -p $f $bak/$i.json
done
trap 'restore; exit 3' INT TERM
for f in $files; do
  python3 - $f <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); n = []
for widget, props in d.items():
    for q in props if isinstance(props, list) else []:
        if isinstance(q, dict) and "oldNames" in q:
            n.append(f"{q.get('name')} <- {', '.join(q['oldNames']) if isinstance(q['oldNames'], list) else q['oldNames']}")
            del q["oldNames"]
json.dump(d, open(p, "w"), indent=2)
print(f"hidden {len(n)} property-level oldNames in {p}" + "".join(f"\n   {x}" for x in n[:12]))
PY
done
[[ ${#files} == 0 ]] && echo "no internal design system declares property-level oldNames: the rename runs unchanged"
$mx $ver mx rename-design-properties $mpr; rc=$?
trap - INT TERM
restore || exit 3
echo "restored ${#files} design-properties file(s) byte for byte; rename rc $rc"
exit $rc
