#!/usr/bin/env bash
# fake-mxcli-download.sh marketplace download <cid> --version <v> -o <out.mpk>: stands in for mxcli in the localedits
# network controls (T3-2, T5-2, T7-2, T8-5). FAKE_DL_SRC is the .mpk to hand out, FAKE_DL_MODE picks the behaviour:
#   flaky  the first call per FAKE_DL_STATE file fails with a TLS handshake timeout, the next ones work
#   down   every call fails with a TLS handshake timeout
out=""; prev=""
for a in "$@"; do [ "$prev" = -o ] && out=$a; prev=$a; done
n=$(cat "$FAKE_DL_STATE" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$FAKE_DL_STATE"
TLS='Error: download: Get "https://marketplace-api.mendix.com/v1/content/23513/versions": net/http: TLS handshake timeout'
case "$FAKE_DL_MODE" in
  flaky) if [ $n = 1 ]; then echo "$TLS" >&2; exit 1; fi; cp "$FAKE_DL_SRC" "$out";;
  down) echo "$TLS" >&2; exit 1;;
  *) echo "fake-mxcli-download: FAKE_DL_MODE?" >&2; exit 9;;
esac
