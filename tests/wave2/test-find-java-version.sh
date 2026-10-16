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
# Mimics the REAL macOS /usr/libexec/java_home: plain `-v N` for a version that is not installed
# falls back to the default JDK and exits 0; only `-F -v N` fails (exit 1). MXTK_FAKE_JDKS lists
# the installed majors (default "21 25"); the default JDK is the highest.
cat > "$T/java_home" <<'SH'
#!/bin/sh
JDKS="${MXTK_FAKE_JDKS:-21 25}"; FAIL=0; V=""
while [ $# -gt 0 ]; do case "$1" in -F) FAIL=1;; -v) V="$2"; shift;; esac; shift; done
default=""; for j in $JDKS; do default="$j"; done
if [ -n "$V" ]; then
  for j in $JDKS; do [ "$j" = "$V" ] && { echo "/jdk/$j"; exit 0; }; done
  [ "$FAIL" = 1 ] && { echo "Unable to locate a Java Runtime." >&2; exit 1; }
fi
echo "/jdk/$default"
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
note() { # <model version> -> prints find_java_note output
  ( unset JAVA_HOME; export MXTK_JAVA_HOME_BIN="$T/java_home"
    # shellcheck disable=SC1090
    . "$COMMON" >/dev/null 2>&1
    mxtk_platform() { echo macos; }
    MV="$1"; mxtk_model_version() { echo "$MV"; }
    find_java_note ) 2>/dev/null
}
checknote() { # <label> <model> <want substring or EMPTY>
  got="$(note "$2")"
  if { [ "$3" = EMPTY ] && [ -z "$got" ]; } || { [ "$3" != EMPTY ] && case "$got" in *"$3"*) true;; *) false;; esac; }; then
    PASS=$((PASS+1)); echo "  ok    $1"; else FAIL=$((FAIL+1)); echo "  FAIL  $1 -> '$got'"; fi
}
check() { got="$(run "$1")"; if [ "$got" = "$2" ]; then PASS=$((PASS+1)); echo "  ok    model $1 -> $got"; else FAIL=$((FAIL+1)); echo "  FAIL  model $1 -> '$got' (want $2)"; fi; }
check 11.15.0 /jdk/25
check 11.14.0 /jdk/25
check 11.13.2 /jdk/21
check 11.12.2 /jdk/21
check 10.24.3 /jdk/21
check 12.0.0  /jdk/25
check none    /jdk/21
# Only JDK 21 installed, 11.15 model: java_home -v 25 would silently return 21 (real macOS), so
# the mismatch has to be reported, and find_java still falls back (no new blocking path).
export MXTK_FAKE_JDKS="21"
check 11.15.0 /jdk/21
checknote "11.15 model, only JDK 21: mismatch reported" 11.15.0 "wanted JDK 25"
checknote "11.15 model, only JDK 21: note names the JDK used" 11.15.0 "using /jdk/21"
checknote "11.12 model, JDK 21 present: no note" 11.12.2 EMPTY
export MXTK_FAKE_JDKS="25"
checknote "11.12 model, only JDK 25: mismatch reported" 11.12.2 "wanted JDK 21"
export MXTK_FAKE_JDKS="21 25"
checknote "11.15 model, both JDKs: no note" 11.15.0 EMPTY
# the exec.sh / verify-model.sh caller sequence: the note is taken BEFORE JAVA_HOME is assigned
# (after it, find_java_note sees JAVA_HOME set and always stays silent)
MXTK_FAKE_JDKS=21
for f in exec.sh verify-model.sh; do
  grep -n 'find_java_note\|^JAVA_HOME="\$(find_java' "$(dirname "$COMMON")/$f" | cut -d: -f1 | tr '\n' ' ' | awk '{exit !($1 < $2)}' \
    && { PASS=$((PASS+1)); echo "  ok    $f: note computed before JAVA_HOME is set"; } \
    || { FAIL=$((FAIL+1)); echo "  FAIL  $f: note computed after JAVA_HOME is set"; }
done
got="$( unset JAVA_HOME; export MXTK_JAVA_HOME_BIN="$T/java_home"; . "$COMMON" >/dev/null 2>&1; mxtk_platform() { echo macos; }; mxtk_model_version() { echo 11.15.0; }
  _jnote="$(find_java_note 2>/dev/null || true)"; JAVA_HOME="$(find_java 2>/dev/null || true)"; echo "$_jnote" )"
case "$got" in *"wanted JDK 25"*) PASS=$((PASS+1)); echo "  ok    caller sequence: 11.15 model, only JDK 21: note reaches exec.sh/verify-model.sh";; *) FAIL=$((FAIL+1)); echo "  FAIL  caller sequence -> '$got'";; esac
# explicit JAVA_HOME wins and needs no note
got="$( export JAVA_HOME="$T" MXTK_FAKE_JDKS=21 MXTK_JAVA_HOME_BIN="$T/java_home"; . "$COMMON" >/dev/null 2>&1; mxtk_platform() { echo macos; }; mxtk_model_version() { echo 11.15.0; }; echo "$(find_java)|$(find_java_note)" 2>/dev/null )"
if [ "$got" = "$T|" ]; then PASS=$((PASS+1)); echo "  ok    explicit JAVA_HOME wins, no note"; else FAIL=$((FAIL+1)); echo "  FAIL  JAVA_HOME -> '$got'"; fi
echo "$PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]
