# own-modules.awk — print the own modules of a `mxcli list modules` capture, one per line.
#   awk -F'|' -f lib/own-modules.awk list-modules.txt
# Own module = empty Source column (Marketplace modules carry "Marketplace vX"), System excluded.
# Rows are the table lines after the `|---` separator, so a leading WARNING / "Connected to:" line
# and the trailing "(N modules)" line are skipped whether or not they are present.
# Golden input: tests/wave2/fixtures/rehost-list-modules/ (verbatim mxcli v0.25.0 and v0.26.0).
/^\|-/ { body = 1; next }
body && NF > 3 {
  name = $2; src = $3
  gsub(/ /, "", name); gsub(/ /, "", src)
  if (src == "" && name != "System" && name != "") print name
}
