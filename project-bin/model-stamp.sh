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

_fp_worktree() {
  if in_git; then
    local top lst; top="$(git -C "$MODEL_DIR" rev-parse --show-toplevel)"
    lst="$(mktemp "${TMPDIR:-/tmp}/model-stamp.XXXXXX")"
    # Tracked + untracked-not-ignored, minus anything deleted in the working tree. Newline
    # separated: `git hash-object --stdin-paths` has no -z, and unit file names carry none.
    ( cd "$top" && git ls-files -c -o --exclude-standard -- $(model_paths) 2>/dev/null \
        | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done > "$lst"
      if [ -s "$lst" ]; then
        paste -d' ' <(git hash-object --stdin-paths < "$lst") "$lst"
      fi ) | LC_ALL=C sort -k2 | mxtk_sha256
    rm -f "$lst"
  else
    { cksum < "$MPR"; [ -d "$MPRC" ] && find "$MPRC" -type f -exec cksum {} + | LC_ALL=C sort -k3; } | mxtk_sha256
  fi
}

_fp_staged() {
  in_git || { echo "model-stamp: not a git repository — --staged has no meaning" >&2; return 1; }
  local top; top="$(git -C "$MODEL_DIR" rev-parse --show-toplevel)"
  ( cd "$top" && git ls-files -s -- $(model_paths) \
      | awk -F'\t' '{ split($1, a, " "); print a[2] " " $2 }' | LC_ALL=C sort -k2 | mxtk_sha256 )
}

fingerprint() { if [ "${1:-}" = "--staged" ]; then _fp_staged; else _fp_worktree; fi; }

stamp_field() { sed -n "s/^$1: //p" "$STAMP" 2>/dev/null | head -1; }

cmd="${1:-}"; shift || true
case "$cmd" in
  fingerprint) fingerprint "${1:-}" ;;
  paths) model_paths ;;
  write)
    state="${1:?usage: model-stamp.sh write <state> <source…>}"; shift
    mkdir -p "$(dirname "$STAMP")"
    { printf 'fingerprint: %s\n' "$(fingerprint)"
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
      if [ -z "$(cd "$top" && git diff --cached --name-only -- $(model_paths))" ]; then
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
