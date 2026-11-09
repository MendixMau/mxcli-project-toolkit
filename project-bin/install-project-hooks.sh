#!/usr/bin/env bash
# install-project-hooks.sh — the commit-time backstop for the mxbuild gate.
#
#   ./bin/install-project-hooks.sh           # install/refresh the pre-commit, pre-push + revision-note hooks
#   ./bin/install-project-hooks.sh --check   # exit 1 if any is missing or stale
#
# Three jobs. (1) pre-commit: the mxbuild-gate backstop below. (2) post-commit + post-rewrite: the
# Studio Pro revision note (2026-10-12, field project). Studio Pro's History pane lists a commit's
# changed documents from refs/notes/mx_metadata "ModelChanges", which only Studio Pro filled; CLI
# commits showed "Model changes 0". These hooks run bin/mx-metadata-note.py write HEAD after every
# commit, amend and rebase; they never block (a missing note costs a History entry, nothing
# more). Notes are published explicitly, never by `git push`: after pushing the branch, run
# mx-metadata-note.py sync <remote> (fetch, 3-way merge, push the notes ref).
#
# No push config, ever (review decision, 2026-10-14). An earlier revision of this script added
# `HEAD` + `refs/notes/mx_metadata:refs/notes/mx_metadata` to remote.<r>.push. Any push refspec
# replaces push.default for that remote: `HEAD` pushed a branch tracking a differently named
# upstream to a NEW same-named branch (push.default=simple refuses that), a detached HEAD failed
# confusingly, the notes refspec failed the whole push while no local notes ref existed, and
# nobody knows whether Studio Pro's own push reads remote.<r>.push at all. So git and Studio Pro
# push exactly as they do without this toolkit. The installer only fetches the remote's notes
# (non-forced, creates the ref) and removes the exact pair that earlier revision wrote.
#
# (3) post-merge + post-checkout: the restatement-guard marker (#504). script-owners.sh's
# last-writer ledger (.claude/loop/script-owners/written.tsv, machine-local) sees only exec.sh's
# writes, so a `git pull` / `git checkout` that brought newer model work in left it saying "S wrote
# last", and a replay of S over that work stayed quiet. When the operation changed the .mpr or
# mprcontents/, the hook appends `<epoch> RESTORE git-<op>:<sha>` exactly as restore-mpr.sh does;
# rows before it stop counting and the next replay check asks the model (DESCRIBE, at most 5).
# A file checkout (`git checkout -- <paths>`) names no paths to the hook, so it always marks:
# the cost is at most one capped DESCRIBE round. No ledger yet → nothing to mark. Never blocks.
#
# WHY (2026-09-17, field project). A model can change without the mxbuild gate ever running — a
# bare `./mxcli exec`, an exec.sh run on a machine with no mxbuild, a Studio Pro save —
# and until now every such change committed and pushed like any other. The hook refuses
# a commit that stages model files (the .mpr and mprcontents/) unless bin/model-stamp.sh
# holds a PASS stamp for exactly that staged content. Commits that touch no model file
# are untouched. It runs on every machine, cloud or laptop, with no toolkit clone needed.
#
# Guard rules (toolkit CLAUDE.md, "Shipping an instrument" rules 6/7):
#   * rule 7 — it never blocks the remedy: ./bin/verify-model.sh is not itself a commit, so
#     there is always a way to earn the stamp without going through this hook.
#   * rule 6 — a missing/stale bin/model-stamp.sh stamp is not the only evidence accepted.
#     A recent PASS row in docs/BUILD-LOG.md (written by exec.sh on every exec, independently
#     of the stamp file — the two share no code path) lets the commit through, with a warning
#     naming which row it trusted. A stale or non-pass row does not count. Absent BOTH the
#     stamp and a qualifying BUILD-LOG row, MODEL_UNVERIFIED_OK=1 lets one commit through,
#     out loud, when someone decides to.
#
# An existing pre-commit hook that is not ours is kept and chained (moved to
# pre-commit.pre-mxtk, called first). A repo with core.hooksPath set is reported, not
# edited — its hooks live somewhere this script must not write to.
set -e
. "$(dirname "$0")/_common.sh"

cd "$PROJECT_ROOT"
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "install-project-hooks.sh: $PROJECT_ROOT is not in a git repository"; exit 2; }
HOOKS="$(git rev-parse --git-path hooks)"
HOOK="$HOOKS/pre-commit"
MARK="# mxtk-model-stamp hook v1"
# bin/ relative to the git top level, so the hook works when the project root is a subdir.
BIN_REL="$(git rev-parse --show-prefix)bin"

NOTE_MARK="# mxtk-mx-metadata hook v1"
RESTATE_MARK="# mxtk-restatement-mark hook v1"
# Team Server remotes: the platform's git host, plus any remote named in MXTK_TS_REMOTES.
# The configured URL, not `git remote -v`: that one shows the URL after url.*.insteadOf rewriting.
ts_remotes() {
  { git config --get-regexp '^remote\..*\.url$' 2>/dev/null \
      | awk '$2 ~ /git\.api\.mendix\.com/ { n = $1; sub(/^remote\./, "", n); sub(/\.url$/, "", n); print n }'
    for r in ${MXTK_TS_REMOTES:-}; do git config --get "remote.$r.url" >/dev/null 2>&1 && echo "$r"; done
  } | sort -u
}
has_notes() { git rev-parse -q --verify refs/notes/mx_metadata >/dev/null 2>&1; }
# The exact pair an earlier revision of this script wrote (HEAD first, only when the remote had
# no push config). Anything else in remote.<r>.push is the user's, and is never touched.
OLD_PAIR="HEAD
refs/notes/mx_metadata:refs/notes/mx_metadata"
leftover() {   # ours | foreign | none
  _p="$(git config --get-all "remote.$1.push" 2>/dev/null)"
  if [ "$_p" = "$OLD_PAIR" ]; then echo ours
  elif printf '%s\n' "$_p" | grep -q 'refs/notes/mx_metadata'; then echo foreign
  else echo none; fi
}

if [ -n "$(git config --get core.hooksPath 2>/dev/null)" ]; then
  echo "⚠ core.hooksPath is set ($(git config --get core.hooksPath)) — add this to that pre-commit yourself:"
  echo "    \"\$(git rev-parse --show-toplevel)/$BIN_REL/model-stamp.sh\" check --staged || exit 1"
  echo "  and this to its post-commit (revision notes for Studio Pro History; python via resolve_py, never the shebang):"  # portability-ok: advice text
  echo "    b=\"\$(git rev-parse --show-toplevel)/$BIN_REL\"; py=\"\$(PROJECT_ROOT=\"\$b/..\" bash -c '. \"\$1/_common.sh\" >/dev/null 2>&1 && resolve_py' _ \"\$b\")\""
  echo "    [ -n \"\$py\" ] && MXTK_HOOK=1 \"\$py\" \"\$b/mx-metadata-note.py\" write HEAD || true"
  echo "  and this to its post-merge and post-checkout (restatement-ledger marker, #504; for post-checkout use \"\$1\" \"\$2\" in place of ORIG_HEAD HEAD):"
  echo "    l=\"\$(git rev-parse --show-toplevel)/$BIN_REL/../.claude/loop/script-owners/written.tsv\"; [ -f \"\$l\" ] && git diff --name-only ORIG_HEAD HEAD | grep -qE '(\\.mpr\$|(^|/)mprcontents/)' \\"
  echo "      && printf '%s\\tRESTORE\\tgit-hook:%s\\n' \"\$(date +%s)\" \"\$(git rev-parse --short HEAD)\" >> \"\$l\"; true"
  exit 1
fi

if [ "${1:-}" = "--check" ]; then
  rc=0
  if [ -f "$HOOK" ] && grep -q "^$MARK" "$HOOK"; then echo "  ✓ pre-commit hook installed ($HOOK)"
  else echo "  ✗ pre-commit model-verification hook missing — run ./bin/install-project-hooks.sh"; rc=1; fi
  # Missing pre-push = rc 1, so sync-project.sh (which installs only when --check fails) adds it
  # to existing projects: `Gate mode: check` is the default, and this hook is its full build.
  # v2 (#686): full build once per module. A v1 hook fails --check so sync-project.sh refreshes it.
  if [ -f "$HOOKS/pre-push" ] && grep -q "^# mxtk-pre-push full-build hook v2" "$HOOKS/pre-push"; then echo "  ✓ pre-push full-build hook installed"
  else echo "  ✗ pre-push full-build hook missing or older than v2 — run ./bin/install-project-hooks.sh"; rc=1; fi
  for h in post-commit post-rewrite; do
    if [ -f "$HOOKS/$h" ] && grep -q "^$NOTE_MARK" "$HOOKS/$h"; then echo "  ✓ $h revision-note hook installed"
    else echo "  ✗ $h revision-note hook missing — run ./bin/install-project-hooks.sh"; rc=1; fi
  done
  for h in post-merge post-checkout; do
    if [ -f "$HOOKS/$h" ] && grep -q "^$RESTATE_MARK" "$HOOKS/$h"; then echo "  ✓ $h restatement-ledger hook installed"
    else echo "  ✗ $h restatement-ledger hook missing — run ./bin/install-project-hooks.sh"; rc=1; fi
  done
  for r in $(ts_remotes); do
    case "$(leftover "$r")" in
      ours)    echo "  ✗ remote.$r.push still holds the HEAD + notes refspecs an earlier toolkit revision added — run ./bin/install-project-hooks.sh to remove them"; rc=1 ;;
      foreign) echo "  – remote.$r.push names refs/notes/mx_metadata beside other entries; not ours to remove (see 'git config --get-all remote.$r.push')" ;;
    esac
  done
  exit $rc
fi

mkdir -p "$HOOKS"
if [ -f "$HOOK" ] && ! grep -q "^$MARK" "$HOOK"; then
  mv "$HOOK" "$HOOK.pre-mxtk"
  echo "  existing pre-commit hook kept as $(basename "$HOOK").pre-mxtk and chained first"
fi
cat > "$HOOK" <<HOOKEOF
#!/usr/bin/env bash
$MARK — written by bin/install-project-hooks.sh (mxcli-project-toolkit). Re-run it to refresh.
top="\$(git rev-parse --show-toplevel)"
[ -x "\$(dirname "\$0")/pre-commit.pre-mxtk" ] && { "\$(dirname "\$0")/pre-commit.pre-mxtk" || exit 1; }
stamp="\$top/$BIN_REL/model-stamp.sh"
if [ ! -x "\$stamp" ]; then
  echo "⚠ $BIN_REL/model-stamp.sh is missing — the model-verification hook cannot check this commit (re-run the toolkit's sync-project.sh)" >&2
  exit 0
fi
if ! "\$stamp" check --staged; then
  alt=""
  blog="\$top/docs/BUILD-LOG.md"
  max_age="\${MODEL_EVIDENCE_MAX_AGE:-14400}"
  if [ -f "\$blog" ]; then
    bmtime="\$(stat -c %Y "\$blog" 2>/dev/null || stat -f %m "\$blog" 2>/dev/null || echo 0)"
    case "\$bmtime" in ''|*[!0-9]*) bmtime=0 ;; esac
    now="\$(date +%s)"
    lastrow="\$(grep '^| 20' "\$blog" 2>/dev/null | tail -1)"
    if [ "\$bmtime" -gt 0 ] && [ \$(( now - bmtime )) -le "\$max_age" ] && printf '%s' "\$lastrow" | grep -q '| pass |'; then
      alt="a recent docs/BUILD-LOG.md row (gate: pass, \$(( (now - bmtime) / 60 )) min ago)"
    fi
  fi
  if [ -n "\$alt" ]; then
    echo "⚠ no local model-stamp, but accepting \$alt as evidence the model was mxbuild-gated." >&2
    echo "  (this is NOT a guarantee the staged content matches that row — verify-model.sh is the strong check)" >&2
  elif [ "\${MODEL_UNVERIFIED_OK:-0}" = "1" ]; then
    echo "⚠ MODEL_UNVERIFIED_OK=1 — committing a model the mxbuild gate has not verified." >&2
  else
    echo "" >&2
    echo "✗ commit refused: the staged model has not passed the mxbuild gate on this machine." >&2
    echo "  Run   ./bin/verify-model.sh   (one mxbuild, stamps the model when clean), then commit again." >&2
    echo "  Deliberate override, once:   MODEL_UNVERIFIED_OK=1 git commit ..." >&2
    exit 1
  fi
fi
exit 0
HOOKEOF
chmod +x "$HOOK"
echo "  ✓ pre-commit hook installed -> $HOOK"
echo "    (refuses to commit .mpr/mprcontents changes that have no mxbuild-gate PASS stamp; ./bin/verify-model.sh writes one)"

# --- pre-push: the full build `Gate mode: check` defers (exec.sh "Gate kind") ------------------------
# Under `Gate mode: check` (the default) exec.sh runs `mx check` per script, which compiles no Java. A push is where
# a model leaves this machine, so this hook runs the full mxbuild (bin/verify-model.sh) when the
# stamp matches the model but says `mx check` only. It does the remedy itself (guard rule 7) and
# refuses only when that full build finds errors. Every other project: a no-op (no gate-kind state,
# or a full-build stamp, or a stamp that does not match — the pre-commit hook's business).
# MODEL_UNVERIFIED_OK=1 pushes anyway, once, out loud.
#
# Once per module, not every push (#686: one full mxbuild per push, 1-2 min, on rows that average
# 19 min), under `Pipeline mode: balanced` (the default, also with no line) and `high-speed`.
# module-close.sh already runs this full build at the module boundary, so mid-module pushes skip
# it. The build runs when (a) no full build was ever recorded here (.claude/loop/prepush-build.last,
# written by this hook's and module-close.sh's passing full builds), (b) a module-close report is
# newer than that stamp, (c) a pushed commit touches docs/progress/module-close/, (d) Java/JavaScript/
# theme files changed since the last full build (gate-kind.state's `java` fingerprint vs
# _common.sh mxtk_model_java_fp, the helper exec.sh records with), or (e)
# MXTK_PREPUSH_MAX_DEFERRED (10) pushes in a row deferred it, so a
# project that never runs module-close still gets one. `Pipeline mode: high-quality` (_common.sh
# mxtk_pipeline_mode) or MXTK_PREPUSH_BUILD=always: every push, as before #686. If _common.sh cannot
# be read, the hook builds: unsure means the safe side (PR #700 review).
PP="$HOOKS/pre-push"
PP_MARK="# mxtk-pre-push full-build hook v2"
# Any version of our own hook is replaced in place; only a foreign hook is kept and chained.
if [ -f "$PP" ] && ! grep -q "^# mxtk-pre-push full-build hook v" "$PP"; then
  mv "$PP" "$PP.pre-mxtk"
  echo "  existing pre-push hook kept as pre-push.pre-mxtk and chained first"
fi
cat > "$PP" <<HOOKEOF
#!/usr/bin/env bash
$PP_MARK — written by bin/install-project-hooks.sh (mxcli-project-toolkit). Re-run it to refresh.
input="\$(cat)"
[ -x "\$(dirname "\$0")/pre-push.pre-mxtk" ] && { printf '%s\n' "\$input" | "\$(dirname "\$0")/pre-push.pre-mxtk" "\$@" || exit 1; }
b="\$(git rev-parse --show-toplevel)/$BIN_REL"
[ -x "\$b/model-stamp.sh" ] && [ -f "\$b/verify-model.sh" ] && [ -f "\$b/../.claude/loop/gate-kind.state" ] || exit 0
"\$b/model-stamp.sh" check -q >/dev/null 2>&1 || exit 0
"\$b/model-stamp.sh" check -q --full >/dev/null 2>&1 && exit 0
last="\$b/../.claude/loop/prepush-build.last"
info="\$(PROJECT_ROOT="\$b/.." bash -c '. "\$1/_common.sh" >/dev/null 2>&1 || exit 1; mxtk_pipeline_mode "\$1/.." || exit 1; mxtk_model_java_fp "\$1/.."' _ "\$b" 2>/dev/null)"
mode="\$(printf '%s\n' "\$info" | sed -n 1p)"; jfp="\$(printf '%s\n' "\$info" | sed -n 2p)"
cnt="\$b/../.claude/loop/prepush-deferred"
if [ "\${MXTK_PREPUSH_BUILD:-module}" != always ] && [ "\$mode" != high-quality ]; then
  due=""
  mc="\$b/../docs/progress/module-close"
  case "\$mode" in
    balanced|high-speed) ;;
    *) due="the pipeline mode could not be read (bin/_common.sh), so building to be safe" ;;
  esac
  [ -z "\$due" ] && [ ! -f "\$last" ] && due="no full build recorded on this machine yet"
  [ -z "\$due" ] && [ -d "\$mc" ] && [ -n "\$(find "\$mc" -name '*.md' -newer "\$last" 2>/dev/null | head -1)" ] && due="a module-close report newer than the last full build"
  if [ -z "\$due" ]; then
    z=0000000000000000000000000000000000000000
    while read -r _lr lsha _rr rsha; do
      [ -n "\$lsha" ] && [ "\$lsha" != "\$z" ] || continue
      if [ -n "\$rsha" ] && [ "\$rsha" != "\$z" ] && git cat-file -e "\$rsha" 2>/dev/null; then files="\$(git diff --name-only "\$rsha" "\$lsha" 2>/dev/null)"
      else files="\$(git log --name-only --format= "\$lsha" --not --remotes 2>/dev/null)"; fi
      printf '%s\n' "\$files" | grep -q 'docs/progress/module-close/' && { due="this push carries a module-close commit"; break; }
    done <<< "\$input"
  fi
  if [ -z "\$due" ] && [ -n "\$jfp" ]; then
    rec="\$(sed -n 's/^java //p' "\$b/../.claude/loop/gate-kind.state" 2>/dev/null | tail -1)"
    [ -n "\$rec" ] && [ "\$rec" != "\$jfp" ] && due="Java/JavaScript/theme files changed since the last full build"
  fi
  n="\$(cat "\$cnt" 2>/dev/null)"; case "\$n" in ''|*[!0-9]*) n=0 ;; esac
  [ -z "\$due" ] && [ "\$n" -ge "\${MXTK_PREPUSH_MAX_DEFERRED:-10}" ] && due="\$n pushes in a row deferred the full build"
  if [ -z "\$due" ]; then
    echo \$((n + 1)) > "\$cnt" 2>/dev/null
    echo "→ pre-push: model mx-checked only; full build deferred to module close (bin/module-close.sh; Pipeline mode: \$mode). Every push: Pipeline mode: high-quality, or MXTK_PREPUSH_BUILD=always." >&2
    exit 0
  fi
  echo "→ pre-push: \$due." >&2
fi
if [ "\${MODEL_UNVERIFIED_OK:-0}" = "1" ]; then
  echo "⚠ MODEL_UNVERIFIED_OK=1 — pushing a model verified by mx check only (no Java compile)." >&2; exit 0
fi
echo "→ pre-push: the model was verified by mx check only; running the full build first (bin/verify-model.sh)..." >&2
( cd "\$b/.." && bash bin/verify-model.sh ) >&2; vrc=\$?
[ "\$vrc" = 0 ] && { mkdir -p "\$(dirname "\$last")" && touch "\$last" && rm -f "\$cnt"; } 2>/dev/null
# verify-model.sh builds a copy (.mxtk/build/) and says so; the restart line only after an in-place build (#686).
[ "\$vrc" = 0 ] && ! grep -qs '^copy' "\$b/../.claude/loop/last-full-build" && echo "→ pre-push: full build done: if the app runs with --watch, run \\\`mxcli run restart\\\` before the next LOOK" >&2
if [ "\$vrc" = 1 ]; then
  echo "✗ push refused: the full build found errors (above). Fix them, commit, push again." >&2
  echo "  Deliberate override, once:   MODEL_UNVERIFIED_OK=1 git push ..." >&2
  exit 1
elif [ "\$vrc" != 0 ]; then
  # exit 2: mxbuild could not run here — not a finding about the model; never block the push on it.
  echo "⚠ pre-push: the full build could not run on this machine (verify-model.sh exit \$vrc) — pushing a model verified by mx check only." >&2
fi
exit 0
HOOKEOF
chmod +x "$PP"
echo "  ✓ pre-push hook installed (full build once per module; every push under Pipeline mode: high-quality)"

# --- revision notes for Studio Pro History (post-commit + post-rewrite) -------------------------
# Both hooks find Python through bin/_common.sh's resolve_py (executes each candidate, skips the
# Windows Store alias stub). No Python, or no _common.sh: one warning, the commit stands.
for h in post-commit post-rewrite; do
  HF="$HOOKS/$h"
  if [ -f "$HF" ] && ! grep -q "^$NOTE_MARK" "$HF"; then
    mv "$HF" "$HF.pre-mxtk"
    echo "  existing $h hook kept as $h.pre-mxtk and chained first"
  fi
  if [ "$h" = post-commit ]; then
    RUN='note_one HEAD'
    CHAIN='[ -x "$(dirname "$0")/post-commit.pre-mxtk" ] && "$(dirname "$0")/post-commit.pre-mxtk"'
  else
    # stdin: "<old> <new> [extra]" per rewritten commit (amend, rebase). Read it once, feed both.
    RUN='printf "%s\n" "$input" | while read -r _old new _rest; do [ -n "$new" ] && note_one "$new"; done'
    CHAIN='[ -x "$(dirname "$0")/post-rewrite.pre-mxtk" ] && printf "%s\n" "$input" | "$(dirname "$0")/post-rewrite.pre-mxtk" "$@"'
  fi
  cat > "$HF" <<HOOKEOF
#!/usr/bin/env bash
$NOTE_MARK — written by bin/install-project-hooks.sh (mxcli-project-toolkit). Re-run it to refresh.
# Writes the Studio Pro revision note (refs/notes/mx_metadata, with ModelChanges) for model commits.
# Never fails the git operation: every problem is one warning on stderr.
$( [ "$h" = post-rewrite ] && echo 'input="$(cat)"' )
$CHAIN
note="\$(git rev-parse --show-toplevel)/$BIN_REL/mx-metadata-note.py"
proj="\$(dirname "\$(dirname "\$note")")"
# mxcli v0.26+ writes this note itself (mxcli git note, mendixlabs/mxcli#1337): prefer it when the
# project's pinned binary has the command; older pins fall back to bin/mx-metadata-note.py.
mx="\$proj/mxcli"; mpr="\$(ls "\$proj"/*.mpr 2>/dev/null | head -1)"
# Probe for --write in the help text: an mxcli with \`git\` but no \`note\` can still exit 0 on --help.
if [ -x "\$mx" ] && [ -n "\$mpr" ] && "\$mx" git note --help 2>&1 | grep -q -- '--write'; then
  note_one() { "\$mx" git note -p "\$mpr" --write "\$1" >/dev/null 2>&1 || echo "⚠ mxcli git note failed for \$1 — Studio Pro History will show 'Model changes 0' (re-run: ./mxcli git note -p \$(basename "\$mpr") --write \$1)" >&2; }
else
  [ -f "\$note" ] || exit 0
  py=""
  [ -f "\$(dirname "\$note")/_common.sh" ] && py="\$(PROJECT_ROOT="\$proj" bash -c '. "\$1/_common.sh" >/dev/null 2>&1 && resolve_py' _ "\$(dirname "\$note")" 2>/dev/null)"
  [ -z "\$py" ] && { echo "⚠ no python found — Studio Pro History will show 'Model changes 0' for this commit (bin/mx-metadata-note.py backfill fixes it later)" >&2; exit 0; }  # portability-ok: resolve_py above is the probe
  note_one() { MXTK_HOOK=1 "\$py" "\$note" write "\$1" || true; }
fi
$RUN
exit 0
HOOKEOF
  chmod +x "$HF"
done
echo "  ✓ post-commit + post-rewrite revision-note hooks installed (Studio Pro History lists each commit's changed documents)"

# --- restatement-guard ledger marker (post-merge + post-checkout), #504 --------------------------
# post-merge: $1 = 1 for a squash merge (HEAD unmoved: always mark), else the range ORIG_HEAD..HEAD.
# post-checkout: $1 prev, $2 new, $3 = 1 for a branch checkout, 0 for a file checkout (no paths
# given to the hook: always mark).
for h in post-merge post-checkout; do
  HF="$HOOKS/$h"
  if [ -f "$HF" ] && ! grep -q "^$RESTATE_MARK" "$HF"; then
    mv "$HF" "$HF.pre-mxtk"
    echo "  existing $h hook kept as $h.pre-mxtk and chained first"
  fi
  if [ "$h" = post-merge ]; then RANGE='ORIG_HEAD HEAD'; FILEMODE='[ "${1:-0}" = 1 ]'
  else RANGE='"$1" "$2"'; FILEMODE='[ "${3:-1}" = 0 ]'; fi
  cat > "$HF" <<HOOKEOF
#!/usr/bin/env bash
$RESTATE_MARK — written by bin/install-project-hooks.sh (mxcli-project-toolkit). Re-run it to refresh.
# Marks the restatement guard's last-writer ledger when this $h changed the model (.mpr or
# mprcontents/), so a replay of an older script asks the model again. Never fails the git operation.
[ -x "\$(dirname "\$0")/$h.pre-mxtk" ] && "\$(dirname "\$0")/$h.pre-mxtk" "\$@"
top="\$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
ledger="\$top/$BIN_REL/../.claude/loop/script-owners/written.tsv"
[ -f "\$ledger" ] || exit 0
if $FILEMODE; then why="unscoped"
else
  git diff --name-only $RANGE 2>/dev/null | grep -qE '(\.mpr\$|(^|/)mprcontents/)' || exit 0
  why="\$(git rev-parse --short HEAD 2>/dev/null)"
fi
printf '%s\tRESTORE\tgit-$h:%s\n' "\$(date +%s)" "\$why" >> "\$ledger" 2>/dev/null || true
exit 0
HOOKEOF
  chmod +x "$HF"
done
echo "  ✓ post-merge + post-checkout restatement-ledger hooks installed (a pull/checkout that changes the model resets the last-writer ledger)"

for r in $(ts_remotes); do
  if ! has_notes && GIT_TERMINAL_PROMPT=0 git fetch -q "$r" refs/notes/mx_metadata:refs/notes/mx_metadata >/dev/null 2>&1; then
    echo "  ✓ $r: fetched its refs/notes/mx_metadata (non-forced; Studio Pro's notes, so ours merge onto them)"
  fi
  case "$(leftover "$r")" in
    ours)    git config --unset-all "remote.$r.push"
             echo "  ✓ $r: removed the HEAD + notes push refspecs an earlier toolkit revision added — git push behaves as git's default again" ;;
    foreign) echo "  ⚠ $r: remote.$r.push names refs/notes/mx_metadata beside other entries — left alone, as it may be yours." ;;
  esac
done
echo "  Publish the History notes after pushing a branch:  \"\$PY\" bin/mx-metadata-note.py sync <remote>   (PY from resolve_py)"
