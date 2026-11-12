#!/bin/bash
# pgtmp.sh start | stop DIR: a throwaway Postgres (unix socket in a fresh /var/tmp/upg-pg.* folder the postgres user can
# reach, no network) for the seed_snapshot controls. start prints the psql command line (it names DIR) on stdout; exit 3 when no postgres binaries are installed (the control SKIPs).
bin=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)
[ -n "$bin" ] && [ -x "$bin/initdb" ] || { echo "no postgres binaries"; exit 3; }
d=${2:-}; run() { if [ "$(id -u)" = 0 ]; then runuser -u postgres -- "$@"; else "$@"; fi; }
case "$1" in
  start)
    d=$(mktemp -d /var/tmp/upg-pg.XXXXXX); [ "$(id -u)" = 0 ] && chown postgres "$d"
    run "$bin/initdb" -D "$d/data" -A trust -U mendix >/dev/null 2>&1 || { echo "initdb failed"; exit 3; }
    run "$bin/pg_ctl" -D "$d/data" -o "-k $d -c listen_addresses=''" -w -l "$d/pg.log" start >/dev/null 2>&1 || { echo "pg_ctl failed"; exit 3; }
    run "$bin/psql" -h "$d" -U mendix -d postgres -qc 'create database fx' >/dev/null 2>&1 || exit 3
    echo "psql -h $d -U mendix -d fx";;
  stop) run "$bin/pg_ctl" -D "$d/data" -m immediate stop >/dev/null 2>&1; rm -rf "$d"; exit 0;;
esac
