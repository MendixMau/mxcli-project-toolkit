#!/usr/bin/env bash
# test-wire-agents-kiro.sh — the opt-in `--with-kiro` steering pointer on wire-agents.sh.
#
# Kiro (kiro.dev) is not one of mxcli's --tool targets, so wire-agents.sh has to write and
# stamp `.kiro/steering/mxtk-toolkit.md` itself rather than routing it through `mxcli init`
# like the default six tools. This fixture is the field proof that:
#   - a plain run touches nothing under .kiro/ (opt-in, never on by default)
#   - --with-kiro writes a steering file Kiro will actually load (frontmatter in the first
#     three lines, the spec-mode prohibition, the RESUME.md pointer)
#   - re-running --with-kiro is idempotent and never clobbers a hand-edited preamble line
#   - --dry-run writes nothing
#   - --check reports the kiro file only when it is relevant (asked for, or already there)
#
# Usage: bash test-wire-agents-kiro.sh [path-to-wire-agents.sh]

set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/bin/wire-agents.sh}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

[ -x "$SUBJECT" ] || { echo "test-wire-agents-kiro.sh: subject not found/executable: $SUBJECT" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/wakiro.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"

# A stub mxcli, same shape as test-exec-approval.sh's — good enough for wire-agents.sh to find
# a "project-local" binary and run `init` for the default six tools without touching .kiro/ at
# all (mxcli has no --tool kiro target, which is the whole reason this fixture exists).
mkstub() {
  dir="$1"
  cat > "$dir/mxcli" <<'MXCLI'
#!/bin/sh
case "$1" in
  init)
    for f in AGENTS.md CLAUDE.md .github/copilot-instructions.md .cursorrules .windsurfrules .aider.conf.yml; do
      mkdir -p "$(dirname "$f")"
      [ -f "$f" ] || printf '# stub\n' > "$f"
    done
    exit 0 ;;
  --help) exit 0 ;;
  *) exit 0 ;;
esac
MXCLI
  chmod +x "$dir/mxcli"
}

KFILE=".kiro/steering/mxtk-toolkit.md"

# --- (a) default run writes no .kiro/ dir at all -------------------------------------------
P1="$WORK/default"; mkdir -p "$P1"; : > "$P1/Fixture.mpr"; mkstub "$P1"
bash "$SUBJECT" "$P1" >/dev/null 2>&1
if [ -d "$P1/.kiro" ]; then
  bad "default run created .kiro/ without --with-kiro"
else
  ok "default run touches no .kiro/ dir"
fi

# --- (b) --with-kiro writes the steering file, loadable by Kiro ----------------------------
P2="$WORK/kiro"; mkdir -p "$P2"; : > "$P2/Fixture.mpr"; mkstub "$P2"
bash "$SUBJECT" "$P2" --with-kiro >/dev/null 2>&1
F2="$P2/$KFILE"
if [ -f "$F2" ]; then
  ok "--with-kiro wrote $KFILE"
else
  bad "--with-kiro did not write $KFILE"
fi
head -3 "$F2" 2>/dev/null | grep -q '^inclusion: always$' \
  && ok "inclusion: always appears within the first 3 lines (frontmatter)" \
  || bad "inclusion: always missing from the frontmatter (first 3 lines)"
grep -q 'mxtk:wiring:start' "$F2" 2>/dev/null \
  && ok "carries the shared wiring marker block" \
  || bad "missing the mxtk:wiring:start marker"
grep -q '\.kiro/specs' "$F2" 2>/dev/null \
  && ok "states the spec-mode prohibition (.kiro/specs)" \
  || bad "missing the .kiro/specs prohibition line"
grep -q 'RESUME.md' "$F2" 2>/dev/null \
  && ok "points at RESUME.md (same start-here block as every other agent)" \
  || bad "missing the RESUME.md pointer"

# --- (c) running --with-kiro twice: exactly one marker block, hand edit survives -----------
# Hand-edit a preamble line (above the marker block) the way a human would.
awk '1; /This file is a pointer/{print "HAND-EDITED LINE SURVIVES"}' "$F2" > "$F2.tmp" && mv "$F2.tmp" "$F2"
grep -q 'HAND-EDITED LINE SURVIVES' "$F2" || echo "  (setup) hand-edit insertion did not take — check the preamble wording"

bash "$SUBJECT" "$P2" --with-kiro >/dev/null 2>&1
MARKS="$(grep -c 'mxtk:wiring:start' "$F2" 2>/dev/null || echo 0)"
[ "$MARKS" -eq 1 ] \
  && ok "re-running --with-kiro leaves exactly one marker block" \
  || bad "re-running --with-kiro left $MARKS marker blocks (expected 1)"
grep -q 'HAND-EDITED LINE SURVIVES' "$F2" \
  && ok "a hand-edited preamble line survives the re-stamp" \
  || bad "the re-stamp clobbered the hand-edited preamble line"

# --- (d) --with-kiro --dry-run writes nothing -----------------------------------------------
P3="$WORK/dry"; mkdir -p "$P3"; : > "$P3/Fixture.mpr"; mkstub "$P3"
bash "$SUBJECT" "$P3" --with-kiro --dry-run >/dev/null 2>&1
if [ -e "$P3/.kiro" ]; then
  bad "--with-kiro --dry-run created .kiro/ (should write nothing)"
else
  ok "--with-kiro --dry-run writes nothing"
fi

# --- (e) --check reports the kiro file only when relevant -----------------------------------
# After a kiro wire, a plain --check (no --with-kiro flag) still reports it, because the file
# is already there. Captured into a variable rather than piped straight into `grep -q` — with
# `pipefail` on, `grep -q` exiting at its first match can SIGPIPE the still-writing producer
# and turn a real match into a reported failure.
CHECK2="$(bash "$SUBJECT" "$P2" --check 2>/dev/null)"
printf '%s' "$CHECK2" | grep -qi 'kiro' \
  && ok "--check after a kiro wire reports the kiro file as wired" \
  || bad "--check after a kiro wire says nothing about it"

# A project that never opted into Kiro must not have it mentioned at all — MISSING-by-default
# would be a false alarm on every non-Kiro project in the fleet.
CHECK1="$(bash "$SUBJECT" "$P1" --check 2>/dev/null)"
printf '%s' "$CHECK1" | grep -qi 'kiro' \
  && bad "--check on a non-kiro project mentions .kiro (false alarm)" \
  || ok "--check on a non-kiro project does not mention .kiro"

# --- (f) --with-kiro with NO mxcli reachable at all still writes the steering pointer -------
# The regression this fixture exists to catch: the Kiro write used to sit structurally after
# mxcli discovery, which does `exit 0` the moment mxcli can't be found — silently dropping
# --with-kiro along with the rest of the wiring, though the Kiro pointer never reads mxcli.
# No mkstub() here (no project-local binary), and PATH is trimmed to the bare system dirs
# (no dev tool paths, no project bin/) so `command -v mxcli` also fails — this project has no
# mxcli reachable by either route. A wholly empty PATH would also take `bash`, `mkdir` etc.
# down with it (the subject re-execs itself and calls ordinary coreutils), so this keeps just
# /usr/bin and /bin rather than scrubbing to nothing.
P4="$WORK/nomxcli"; mkdir -p "$P4"; : > "$P4/Fixture.mpr"
PATH="/usr/bin:/bin" bash "$SUBJECT" "$P4" --with-kiro >/dev/null 2>&1
F4="$P4/$KFILE"
if [ -f "$F4" ]; then
  ok "--with-kiro writes $KFILE even with no mxcli on PATH or in the project"
else
  bad "--with-kiro did not write $KFILE when mxcli was unreachable (the exit-0 regression)"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
