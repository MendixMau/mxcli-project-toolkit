#!/usr/bin/env bash
# model-stamp.sh — the verification stamp: "THIS model state was mxbuild-verified".
#
#   ./bin/model-stamp.sh fingerprint [--staged]   # print the model fingerprint
#   ./bin/model-stamp.sh write <state> <source…>  # record that the current model was verified
#   ./bin/model-stamp.sh check [--staged] [-q] [--clean] [--full]  # exit 0 iff the (staged) model matches a PASS stamp
#                                                          (--clean: and that pass saw 0 mxbuild errors;
#                                                           --full: and it was a full mxbuild, not `mx check`)
#   ./bin/model-stamp.sh clear                    # forget the stamp (the model changed unverified)
#   ./bin/model-stamp.sh paths                    # the repo-relative model paths this covers
#
# WHY (2026-09-17, field project). exec.sh's mxbuild gate is the only thing that can see a
# consistency error like CE0117 (`mxcli check` cannot), and exec.sh is the only thing
# that runs it. Nothing sat between "the model changed" and "the model was committed":
# a bare `./mxcli exec` wrote nine scripts with no gate at all, exec.sh itself wrote
# and warned when mxbuild was missing, and every one of those commits looked like every
# other commit. A CE0117 reached the Team Server that way.
#
# The stamp closes that gap at COMMIT time, on any machine, in any session:
#   * exec.sh writes it only when its gate reports PASS (bin/exec.sh);
#   * bin/verify-model.sh writes it after a standalone clean mxbuild — the remedy the
#     hook points at (rule 7: a guard never blocks the action that resolves it);
#   * the pre-commit hook (bin/install-project-hooks.sh) refuses to commit model files
#     whose staged fingerprint does not match a PASS stamp — UNLESS a recent PASS row
#     in docs/BUILD-LOG.md (written by exec.sh independently of this stamp file, and
#     pre-dating this stamp mechanism) stands in as evidence, per rule 6 ("never only
#     its own stamp file" — see install-project-hooks.sh for that check). Absent both,
#     MODEL_UNVERIFIED_OK=1 overrides once, out loud.
#
# The fingerprint is a SHA-256 over "<git blob hash> <path>" for the .mpr and every
# file under its mprcontents/ (MPR v2 keeps unit content there, so the .mpr alone is
# not the model). Working tree and index are hashed the same way — `git hash-object`
# applies the same clean filters the index carries — so a fully staged model gives the
# same fingerprint as the working tree it was verified in. Outside a git repo the
# fallback is a checksum of the files themselves; the hook does not exist there anyway.
#
# The stamp is machine-local (.claude/.model-verified, self-gitignored): a clone on
# another machine starts unverified, which is the truth.
set -e
_msd="${0%/*}"; [ "$_msd" != "$0" ] || _msd=.   # dirname without a process
. "$_msd/_common.sh"
_NL=$'\n'

STAMP="$PROJECT_ROOT/.claude/.model-verified"

# `clear` needs nothing but the stamp path. Under exec.sh (a model resolved once for the run) it
# answers before the model, git and fingerprint set-up below, which `clear` never reads.
if [ "${1:-}" = clear ] && _mxtk_mpr_memo_ok; then
  [ ! -e "$STAMP" ] || rm -f "$STAMP"
  echo "  verification stamp cleared"; exit 0
fi

_real() {  # resolve symlinks by hand (GNU-only resolvers are absent on older macOS)
  local p="$1" d
  while [ -L "$p" ]; do
    d="${p%/*}"; [ "$d" != "$p" ] || d=.
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  d="${p%/*}"; [ "$d" != "$p" ] || d=.; [ -n "$d" ] || d=/
  printf '%s/%s\n' "$(cd "$d" && pwd -P)" "${p##*/}"
}

# Pin git's view of the repository before any `git -C "$MODEL_DIR"` below.
#
# WHY (2026-09-26, card-disbursement requirements-driven build). A commit made from a
# `git worktree` runs this hook with GIT_DIR exported (the absolute .git/worktrees/<name>),
# and so does `git --git-dir=… commit` (a RELATIVE GIT_DIR). Git's rule for GIT_DIR without
# GIT_WORK_TREE is "the current directory is the top of the work tree" — so on a two-tree
# checkout `git -C app …` saw app/ as the top with an empty prefix, the pathspecs
# `App.mpr mprcontents` matched nothing in an index that holds `app/App.mpr`, and
# `check --staged` said "no model files staged" and passed a model nobody had verified
# (a relative GIT_DIR instead made `git -C app` fail, `in_git` false, exit 0: same pass).
# Resolving the top once from the caller's cwd and exporting absolute paths makes every
# later `git -C` agree with the git that invoked the hook.
_mxtk_abs() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$(pwd -P)" "$1" ;; esac; }
case "${GIT_INDEX_FILE:-}" in ''|/*) ;; *) GIT_INDEX_FILE="$(_mxtk_abs "$GIT_INDEX_FILE")"; export GIT_INDEX_FILE ;; esac
if [ -n "${GIT_DIR:-}" ]; then
  _gtop="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  GIT_DIR="$(_mxtk_abs "$GIT_DIR")"; export GIT_DIR
  if [ -n "${GIT_WORK_TREE:-}" ]; then GIT_WORK_TREE="$(_mxtk_abs "$GIT_WORK_TREE")"; export GIT_WORK_TREE
  elif [ -n "$_gtop" ]; then GIT_WORK_TREE="$_gtop"; export GIT_WORK_TREE; fi
fi

# A project with no model yet (requirements-driven Stages P-4) has nothing to verify.
#
# WHY (2026-09-25, same build). `find_mpr` failing used to end every command here, `check`
# included — so the pre-commit hook refused the Stage P intake commit with "no .mpr found"
# although nothing model-related was staged, and each pre-model commit needed the override.
# `check` now passes when no .mpr exists at the root, under app/ or under apps/<X>/ AND no model path
# (*.mpr, mprcontents/) is staged; a staged model that no .mpr resolves still refuses, and
# two .mpr files still refuse (find_mpr's "refusing to guess"). Every other command still
# needs a model: a stamp or fingerprint over no model would be a constant.
# The same three-layout probe as the root search (_common.sh _mxtk_has_model, #420): without
# apps/<X>/ a staged model in a multi-app folder exited 1 "no .mpr resolves". The inline
# fallback is for an older hand-edited _common.sh that sync held back.
_mxtk_any_mpr() {
  if type _mxtk_has_model >/dev/null 2>&1; then _mxtk_has_model "$PROJECT_ROOT"; return; fi
  local f; for f in "$PROJECT_ROOT"/*.mpr "$PROJECT_ROOT"/app/*.mpr "$PROJECT_ROOT"/apps/*/*.mpr; do [ -e "$f" ] && return 0; done; return 1
}
# A multi-app folder with several apps (apps/A/A.mpr, apps/B/B.mpr) has no single model either:
# find_mpr refuses to guess, and that refusal must not block every commit (#420). So `check`
# treats it like the no-model case: nothing model-related staged passes; staged files that all
# sit under ONE apps/<X>/ are checked against that app's .mpr; staged files across several apps
# refuse and name MPR_FILE.
_mxtk_several_apps() {
  ls "$PROJECT_ROOT"/*.mpr >/dev/null 2>&1 && return 1
  ls "$PROJECT_ROOT"/app/*.mpr >/dev/null 2>&1 && return 1
  [ "$(ls "$PROJECT_ROOT"/apps/*/*.mpr 2>/dev/null | wc -l | tr -d ' ')" -gt 1 ]
}
_several=0
# Under exec.sh the model was resolved once for this run (MXTK_MPR_MEMO): a single .mpr exists,
# so neither the several-apps nor the no-model probe (six ls processes) can apply.
if [ "${1:-}" = "check" ] && [ -z "${MPR_FILE:-}" ] && ! _mxtk_mpr_memo_ok && _mxtk_several_apps; then _several=1; fi
if [ "${1:-}" = "check" ] && [ -z "${MPR_FILE:-}" ] && ! _mxtk_mpr_memo_ok && { [ "$_several" = 1 ] || ! _mxtk_any_mpr; }; then
  _q=0; for a in "$@"; do case "$a" in -q|--quiet) _q=1 ;; esac; done
  _staged=""
  if git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    _staged="$(git -C "$PROJECT_ROOT" diff --cached --name-only --diff-filter=d 2>/dev/null \
      | grep -E '(^|/)[^/]+\.mpr$|(^|/)mprcontents/' || true)"
    # the same list relative to the project folder, to tell which apps/<X>/ it touches
    [ "$_several" = 1 ] && _staged="$(git -C "$PROJECT_ROOT" diff --cached --name-only --relative --diff-filter=d 2>/dev/null \
      | grep -E '(^|/)[^/]+\.mpr$|(^|/)mprcontents/' || true)"
  fi
  if [ -z "$_staged" ]; then
    if [ "$_several" = 1 ]; then
      [ "$_q" = 1 ] || echo "  several apps under apps/ and no model files staged — nothing to verify"
    else
      [ "$_q" = 1 ] || echo "  no model in this project yet (no .mpr at the root, under app/ or under apps/<X>/) — nothing to verify"
    fi
    exit 0
  fi
  if [ "$_several" = 1 ]; then
    _apps="$(printf '%s\n' "$_staged" | sed -n 's#^\(apps/[^/]*\)/.*#\1#p' | sort -u)"
    if [ "$(printf '%s\n' "$_staged" | grep -vc '^apps/[^/]*/')" -eq 0 ] && [ "$(printf '%s\n' "$_apps" | grep -c .)" -eq 1 ] \
       && [ "$(ls "$PROJECT_ROOT/$_apps"/*.mpr 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]; then
      MPR_FILE="$_apps/$(basename "$(ls "$PROJECT_ROOT/$_apps"/*.mpr)")"; export MPR_FILE
    else
      # Not "set MPR_FILE": that verifies one app and would let the others' staged changes
      # through unverified (the stamp covers one model's paths). One app per commit.
      echo "  ✗ model files are staged across several apps (or outside apps/<X>/) — commit one app at a time:" >&2
      printf '%s\n' "$_staged" | head -5 | sed 's/^/      /' >&2
      echo "    git reset apps/<Y>   (unstage the other apps), then" >&2
      echo "    MPR_FILE=apps/<X>/<X>.mpr ./bin/verify-model.sh   then commit; repeat per app" >&2
      exit 1
    fi
  else
    echo "  ✗ model files are staged, but no .mpr resolves under $PROJECT_ROOT (root, app/ or apps/<X>/):" >&2
    printf '%s\n' "$_staged" | head -5 | sed 's/^/      /' >&2
    exit 1
  fi
fi

# Several apps and MPR_FILE set (by the caller, or derived above): the stamp covers that one
# app's paths only, so a staged model path in ANY other folder would pass unverified. Refuse it
# and name the paths (#420 review: MPR_FILE=apps/A/A.mpr with A and B staged let B through).
if [ "${1:-}" = "check" ] && [ -n "${MPR_FILE:-}" ] && [ -d "$PROJECT_ROOT/apps" ] \
   && [ "$(ls "$PROJECT_ROOT"/apps/*/*.mpr 2>/dev/null | wc -l | tr -d ' ')" -gt 1 ] \
   && git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  _mdir="$(dirname "${MPR_FILE#"$PROJECT_ROOT"/}")"
  _outside="$(git -C "$PROJECT_ROOT" diff --cached --name-only --relative --diff-filter=d 2>/dev/null \
    | grep -E '(^|/)[^/]+\.mpr$|(^|/)mprcontents/' | grep -v "^$_mdir/" || true)"
  if [ -n "$_outside" ]; then
    _how=""; [ -n "${MXTK_MPR_PICKED:-}" ] && [ "$MPR_FILE" = "$MXTK_MPR_PICKED" ] && _how=" (picked from your cwd)"
    echo "  ✗ MPR_FILE=$MPR_FILE$_how covers $_mdir/ only, but model files outside it are staged:" >&2
    printf '%s\n' "$_outside" | head -5 | sed 's/^/      /' >&2
    echo "    commit one app at a time: git reset those paths, verify and commit $_mdir/, then the next app" >&2
    exit 1
  fi
fi

MPR="$(find_mpr)" || exit 1
MPR="$(_real "$MPR")"
MODEL_DIR="${MPR%/*}"; [ "$MODEL_DIR" != "$MPR" ] || MODEL_DIR=.
MPRC="$MODEL_DIR/mprcontents"

# git's answers for the model folder, asked ONCE per run of this script (it used to ask
# `rev-parse --show-toplevel` four to six times and `--show-prefix` twice: a process each).
# Called in the main shell before any $(...) so the subshells see the cached values.
_GI_DONE=""; _GI_IN=0; _GI_TOP=""; _GI_PFX=""
_git_info() {
  [ -z "$_GI_DONE" ] || return 0
  _GI_DONE=1
  local out
  if out="$(git -C "$MODEL_DIR" rev-parse --show-toplevel --show-prefix 2>/dev/null)"; then
    _GI_IN=1; _GI_TOP="${out%%$'\n'*}"
    if [ "$_GI_TOP" != "$out" ]; then _GI_PFX="${out#*$'\n'}"; else _GI_PFX=""; fi
  fi
  return 0
}
in_git() { _git_info; [ "$_GI_IN" = 1 ]; }

# Repo-relative paths (from the git top level), printed one per line.
model_paths() {
  _git_info
  printf '%s%s\n' "$_GI_PFX" "${MPR##*/}"
  [ -d "$MPRC" ] && printf '%smprcontents\n' "$_GI_PFX"
  return 0
}

# _load_model_paths — model_paths into the MODEL_PATHS array, one line per element.
#
# WHY (2026-09-17, review of this file). Every consumer used to say
# `git ls-files … -- $(model_paths)`, unquoted. A Mendix .mpr with a SPACE in its name is
# routine ("My Project.mpr"), and a glob character is legal too: word splitting then handed
# git two pathspecs that match nothing, git listed nothing, and the fingerprint silently
# covered FEWER files than the model has — so a model that changed could still match its own
# stamp, and the pre-commit hook would wave it through. Green-by-absence, inside the guard
# whose entire job is to prevent green-by-absence.
#
# An empty path set is never a fingerprint: see _fp_worktree/_fp_staged below.
MODEL_PATHS=()
_load_model_paths() {
  local n=0
  MODEL_PATHS=()
  _git_info
  # The same two entries model_paths prints, without running it in a subshell.
  [ -n "${MPR##*/}" ] && { MODEL_PATHS[$n]="${_GI_PFX}${MPR##*/}"; n=$((n + 1)); }
  [ -d "$MPRC" ] && { MODEL_PATHS[$n]="${_GI_PFX}mprcontents"; n=$((n + 1)); }
  if [ "$n" -eq 0 ]; then
    echo "model-stamp: no model paths resolved for $MPR — refusing to fingerprint (a stamp over" >&2
    echo "  nothing would match every model state, which is worse than no stamp at all)." >&2
    return 1
  fi
  return 0
}

_fp_worktree() {
  if in_git; then
    local top f h n=0 k=0 files=() hashes=(); _git_info; top="$_GI_TOP"
    _load_model_paths || return 1
    # Tracked + untracked-not-ignored, minus anything deleted in the working tree. Newline
    # separated: `git hash-object --stdin-paths` has no -z, and unit file names carry none.
    # Held in an array, not a temp file: the file, its rm and the paste that rejoined it with
    # the hashes were three more process starts per fingerprint.
    while IFS= read -r f; do
      [ -f "$top/$f" ] && files[${#files[@]}]="$f"
    done < <(cd "$top" && git ls-files -c -o --exclude-standard -- "${MODEL_PATHS[@]}" 2>/dev/null)
    n=${#files[@]}
    # An EMPTY list is not a fingerprint over nothing — that used to fall through to
    # `mxtk_sha256` over empty stdin, which is a CONSTANT, so a project whose mprcontents/
    # is gitignored fingerprinted identically no matter what the model contained, and every
    # stamp matched forever.
    #
    # A gitignored model is not the same failure as a MISSING one, though: the files are
    # still sitting right there on disk (find_mpr resolved $MPR before we got here), git
    # just isn't the one who can see them. So when every model path is actually ignored,
    # fall back to the same direct-file cksum the non-git branch below already uses — it
    # hashes real bytes, not an empty list, so it carries none of the constant-hash risk
    # this guard exists to prevent. Only a genuinely unresolvable empty set (paths git
    # neither tracks NOR ignores — e.g. deleted mid-session) still refuses.
    if [ "$n" -eq 0 ]; then
      local ignored=1 p
      for p in "${MODEL_PATHS[@]}"; do
        ( cd "$top" && git check-ignore -q -- "$p" ) || { ignored=0; break; }
      done
      if [ "$ignored" = 1 ]; then
        { cksum < "$MPR"; [ -d "$MPRC" ] && find "$MPRC" -type f -exec cksum {} + | LC_ALL=C sort -k3; } | mxtk_sha256
        return 0
      fi
      echo "model-stamp: git lists no files under $(printf '%s ' "${MODEL_PATHS[@]}")in $top —" >&2
      echo "  refusing to fingerprint (not gitignored either — the model path may not exist)." >&2
      echo "  a stamp over an empty set would match every model state." >&2
      return 1
    fi
    IFS=$'\n' read -r -d '' -a hashes < <(cd "$top" && printf '%s\n' "${files[@]}" | git hash-object --stdin-paths) || true
    for f in "${files[@]}"; do printf '%s %s\n' "${hashes[$k]:-}" "$f"; k=$((k + 1)); done \
      | LC_ALL=C sort -k2 | mxtk_sha256
  else
    { cksum < "$MPR"; [ -d "$MPRC" ] && find "$MPRC" -type f -exec cksum {} + | LC_ALL=C sort -k3; } | mxtk_sha256
  fi
}

_fp_staged() {
  in_git || { echo "model-stamp: not a git repository — --staged has no meaning" >&2; return 1; }
  local top lst; _git_info; top="$_GI_TOP"
  _load_model_paths || return 1
  lst="$(mktemp "${TMPDIR:-/tmp}/model-stamp.XXXXXX")"
  ( cd "$top" && git ls-files -s -- "${MODEL_PATHS[@]}" \
      | awk -F'\t' '{ split($1, a, " "); print a[2] " " $2 }' ) > "$lst"
  if [ ! -s "$lst" ]; then            # same constant-hash trap as _fp_worktree
    rm -f "$lst"
    echo "model-stamp: the index holds no model files under $(printf '%s ' "${MODEL_PATHS[@]}")—" >&2
    echo "  refusing to fingerprint an empty set." >&2
    return 1
  fi
  LC_ALL=C sort -k2 < "$lst" | mxtk_sha256
  rm -f "$lst"
}

fingerprint() { if [ "${1:-}" = "--staged" ]; then _fp_staged; else _fp_worktree; fi; }

# The stamp is a handful of "key: value" lines. _sload reads it once; _sf <key> sets _SF to the
# value of the FIRST line with that key (what `sed -n "s/^key: //p" | head -1` printed, at two
# process starts per field and six fields per check).
_stxt=""
_sload() { _stxt=""; IFS= read -r -d '' _stxt < "$STAMP" 2>/dev/null || true; }
_sf() { _SF=""; if [[ "$_NL$_stxt" =~ $_NL$1:\ ([^$_NL]*) ]]; then _SF="${BASH_REMATCH[1]}"; fi; return 0; }

cmd="${1:-}"; shift || true
case "$cmd" in fingerprint|write|check|paths) _git_info ;; esac
case "$cmd" in
  fingerprint) fingerprint "${1:-}" ;;
  paths) model_paths ;;
  write)
    state="${1:?usage: model-stamp.sh write <state> <source…>}"; shift
    # Compute FIRST, so a refusal (empty path set, empty file list) aborts here under `set -e`
    # instead of writing a stamp with an empty fingerprint field.
    fp="$(fingerprint)"
    [ -n "$fp" ] || { echo "model-stamp: empty fingerprint — refusing to write a stamp" >&2; exit 1; }
    mkdir -p "${STAMP%/*}"
    { printf 'fingerprint: %s\n' "$fp"
      printf 'state: %s\n' "$state"
      printf 'source: %s\n' "$*"
      # mxbuild error count the pass saw. exec.sh's delta gate also passes a model that
      # still carries pre-existing errors, so "pass" alone does not mean clean; exec.sh
      # skips its pre-flight mxbuild only on a stamp that says 0 here (check --clean).
      printf 'errors: %s\n' "${MXTK_STAMP_ERRORS:-?}"
      # full = mxbuild deploy build (Java compiled); check = `mx check` only (exec.sh `Gate mode: check`).
      # The pre-push hook and module-close.sh run a full build when the stamp says check.
      printf 'kind: %s\n' "${MXTK_STAMP_KIND:-full}"
      if [ -n "${EPOCHSECONDS:-}" ]; then TZ=UTC printf 'at: %(%Y-%m-%dT%H:%M:%SZ)T\n' -1   # no date process (bash 5)
      else printf 'at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; fi
    } > "$STAMP"
    # Machine-local, like the doctor receipt: never let it travel with the repo.
    if in_git && ! git -C "$PROJECT_ROOT" check-ignore -q .claude/.model-verified 2>/dev/null; then
      printf '\n# Machine-local toolkit marker (model-stamp.sh verification stamp)\n/.claude/.model-verified\n' \
        >> "$PROJECT_ROOT/.gitignore" 2>/dev/null || true
    fi
    echo "  ✓ verification stamp written ($state — $*)"
    ;;
  clear) rm -f "$STAMP"; echo "  verification stamp cleared" ;;
  check)
    staged=0; quiet=0; clean=0; full=0
    for a in "$@"; do case "$a" in --staged) staged=1 ;; -q|--quiet) quiet=1 ;; --clean) clean=1 ;; --full) full=1 ;; esac; done
    say() { [ "$quiet" = 1 ] || echo "$@"; }
    if [ "$staged" = 1 ]; then
      in_git || exit 0
      _git_info; top="$_GI_TOP"
      _load_model_paths || exit 1
      if [ -z "$(cd "$top" && git diff --cached --name-only -- "${MODEL_PATHS[@]}")" ]; then
        say "  no model files staged — nothing to verify"; exit 0
      fi
      fp="$(_fp_staged)"; what="staged model"
    else
      fp="$(_fp_worktree)"; what="model"
    fi
    if [ ! -f "$STAMP" ]; then
      say "  ✗ $what is UNVERIFIED: no verification stamp in this clone"
      say "    (nothing has run the mxbuild gate on this model here — ./bin/verify-model.sh runs it)"
      exit 1
    fi
    _sload
    _sf state; st="$_SF"; _sf source; src="$_SF"; _sf at; at="$_SF"; _sf fingerprint; sfp="$_SF"
    if [ "$sfp" != "$fp" ]; then
      if [ "$staged" = 1 ] && [ "$(_fp_worktree)" = "$sfp" ] && [ "$st" = "pass" ]; then
        say "  ✗ the verified model is in the working tree but the STAGED model differs from it"
        say "    (stage the whole model — $(model_paths | tr '\n' ' ')— or unstage the model files)"
      else
        say "  ✗ $what is UNVERIFIED: it changed after the last verification ($src, $at)"
        say "    (./bin/verify-model.sh re-runs the mxbuild gate and stamps it)"
      fi
      exit 1
    fi
    if [ "$st" != "pass" ]; then
      say "  ✗ $what is UNVERIFIED: last verification was '$st' ($src, $at)"; exit 1
    fi
    if [ "$clean" = 1 ]; then
      _sf errors
      if [ "$_SF" != "0" ]; then say "  ✗ $what passed with pre-existing errors ($_SF) — not a clean stamp"; exit 1; fi
    fi
    # A stamp without a kind line predates `mx check` stamps: it was a full build.
    _sf kind
    if [ "$full" = 1 ] && [ "$_SF" = "check" ]; then
      say "  ✗ $what was verified by mx check only ($src, $at) — no full build (Java compile) yet"; exit 1
    fi
    say "  ✓ $what verified ($src, $at)"
    ;;
  ""|-h|--help) sed -n '2,7p' "$0"; exit 0 ;;
  *) echo "model-stamp.sh: unknown command '$cmd'" >&2; sed -n '2,7p' "$0" >&2; exit 2 ;;
esac
