#!/usr/bin/env bash
# test-find-java-version.sh — find_java picks the JDK that matches the model's Mendix version
# (TK-018, field report from a five-app lab project, Mendix 11.15, mxcli v0.26.0).
#   usage: bash tests/wave2/test-find-java-version.sh project-bin/_common.sh
# Studio Pro 11.13 and below: JDK 21; 11.14 and above: JDK 25 (docs.mendix.com/refguide/
# system-requirements). Before: always `java_home -v 21`, so an 11.15 build died with
# "release version 25 not supported". A fake java_home stands in for /usr/libexec/java_home and
# the platform and model version are stubbed, so this runs anywhere.
set -u
COMMON="${1:?usage: $0 project-bin/_common.sh}"
COMMON="$(cd "$(dirname "$COMMON")" && pwd)/$(basename "$COMMON")"
T="$(mktemp -d "${TMPDIR:-/tmp}/mxtk-findjava.XXXXXX")"; trap 'rm -rf "$T"' EXIT
cat > "$T/java_home" <<'SH'
#!/bin/sh
case "$1 $2" in
  "-v 21") echo /jdk/21;; "-v 25") echo /jdk/25;; "-v "*) exit 1;; *) echo /jdk/default;;
esac
SH
chmod +x "$T/java_home"
PASS=0; FAIL=0
run() { # <model version|none> -> prints find_java result
  ( unset JAVA_HOME; export MXTK_JAVA_HOME_BIN="$T/java_home"
    # shellcheck disable=SC1090
    . "$COMMON" >/dev/null 2>&1
    mxtk_platform() { echo macos; }
    MV="$1"; if [ "$MV" = none ]; then mxtk_model_version() { return 1; }; else mxtk_model_version() { echo "$MV"; }; fi
    find_java ) 2>/dev/null
}
check() { got="$(run "$1")"; if [ "$got" = "$2" ]; then PASS=$((PASS+1)); echo "  ok    model $1 -> $got"; else FAIL=$((FAIL+1)); echo "  FAIL  model $1 -> '$got' (want $2)"; fi; }
check 11.15.0 /jdk/25
check 11.14.0 /jdk/25
check 11.13.2 /jdk/21
check 11.12.2 /jdk/21
check 10.24.3 /jdk/21
check 12.0.0  /jdk/25
check none    /jdk/21
echo "$PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]
