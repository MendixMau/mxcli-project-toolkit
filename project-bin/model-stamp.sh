#!/usr/bin/env bash
# model-stamp.sh — the verification stamp: "THIS model state was mxbuild-verified".
#
#   ./bin/model-stamp.sh fingerprint [--staged]   # print the model fingerprint
#   ./bin/model-stamp.sh write <state> <source…>  # record that the current model was verified
#   ./bin/model-stamp.sh check [--staged] [-q]    # exit 0 iff the (staged) model matches a PASS stamp
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
#   * bin/verify-model.sh writes it after a standalone clean mxbuild — evidence the
#     hook did not create itself (toolkit guard rule 6), and the remedy the hook
#     points at (rule 7: a guard never blocks the action that resolves it);
#   * the pre-commit hook (bin/install-project-hooks.sh) refuses to commit model files
#     whose staged fingerprint does not match a PASS stamp. MODEL_UNVERIFIED_OK=1
#     overrides once, out loud.
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
. "$(dirname "$0")/_common.sh"

STAMP="$PROJECT_ROOT/.claude/.model-verified"

_real() {  # resolve symlinks by hand (GNU-only resolvers are absent on older macOS)
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(dirname "$p")"; p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd -P)" "$(basename "$p")"
}

MPR="$(find_mpr)" || exit 1
MPR="$(_real "$MPR")"
MODEL_DIR="$(dirname "$MPR")"
MPRC="$MODEL_DIR/mprcontents"

in_git() { git -C "$MODEL_DIR" rev-parse --show-toplevel >/dev/null 2>&1; }

# Repo-relative paths (from the git top level), printed one per line.
model_paths() {
  local prefix
  prefix="$(git -C "$MODEL_DIR" rev-parse --show-prefix)"
  printf '%s%s\n' "$prefix" "$(basename "$MPR")"
  [ -d "$MPRC" ] && printf '%smprcontents\n' "$prefix"
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
  local p n=0
  MODEL_PATHS=()
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    MODEL_PATHS[$n]="$p"; n=$((n + 1))
  done <<EOF
$(model_paths)
EOF
  if [ "$n" -eq 0 ]; then
    echo "model-stamp: no model paths resolved for $MPR — refusing to fingerprint (a stamp over" >&2
    echo "  nothing would match every model state, which is worse than no stamp at all)." >&2
    return 1
  fi
  return 0
}

_fp_worktree() {
  if in_git; then
    local top lst; top="$(git -C "$MODEL_DIR" rev-parse --show-toplevel)"
    _load_model_paths || return 1
    lst="$(mktemp "${TMPDIR:-/tmp}/model-stamp.XXXXXX")"
    # Tracked + untracked-not-ignored, minus anything deleted in the working tree. Newline
    # separated: `git hash-object --stdin-paths` has no -z, and unit file names carry none.
    ( cd "$top" && git ls-files -c -o --exclude-standard -- "${MODEL_PATHS[@]}" 2>/dev/null \
        | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done ) > "$lst"
    # An EMPTY list is not a fingerprint. It used to fall through to `mxtk_sha256` over empty
    # stdin, which is a CONSTANT — so a project whose mprcontents/ is gitignored fingerprinted
    # identically no matter what the model contained, and every stamp matched forever.
    if [ ! -s "$lst" ]; then
      rm -f "$lst"
      echo "model-stamp: git lists no files under $(printf '%s ' "${MODEL_PATHS[@]}")in $top —" >&2
      echo "  refusing to fingerprint. Most likely the model is gitignored in this clone; a stamp" >&2
      echo "  over an empty set would match every model state." >&2
      return 1
    fi
    ( cd "$top" && paste -d' ' <(git hash-object --stdin-paths < "$lst") "$lst" ) \
      | LC_ALL=C sort -k2 | mxtk_sha256
    rm -f "$lst"
  else
    { cksum < "$MPR"; [ -d "$MPRC" ] && find "$MPRC" -type f -exec cksum {} + | LC_ALL=C sort -k3; } | mxtk_sha256
  fi
}

_fp_staged() {
  in_git || { echo "model-stamp: not a git repository — --staged has no meaning" >&2; return 1; }
  local top lst; top="$(git -C "$MODEL_DIR" rev-parse --show-toplevel)"
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

stamp_field() { sed -n "s/^$1: //p" "$STAMP" 2>/dev/null | head -1; }

cmd="${1:-}"; shift || true
case "$cmd" in
  fingerprint) fingerprint "${1:-}" ;;
  paths) model_paths ;;
  write)
    state="${1:?usage: model-stamp.sh write <state> <source…>}"; shift
    # Compute FIRST, so a refusal (empty path set, empty file list) aborts here under `set -e`
    # instead of writing a stamp with an empty fingerprint field.
    fp="$(fingerprint)"
    [ -n "$fp" ] || { echo "model-stamp: empty fingerprint — refusing to write a stamp" >&2; exit 1; }
    mkdir -p "$(dirname "$STAMP")"
    { printf 'fingerprint: %s\n' "$fp"
      printf 'state: %s\n' "$state"
      printf 'source: %s\n' "$*"
      printf 'at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
    staged=0; quiet=0
    for a in "$@"; do case "$a" in --staged) staged=1 ;; -q|--quiet) quiet=1 ;; esac; done
    say() { [ "$quiet" = 1 ] || echo "$@"; }
    if [ "$staged" = 1 ]; then
      in_git || exit 0
      top="$(git -C "$MODEL_DIR" rev-parse --show-toplevel)"
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
    st="$(stamp_field state)"; src="$(stamp_field source)"; at="$(stamp_field at)"
    if [ "$(stamp_field fingerprint)" != "$fp" ]; then
      if [ "$staged" = 1 ] && [ "$(_fp_worktree)" = "$(stamp_field fingerprint)" ] && [ "$st" = "pass" ]; then
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
    say "  ✓ $what verified ($src, $at)"
    ;;
  ""|-h|--help) sed -n '2,7p' "$0"; exit 0 ;;
  *) echo "model-stamp.sh: unknown command '$cmd'" >&2; sed -n '2,7p' "$0" >&2; exit 2 ;;
esac
