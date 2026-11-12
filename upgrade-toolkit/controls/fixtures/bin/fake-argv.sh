#!/usr/bin/env bash
# fake-argv.sh SRC -p MPR [more...]: stands in for "mxcli marketplace update ... -p {mpr}" in the quoting controls
# (T1-11, T4-1, T8-10). Like mxcli's -p it accepts exactly one argument; with more it prints mxcli's own refusal.
src=$1; shift; [ "${1:-}" = -p ] && shift
echo "argc after -p: $#"
if [ $# != 1 ]; then echo "Error: accepts 1 arg(s), received $#"; exit 1; fi
cp "$src/step1-adds/App.mpr" "$1"
