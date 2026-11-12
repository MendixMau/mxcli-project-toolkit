#!/bin/bash
# convertmade.sh: tell whether a module's "local edits" can only have come from mx convert (E6-13, T1-15, T4-3, T7-12).
#
#   convertmade.sh <app dir> <Module> [rev] [--localedits <pre-convert localedits.json>]     (rev: default HEAD)
#
# Run E6: the pre pass installed GoogleAuthenticator 2.3.0 and Atlas_NativeMobile_Content 3.1.0 pristine, then mx
# convert rewrote their pages, then the post pass refused both updates ("1 element(s) have been changed locally",
# "22 element(s) could not be read"). No person had touched them: the differences were the convert's own rewrite.
# Batch 1 (T1, T3, T4, T5, T7, T8): a 9.x source can never have a pristine "step:" commit before the convert (9.24 has
# no module-import, the playbook converts first), nor can a 10.x run that skipped the pre-convert pass. The convert's
# own rewrites (@curve geometry, JAVA_ACTION parameter metadata, JAR_DEPENDENCY rows, a widget app id) then read as LOCAL.
#
# Neutral commits (cannot hold a person's edit to a module), in both modes:
#   subject "step: " (a module step), "convert" (mx convert), "stepupdate: " (its .gitignore commit);
#   subject "build:" (regenerated stubs) when it does not touch the model (*.mpr, mprcontents/);
#   any subject when every file it changes is .gitignore or under userlib/ or vendorlib/ (jar cleanup, tool ignores).
# CONVERT-MADE (exit 0), mode 1 (pristine step):
#   - a commit "step: <Module> <version> ..." exists (stepupdate installed the package pristine, idcheck PASS)
#   - every commit after the last such commit, up to rev, is neutral, and at least one is a convert commit
# CONVERT-MADE (exit 0), mode 2 (pre-convert localedits; only when there is NO "step: <Module>" commit):
#   - every commit from the original commit (the oldest subject starting with "original", else the root commit) up to
#     rev is neutral, and at least one is a convert commit
#   - --localedits names the module with the domain layer unchanged (no rows at all), 0 UI and 0 logic lines,
#     compared with the installed version itself (not a --proxy), AND its element layer present (the report ran
#     with --mxcli-diff): verified, 0 modified, nothing only in the app but JAR_DEPENDENCY rows. The offline layers
#     alone compare no contents (a microflow body or page edit is invisible), so without --mxcli-diff it is LOCAL.
# LOCAL (exit 1) otherwise, with the reason. Exit 2 = input error. Read only: git log and the JSON, nothing else.
set -u
pos=(); le=""
while [ $# -gt 0 ]; do
  case "$1" in
    --localedits) [ $# -ge 2 ] || { echo "convertmade: --localedits needs a file" >&2; exit 2; }; le=$2; shift 2;;
    *) pos+=("$1"); shift;;
  esac
done
[ ${#pos[@]} -ge 2 ] || { sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
app=${pos[0]} mod=${pos[1]} rev=${pos[2]:-HEAD}
git -C "$app" rev-parse --verify -q "$rev^{commit}" > /dev/null || { echo "convertmade: $app: no commit $rev" >&2; exit 2; }
[ -z "$le" ] || [ -f "$le" ] || { echo "convertmade: no localedits file $le" >&2; exit 2; }

# neutral_list RANGE: print the non-neutral commits ("<hash> <subject>") of RANGE, one per line
neutral_list() {
  git -C "$app" log --format='%h %s' "$1" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    h=${line%% *} s=${line#* }
    case "$s" in "step: "*|convert*|"stepupdate: "*) continue;; esac
    files=$(git -C "$app" diff-tree --no-commit-id --name-only -r "$h")
    case "$s" in "build:"*)
      echo "$files" | grep -Eq '(\.mpr$|^mprcontents/)' || continue
      echo "$line  [build commit changes the model]"; continue;;
    esac
    if [ -n "$files" ] && ! echo "$files" | grep -Ev '^(\.gitignore$|userlib/|vendorlib/)' | grep -q .; then continue; fi
    echo "$line"
  done
}

step=$(git -C "$app" log --format='%H %s' "$rev" | awk -v m="$mod" '$2 == "step:" && $3 == m {print $1; exit}')
if [ -n "$step" ]; then
  other=$(neutral_list "$step..$rev")
  if [ -n "$other" ]; then
    echo "LOCAL: after the pristine install of $mod ($(git -C "$app" log -1 --format='%h %s' "$step")) these commits may hold edits:"
    echo "$other" | head -8 | sed 's/^/   /'
    exit 1
  fi
  after=$(git -C "$app" log --format='%h %s' "$step..$rev")
  conv=$(echo "$after" | grep -E '^[0-9a-f]+ convert' | head -1)
  if [ -z "$conv" ]; then
    echo "LOCAL: no convert commit after the pristine install of $mod; the differences are not convert-made"; exit 1
  fi
  echo "CONVERT-MADE: $mod was installed pristine at $(git -C "$app" log -1 --format='%h %s' "$step"); since then only step, convert, build and jar commits ($(echo "$after" | grep -c .), convert: ${conv%% *})"
  exit 0
fi

# mode 2: no step commit; the pre-convert localedits run is the pristine proof
if [ -z "$le" ]; then
  echo "LOCAL: no 'step: $mod' commit before $rev, so the installed $mod was never shown pristine"
  echo "   (a 9.x source or a 10.x run without the pre-convert pass: give --localedits <pre-convert localedits.json>)"
  exit 1
fi
orig=$(git -C "$app" log --reverse --format='%H %s' "$rev" | awk 'tolower($2) ~ /^original/ {print $1; exit}')
[ -n "$orig" ] || orig=$(git -C "$app" rev-list --max-parents=0 "$rev" | tail -1)
origs=$(git -C "$app" log -1 --format='%h %s' "$orig")
other=$(neutral_list "$orig..$rev")
if [ -n "$other" ]; then
  echo "LOCAL: no 'step: $mod' commit, and after the original commit ($origs) these commits may hold edits:"
  echo "$other" | head -8 | sed 's/^/   /'
  exit 1
fi
after=$(git -C "$app" log --format='%h %s' "$orig..$rev")
conv=$(echo "$after" | grep -E '^[0-9a-f]+ convert' | head -1)
if [ -z "$conv" ]; then
  echo "LOCAL: no convert commit after the original commit ($origs); the differences in $mod are not convert-made"; exit 1
fi
verdict=$(python3 - "$le" "$mod" <<'PY'
import json, sys
try:
    rep = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"ERROR {sys.argv[1]}: not a localedits.py --json file ({e})"); sys.exit(2)
if not isinstance(rep, list):
    print(f"ERROR {sys.argv[1]}: not a localedits.py --json file (no module list)"); sys.exit(2)
e = next((x for x in rep if isinstance(x, dict) and x.get("name") == sys.argv[2]), None)
if e is None:
    print("not in the localedits report: never judged"); sys.exit(1)
why = []
if e.get("domain") is None:
    why.append("UNKNOWN (package not readable)")
else:
    if e["domain"]: why.append(f"{len(e['domain'])} domain rows")
    if e.get("ui") is None or e.get("logic") is None: why.append("UI or logic layer not compared")
    if e.get("ui"): why.append(f"{len(e['ui'])} UI lines")
    if e.get("logic"): why.append(f"{len(e['logic'])} logic lines")
    if e.get("compared_with") not in (None, e.get("version")):
        why.append(f"compared with a proxy ({e['compared_with']}), not the installed {e.get('version')}")
    # The offline layers do not compare CONTENTS: logic is "document present on one side only", UI is "page
    # added/removed or layout changed". A person's edit inside a microflow, page or Java action is invisible to them,
    # and --force would discard it. Only the element layer (--mxcli-diff) compares contents, so it is required here.
    el = e.get("elements")
    if not isinstance(el, dict) or e.get("elements_error"):
        why.append("element contents not compared (the report ran without --mxcli-diff, or the diff failed: "
                   "microflow, page and Java action edits are invisible to the offline layers)")
    else:
        if el.get("verified") is False:
            why.append(f"mxcli-diff verified=false ({len(el.get('unknown') or [])} elements not describable)")
        if el.get("modified"):
            why.append(f"{len(el['modified'])} mxcli-diff modified elements")
        only = [x for x in (el.get("onlyInstalled") or []) if not str(x).startswith("JAR_DEPENDENCY")]
        if only:
            why.append(f"{len(only)} mxcli-diff elements only in the app")
if why:
    print("; ".join(why)); sys.exit(1)
print(f"{e.get('version')}: domain model unchanged, 0 UI lines, 0 logic lines, mxcli-diff 0 modified elements")
PY
)
vrc=$?
[ $vrc = 2 ] && { echo "convertmade: $verdict" >&2; exit 2; }
if [ $vrc != 0 ]; then
  echo "LOCAL: no 'step: $mod' commit, and the pre-convert localedits ($le) does not show $mod clean: $verdict"; exit 1
fi
echo "CONVERT-MADE: $mod has no step commit; source: pre-convert localedits ($le) shows $mod $verdict; since the original commit ($origs) only step, convert, build and jar commits ($(echo "$after" | grep -c .), convert: ${conv%% *})"
exit 0
