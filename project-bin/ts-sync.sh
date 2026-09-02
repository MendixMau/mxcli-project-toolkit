#!/usr/bin/env bash
# ts-sync.sh — content transplant between this project (the GitHub/Claude side) and a local
# Mendix Team Server clone. GitHub is the workshop, Team Server the showroom: the daily build
# loop stays on GitHub, and "every now and then" a model snapshot crosses to Team Server for
# colleagues in Studio Pro — or a colleague's Team Server commit crosses back.
#
# ⚠️  STATUS: UNPROVEN AGAINST A REAL TEAM SERVER (2026-09-01). The transplant logic is
#     selftested on local fixture repos only; nothing here has touched git.api.mendix.com.
#     First field run owed from a machine holding both clones. Until that run is recorded in
#     this header, treat every TS-side behaviour claim as a hypothesis — per
#     skills/tool-output-is-not-ground-truth.md, and the capability-probe rule.
#
# WHY TRANSPLANT, NOT MERGE. A Team Server repo is born on the platform with its own initial
# history, unrelated to the GitHub repo's — pushing one into the other means unrelated-history
# force pushes, and model units do not text-merge anyway. So this script never crosses
# histories: it copies the MODEL CONTENT (.mpr + mprcontents/ + app dirs) onto the other
# side's clean working tree and commits it there as a snapshot naming its source revision.
# Two histories, one content flow, full provenance.
#
# THE MODEL TOKEN. Only one side edits the model between syncs — while colleagues work on
# Team Server, the Claude loop makes no model writes, and vice versa. If both sides edited
# anyway: do not merge; pick the winner, re-transplant, and say so in the snapshot message.
#
#   TS_CLONE=/path/to/teamserver-clone bin/ts-sync.sh status   # both sides at a glance
#   TS_CLONE=...                       bin/ts-sync.sh push     # this side  -> TS clone
#   TS_CLONE=...                       bin/ts-sync.sh pull     # TS clone   -> this side
#
# TS_CLONE can also live in <project>/.ts-sync.env (gitignored; a real local path).
# The script COMMITS on the receiving side but never pushes — review the snapshot commit,
# then push it yourself (Team Server auth is a Mendix PAT on the https remote).
#
# Guards (each one is a lesson this toolkit already paid for elsewhere):
#   - source mprcontents/ must hold >0 .mxunit — a consolidated (docker build / run --local)
#     .mpr must never be transplanted; see bug-logs' split-model-collapse entries.
#   - BOTH trees must be clean — the snapshot SHA must actually describe the content moved.
#   - After a pull, run the mxbuild gate before building on the imported model.
set -euo pipefail
. "$(dirname "$0")/_common.sh"

MODEL_DIR="$(find_model_dir)" || exit 1
MPR="$(find_mpr)" || exit 1
MPR_BASE="$(basename "$MPR")"

[ -f "$PROJECT_ROOT/.ts-sync.env" ] && . "$PROJECT_ROOT/.ts-sync.env"
CMD="${1:-status}"

# App content that travels with the model. Explicit list, not a glob over the root:
# analysis/, docs/, tests/ and the toolkit wiring are GitHub-side working material a
# Studio Pro colleague neither needs nor should have to explain to their diff.
MODEL_ITEMS="mprcontents javasource javascriptsource theme themesource widgets resources userlib vendorlib"

# find on a missing mprcontents/ exits non-zero, and under `set -o pipefail` that killed the
# whole script INSIDE the consolidation guard — the refusal became a silent death (caught by
# fixture test 5, 2026-09-01). The || true keeps the count honest at 0 instead.
_units() { { find "$1/mprcontents" -name '*.mxunit' 2>/dev/null || true; } | wc -l | tr -d ' '; }
_dirty() { [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]; }
_sha()   { git -C "$1" rev-parse --short HEAD 2>/dev/null || echo '<no git>'; }

_need_ts() {
  [ -n "${TS_CLONE:-}" ] || {
    echo "ts-sync: TS_CLONE is not set. Point it at your local Team Server clone:" >&2
    echo "  TS_CLONE=/path/to/ts-clone bin/ts-sync.sh $CMD    (or put it in .ts-sync.env)" >&2
    exit 2; }
  [ -d "$TS_CLONE/.git" ] || { echo "ts-sync: $TS_CLONE is not a git work tree" >&2; exit 2; }
  TS_MPR="$(ls "$TS_CLONE"/*.mpr 2>/dev/null | head -1 || true)"
}

# _transplant <src_model_dir> <src_repo_root> <dst_root> <label-of-source>
_transplant() {
  local src="$1" src_root="$2" dst="$3" label="$4" item n
  n="$(_units "$src")"
  if [ "$n" -eq 0 ]; then
    echo "ts-sync: REFUSING — $src has no mprcontents/*.mxunit." >&2
    echo "  A consolidated .mpr (mxcli docker build / run --local does this) must not be" >&2
    echo "  transplanted: the receiving side loses its reviewable split-model diff." >&2
    echo "  Restore split form first (git checkout -- <mpr> mprcontents/)." >&2
    exit 1
  fi
  if _dirty "$src_root"; then
    echo "ts-sync: REFUSING — the source tree has uncommitted changes; the snapshot SHA" >&2
    echo "  would not describe what is being copied. Commit there first." >&2
    exit 1
  fi
  if _dirty "$dst"; then
    echo "ts-sync: REFUSING — the receiving tree is not clean. Commit or discard there first." >&2
    exit 1
  fi
  local src_sha copied
  src_sha="$(_sha "$src_root")"
  copied=""
  local src_mpr
  src_mpr="$(ls "$src"/*.mpr | head -1)"
  cp "$src_mpr" "$dst/$(basename "$src_mpr")"
  copied="$(basename "$src_mpr")"
  for item in $MODEL_ITEMS; do
    [ -d "$src/$item" ] || continue
    rm -rf "${dst:?}/$item"
    cp -r "$src/$item" "$dst/$item"
    copied="$copied $item"
  done
  # Explicit paths only — never add -A; the receiving clone may hold anything.
  ( cd "$dst" && git add -- $copied
    if git -C "$dst" diff --cached --quiet; then
      echo "ts-sync: no differences — the two sides already hold the same model. Nothing committed."
      exit 0
    fi
    cd "$dst" && git commit -m "Model snapshot from $label @ $src_sha ($n units)" -- $copied )
  echo "ts-sync: snapshot committed on $dst (source: $label @ $src_sha, $n units: $copied)."
  echo "  Review it, then push it yourself: git -C '$dst' push"
}

case "$CMD" in
  status)
    echo "this side (GitHub/Claude): $MODEL_DIR"
    printf '  HEAD %s · %s units · %s\n' "$(_sha "$PROJECT_ROOT")" "$(_units "$MODEL_DIR")" \
      "$(_dirty "$PROJECT_ROOT" && echo DIRTY || echo clean)"
    if [ -n "${TS_CLONE:-}" ] && [ -d "$TS_CLONE" ]; then
      echo "Team Server clone: $TS_CLONE"
      printf '  HEAD %s · %s units · %s\n' "$(_sha "$TS_CLONE")" "$(_units "$TS_CLONE")" \
        "$(_dirty "$TS_CLONE" && echo DIRTY || echo clean)"
    else
      echo "Team Server clone: TS_CLONE not set (or missing) — set it to compare."
    fi
    ;;
  push)
    _need_ts
    _transplant "$MODEL_DIR" "$PROJECT_ROOT" "$TS_CLONE" "GitHub $(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    ;;
  pull)
    _need_ts
    [ -n "$TS_MPR" ] || { echo "ts-sync: no .mpr in $TS_CLONE — nothing to pull" >&2; exit 1; }
    _transplant "$TS_CLONE" "$TS_CLONE" "$MODEL_DIR" "Team Server $(git -C "$TS_CLONE" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    echo "  NOW RUN THE GATE before building on this: a colleague's Studio Pro save is"
    echo "  unverified until mxbuild says otherwise (bin/exec.sh runs it; or mx check)."
    ;;
  *)
    echo "usage: bin/ts-sync.sh status|push|pull    (TS_CLONE=<path to Team Server clone>)" >&2
    exit 2
    ;;
esac
