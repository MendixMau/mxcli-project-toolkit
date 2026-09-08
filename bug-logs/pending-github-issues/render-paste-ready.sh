#!/usr/bin/env bash
# render-paste-ready.sh — turn every NOT-YET-FILED draft in this directory into a file a
# human can paste straight into https://github.com/mendixlabs/mxcli/issues/new.
#
# Why: the drafts carry a local header (Repo/Source/Status/labels) above a `---` rule that
# must never reach GitHub, and two draft shapes exist (`**Title:**`+`**Body:**` markers, or a
# plain `# H1`). Stripping by hand is how a half-redacted header shipped once. This does it
# mechanically and writes an index with the filing order.
#
#   bash render-paste-ready.sh            # writes paste-ready/<NN>-<slug>.md + INDEX.md
#
# Output line 1 is the issue title (paste into the Title box); everything after the blank
# line is the body. Drafts whose Status line says FILED are skipped. POSIX awk + coreutils.
set -eu
cd "$(dirname "$0")"
OUT=paste-ready
rm -rf "$OUT"; mkdir -p "$OUT"
n=0
INDEX="$OUT/INDEX.md"
{
  echo "# Paste-ready mxcli issues — $(date +%Y-%m-%d)"
  echo
  echo "One file per issue. Line 1 = title, rest = body. File in this order (worst first)."
  echo "After filing, write the issue URL back into the draft's **Status:** line and into"
  echo "\`bug-logs/mxcli-bugs.md\`, then re-run this script."
  echo
  echo "| # | File | Suggested labels | Duplicate check |"
  echo "|---|---|---|---|"
} > "$INDEX"
# Filing order: explicit, worst first. Anything not listed renders after these, alphabetically.
ORDER="bug76-workflow-decision-enum-identifier
bug107-workflow-call-with-unquoted-value-segfault
bug109-jump-to-in-boundary-event-writes-targetless-jump
create-association-corrupts-mpr
bug102-alter-page-set-datasource-datagrid-silent-noop
bug84-alter-page-dataview-database-wipe
exec-non-transactional-silent-skip
bug70-95-show-page-arg-rebound-currentobject
bug104-quoted-parameter-keeps-dollar-sigil
bug106-widget-names-burned-after-rollback
bug112-mxcli-new-path-too-long-hangs
bug100-docker-init-compose-project-name
bug73-raise-error-main-flow-ce0710
bug67-snippet-primitive-param
bug86-nanoflow-devicetype-write-barrier
gallery-widget-ce0463-survives-regeneration
widget-init-docs-do-not-parse
bug87-describe-java-action-type-param-name
bug63-write-lint-rules-fictional-values
bug82-calculated-attribute-not-wired
feature-mxcli-doctor
feature-mxcli-new-teamserver-app"
list() {
  for s in $ORDER; do [ -f "$s.md" ] && echo "$s.md"; done
  for f in *.md; do
    printf '%s\n' $ORDER | grep -qx "${f%.md}" || echo "$f"
  done
}
for f in $(list); do
  case "$f" in INDEX.md|README.md) continue ;; esac
  if grep -q '^\*\*Status:\*\*.*FILED —' "$f"; then continue; fi
  n=$((n+1)); nn=$(printf '%02d' "$n")
  slug="${f%.md}"
  labels=$(grep -m1 '^\*\*Suggested labels:\*\*' "$f" | sed 's/^\*\*Suggested labels:\*\* *//' || true)
  dup=$(grep -m1 '^\*\*Duplicate check:\*\*' "$f" | sed 's/^\*\*Duplicate check:\*\* *//' || true)
  awk '
    BEGIN{hdr=1; title=""; body=0}
    hdr && /^---[[:space:]]*$/ {hdr=0; next}
    hdr {next}
    /^\*\*Title:\*\*/ && title=="" {t=$0; sub(/^\*\*Title:\*\*[[:space:]]*/,"",t); title=t; intitle=1; next}
    intitle && /^\*\*Body:\*\*/ {intitle=0; body=1; print title; print ""; next}
    intitle {if ($0 ~ /^[[:space:]]*$/) next; title=title " " $0; next}
    /^# / && title=="" {t=$0; sub(/^# /,"",t); title=t; body=1; print title; print ""; next}
    body {print}
  ' "$f"  > "$OUT/$nn-$slug.md"
  title=$(head -1 "$OUT/$nn-$slug.md")
  echo "| $nn | \`$nn-$slug.md\` | ${labels:-bug} | ${dup:-see draft} |" >> "$INDEX"
  printf '%s  %s\n' "$nn" "$title" | cut -c1-120
done
echo "rendered $n issues into $OUT/"
