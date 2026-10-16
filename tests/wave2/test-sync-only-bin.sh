#!/usr/bin/env bash
# Fixture for sync-project.sh --only-bin, the scoped install (issue #390, field finding 1).
#
# The field run that prompted it: "sync-project.sh <project> --upgrade-bin exec.sh ..." was
# handed out as "install just these scripts". --upgrade-bin only lifts the overwrite refusal;
# the full sync still ran and changed 244 tracked files, deleted one, added ~30 and
# reinstalled the git hooks. --only-bin must write the named bin/ scripts and NOTHING else.
#
#   usage: test-sync-only-bin.sh /path/to/sync-project.sh
#
# Each case runs on BOTH layouts (single-tree, and two-tree with the .mpr under app/):
#   O1  --only-bin restore-mpr.sh on a git-committed project: git status shows exactly one
#       change (bin/restore-mpr.sh), although a full sync would have done more (control)
#   O2  hooks are not touched (removed hooks stay removed; a full sync reinstalls them)
#   O3  skills are not touched, and the whole tree outside bin/<name> is byte-identical
#   O4  an unknown script exits non-zero and writes nothing; so does a path-like name
#   O5  a locally modified copy is refused (exit 1, nothing written), accepted with
#       --upgrade-bin <name> or --force, backed up first, and every written file is printed
#   O6  the full sync's refresh hold: an unedited OLDER exec.sh is refreshed on a clean
#       _common.sh (control) but refused on a hand-edited one, unless --upgrade-bin names it;
#       --dry-run of that upgrade says a backup would be written, and writes nothing
#   O7  a project-bin/ file outside the install manifest (NOINSTALL) is refused
#   O8  --only-bin '*' from a cwd full of script names installs nothing (no glob expansion)
#   O9  --only-bin '' is a usage error
#
# Every fixture is built by the REAL bin/init-project.sh under /tmp. No real project is touched.
export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
export MXTK_SYNC_SKIP_CLONE_CHECK=1
set -uo pipefail

SYNC="${1:?usage: test-sync-only-bin.sh /path/to/sync-project.sh}"
case "$SYNC" in /*) ;; *) SYNC="$PWD/$SYNC" ;; esac
TK="$(cd "$(dirname "$SYNC")/.." && pwd)"
# O6 needs an older exec.sh the toolkit really shipped (CI checks out full history).
OLD_EXEC_REV="$(git -C "$TK" log --format=%H -n2 -- project-bin/exec.sh 2>/dev/null | sed -n 2p)"
INIT="$TK/bin/init-project.sh"
WORK="$(mktemp -d /tmp/onlybin.XXXXXX)"
trap 'rm -f "$MXTK_LEAKGUARD_DENYFILE"; rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

# Path, exec bit and content hash of every file, .git/hooks included (that is where the
# reinstall lands) but the rest of .git excluded (index stat noise). $2 = a path to leave out.
fingerprint() {
  ( cd "$1" && find . -type f ! -path './.git/*' -o -type f -path './.git/hooks/*' ) 2>/dev/null \
    | LC_ALL=C sort | while read -r f; do
      [ "$f" = "./${2:-//none}" ] && continue
      if [ -x "$1/$f" ]; then x=x; else x=-; fi
      printf '%s %s %s\n' "$f" "$x" "$(md5 -q "$1/$f" 2>/dev/null || md5sum "$1/$f" | cut -d' ' -f1)"
    done
}

# A committed project in which a FULL sync has work to do: two bin/ scripts missing, the git
# hooks removed, and a skills tree a sync must not touch.
mkproj() {
  d="$WORK/$1-$2"; mkdir -p "$d"
  if [ "$2" = two ]; then mkdir -p "$d/app"; : > "$d/app/Fixture.mpr"; else : > "$d/Fixture.mpr"; fi
  git -C "$d" init -q
  MXTK_NO_GUIDE=1 "$INIT" "$d" >/dev/null 2>&1
  mkdir -p "$d/.claude/skills/demo" "$d/.ai-context/skills"
  echo "# demo skill" > "$d/.claude/skills/demo/SKILL.md"
  echo "# local skill" > "$d/.ai-context/skills/local.md"
  rm -f "$d/bin/restore-mpr.sh" "$d/bin/snapshot-mpr.sh"
  find "$d/.git/hooks" -type f ! -name '*.sample' -exec rm -f {} +
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c user.name=fx -c user.email=t@t commit -qm fixture --no-verify >/dev/null 2>&1
  echo "$d"
}
# git status lines (ignored files included) that differ from the snapshot $2 — what a run changed.
gst() { git -C "$1" status --porcelain --ignored | LC_ALL=C sort; }
st_delta() { gst "$1" | LC_ALL=C comm -3 - <(printf '%s\n' "$2"); }
hooks_of() { find "$1/.git/hooks" -type f ! -name '*.sample' | LC_ALL=C sort; }

for L in single two; do
  echo "== layout: $L =="
  P="$(mkproj o1 "$L")"
  B="$(fingerprint "$P" bin/restore-mpr.sh)"; S0="$(gst "$P")"
  OUT="$("$SYNC" "$P" --only-bin restore-mpr.sh 2>&1)"; RC=$?
  ST="$(st_delta "$P" "$S0")"
  [ "$RC" -eq 0 ] && ok "O1[$L] exit 0" || bad "O1[$L] exit $RC" "$OUT"
  [ "$ST" = "?? bin/restore-mpr.sh" ] && ok "O1[$L] git status shows exactly bin/restore-mpr.sh" \
    || bad "O1[$L] git status is not exactly one change" "$ST"
  cmp -s "$TK/project-bin/restore-mpr.sh" "$P/bin/restore-mpr.sh" && [ -x "$P/bin/restore-mpr.sh" ] \
    && ok "O1[$L] bin/restore-mpr.sh is the toolkit copy, executable" || bad "O1[$L] restore-mpr.sh not installed"
  printf '%s' "$OUT" | grep -q '^Wrote: bin/restore-mpr.sh' && printf '%s' "$OUT" | grep -q '1 file(s) written' \
    && ok "O1[$L] prints the file written" || bad "O1[$L] written file not printed" "$OUT"
  [ -z "$(hooks_of "$P")" ] && ok "O2[$L] hooks not touched (still absent)" || bad "O2[$L] hooks were installed" "$(hooks_of "$P")"
  [ "$B" = "$(fingerprint "$P" bin/restore-mpr.sh)" ] && ok "O3[$L] skills and every other file byte-identical" \
    || bad "O3[$L] something besides bin/restore-mpr.sh changed" "$(diff <(echo "$B") <(fingerprint "$P" bin/restore-mpr.sh))"

  # Control: the same project under the old instruction does far more — the fixture discriminates.
  "$SYNC" "$P" --upgrade-bin restore-mpr.sh >/dev/null 2>&1
  { [ -f "$P/bin/snapshot-mpr.sh" ] && [ -n "$(hooks_of "$P")" ]; } \
    && ok "control[$L] a full --upgrade-bin sync installs other scripts and the hooks" \
    || bad "control[$L] the full sync did not do more — O1-O3 prove nothing"

  P="$(mkproj o4 "$L")"; B="$(fingerprint "$P")"
  OUT="$("$SYNC" "$P" --only-bin restore-mpr.sh --only-bin no-such-script.sh 2>&1)"; RC=$?
  [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'no-such-script.sh' && [ "$B" = "$(fingerprint "$P")" ] \
    && ok "O4[$L] unknown script: exit $RC, named, nothing written (not even the valid one)" \
    || bad "O4[$L] unknown script: rc=$RC" "$OUT"
  OUT="$("$SYNC" "$P" --only-bin ../bin/gate-check.sh 2>&1)"; RC=$?
  [ "$RC" -ne 0 ] && [ "$B" = "$(fingerprint "$P")" ] && ok "O4[$L] path-like name refused" || bad "O4[$L] path-like name: rc=$RC" "$OUT"

  P="$(mkproj o5 "$L")"
  printf '#!/usr/bin/env bash\n# LOCAL HARDENING\nexit 0\n' > "$P/bin/exec.sh"
  git -C "$P" -c user.name=fx -c user.email=t@t commit -qam local --no-verify >/dev/null 2>&1
  B="$(fingerprint "$P")"; S0="$(gst "$P")"
  OUT="$("$SYNC" "$P" --only-bin exec.sh 2>&1)"; RC=$?
  [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'LOCALLY MODIFIED' && [ "$B" = "$(fingerprint "$P")" ] \
    && ok "O5[$L] locally modified copy refused, nothing written" || bad "O5[$L] refusal: rc=$RC" "$OUT"
  OUT="$("$SYNC" "$P" --only-bin exec.sh --upgrade-bin exec.sh 2>&1)"; RC=$?
  BAK="$(find "$P/bin" -name 'exec.sh.local-*' | head -1)"
  { [ "$RC" -eq 0 ] && cmp -s "$TK/project-bin/exec.sh" "$P/bin/exec.sh" && [ -n "$BAK" ] \
    && grep -q 'LOCAL HARDENING' "$BAK" && printf '%s' "$OUT" | grep -q '2 file(s) written'; } \
    && ok "O5[$L] --upgrade-bin names it: upgraded, backed up, both files printed" || bad "O5[$L] --upgrade-bin: rc=$RC" "$OUT"
  ST="$(st_delta "$P" "$S0")"
  { [ "$(printf '%s\n' "$ST" | wc -l | tr -d ' ')" = 2 ] && printf '%s' "$ST" | grep -q '^ M bin/exec.sh$' \
    && printf '%s' "$ST" | grep -q '^?? bin/exec.sh.local-'; } \
    && ok "O5[$L] git status: exec.sh + its backup, nothing else" || bad "O5[$L] extra changes" "$ST"
  printf '#!/usr/bin/env bash\n# LOCAL AGAIN\n' > "$P/bin/exec.sh"
  "$SYNC" "$P" --only-bin exec.sh --force >/dev/null 2>&1 && cmp -s "$TK/project-bin/exec.sh" "$P/bin/exec.sh" \
    && ok "O5[$L] --force overwrites (after a backup)" || bad "O5[$L] --force did not overwrite"

  P="$(mkproj o6 "$L")"
  if [ -z "$OLD_EXEC_REV" ]; then
    bad "O6[$L] no older project-bin/exec.sh in the toolkit's git history (shallow clone?)"
  else
    old_exec() { git -C "$TK" show "$OLD_EXEC_REV:project-bin/exec.sh" > "$P/bin/exec.sh"; chmod +x "$P/bin/exec.sh"; }
    old_exec
    OUT="$("$SYNC" "$P" --only-bin exec.sh 2>&1)"; RC=$?
    [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^Wrote: bin/exec.sh (refresh)' \
      && ok "O6[$L] control: older unedited exec.sh refreshed on a clean _common.sh" || bad "O6[$L] control: rc=$RC" "$OUT"
    old_exec; printf '# local hardening\n' >> "$P/bin/_common.sh"
    git -C "$P" -c user.name=fx -c user.email=t@t commit -qam held --no-verify >/dev/null 2>&1
    B="$(fingerprint "$P")"
    OUT="$("$SYNC" "$P" --only-bin exec.sh 2>&1)"; RC=$?
    [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'NOT refreshed: bin/_common.sh is' && [ "$B" = "$(fingerprint "$P")" ] \
      && ok "O6[$L] held on an edited _common.sh: refused with the full sync's message, nothing written" || bad "O6[$L] hold: rc=$RC" "$OUT"
    OUT="$("$SYNC" "$P" --only-bin exec.sh --upgrade-bin exec.sh --dry-run 2>&1)"; RC=$?
    [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'local copy would be backed up first' && [ "$B" = "$(fingerprint "$P")" ] \
      && ok "O6[$L] --dry-run upgrade names the backup and writes nothing" || bad "O6[$L] dry-run: rc=$RC" "$OUT"
    OUT="$("$SYNC" "$P" --only-bin exec.sh --upgrade-bin exec.sh 2>&1)"; RC=$?
    [ "$RC" -eq 0 ] && cmp -s "$TK/project-bin/exec.sh" "$P/bin/exec.sh" && [ -n "$(find "$P/bin" -name 'exec.sh.local-*')" ] \
      && ok "O6[$L] --upgrade-bin exec.sh lifts the hold (backed up)" || bad "O6[$L] upgrade: rc=$RC" "$OUT"
  fi

  P="$(mkproj o7 "$L")"; B="$(fingerprint "$P")"
  OUT="$("$SYNC" "$P" --only-bin report-disposition-check.sh 2>&1)"; RC=$?
  [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'NOINSTALL' && [ "$B" = "$(fingerprint "$P")" ] \
    && ok "O7[$L] NOINSTALL script refused, nothing written" || bad "O7[$L] NOINSTALL: rc=$RC" "$OUT"

  G="$WORK/glob-$L"; mkdir -p "$G"; : > "$G/restore-mpr.sh"; : > "$G/snapshot-mpr.sh"
  OUT="$(cd "$G" && "$SYNC" "$P" --only-bin '*' 2>&1)"; RC=$?
  [ "$RC" -ne 0 ] && [ ! -e "$P/bin/restore-mpr.sh" ] && [ ! -e "$P/bin/snapshot-mpr.sh" ] && [ "$B" = "$(fingerprint "$P")" ] \
    && ok "O8[$L] --only-bin '*' is not glob-expanded: refused, nothing written" || bad "O8[$L] glob: rc=$RC" "$OUT"

  OUT="$("$SYNC" "$P" --only-bin '' 2>&1)"; RC=$?
  [ "$RC" -ne 0 ] && [ "$B" = "$(fingerprint "$P")" ] && ok "O9[$L] --only-bin '' is a usage error" || bad "O9[$L] empty name: rc=$RC" "$OUT"
done

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
