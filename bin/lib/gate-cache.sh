#!/usr/bin/env bash
# gate-cache.sh — let `gate-check.sh --closeout <dir> <stage>` reuse the evaluation that
# `gate-check.sh <dir> <stage>` just finished, instead of running all of it a second time.
#
# WHY (#583, reported by OlafFede). A Stage 3 close is `gate-check <dir> 3` (the verdict the
# agent reads) and then `gate-check --closeout <dir> 3` (the block the user reads). The second
# one re-ran the ENTIRE evaluation — every stage checker, the obligation and artifact checks,
# the source ledger — to arrive at the verdict the first had already printed: ~850 process
# starts the second time round, a large part of a 12-minute close under Git Bash on Windows.
#
# WHAT IS CACHED. Not the printed text. The VARIABLES the evaluation leaves behind (results
# table, notes, drift/sync/open-question statuses, counts…): bin/gate-check.sh snapshots
# `declare -p` before and after the evaluation block, and this file keeps exactly the records
# that changed. A hit replays them with `eval` and the script continues into the code that
# follows the evaluation (the board write and the close-out block) exactly as if it had run it.
# The close-out block itself is always produced fresh from the files on disk.
#
# WHEN IT IS VALID — all of these, else the evaluation simply runs (a miss costs nothing but
# the evaluation that would have run anyway; a wrong hit would be a wrong verdict, so every
# doubt is a miss):
#   - same key: stage, absolute project dir, register, the flags that alter a verdict
#     (--strict-protocol, --force-stale, ...), the calendar day, the project's git HEAD and the
#     environment variables a verdict can read (MXTK_*, PATH, ...);
#   - the snapshot is complete (end marker) and replays without error in a trial subshell;
#   - younger than MXTK_GATE_CACHE_TTL_MIN minutes (default 30; 0 turns the cache off);
#   - NOTHING under the project (outside .git, node_modules and the cache itself) and nothing
#     under the toolkit (outside .git) has a modification time later than the moment the
#     cached run STARTED. That is the "key on the project files' state": a changed
#     PROJECT.md, stage artifact, source file, mpr, deleted file (its directory's mtime moves)
#     or a toolkit pull all end the cache. The reference time is backdated two seconds so a
#     coarse-timestamp filesystem cannot hide an edit made in the same second.
#   - only for a plain stage query or --closeout: never with --adopt, --waive,
#     --ack-protocol (they write the register, so there is nothing to reuse).
#
# Written by bin/gate-check.sh after a stage-requested evaluation, into <project>/.mxtk/ (the
# per-machine, gitignored state directory; created only when the project's .gitignore already
# names it). Opt-out: MXTK_GATE_CACHE_TTL_MIN=0. Sourced by bin/gate-check.sh; no side effects
# on source.

# gc_cache_enabled — are we in a run that may read or write the cache?
gc_cache_enabled() {
  case "${MXTK_GATE_CACHE_TTL_MIN:-30}" in ''|*[!0-9]*|0) return 1 ;; esac
  case "${REQUESTED_STAGE:-}" in P|p|[0-7]) ;; *) return 1 ;; esac
  [ -z "${ADOPT_STAGE:-}" ] && [ -z "${WAIVE_STAGE:-}" ] && [ "${ACK_PROTOCOL:-0}" = "0" ] || return 1
  [ -d "${PROJECT_DIR:-/nonexistent}" ] || return 1
  return 0
}

GC_CACHE_DIR=""
gc_cache_paths() {
  GC_CACHE_DIR="$PROJECT_DIR/.mxtk"
  GC_CACHE_FILE="$GC_CACHE_DIR/gate-cache"
  GC_CACHE_REF="$GC_CACHE_DIR/gate-cache.ref"
  GC_CACHE_REF2="$GC_CACHE_DIR/gate-cache.ref2"
}

# gc_cache_key — sets GC_CKEY, one line.
gc_cache_key() {
  local abs v k head="" hf ref today
  abs="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)" || abs="$PROJECT_DIR"
  today="$(date +%F 2>/dev/null)"
  hf="$PROJECT_DIR/.git/HEAD"
  if [ -f "$hf" ]; then
    IFS= read -r head < "$hf" 2>/dev/null || true
    case "$head" in
      "ref: "*) IFS= read -r ref < "$PROJECT_DIR/.git/${head#ref: }" 2>/dev/null || ref="packed"; head="$head@$ref" ;;
    esac
  fi
  GC_CKEY="v1|stage=${REQUESTED_STAGE}|dir=$abs|reg=${REGISTER:-}|strict=${STRICT_PROTOCOL:-0}|force=${FORCE_STALE:-0}|chat=${APPROVED_IN_CHAT:-0}|verbose=${PROTOCOL_VERBOSE:-0}|day=$today|head=$head|tk=${TOOLKIT_DIR:-}"
  # Environment a verdict can read. Names matched by pattern so a new MXTK_ knob needs no edit here.
  for k in $(compgen -e); do
    case "$k" in
      MXTK_GATE_CACHE_*|MXTK_ROWS_UPTO) continue ;;
      MXTK_*|MXCLI*|MX_*|PROJECT_*|JOURNEY_DIR|PATH|ARTIFACT_TSV|OBLIGATIONS_TSV|ROUTING_TSV|SKILL_ROUTING_TSV|TMPDIR)
        v="${!k}"; GC_CKEY="$GC_CKEY|$k=$v" ;;
    esac
  done
  # A key must be one line.
  GC_CKEY="${GC_CKEY//$'\n'/ }"
}

# gc_cache_clean <ref> <ref2> <own-writes> — true when nothing under the project or the toolkit
# changed since the cached run started, other than the files that run itself wrote (generated
# reports such as analysis/source-sufficiency.html, recorded in <own-writes>, "|"-separated),
# and none of THOSE changed after the run finished (ref2).
gc_cache_clean() {
  local ref="$1" ref2="$2" own="$3" f hit
  local P="$PROJECT_DIR"
  # The cache directory's own mtime moves whenever the cache is rewritten; exclude it (not its siblings).
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "|$own|" in *"|$f|"*) ;; *) return 1 ;; esac
  done < <(find "$P" \( -name .git -o -name node_modules -o -name 'gate-cache*' \) -prune -o -newer "$ref" ! -path "$P/.mxtk" -print 2>/dev/null)
  hit="$(find "$P" \( -name .git -o -name node_modules -o -name 'gate-cache*' \) -prune -o -newer "$ref2" ! -path "$P/.mxtk" -print -quit 2>/dev/null)" || return 1
  [ -z "$hit" ] || return 1
  if [ -n "${TOOLKIT_DIR:-}" ] && [ -d "$TOOLKIT_DIR" ]; then
    hit="$(find "$TOOLKIT_DIR" \( -name .git -o -name node_modules \) -prune -o -newer "$ref" -print -quit 2>/dev/null)" || return 1
    [ -z "$hit" ] || return 1
  fi
  return 0
}

# gc_cache_try — on a valid cache, replays the snapshot into THIS shell and sets GC_CACHE_HIT=1.
# Must be called from the top level of the script (not from a function): `declare` inside a
# function would make the replayed variables local to it.
GC_CACHE_HIT=0
GC_CACHE_SNAPSHOT=""
gc_cache_try() {
  GC_CACHE_HIT=0; GC_CACHE_SNAPSHOT=""
  gc_cache_enabled || return 0
  gc_cache_paths
  [ -f "$GC_CACHE_FILE" ] && [ -f "$GC_CACHE_REF" ] && [ -f "$GC_CACHE_REF2" ] || return 0
  [ -n "$(find "$GC_CACHE_FILE" -mmin "-${MXTK_GATE_CACHE_TTL_MIN:-30}" 2>/dev/null)" ] || return 0
  local all first
  IFS= read -r -d '' all < "$GC_CACHE_FILE" || true
  first="${all%%$'\n'*}"
  gc_cache_key
  [ "$first" = "$GC_CKEY" ] || return 0
  case "$all" in *$'\n# gate-cache-end'*) ;; *) return 0 ;; esac
  GC_CACHE_SNAPSHOT="${all#*$'\n'}"
  local own="${GC_CACHE_SNAPSHOT%%$'\n'*}"
  GC_CACHE_SNAPSHOT="${GC_CACHE_SNAPSHOT#*$'\n'}"
  case "$own" in "# own-writes:"*) own="${own#\# own-writes:}" ;; *) return 0 ;; esac
  gc_cache_clean "$GC_CACHE_REF" "$GC_CACHE_REF2" "$own" || return 0
  # Trial replay in a subshell: a snapshot that does not replay cleanly must not half-apply.
  ( eval "$GC_CACHE_SNAPSHOT" ) >/dev/null 2>&1 || return 0
  GC_CACHE_HIT=1
}

# gc_cache_begin — call just BEFORE the evaluation block runs (a miss). Takes the reference
# time and the "before" variable dump.
GC_SNAP_ON=0; GC_SNAP_BEFORE=""; GC_BKEY=""
gc_cache_begin() {
  GC_SNAP_ON=0
  gc_cache_enabled || return 0
  gc_cache_paths
  if [ ! -d "$GC_CACHE_DIR" ]; then
    grep -qsE '^/?\.mxtk/?[[:space:]]*$' "$PROJECT_DIR/.gitignore" 2>/dev/null || return 0
    mkdir -p "$GC_CACHE_DIR" 2>/dev/null || return 0
  fi
  local ts
  ts="$(TZ=UTC date -u -d '2 seconds ago' +%Y%m%d%H%M.%S 2>/dev/null || TZ=UTC date -u -v-2S +%Y%m%d%H%M.%S 2>/dev/null)" || return 0
  [ -n "$ts" ] || return 0
  GC_SNAP_BEFORE="$(mktemp "${TMPDIR:-/tmp}/gate-cache-before.XXXXXX" 2>/dev/null)" || return 0
  TZ=UTC touch -t "$ts" "$GC_CACHE_REF.new" 2>/dev/null || { rm -f "$GC_SNAP_BEFORE"; return 0; }
  # The key is taken HERE, before the evaluation exports anything of its own (MXTK_ROWS_UPTO...),
  # so the key a later --closeout computes at the same point matches.
  gc_cache_key; GC_BKEY="$GC_CKEY"
  declare -p > "$GC_SNAP_BEFORE" 2>/dev/null
  GC_SNAP_ON=1
}

# gc_cache_end — call just AFTER the evaluation block. Writes the cache from the variables that
# changed. Never fails the run; any trouble leaves no cache (the safe state).
gc_cache_end() {
  [ "$GC_SNAP_ON" = "1" ] || return 0
  GC_SNAP_ON=0
  local after out
  after="$(mktemp "${TMPDIR:-/tmp}/gate-cache-after.XXXXXX" 2>/dev/null)" || { rm -f "$GC_SNAP_BEFORE" "$GC_CACHE_REF.new"; return 0; }
  out="$GC_CACHE_FILE.new"
  declare -p > "$after" 2>/dev/null
  local own="" f
  while IFS= read -r f; do own="$own|$f"; done < <(find "$PROJECT_DIR" \( -name .git -o -name node_modules -o -name 'gate-cache*' \) -prune -o -newer "$GC_CACHE_REF.new" ! -path "$PROJECT_DIR/.mxtk" -print 2>/dev/null)
  {
    printf '%s\n' "$GC_BKEY"
    printf '# own-writes:%s\n' "$own"
    awk '
      function flush() {
        if (name != "") {
          if (pass == 1) before[name] = rec
          else if (flags !~ /r/ && name !~ skip && (!(name in before) || before[name] != rec)) print rec
        }
        name = ""; rec = ""
      }
      FNR == 1 { flush(); pass++ }
      /^declare -/ {
        flush()
        split($0, a, " "); flags = a[2]; name = a[3]; sub(/=.*/, "", name)
        rec = $0; next
      }
      { if (name != "") rec = rec "\n" $0 }
      END { flush() }
    ' skip='^(BASH|FUNCNAME$|LINENO$|SECONDS$|RANDOM$|SRANDOM$|EPOCH|PIPESTATUS$|_$|PPID$|UID$|EUID$|GROUPS$|SHLVL$|PWD$|OLDPWD$|COLUMNS$|LINES$|IFS$|REPLY$|OPTIND$|OPTARG$|DIRSTACK$|HISTCMD$|COMP|GC_C|GC_SNAP|GC_FETCH)' \
      "$GC_SNAP_BEFORE" "$after"
    printf '# gate-cache-end\n'
  } > "$out" 2>/dev/null
  rm -f "$GC_SNAP_BEFORE" "$after"
  # Publish: ref first (its mtime is the reference), then the payload, atomically by rename.
  : > "$GC_CACHE_REF2" 2>/dev/null
  if [ -s "$out" ] && mv -f "$GC_CACHE_REF.new" "$GC_CACHE_REF" 2>/dev/null && mv -f "$out" "$GC_CACHE_FILE" 2>/dev/null; then
    return 0
  fi
  rm -f "$out" "$GC_CACHE_REF.new" "$GC_CACHE_FILE" "$GC_CACHE_REF" "$GC_CACHE_REF2" 2>/dev/null
  return 0
}
