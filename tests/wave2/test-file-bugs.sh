#!/usr/bin/env bash
# test-file-bugs.sh — bin/file-bugs.sh: redaction, dry run, y/N filing, --links.
#
# Usage: bash tests/wave2/test-file-bugs.sh [path-to-file-bugs.sh]
#
# An invented project (Zorbix.mpr, module Quuxmod, entity Widgetron) with invented bugs; gh is a
# stub on PATH that logs every call and never touches the network. Cases:
#   A dry run posts nothing (no `issue create` in the gh log), shows title, body and duplicates
#   B redaction of each class: home path, user, host, email, IP, token, other URL, project names,
#     deny list; the allowed github.com URLs survive
#   C final scan: an opaque 36-char string survives redaction, so the bug is refused and no
#     --links URL or create call exists for it
#   D --file with answer n posts nothing; with y calls gh issue create with the redacted body and
#     writes status=filed and issue_url back; the other rows are untouched
#   E --links: URL-encoded, redacted, under the length cap when the body is huge, no gh needed
#   F posting without a terminal and without the test hook is refused; --add numbers the next BUG-NN
set -uo pipefail
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBJ="${1:-$TOOLKIT/bin/file-bugs.sh}"
. "$TOOLKIT/bin/lib/portable.sh"; require_py
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

W="$(mktemp -d "${TMPDIR:-/tmp}/fbtest.XXXXXX")"; trap 'rm -rf "$W"' EXIT
P="$W/proj"; BIN="$W/bin"; GHLOG="$W/gh.log"
mkdir -p "$P/docs" "$P/mdlsource" "$BIN"
: > "$P/Zorbix.mpr"
printf 'CREATE MODULE Quuxmod;\nCREATE PERSISTENT ENTITY Quuxmod.Widgetron (Name: String);\n' > "$P/mdlsource/01-model.mdl"
printf 'Glorpley\\b\n' > "$W/deny"
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GHLOG"
case "$1 $2" in
  "issue list") echo '[{"number":77,"title":"Similar widget crash","state":"OPEN","url":"https://github.com/mendixlabs/mxcli/issues/77"}]' ;;
  "issue create") echo "https://github.com/mendixlabs/mxcli/issues/4242" ;;
  "--version "*) echo "gh version stub" ;;
esac
exit 0
GH
chmod +x "$BIN/gh"; export GHLOG
export PATH="$BIN:$PATH" LEAKGUARD_DENY="$W/deny"
U="${USER:-someone}"; H="$(hostname -s 2>/dev/null || echo myhost)"
HOMEP="/Users/$U/work/Zorbix/mdlsource/01.mdl"
cat > "$P/docs/bugs.jsonl" <<ROWS
{"id":"BUG-01","date":"2026-10-16","target":"mxcli","title":"Crash on Quuxmod.Widgetron in Zorbix","repro":["Open $HOMEP","Run on $H from 10.20.30.40","Mail $U@example.com","token ghp_abcdefghijklmnopqrstuvwx1234","see https://intranet.example.org/x and https://github.com/mendixlabs/mxcli/issues/12","Glorpley asked"],"expected":"no crash","actual":"crash in Quuxmod.ACT_Save","versions":{"mxcli":"v0.27.0","mendix":"11.15.0","toolkit":"v2026.10.16"},"workaround":"avoid Quuxmod.Widgetron","status":"open","issue_url":""}
{"id":"BUG-02","date":"2026-10-16","target":"toolkit","title":"Opaque thing","repro":"value A8f3K2m9Qz7Lp4Xw1Vb6Nc5Rd0Ty8Ue3Ig","expected":"x","actual":"y","versions":{},"workaround":"","status":"open","issue_url":""}
{"id":"BUG-03","date":"2026-10-16","target":"mxcli","title":"Plain bug","repro":"step one","expected":"ok","actual":"not ok","versions":{"mxcli":"v0.27.0"},"workaround":"","status":"open","issue_url":""}
{"id":"BUG-04","date":"2026-10-16","target":"other","title":"Wrong target","repro":"r","expected":"e","actual":"a","versions":{},"workaround":"","status":"open","issue_url":""}
{"id":"BUG-05","date":"2026-10-16","target":"mxcli","title":"Done already","repro":"r","expected":"e","actual":"a","versions":{},"workaround":"","status":"fixed","issue_url":""}
ROWS
run() { MXTK_FILE_BUGS_STDIN=1 "$SUBJ" --project "$P" "$@"; }

echo "A. dry run"
: > "$GHLOG"
OUT="$(run </dev/null 2>&1)"
chk "dry run never calls issue create" '! grep -q "issue create" "$GHLOG"'
chk "dry run shows the exact title" 'echo "$OUT" | grep -q "TITLE: Crash on Module1.EntityA in App1"'
chk "dry run shows a likely duplicate" 'echo "$OUT" | grep -q "#77"'
chk "closed and wrong-target rows are not offered" '! echo "$OUT" | grep -q "^BUG-05" && echo "$OUT" | grep -q "BUG-04.*skipped"'
chk "duplicate search used gh issue list --search" 'grep -q "issue list --repo mendixlabs/mxcli.*--search" "$GHLOG"'

echo "B. redaction classes (BUG-01 body)"
B1="$(run --json </dev/null | "$PY" -c 'import json,sys; print([x for x in json.load(sys.stdin) if x["id"]=="BUG-01"][0]["body"])')"
chk "home path gone"        '! echo "$B1" | grep -q "/Users/"'
chk "user name gone"        '! echo "$B1" | grep -qi "$U@\|/$U/"'
chk "host name gone"        '! echo "$B1" | grep -qiw "$H" || [ "${#H}" -lt 3 ]'
chk "email gone"            '! echo "$B1" | grep -q "example.com"'
chk "ip gone"               '! echo "$B1" | grep -q "10.20.30.40"'
chk "token gone"            '! echo "$B1" | grep -q "ghp_"'
chk "other url gone"        '! echo "$B1" | grep -q "intranet"'
chk "allowed github url kept" 'echo "$B1" | grep -q "https://github.com/mendixlabs/mxcli/issues/12"'
chk "app name replaced"     '! echo "$B1" | grep -q "Zorbix"'
chk "module/entity replaced" '! echo "$B1" | grep -q "Quuxmod\|Widgetron" && echo "$B1" | grep -q "Module1.EntityA"'
chk "module element replaced" '! echo "$B1" | grep -q "ACT_Save"'
chk "deny list applied"     '! echo "$B1" | grep -qi "Glorpley"'

echo "C. final scan refusal"
: > "$GHLOG"
OUT="$(printf 'n\nn\nn\n' | run --all 2>&1)"
chk "BUG-02 warned and refused" 'echo "$OUT" | grep -q "WARNING: redaction left suspicious content.*opaque"'
chk "no create call carries BUG-02 text" '! grep "issue create" "$GHLOG" | grep -q "Opaque"'
chk "--links gives no URL for BUG-02" 'run --links </dev/null | grep -A1 "^BUG-02" | grep -q REFUSED'

echo "D. --file: n then y"
: > "$GHLOG"; cp "$P/docs/bugs.jsonl" "$W/before"
printf 'n\n' | run --file BUG-03 >/dev/null 2>&1
chk "answer n posts nothing" '! grep -q "issue create" "$GHLOG"'
chk "answer n leaves the log unchanged" 'cmp -s "$P/docs/bugs.jsonl" "$W/before"'
printf 'y\n' | run --file BUG-01 >/dev/null 2>&1
chk "answer y calls issue create once, on the target repo" '[ "$(grep -c "issue create" "$GHLOG")" = 1 ] && grep -q "issue create --repo mendixlabs/mxcli --title Crash on Module1.EntityA in App1 --body" "$GHLOG"'
chk "created body is the redacted one" '! grep "issue create" "$GHLOG" | grep -q "Zorbix\|ghp_\|/Users/"'
chk "status and url written back" 'grep "\"BUG-01\"" "$P/docs/bugs.jsonl" | grep -q "\"status\": \"filed\".*issues/4242"'
chk "other rows byte-identical" 'diff <(grep -v BUG-01 "$W/before") <(grep -v BUG-01 "$P/docs/bugs.jsonl") >/dev/null'
chk "a filed bug is not offered again" '! run </dev/null | grep -q "^BUG-01"'

echo "E. --links"
: > "$GHLOG"
L="$(run --links </dev/null)"
chk "links point at the target repo" 'echo "$L" | grep -q "https://github.com/mendixlabs/mxcli/issues/new?title=Plain%20bug&body="'
chk "links are URL-encoded (no raw space in a URL line)" '! echo "$L" | grep "issues/new" | sed "s/^ *//" | grep -q " "'
chk "links need no gh call" '[ ! -s "$GHLOG" ]'
"$PY" - "$P/docs/bugs.jsonl" <<'PY'
import json,sys
with open(sys.argv[1],"a") as f:
    f.write(json.dumps({"id":"BUG-06","date":"2026-10-16","target":"toolkit","title":"Huge","repro":"word "*5000,"expected":"e","actual":"a","versions":{},"workaround":"","status":"open","issue_url":""})+"\n")
PY
HUGE="$(run --links </dev/null | grep "toolkit/issues/new\|MendixMau" | head -1)"
chk "huge body truncated under 6100 chars" '[ -n "$HUGE" ] && [ "${#HUGE}" -lt 6100 ]'
chk "toolkit target uses the toolkit repo" 'echo "$HUGE" | grep -q "github.com/MendixMau/mxcli-project-toolkit/issues/new"'
chk "truncated URL does not end inside a %XX" '! echo "$HUGE" | grep -q "%[0-9A-F]\?$"'

echo "F. guards and --add"
: > "$GHLOG"
OUT="$("$SUBJ" --project "$P" --file BUG-03 </dev/null 2>&1)"
chk "no terminal and no hook: refused" 'echo "$OUT" | grep -q "interactive terminal" && ! grep -q "issue create" "$GHLOG"'
run --add --target toolkit --title "Added" --repro "r" --expected "e" --actual "a" --mxcli v1 >/dev/null
chk "--add numbers the next free BUG-NN" 'tail -1 "$P/docs/bugs.jsonl" | grep -q "\"id\": \"BUG-07\""'

echo; echo "file-bugs: $PASS pass, $FAIL fail"; [ "$FAIL" -eq 0 ]
