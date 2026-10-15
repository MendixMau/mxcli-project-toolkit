#!/usr/bin/env bash
# install-project-hooks.sh — the commit-time backstop for the mxbuild gate.
#
#   ./bin/install-project-hooks.sh           # install/refresh the pre-commit + revision-note hooks
#   ./bin/install-project-hooks.sh --check   # exit 1 if any is missing or stale
#
# Two jobs. (1) pre-commit: the mxbuild-gate backstop below. (2) post-commit + post-rewrite: the
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
  exit 1
fi

if [ "${1:-}" = "--check" ]; then
  rc=0
  if [ -f "$HOOK" ] && grep -q "^$MARK" "$HOOK"; then echo "  ✓ pre-commit hook installed ($HOOK)"
  else echo "  ✗ pre-commit model-verification hook missing — run ./bin/install-project-hooks.sh"; rc=1; fi
  for h in post-commit post-rewrite; do
    if [ -f "$HOOKS/$h" ] && grep -q "^$NOTE_MARK" "$HOOKS/$h"; then echo "  ✓ $h revision-note hook installed"
    else echo "  ✗ $h revision-note hook missing — run ./bin/install-project-hooks.sh"; rc=1; fi
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
