#!/usr/bin/env bash
# fake-net.sh SRC MODULE MPR: network and tool failures as batch 1 saw them (T1-12, T1-13, T3-2, T7-13, T8-11);
# the module name picks the behaviour. Attempt counts live in SRC/net-state/<module>.
src=$1 mod=$2 mpr=$3
mkdir -p "$src/net-state"
n=$(cat "$src/net-state/$mod" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$src/net-state/$mod"
TLS='Error: download: Get "https://marketplace-api.mendix.com/v1/content/1/versions": net/http: TLS handshake timeout'
case "$mod" in
  Flaky*)  # fails once with a TLS handshake timeout, then works
    if [ $n = 1 ]; then echo "$TLS"; exit 1; fi
    cp "$src/step1-adds/App.mpr" "$mpr";;
  Down*) echo "$TLS"; exit 1;;
  Busy*) echo "Error: download version 1.0.0: HTTP 503 Service Unavailable"; exit 1;;
  X509*) echo 'Error: Get "https://marketplace-api.mendix.com/v1/content/1": tls: failed to verify certificate: x509: certificate signed by unknown authority'
         echo junk > "$(dirname "$mpr")/x509-junk.txt"; exit 1;;
  NoAuth*) echo "Error: auth: no credential for profile default"; exit 1;;
  Fine*) cp "$src/step1-adds/App.mpr" "$mpr";;
  *) echo "fake-net: unknown module $mod" >&2; exit 9;;
esac
