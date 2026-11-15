#!/usr/bin/env bash
# test-gitignore-crlf.sh — the .gitignore appenders (bin/init-project.sh, bin/sync-project.sh,
# project-bin/model-stamp.sh, via mxtk_gitignore_has/_ensure) match a CRLF entry, never duplicate
# it, and append in the file's own line ending. Follow-up to test-snapshot-gitignore.sh.
#
# Usage: bash tests/wave2/test-gitignore-crlf.sh      (no argument: it tests the toolkit it lives in)
#
# WHY: `grep -qE '^/?x/?$'` misses `x\r`, so init-project.sh re-appended entries a Windows-made
# .gitignore already had, and sync-project.sh / model-stamp.sh wrote LF lines into CRLF files.
# Input shape: the CRLF .gitignore of issue #739 (`printf 'node_modules/\r\n/.mpr-snapshots/\r\n'`),
# i.e. what a Windows editor writes. The producers are the real scripts run in throwaway projects.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gicrlf.XXXXXX")" || exit 2
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
CR="$(printf '\r')"
nlines()  { tr -d '\r' < "$1" | wc -l | tr -d ' '; }
ncrlf()   { grep -c "${CR}\$" "$1"; }
nmatch()  { tr -d '\r' < "$1" | grep -c "^/\{0,1\}$2/\{0,1\}\$"; }   # entry occurrences, CR-blind

# ---- the helper, both copies, same cases -----------------------------------------------------
for COPY in "bin/lib/gitignore-ensure.sh" "project-bin/_common.sh"; do
  echo "== helper copy: $COPY"
  # shellcheck disable=SC1090
  . "$TOOLKIT/$COPY" 2>/dev/null
  D="$WORK/h-$(echo "$COPY" | tr '/.' '__')"; mkdir -p "$D"
  ens() { mxtk_gitignore_ensure "$1" .mxtk '# machine state' '.mxtk/'; }

  printf 'a/\r\n.mxtk/\r\n' > "$D/crlf-present"; cp "$D/crlf-present" "$D/before"
  ens "$D/crlf-present"; rc=$?
  { [ "$rc" = 1 ] && cmp -s "$D/before" "$D/crlf-present"; } && ok "CRLF, entry present: rc 1, file untouched" || bad "CRLF present rc=$rc"

  printf 'a/\r\n/.mxtk\r\n' > "$D/crlf-spelling"; ens "$D/crlf-spelling"; rc=$?
  [ "$rc" = 1 ] && ok "CRLF, '/.mxtk' spelling counts as present" || bad "spelling variant not matched (rc=$rc)"

  printf 'a/\r\n' > "$D/crlf-missing"; ens "$D/crlf-missing"; ens "$D/crlf-missing"; rc=$?
  { [ "$rc" = 1 ] && [ "$(nmatch "$D/crlf-missing" '\.mxtk')" = 1 ] && [ "$(ncrlf "$D/crlf-missing")" = "$(nlines "$D/crlf-missing")" ]; } \
    && ok "CRLF, missing: appended once, every line CRLF, second call no-op" || bad "CRLF missing: $(od -c "$D/crlf-missing" | head -4)"

  printf 'a/\r\nb/' > "$D/crlf-nonl"; ens "$D/crlf-nonl"
  { [ "$(nmatch "$D/crlf-nonl" '\.mxtk')" = 1 ] && [ "$(ncrlf "$D/crlf-nonl")" = "$(nlines "$D/crlf-nonl")" ]; } \
    && ok "CRLF, no trailing newline: separator is CRLF too" || bad "CRLF nonl: $(od -c "$D/crlf-nonl" | head -4)"

  printf 'a/\n' > "$D/lf"; ens "$D/lf"; ens "$D/lf"
  [ "$(cat "$D/lf")" = "$(printf 'a/\n# machine state\n.mxtk/')" ] && [ "$(ncrlf "$D/lf")" = 0 ] \
    && ok "LF file: block appended once, no CR (same bytes as the old printf)" || bad "LF: $(od -c "$D/lf" | head -4)"

  printf 'a/\n.mxtk/\n' > "$D/lf-present"; cp "$D/lf-present" "$D/before"; ens "$D/lf-present"
  cmp -s "$D/before" "$D/lf-present" && ok "LF file with entry: untouched" || bad "LF present changed"

  printf 'a/' > "$D/lf-nonl"; ens "$D/lf-nonl"
  [ "$(od -An -c "$D/lf-nonl" | tr -d ' \n')" = 'a/\n#machinestate\n.mxtk/\n' ] && ok "LF, no trailing newline: separator added" || bad "LF nonl: $(od -c "$D/lf-nonl" | head -3)"

  ens "$D/absent"; rc=$?
  { [ "$rc" = 0 ] && [ "$(ncrlf "$D/absent")" = 0 ] && [ "$(nmatch "$D/absent" '\.mxtk')" = 1 ]; } && ok "absent file: created with LF" || bad "absent rc=$rc"

  mxtk_gitignore_ensure "$D/nodir/x" .mxtk '.mxtk/'; rc=$?
  [ "$rc" = 2 ] && ok "unwritable path: rc 2, not fatal" || bad "unwritable rc=$rc"
done

# ---- the real scripts -------------------------------------------------------------------------
echo "== init-project.sh on a CRLF .gitignore that already has all four entries"
P="$WORK/init-present"; mkdir -p "$P"
printf 'sources/\r\n.mxtk/\r\n.claude/settings.local.json\r\n/.claude/progress-report-sessions.txt\r\n' > "$P/.gitignore"
cp "$P/.gitignore" "$WORK/before"
( HOME="$WORK/home" bash "$TOOLKIT/bin/init-project.sh" "$P" --ignore-sources </dev/null >"$WORK/init.out" 2>&1 )
cmp -s "$WORK/before" "$P/.gitignore" && ok ".gitignore byte-identical (no duplicate entries)" || bad "init duplicated entries: $(tr -d '\r' < "$P/.gitignore" | sort | uniq -d | tr '\n' ' ')"

echo "== init-project.sh on a CRLF .gitignore with none of them: appended in CRLF"
P="$WORK/init-missing"; mkdir -p "$P"; printf 'node_modules/\r\nbuild/' > "$P/.gitignore"
( HOME="$WORK/home" bash "$TOOLKIT/bin/init-project.sh" "$P" --ignore-sources </dev/null >"$WORK/init.out" 2>&1 )
{ [ "$(ncrlf "$P/.gitignore")" = "$(nlines "$P/.gitignore")" ] && [ "$(nmatch "$P/.gitignore" 'sources')" = 1 ] && [ "$(nmatch "$P/.gitignore" '\.mxtk')" = 1 ]; } \
  && ok "every line CRLF, each entry once" || bad "init CRLF append: $(od -c "$P/.gitignore" | head -6)"

echo "== init-project.sh on a fresh project: LF, four entries once each"
P="$WORK/init-fresh"; mkdir -p "$P"
( HOME="$WORK/home" bash "$TOOLKIT/bin/init-project.sh" "$P" --ignore-sources </dev/null >"$WORK/init.out" 2>&1 )
{ [ "$(ncrlf "$P/.gitignore")" = 0 ] && [ "$(nmatch "$P/.gitignore" 'sources')" = 1 ] && [ "$(nmatch "$P/.gitignore" '\.claude/progress-report-sessions\.txt')" = 1 ]; } \
  && ok "no CR, entries once" || bad "init fresh: $(od -c "$P/.gitignore" | head -6)"

echo "== sync-project.sh on that project, .gitignore turned CRLF without the progress entry"
P="$WORK/init-fresh"; ( cd "$P" && git init -q . 2>/dev/null )
printf 'node_modules/\r\nbuild/' > "$P/.gitignore"
( HOME="$WORK/home" bash "$TOOLKIT/bin/sync-project.sh" "$P" </dev/null >"$WORK/sync.out" 2>&1 )
{ [ "$(nmatch "$P/.gitignore" '\.claude/progress-report-sessions\.txt')" = 1 ] && [ "$(ncrlf "$P/.gitignore")" = "$(nlines "$P/.gitignore")" ]; } \
  && ok "entry added once, every line CRLF" || bad "sync: $(od -c "$P/.gitignore" | head -6)"
( HOME="$WORK/home" bash "$TOOLKIT/bin/sync-project.sh" "$P" </dev/null >"$WORK/sync.out" 2>&1 )
[ "$(nmatch "$P/.gitignore" '\.claude/progress-report-sessions\.txt')" = 1 ] && ok "second sync: still once" || bad "sync duplicated on rerun"

echo "== model-stamp.sh write on a CRLF .gitignore"
P="$WORK/stamp"; mkdir -p "$P/bin" "$P/.claude" "$P/mprcontents/aa"
cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/model-stamp.sh" "$P/bin/"
printf 'index v2\n' > "$P/App.mpr"; printf 'unit\n' > "$P/mprcontents/aa/one.mxunit"
( cd "$P" && git init -q . 2>/dev/null; printf 'node_modules/\r\n' > .gitignore
  git add -A >/dev/null 2>&1; git -c user.email=t@example.com -c user.name=t commit -qm x >/dev/null 2>&1 )
( cd "$P" && PROJECT_ROOT="$P" bash bin/model-stamp.sh write pass test >/dev/null 2>&1 )
( cd "$P" && PROJECT_ROOT="$P" bash bin/model-stamp.sh write pass test >/dev/null 2>&1 )
{ [ "$(nmatch "$P/.gitignore" '\.claude/\.model-verified')" = 1 ] && [ "$(ncrlf "$P/.gitignore")" = "$(nlines "$P/.gitignore")" ]; } \
  && ok "entry once after two writes, every line CRLF" || bad "model-stamp: $(od -c "$P/.gitignore" | head -6)"

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
