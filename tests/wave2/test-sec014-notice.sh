#!/usr/bin/env bash
# Fixture for bin/lib/sec014-notice.sh and its one caller, bin/sync-project.sh: an installed
# SEC014 with no `external_roles` in .claude/lint-config.yaml is reported on every sync, as a
# NOTE (not a counted warning), instead of as a `_rule` blindness finding that would fail every exec (#229
# pattern; review of PR #312).
#
# Usage: bash test-sec014-notice.sh [path-to-sync-project.sh]
#
# The lint-config.yaml bodies below start from the file `mxcli init` writes (v0.26.0, captured
# 2026-10-13 into an empty directory): its `rules: {}` and the commented CONV009 example. A
# commented `# external_roles:` must not count as configured.
# Keep bash-3.2 compatible.

set -uo pipefail
SYNC="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/sync-project.sh}"
case "$SYNC" in /*) ;; *) SYNC="$PWD/$SYNC" ;; esac
SUT="$(dirname "$SYNC")/lib/sec014-notice.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

if [ ! -f "$SUT" ]; then
  bad "bin/lib/sec014-notice.sh missing — nothing tells a project SEC014 is unconfigured"
  echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sec014n.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
STOCK_CFG='# mxcli lint configuration.
excludeModules:
  - System

# Per-rule overrides. Examples:
#
# rules:
#   CONV009:            # max microflow objects
#     severity: warning
#     options:
#       maxObjects: 20
rules: {}
'
mkp() { # name, install-rule(0/1), config-text-or-NONE
  d="$TMP/$1"; mkdir -p "$d/.claude/lint-rules"
  [ "$2" = 1 ] && : > "$d/.claude/lint-rules/sec014_external_role_write.star"
  [ "$3" != NONE ] && printf '%s' "$3" > "$d/.claude/lint-config.yaml"
  echo "$d"
}
notice() { ( . "$SUT"; mxtk_sec014_notice "$1" ); }

echo "== the notice =="
p=$(mkp a 1 "$STOCK_CFG"); out=$(notice "$p"); rc=$?
[ $rc -eq 0 ] && ok "a rule installed, stock config -> notice owed" || bad "a no notice (rc=$rc)"
case "$out" in *"rules:"*"SEC014:"*"options:"*"external_roles:"*) ok "a notice shows the exact config path" ;; *) bad "a config path missing" "$out" ;; esac
case "$out" in *'"none"'*"user's answer"*"PROJECT.md"*) ok "a \"none\" is named as a user decision recorded in PROJECT.md" ;; *) bad "a none-is-a-decision missing" "$out" ;; esac
case "$out" in *"--update-baseline"*"baseline-approve.sh lint"*) ok "a tells to re-baseline right after configuring" ;; *) bad "a re-baseline hint missing" "$out" ;; esac

p=$(mkp b 1 NONE); notice "$p" >/dev/null && ok "b rule installed, no lint-config.yaml -> notice owed" || bad "b no notice without a config file"
p=$(mkp c 1 "${STOCK_CFG}#   SEC014:
#     options:
#       external_roles: \"X\"
"); notice "$p" >/dev/null && ok "c commented external_roles does not count" || bad "c commented line counted as configured"
p=$(mkp d 1 'rules:
  SEC014:
    options:
      external_roles: "Partner"
'); out=$(notice "$p"); rc=$?
[ $rc -eq 1 ] && [ -z "$out" ] && ok "d external_roles set -> silent" || bad "d notice despite configuration" "$out"
p=$(mkp e 1 'rules:
  SEC014:
    options:
      external_roles: "none"
'); notice "$p" >/dev/null && bad "e \"none\" still nagged" || ok "e \"none\" (a recorded decision) -> silent"
p=$(mkp f 0 "$STOCK_CFG"); notice "$p" >/dev/null && bad "f notice without the rule installed" || ok "f rule not installed -> silent"

echo "== external_roles must sit under the SEC014 key =="
p=$(mkp g 1 'rules:
  CONV020:
    options:
      external_roles: "Partner"
  SEC014:
    severity: warning
'); notice "$p" >/dev/null && ok "g external_roles under another rule does not count" || bad "g external_roles under CONV020 counted as SEC014's"
p=$(mkp h 1 'rules:
  SEC014:
    severity: warning
  CONV009:
    options:
      maxObjects: 20
external_roles: "Partner"
'); notice "$p" >/dev/null && ok "h external_roles at top level (outside SEC014) does not count" || bad "h top-level external_roles counted"
p=$(mkp i 1 'rules:
  SEC014:
    enabled: false   # user decision, PROJECT.md D-9
'); notice "$p" >/dev/null && bad "i enabled: false under SEC014 still nagged" || ok "i enabled: false under SEC014 (same user decision as \"none\") -> silent"
p=$(mkp j 1 'rules:
  SEC014: {options: {external_roles: "Partner"}}
'); notice "$p" >/dev/null && bad "j inline-map form not recognised" || ok "j inline map under SEC014 -> silent"
p=$(mkp k 1 'rules:
  "SEC014":
    options:
      # external_roles: "Partner"
      external_roles: "Partner, Customer"
'); notice "$p" >/dev/null && bad "k quoted key not recognised" || ok "k quoted \"SEC014\" key, commented line above the real one -> silent"

echo "== lint-gate.sh prints one uncounted note line =="
GATE="$(dirname "$SYNC")/../project-bin/lint-gate.sh"
if [ ! -f "$GATE" ]; then bad "project-bin/lint-gate.sh not found next to the toolkit"
else
  gate_run() { # project-dir -> sets GOUT (stderr+stdout) and GRC
    mkdir -p "$1/bin"; cp "$GATE" "$1/bin/lint-gate.sh"
    [ -f "$(dirname "$GATE")/_common.sh" ] && cp "$(dirname "$GATE")/_common.sh" "$1/bin/"
    : > "$1/app.mpr"
    GOUT="$(cd "$1" && bash bin/lint-gate.sh 2>&1)"; GRC=$?
  }
  p=$(mkp la 1 "$STOCK_CFG"); gate_run "$p"; rc_unset=$GRC
  n=$(printf '%s\n' "$GOUT" | grep -c '^note: SEC014 not configured')
  [ "$n" -eq 1 ] && ok "la unconfigured: exactly one note line" || bad "la expected 1 note line, got $n" "$GOUT"
  case "$GOUT" in *"rules: SEC014: options: external_roles"*"'none' is their decision"*) ok "la note names the key and that 'none' is the user's call" ;; *) bad "la note text" "$GOUT" ;; esac
  p=$(mkp lb 1 'rules:
  SEC014:
    options:
      external_roles: "Partner"
'); gate_run "$p"; rc_set=$GRC
  case "$GOUT" in *"SEC014 not configured"*) bad "lb configured project still gets the note" ;; *) ok "lb configured -> no note" ;; esac
  [ "$rc_unset" -eq "$rc_set" ] && ok "the note changes no exit code ($rc_unset both ways, no mxcli in the scratch project)" || bad "exit code differs: $rc_unset vs $rc_set"
  p=$(mkp lc 0 "$STOCK_CFG"); gate_run "$p"
  case "$GOUT" in *"SEC014 not configured"*) bad "lc note without SEC014 installed" ;; *) ok "lc SEC014 not installed -> no note" ;; esac
fi

echo "== wired into sync-project.sh =="
if grep -q 'lib/sec014-notice.sh' "$SYNC" && grep -q 'mxtk_sec014_notice "\$PROJECT_DIR"' "$SYNC"; then
  ok "sync-project.sh sources the lib and calls it"
else bad "sync-project.sh does not call mxtk_sec014_notice"; fi
# The call sits inside the WIRED lint block, after the rules are installed.
blk=$(awk '/mxtk_install_lint_rules "\$\(cd/{f=1} f{print} f&&/^fi$/{exit}' "$SYNC")
case "$blk" in *mxtk_sec014_notice*) ok "the call runs after mxtk_install_lint_rules, in the same WIRED block" ;; *) bad "the call is not in the lint install block" ;; esac
# A NOTE, not warn(): a pristine scaffold has not decided yet, and test-bug12-sync.sh T0
# requires a pristine sync to exit 0 with no warning under --strict.
case "$blk" in *'echo "NOTE: $_sec014_msg"'*) ok "the notice prints as a NOTE line" ;; *) bad "the notice is not printed as a NOTE" ;; esac
case "$blk" in *"warn \$_sec014_msg"*|*'warn "$_sec014_msg"'*) bad "the notice goes through warn(): a pristine sync would fail --strict" ;; *) ok "the notice does not count as a sync warning" ;; esac
bash -n "$SYNC" && ok "sync-project.sh parses" || bad "sync-project.sh does not parse"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
