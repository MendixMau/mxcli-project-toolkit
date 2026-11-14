#!/usr/bin/env bash
# fake-proc.sh — sourced by fixtures that need a long-running process whose NAME is a given
# basename (deno, bystander): the product matches by `ps comm` and by the first word of the args.
#
#   . "$(dirname "$0")/fake-proc.sh"; fake_proc_init "$T"       # once; sets FAKE_SRC, FAKE_PRE
#   fake_proc_make "$DIR/deno"                                   # a file whose process name is "deno"
#   "$DIR/deno" ${FAKE_PRE:-} 600 &                              # launch it, 600 s
#
# Why not a plain `cp sleep deno`: where coreutils is one multicall binary (uutils, the default on
# Ubuntu 26.04 — CI image 20261111.82.6, 2026-11-14), a renamed copy looks up the applet "deno" and
# exits at once, so no fake helper ever ran. fake_proc_init copies sleep and runs the copy (`0`);
# if it does not run — or MXTK_FAKE_PROC_FORCE_FALLBACK=1 — it copies bash instead, launched as
# `deno <block.sh> <secs>`: comm is still "deno", the first arg word is still the full path to it,
# and block.sh waits on a fifo it holds open itself (shell builtins only: no child to leak).
# A shell script named deno would not do: its comm would be the interpreter's on some systems.
fake_proc_init() {  # fake_proc_init <scratch-dir>
  local d="$1" probe
  FAKE_SRC="$(command -v sleep)"; FAKE_PRE=""
  probe="$d/fake-proc-probe"; cp "$FAKE_SRC" "$probe" 2>/dev/null && chmod +x "$probe"
  if [ "${MXTK_FAKE_PROC_FORCE_FALLBACK:-}" = 1 ] || ! "$probe" 0 >/dev/null 2>&1; then
    FAKE_SRC="$(command -v bash)"; FAKE_PRE="$d/fake-proc-block.sh"
    printf '#!/bin/sh\nexec 3<>"$0.fifo"\nread -t "$1" -u 3\n' > "$FAKE_PRE"
    mkfifo "$FAKE_PRE.fifo"
  fi
  rm -f "$probe"
}
fake_proc_make() { cp "$FAKE_SRC" "$1" && chmod +x "$1"; }  # fake_proc_make <dest>
