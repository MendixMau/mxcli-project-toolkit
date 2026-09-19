#!/bin/bash
# test-exec-approval.sh — the exec-approval knob (ask|auto), and its two writers.
#
# Same failure-direction discipline as test-interview-mode.sh: every way of getting the mode
# wrong — a typo in PROJECT.md, a corrupted session file, an unset variable — must land on
# `ask`, never on `auto`. A misspelling that silently buys unattended writes to the .mpr is
# the exact complaint this knob exists to answer without becoming the next incident.
#
# DEFAULT FLIPPED 2026-09-16: an unset project now resolves `auto`, not `ask` — "too much
# approval clicking; start on auto ... and let them switch" — and the tier-4 derivation from
# interview-mode.sh is GONE (attended and unattended both start on auto). The state file also
# moved from `<project>/.claude/.exec-approval` to `<project>/.mxtk/exec-approval`, with the
# old path read only as a compatibility fallback.
#
# Also covers the places that WRITE the knob's wording rather than resolve it:
#   - bin/wire-agents.sh: a freshly wired project gets the auto-default sentence, not either
#     of the two earlier wordings.
#   - bin/sync-project.sh: a project wired under EITHER earlier wording — pre-2026-09-15
#     ("without asking the user first — every time") or 2026-09-15 ("`ask` (the default)") —
#     gets item 3 repaired in place, without depending on mxcli being installed, and the
#     repair is idempotent either way.
#
# Usage: bash test-exec-approval.sh [path-to-exec-approval.sh]

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/bin/exec-approval.sh}"
WIRE="$TOOLKIT/bin/wire-agents.sh"
SYNC="$TOOLKIT/bin/sync-project.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/eappr.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"

P="$WORK/proj"; mkdir -p "$P"

# --- resolution order --------------------------------------------------------------------
[ "$(bash "$SUBJECT" "$P")" = "auto" ] \
  && ok "unset, nothing configured, resolves to auto (the new default)" \
  || bad "unset did not resolve to auto — the default was supposed to flip 2026-09-16"

printf 'Interview mode: auto\n' > "$P/PROJECT.md"
[ "$(bash "$SUBJECT" "$P")" = "auto" ] \
  && ok "interview mode auto: still auto (no longer relevant either way)" \
  || bad "interview mode auto did not resolve exec approval auto"

printf 'Interview mode: steering\n' > "$P/PROJECT.md"
[ "$(bash "$SUBJECT" "$P")" = "auto" ] \
  && ok "interview mode steering: STILL auto — tier 4 no longer derives from interview mode" \
  || bad "exec approval is still coupled to interview mode; the 2026-09-16 flip decoupled it"

printf 'Interview mode: auto\nExec approval: ask\n' > "$P/PROJECT.md"
[ "$(bash "$SUBJECT" "$P")" = "ask" ] \
  && ok "PROJECT.md 'Exec approval:' still overrides the default" \
  || bad "explicit PROJECT.md value was ignored"

rm -f "$P/PROJECT.md"

# --- state file: new path, old path, and the compat story --------------------------------
mkdir -p "$P/.mxtk"; printf 'ask\n' > "$P/.mxtk/exec-approval"
[ "$(bash "$SUBJECT" "$P")" = "ask" ] \
  && ok "new-path (.mxtk/exec-approval) session override resolves" \
  || bad "new-path session file did not resolve"
rm -f "$P/.mxtk/exec-approval"

mkdir -p "$P/.claude"; printf 'auto\n' > "$P/.claude/.exec-approval"
[ "$(bash "$SUBJECT" "$P")" = "auto" ] \
  && ok "old path (.claude/.exec-approval) still read as a compatibility fallback" \
  || bad "old-path session file was not honoured — back-compat broke a project mid-flip"

mkdir -p "$P/.mxtk"; printf 'ask\n' > "$P/.mxtk/exec-approval"
[ "$(bash "$SUBJECT" "$P")" = "ask" ] \
  && ok "new path wins when BOTH the new and old session files are present" \
  || bad "old path took priority over new — back-compat should only fire when new is absent"
rm -f "$P/.mxtk/exec-approval" "$P/.claude/.exec-approval"

printf 'auto\n' > "$P/.mxtk/exec-approval"
[ "$(bash "$SUBJECT" "$P")" = "auto" ] \
  && ok "session override beats PROJECT.md" \
  || bad "session file did not override PROJECT.md"

[ "$(CLAUDE_EXEC_APPROVAL=ask bash "$SUBJECT" "$P")" = "ask" ] \
  && ok "env beats the session file" \
  || bad "env did not win — no way to override for one command"

# --- failure direction: every bad value lands on ask, never auto --------------------------
[ "$(CLAUDE_EXEC_APPROVAL=atuo bash "$SUBJECT" "$P" 2>/dev/null)" = "ask" ] \
  && ok "typo in env falls back to ask, not the new auto default" \
  || bad "a typo resolved to something other than ask"
CLAUDE_EXEC_APPROVAL=atuo bash "$SUBJECT" "$P" 2>&1 >/dev/null | grep -q 'not a mode' \
  && ok "and says so on stderr rather than failing silently" \
  || bad "bad env value was swallowed — the user thinks they set a mode and did not"

printf 'garbage\n' > "$P/.mxtk/exec-approval"
[ "$(bash "$SUBJECT" "$P" 2>/dev/null)" = "ask" ] \
  && ok "corrupt new-path session file falls back to ask" \
  || bad "corrupt session file did not fall back safely"
rm -f "$P/.mxtk/exec-approval"

printf 'garbage\n' > "$P/.claude/.exec-approval"
mkdir -p "$P/.claude"
[ "$(bash "$SUBJECT" "$P" 2>/dev/null)" = "ask" ] \
  && ok "corrupt old-path (compat) session file falls back to ask" \
  || bad "corrupt old-path session file did not fall back safely"
rm -f "$P/.claude/.exec-approval"

printf 'Exec approval: aggressive\n' > "$P/PROJECT.md"
[ "$(bash "$SUBJECT" "$P" 2>/dev/null)" = "ask" ] \
  && ok "unknown mode in PROJECT.md falls back to ask" \
  || bad "unknown PROJECT.md mode did not fall back safely"

# --- writers --------------------------------------------------------------------------------
rm -f "$P/PROJECT.md"
mkdir -p "$P/.claude"; printf 'ask\n' > "$P/.claude/.exec-approval"   # pretend an old install
bash "$SUBJECT" "$P" --set auto >/dev/null 2>&1
[ "$(bash "$SUBJECT" "$P")" = "auto" ] && ok "--set writes the new-path session override" \
                                       || bad "--set did not take effect"
[ -f "$P/.mxtk/exec-approval" ] && ok "--set writes .mxtk/exec-approval" \
                                 || bad "--set did not create the new state path"
[ -f "$P/.claude/.exec-approval" ] && bad "--set left the old .claude/.exec-approval path behind" \
                                    || ok "--set removes the old .claude/.exec-approval path"

bash "$SUBJECT" "$P" --set nonsense >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "--set rejects an unknown mode with exit 2" \
               || bad "--set accepted a mode that does not exist"

mkdir -p "$P/.claude"; printf 'ask\n' > "$P/.claude/.exec-approval"   # both paths present
bash "$SUBJECT" "$P" --clear >/dev/null 2>&1
[ -f "$P/.mxtk/exec-approval" ] && bad "--clear left the new-path override in place" \
                                 || ok "--clear removes the new-path override"
[ -f "$P/.claude/.exec-approval" ] && bad "--clear left the old-path override in place" \
                                    || ok "--clear removes the old-path override too"
[ "$(bash "$SUBJECT" "$P")" = "auto" ] && ok "--clear reverts to the default (auto)" \
                                       || bad "--clear did not revert to the new default"

bash "$SUBJECT" "$P" --explain 2>/dev/null | grep -q '^from:' \
  && ok "--explain reports WHERE the mode came from" \
  || bad "--explain does not say which source won — undebuggable"
bash "$SUBJECT" "$P" --explain 2>/dev/null | grep -q '^effect:' \
  && ok "--explain reports the one-line effect" \
  || bad "--explain does not say what the mode does"
bash "$SUBJECT" "$P" --explain 2>/dev/null | grep -q 'from: default' \
  && ok "--explain names the source as \"default\" for an unconfigured project" \
  || bad "--explain does not say 'default' when nothing else resolved it"

bash "$SUBJECT" 2>/dev/null; [ "$?" -eq 2 ] && ok "no argument exits 2" || bad "no argument did not exit 2"

# --- wire-agents.sh: a fresh wire gets the auto-default sentence, not either old one --------
if [ -x "$WIRE" ]; then
  WP="$WORK/wireproj"; mkdir -p "$WP"; : > "$WP/Fixture.mpr"
  cat > "$WP/mxcli" <<'MXCLI'
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
  chmod +x "$WP/mxcli"
  bash "$WIRE" "$WP" >/dev/null 2>&1
  if [ -f "$WP/CLAUDE.md" ]; then
    if grep -q 'bin/exec-approval.sh' "$WP/CLAUDE.md"; then
      ok "wire-agents.sh: freshly wired CLAUDE.md names bin/exec-approval.sh"
    else
      bad "wire-agents.sh: freshly wired CLAUDE.md does not mention bin/exec-approval.sh"
    fi
    if grep -q 'without asking the user first' "$WP/CLAUDE.md"; then
      bad "wire-agents.sh: freshly wired CLAUDE.md STILL carries the pre-2026-09-15 wording"
    else
      ok "wire-agents.sh: freshly wired CLAUDE.md does not carry the pre-2026-09-15 wording"
    fi
    if grep -qF '`ask` (the default)' "$WP/CLAUDE.md"; then
      bad "wire-agents.sh: freshly wired CLAUDE.md STILL says ask is the default"
    else
      ok "wire-agents.sh: freshly wired CLAUDE.md does not say ask is the default"
    fi
    grep -q 'Exec approval defaults to' "$WP/CLAUDE.md" \
      && ok "wire-agents.sh: freshly wired CLAUDE.md states the new auto default" \
      || bad "wire-agents.sh: freshly wired CLAUDE.md does not state the new auto default"
  else
    bad "wire-agents.sh: did not produce CLAUDE.md at all — cannot check its wording"
  fi
else
  bad "wire-agents.sh not found/executable at $WIRE — cannot check a fresh wire"
fi

# --- sync-project.sh: repairs item 3 on a project wired under EITHER earlier wording -------
if [ -x "$SYNC" ]; then
  SP="$WORK/syncproj"; mkdir -p "$SP/.github" "$SP/bin"
  : > "$SP/Fixture.mpr"
  printf 'placeholder\n' > "$SP/PROJECT.md"
  printf 'placeholder\n' > "$SP/CLAUDE.local.md"
  printf 'placeholder\n' > "$SP/intake.md"
  OLDBLOCK='<!-- mxtk:wiring:start — written by mxcli-project-toolkit/bin/wire-agents.sh.
     Edit that script, not this block: it is replaced wholesale on every re-run. -->

## Start here (all AI agents, every session)

1. **Read `docs/progress/RESUME.md` first, and nothing else yet.** stuff.
2. **`CLAUDE.md` is the canonical project instruction file** stuff.
3. **Never run `./mxcli exec`, `./bin/exec.sh`, `mxcli test`, `mxcli docker check`, or any
   `--mcp` write against the real `.mpr` without asking the user first — every time.** All of
   those mutate the model; the last two mutate it despite sounding read-only.
4. **`./mxcli`, not `mxcli`.** The binary is in the project root, never on PATH.
5. **No new `.md`/`.html` in the project root.** stuff.

Skill guides live in `.ai-context/skills/` — read the relevant one before writing MDL.

<!-- mxtk:wiring:end -->'
  for f in AGENTS.md CLAUDE.md .github/copilot-instructions.md .cursorrules .windsurfrules; do
    printf '%s\n' "$OLDBLOCK" > "$SP/$f"
  done
  printf '%s\n' "$OLDBLOCK" | sed 's/^/# /' | sed 's/[[:space:]]*$//' > "$SP/.aider.conf.yml"

  bash "$SYNC" "$SP" >/dev/null 2>&1
  if grep -q 'without asking the user first' "$SP/CLAUDE.md" 2>/dev/null; then
    bad "sync-project.sh: CLAUDE.md STILL carries the pre-2026-09-15 wording after a sync"
  else
    ok "sync-project.sh: rewrites CLAUDE.md's item 3 in place (pre-2026-09-15 wording)"
  fi
  grep -q 'bin/exec-approval.sh' "$SP/CLAUDE.md" 2>/dev/null \
    && ok "sync-project.sh: CLAUDE.md now names bin/exec-approval.sh" \
    || bad "sync-project.sh: rewritten CLAUDE.md does not mention bin/exec-approval.sh"
  grep -q 'without asking the user first' "$SP/.aider.conf.yml" 2>/dev/null \
    && bad "sync-project.sh: .aider.conf.yml (hash format) STILL carries the old wording" \
    || ok "sync-project.sh: rewrites .aider.conf.yml's item 3 (hash format) too"
  grep -q '^2\. \*\*`CLAUDE.md`' "$SP/CLAUDE.md" 2>/dev/null \
    && ok "sync-project.sh: item 2 (outside the replaced range) is untouched" \
    || bad "sync-project.sh: item 2 was disturbed by the item-3 rewrite"
  grep -q '^5\. \*\*No new' "$SP/CLAUDE.md" 2>/dev/null \
    && ok "sync-project.sh: item 5 (outside the replaced range) is untouched" \
    || bad "sync-project.sh: item 5 was disturbed by the item-3 rewrite"

  SNAP1="$(cat "$SP/CLAUDE.md")"
  OUT2="$(bash "$SYNC" "$SP" 2>&1)"
  SNAP2="$(cat "$SP/CLAUDE.md")"
  [ "$SNAP1" = "$SNAP2" ] && ok "sync-project.sh: repair is idempotent (byte-identical on re-run)" \
                          || bad "sync-project.sh: re-running the repair changed the file again"
  printf '%s' "$OUT2" | grep -q 'item 3' \
    && bad "sync-project.sh: re-run still reports rewriting item 3 (already current)" \
    || ok "sync-project.sh: re-run reports nothing for item 3 (nothing left to fix)"
else
  bad "sync-project.sh not found/executable at $SYNC — cannot check the pre-2026-09-15 repair"
fi

# --- sync-project.sh: repairs item 3 on a project wired under the 2026-09-15 wording --------
# ("`ask` (the default)") — the wording introduced by the knob itself, distinct from both the
# pre-2026-09-15 sentence above and the 2026-09-16 text that replaces it.
if [ -x "$SYNC" ]; then
  SP2="$WORK/syncproj2"; mkdir -p "$SP2/.github" "$SP2/bin"
  : > "$SP2/Fixture.mpr"
  printf 'placeholder\n' > "$SP2/PROJECT.md"
  printf 'placeholder\n' > "$SP2/CLAUDE.local.md"
  printf 'placeholder\n' > "$SP2/intake.md"
  MIDBLOCK='<!-- mxtk:wiring:start — written by mxcli-project-toolkit/bin/wire-agents.sh.
     Edit that script, not this block: it is replaced wholesale on every re-run. -->

## Start here (all AI agents, every session)

1. **Read `docs/progress/RESUME.md` first, and nothing else yet.** stuff.
2. **`CLAUDE.md` is the canonical project instruction file** stuff.
3. **Before any `./mxcli exec`, `./bin/exec.sh`, `mxcli test`, `mxcli docker check`, or any
   `--mcp` write against the real `.mpr`, run `'"$TOOLKIT"'/bin/exec-approval.sh <project-root>`.** All
   of those mutate the model; the last two mutate it despite sounding read-only. `ask` (the
   default) → ask the user first, every time, as today. `auto` → run it without asking and say
   in chat what ran; the BUILD-LOG row is the record instead. The user turns this on or off at
   any time by saying so — only then run `bin/exec-approval.sh <project-root> --set auto` /
   `--set ask`, never on your own judgement.
4. **`./mxcli`, not `mxcli`.** The binary is in the project root, never on PATH.
5. **No new `.md`/`.html` in the project root.** stuff.

Skill guides live in `.ai-context/skills/` — read the relevant one before writing MDL.

<!-- mxtk:wiring:end -->'
  for f in AGENTS.md CLAUDE.md .github/copilot-instructions.md .cursorrules .windsurfrules; do
    printf '%s\n' "$MIDBLOCK" > "$SP2/$f"
  done
  printf '%s\n' "$MIDBLOCK" | sed 's/^/# /' | sed 's/[[:space:]]*$//' > "$SP2/.aider.conf.yml"

  bash "$SYNC" "$SP2" >/dev/null 2>&1
  if grep -qF '`ask` (the default)' "$SP2/CLAUDE.md" 2>/dev/null; then
    bad "sync-project.sh: CLAUDE.md STILL says ask is the default after a sync"
  else
    ok "sync-project.sh: rewrites CLAUDE.md's item 3 in place (2026-09-15 wording)"
  fi
  grep -q 'Exec approval defaults to' "$SP2/CLAUDE.md" 2>/dev/null \
    && ok "sync-project.sh: CLAUDE.md now states the auto default" \
    || bad "sync-project.sh: rewritten CLAUDE.md does not state the auto default"
  grep -qF '`ask` (the default)' "$SP2/.aider.conf.yml" 2>/dev/null \
    && bad "sync-project.sh: .aider.conf.yml (hash format) STILL says ask is the default" \
    || ok "sync-project.sh: rewrites .aider.conf.yml's item 3 (2026-09-15 wording) too"
  grep -q '^2\. \*\*`CLAUDE.md`' "$SP2/CLAUDE.md" 2>/dev/null \
    && ok "sync-project.sh: item 2 (outside the replaced range) is untouched (2026-09-15 case)" \
    || bad "sync-project.sh: item 2 was disturbed by the item-3 rewrite (2026-09-15 case)"
  grep -q '^5\. \*\*No new' "$SP2/CLAUDE.md" 2>/dev/null \
    && ok "sync-project.sh: item 5 (outside the replaced range) is untouched (2026-09-15 case)" \
    || bad "sync-project.sh: item 5 was disturbed by the item-3 rewrite (2026-09-15 case)"

  SNAP3="$(cat "$SP2/CLAUDE.md")"
  OUT3="$(bash "$SYNC" "$SP2" 2>&1)"
  SNAP4="$(cat "$SP2/CLAUDE.md")"
  [ "$SNAP3" = "$SNAP4" ] && ok "sync-project.sh: 2026-09-15 repair is idempotent too" \
                          || bad "sync-project.sh: re-running the 2026-09-15 repair changed the file again"
  printf '%s' "$OUT3" | grep -q 'item 3' \
    && bad "sync-project.sh: re-run still reports rewriting item 3 (2026-09-15 case, already current)" \
    || ok "sync-project.sh: re-run reports nothing for item 3 (2026-09-15 case, nothing left to fix)"
else
  bad "sync-project.sh not found/executable at $SYNC — cannot check the 2026-09-15 repair"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
