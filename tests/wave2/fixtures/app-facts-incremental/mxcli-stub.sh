#!/usr/bin/env bash
# A stub mxcli for the app-facts incremental-sweep fixture and bench. It never reads the model:
#   --version         prints $STUB_VERSION (a change forces a full sweep)
#   graph-report      copies $PREP_DB to .mxcli/catalog.db and writes an empty report to -o
#   describe <qn>     appends <qn> to $DESCRIBE_LOG and prints stub-bodies/<qn>.mdl;
#                     exits 1 for any name listed in $STUB_FAIL (space-separated)
case "${1:-}" in
  --version) echo "${STUB_VERSION:-mxcli stub 1.0}" ;;
  graph-report)
    o=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && o="$2"; shift; done
    mkdir -p .mxcli && cp "$PREP_DB" .mxcli/catalog.db && echo '{}' > "$o" ;;
  describe)
    echo "$2" >> "$DESCRIBE_LOG"
    case " ${STUB_FAIL:-} " in *" $2 "*) exit 1 ;; esac
    cat "stub-bodies/$2.mdl" ;;
  *) exit 1 ;;
esac
