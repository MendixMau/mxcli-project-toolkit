#!/bin/bash
# Control for filecheck.js --compare: two equal sides are SAME (exit 0); a side that did not complete, or a different
# download checksum, is DIFFERENT (exit 1) and says which. No browser, no app.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
side='{"ok":true,"name":"a.txt","size":5,"hasContents":true,"upload_sha":"aa","download":{"status":200,"bytes":5,"sha":"aa","type":"text/plain"},"thumbnail":{"status":404}}'
echo "$side" > "$t/old.json"; echo "$side" > "$t/new.json"
node "$here/../bin/filecheck.js" --compare "$t/old.json" "$t/new.json"; echo "rc=$?"
echo "${side/\"sha\":\"aa\"/\"sha\":\"bb\"}" > "$t/new.json"
node "$here/../bin/filecheck.js" --compare "$t/old.json" "$t/new.json"; echo "rc=$?"
echo '{"ok":false,"steps":["login"]}' > "$t/new.json"
node "$here/../bin/filecheck.js" --compare "$t/old.json" "$t/new.json"; echo "rc=$?"
