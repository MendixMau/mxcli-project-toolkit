#!/usr/bin/env bash
# mxcli_pin.sh: one mxcli version per run. Record the version at triage, refuse (exit 3, with the reason) when a later
# step or a hand-run helper would use a different one.
#
#   mxcli_pin.sh record STATEFILE [BIN ...]   write the version of every BIN (one line); refuse when the BINs disagree
#   mxcli_pin.sh check  STATEFILE [BIN ...]   compare every BIN with the recorded line; mismatch = exit 3
#   mxcli_pin.sh show   [BIN ...]             print the identity of every BIN, one per line
# Without BIN the binaries the run really uses are taken from the environment: $MXCLI, else $UPG_MXCLI, else
# $UPG_TOOLS/mxcli-linux (what mxcli-container.sh runs); plus the binary UPG_UPDATE_CMD calls ("<binary> marketplace update ...") when that is not
# mxcli-container.sh (the host route that works behind the agent proxy, setup.sh T8): a second binary in the same run, and the
# two are not guaranteed to be the same build. A custom command that is no mxcli call (a test stub) adds none.
#
# Identity = the version label `mxcli --version` prints ("mxcli version v0.28.0" -> v0.28.0; a source build prints a short
# commit); a binary that cannot run here (a Linux binary on a Mac host) is identified by "sha256:<12 hex>" of the file.
#
# Why (mxcli v0.28.0 field comparison): DESCRIBE output changed between the old and the new binary (widgets gain
# readOnlyStyle, microflow anchors are written in full, context comments are qualified). Anything made by one version and
# compared with output of another reads those format changes as local edits:
#   - localedits.json (--mxcli-diff, made at triage) is what convertmade.sh trusts after the convert and the updates;
#   - the catalog REFRESH CATALOG FULL writes at triage is what test_inventory.py / impact_map.py read later;
#   - replay/<Module>.mdl is written from a DESCRIBE of the old app and run with `mxcli exec` after the updates.
# alter_guard.py and the localedits.py diff compare before and after ONE command, so they cannot straddle versions.
# The pipeline calls this before every step that uses mxcli; stepupdate.sh calls it when UPG_MXCLI_STATE names the state file.
# Exit: 0 = ok (or nothing to pin), 2 = usage, 3 = a different version (or the binaries disagree).
set -u
cmd=${1:-}; [ -n "$cmd" ] || { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
shift
state=""
case "$cmd" in
  record|check) state=${1:-}; [ -n "$state" ] || { echo "mxcli_pin: $cmd needs a STATEFILE" >&2; exit 2; }; shift;;
  show) ;;
  *) echo "mxcli_pin: unknown command $cmd (record, check, show)" >&2; exit 2;;
esac

sha12() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -c1-12; else shasum -a 256 "$1" | cut -c1-12; fi; }
ident() { # path -> identity
  local p=$1 v
  v=$("$p" --version 2>/dev/null | head -1) || v=""
  case "$v" in
    "mxcli version "*) v=${v#mxcli version }; v=${v%% *};;
    *) v="";;
  esac
  [ -n "$v" ] || v="sha256:$(sha12 "$(readlink -f "$p" 2>/dev/null || echo "$p")")"
  printf '%s' "$v"
}

bins=("$@")
if [ ${#bins[@]} -eq 0 ]; then
  main=${MXCLI:-${UPG_MXCLI:-}}
  [ -n "$main" ] || main=${UPG_TOOLS:+$UPG_TOOLS/mxcli-linux}
  [ -z "$main" ] || [ ! -x "$main" ] || bins+=("$main")
  # the binary UPG_UPDATE_CMD calls is the word before "marketplace update"; mxcli-container.sh runs $main in the container
  # (already listed), any other word is a second binary (setup.sh T8: the host mxcli); a command that is no mxcli call is none
  tok=$(printf '%s' "${UPG_UPDATE_CMD:-}" | sed -nE 's/.*[[:space:]]([^[:space:]]+)[[:space:]]+marketplace[[:space:]]+update([[:space:]].*)?$/\1/p; s/^([^[:space:]]+)[[:space:]]+marketplace[[:space:]]+update([[:space:]].*)?$/\1/p' | head -1)
  tok=${tok#[\'\"]}; tok=${tok%[\'\"]}; tok=${tok/#\~/$HOME}
  case "$tok" in
    ''|*mxcli-container.sh) ;;
    */*) [ ! -x "$tok" ] || bins+=("$tok");;
    *) h=$(command -v "$tok" 2>/dev/null || true); [ -z "$h" ] || bins+=("$h");;
  esac
fi
if [ ${#bins[@]} -eq 0 ]; then
  [ "$cmd" = show ] || echo "mxcli_pin: no mxcli binary found (MXCLI, UPG_MXCLI, UPG_TOOLS/mxcli-linux): version not pinned or checked"
  exit 0
fi

ids=(); first=""
for b in "${bins[@]}"; do
  id=$(ident "$b"); ids+=("$id")
  if [ -z "$first" ]; then first=$id
  elif [ "$id" != "$first" ] && [ "$cmd" != show ]; then
    echo "mxcli_pin: REFUSED, this run would use two different mxcli versions: ${bins[0]} is $first, $b is $id." >&2
    echo "  One run, one version (DESCRIBE output differs between versions and would read as local edits). Use one binary for the container and the host (UPG_UPDATE_CMD), then rerun." >&2
    exit 3
  fi
done

case "$cmd" in
  show) i=0; for b in "${bins[@]}"; do printf '%s %s\n' "${ids[$i]}" "$b"; i=$((i + 1)); done; exit 0;;
  record)
    mkdir -p "$(dirname "$state")"
    printf '%s\n# recorded %s from %s\n' "$first" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${bins[0]}" > "$state"
    echo "mxcli_pin: this run uses mxcli $first (recorded in $state)"; exit 0;;
  check)
    if [ ! -s "$state" ]; then echo "mxcli_pin: no recorded version in $state: nothing to compare" >&2; exit 0; fi
    want=$(head -1 "$state")
    if [ "$first" != "$want" ]; then
      echo "mxcli_pin: REFUSED, this run was started with mxcli $want (recorded in $state), but ${bins[0]} is $first." >&2
      echo "  Comparing DESCRIBE output, localedits.json, the catalog or replay scripts across versions reads format changes as local edits." >&2
      echo "  Use the $want binary again, or start a new run. To move this run to $first on purpose: rerun the pipeline with --from triage (re-records the version and redoes the checks that depend on it)." >&2
      exit 3
    fi
    exit 0;;
esac
