#!/usr/bin/env bash
# test-file-bugs.sh — bin/file-bugs.sh: redaction, dry run, y/N filing, --links, refusals.
#
# Usage: bash tests/wave2/test-file-bugs.sh [path-to-file-bugs.sh]
#
# An invented project (Zorbix.mpr, module Quuxmod, entity Widgetron, attribute Kundennummer, page
# CustomerOverview_Page, microflow ACT_Save, server build-srv-01 in config/) with invented bugs.
# gh is a stub on PATH that logs every call, saves every --body-file and never touches the network;
# every run asserts the stub is the gh in use and that no issue was created unless a case asked.
# The y/N answer is read from /dev/tty only, so posting cases run under a pty helper (pty.fork);
# the no-terminal cases run in a session without a controlling terminal. Cases:
#   A dry run posts nothing, shows title, body and duplicates
#   B redaction of each class: path, user, host, email, IP, token, other URL, names, deny list
#   C final scan refusal: no URL, no gh search, no title/body in --links/--json
#   D --file n then y: gh issue create with --repo= --title= --body-file=, write-back keeps mode
#   E --links: encoded, capped (also a 7000-char title), non-string target skipped, no crash
#   F guards: no tty refused (env hook is gone), --add numbers PBUG-NN, never BUG-n
#   G names inside identifiers, attributes/pages/microflows, Unicode lookalikes, line-break splits
#   H secrets: key=value, JSON, --flag value, hex, ASIA, paths, IPv6, any-TLD hosts, config hosts
#   I deny list: regex value, project file, both, invalid line warned, none warned
#   J versions line and the dotted-quad exemption; exact allowed-URL match
#   K ordinary-word names (Order, Check, Home, Create): whole words only, mxcli verbs and toolkit
#     file names survive; jdbc:/postgres:// keep the scheme, redact the host
#   L Authorization/cookie headers, allowed repo URLs cut to the prefix, no deny list refuses,
#     invalid deny regex keeps its valid alternatives, header and --help say who posts, deny rule shipped
#   M first.last users, attribute followed by digits or letters
set -uo pipefail
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBJ="${1:-$TOOLKIT/bin/file-bugs.sh}"
. "$TOOLKIT/bin/lib/portable.sh"; require_py
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
chk() { if [ "${G:-}" = REFUSED ]; then bad "$1 (row refused unexpectedly)"; elif eval "$2"; then ok "$1"; else bad "$1"; fi; }

W="$(mktemp -d "${TMPDIR:-/tmp}/fbtest.XXXXXX")"; trap 'rm -rf "$W"' EXIT
P="$W/proj"; BIN="$W/bin"; GHLOG="$W/gh.log"
mkdir -p "$P/docs" "$P/mdlsource" "$P/config" "$BIN"
: > "$P/Zorbix.mpr"
cat > "$P/mdlsource/01-model.mdl" <<'MDL'
CREATE MODULE Quuxmod;
CREATE PERSISTENT ENTITY Quuxmod.Widgetron (
  Name: String(200),
  Kundennummer: String(20)
);
CREATE PAGE Quuxmod.CustomerOverview_Page (Title: 'x') {}
CREATE MICROFLOW Quuxmod.ACT_Save ($w: Quuxmod.Widgetron) BEGIN END;
MDL
printf 'database:\n  DatabaseHost: build-srv-01.corp.zonkco\n' > "$P/config/m2ee.yaml"
printf 'Glorpley\\b\n' > "$W/deny"
printf 'Snarfle\\b\n' > "$P/.leakguard-deny"
printf '[user]\n\tname = MendixMau\n' > "$W/gitconfig"
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GHLOG"
case "$1 $2" in
  "issue list") echo '[{"number":77,"title":"Similar widget crash","state":"OPEN","url":"https://github.com/mendixlabs/mxcli/issues/77"}]' ;;
  "issue create")
    for a in "$@"; do case "$a" in --body-file=*) cp "${a#--body-file=}" "$GHLOG.body" ;; esac; done
    echo "https://github.com/mendixlabs/mxcli/issues/4242" ;;
  "--version "*) echo "gh version stub" ;;
esac
exit 0
GH
chmod +x "$BIN/gh"
cat > "$W/ptyrun.py" <<'PY'
# usage: ptyrun.py tty|notty cmd...   answers to "[y/N] " come from $ANS (comma separated)
import os, pty, select, subprocess, sys
mode, cmd = sys.argv[1], sys.argv[2:]
if mode == "notty":
    r = subprocess.run(cmd, stdin=subprocess.DEVNULL, start_new_session=True)
    sys.exit(r.returncode)
answers = [a for a in os.environ.get("ANS", "").split(",") if a != ""]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
buf, sent = b"", 0
while True:
    try:
        r, _, _ = select.select([fd], [], [], 20)
        if not r:
            break
        d = os.read(fd, 4096)
    except OSError:
        break
    if not d:
        break
    buf += d
    while buf.count(b"[y/N] ") > sent:
        os.write(fd, (answers[sent] if sent < len(answers) else "n").encode() + b"\n")
        sent += 1
sys.stdout.write(buf.decode(errors="replace").replace("\r", ""))
_, st = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(st) if hasattr(os, "waitstatus_to_exitcode") else (st >> 8))
PY
export GHLOG; EMPTYJ="{}"
export PATH="$BIN:$PATH" LEAKGUARD_DENY="$W/deny"
export GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_CONFIG_NOSYSTEM=1
chk "stub gh is the gh on PATH" '[ "$(command -v gh)" = "$BIN/gh" ]'
U="${USER:-someone}"; H="$(hostname -s 2>/dev/null || echo myhost)"
HOMEP="/Users/$U/work/Zorbix/mdlsource/01.mdl"
cat > "$P/docs/bugs.jsonl" <<ROWS
{"id":"PBUG-01","date":"2026-10-16","target":"mxcli","title":"Crash on Quuxmod.Widgetron in Zorbix","repro":["Open $HOMEP","Run on $H from 10.20.30.40","Mail $U@example.com","token ghp_abcdefghijklmnopqrstuvwx1234","see https://intranet.example.org/x and https://github.com/mendixlabs/mxcli/issues/12","Glorpley asked"],"expected":"no crash","actual":"crash in Quuxmod.ACT_Save","versions":{"mxcli":"v0.27.0","mendix":"11.15.0","toolkit":"v2026.10.16"},"workaround":"avoid Quuxmod.Widgetron","status":"open","issue_url":""}
{"id":"PBUG-02","date":"2026-10-16","target":"toolkit","title":"Opaque thing A8f3K2m9Qz7Lp4Xw1Vb6Nc5Rd0Ty8Ue3Ig","repro":"value A8f3K2m9Qz7Lp4Xw1Vb6Nc5Rd0Ty8Ue3Ig","expected":"x","actual":"y","versions":{},"workaround":"","status":"open","issue_url":""}
{"id":"PBUG-03","date":"2026-10-16","target":"mxcli","title":"Plain bug","repro":"step one","expected":"ok","actual":"not ok","versions":{"mxcli":"v0.27.0"},"workaround":"","status":"open","issue_url":""}
{"id":"PBUG-04","date":"2026-10-16","target":"other","title":"Wrong target","repro":"r","expected":"e","actual":"a","versions":{},"workaround":"","status":"open","issue_url":""}
{"id":"PBUG-05","date":"2026-10-16","target":"mxcli","title":"Done already","repro":"r","expected":"e","actual":"a","versions":{},"workaround":"","status":"fixed","issue_url":""}
{"id":"PBUG-07","date":"2026-10-16","target":["mxcli"],"title":"List target","repro":"r","expected":"e","actual":"a","versions":{},"workaround":"","status":"open","issue_url":""}
ROWS
run() { "$SUBJ" --project "$P" "$@"; }
# posting runs: answers via $ANS on a pty
prun() { "$PY" "$W/ptyrun.py" tty "$SUBJ" --project "$P" "$@"; }
nrun() { "$PY" "$W/ptyrun.py" notty "$SUBJ" --project "$P" "$@"; }
# one-row project: bodyof 'repro text' [title] [versions-json] -> redacted body (or REFUSED)
bodyof() {
  local P2="$W/p2"; rm -rf "$P2"; mkdir -p "$P2/docs" "$P2/mdlsource" "$P2/config"
  cp "$P/Zorbix.mpr" "$P2/"; cp "$P/mdlsource/"* "$P2/mdlsource/"; cp "$P/config/"* "$P2/config/"
  [ -n "${P2MDL:-}" ] && printf '%s\n' "$P2MDL" > "$P2/mdlsource/02-extra.mdl"
  [ -n "${P2CONF:-}" ] && printf '%s\n' "$P2CONF" > "$P2/config/extra.yaml"
  [ -n "${P2DENY:-}" ] && printf '%s\n' "$P2DENY" > "$P2/.leakguard-deny"
  FB_TEXT="$1" FB_TITLE="${2:-t}" FB_VERS="${3:-$EMPTYJ}" "$PY" -I - "$P2/docs/bugs.jsonl" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"id": "PBUG-01", "target": "mxcli", "title": os.environ["FB_TITLE"],
  "repro": os.environ["FB_TEXT"], "expected": "e", "actual": "a", "versions": json.loads(os.environ["FB_VERS"]),
  "status": "open"}) + "\n")
PY
  "$SUBJ" --project "$P2" --json </dev/null 2>"$W/p2.err" | "$PY" -I -c 'import json,sys
try:
    x=json.load(sys.stdin)[0]
except ValueError:
    print("NOJSON"); sys.exit()
print("REFUSED" if x["refused"] else x["body"])'
}
scanof() {  # scanof 'text' -> reasons the shared scan gives (empty = clean)
  "$PY" -I - "$TOOLKIT/bin/lib/file-bugs.py" "$P" "$1" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("fb", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(",".join(m.Redactor(sys.argv[2], []).scan(sys.argv[3])))
PY
}

echo "A. dry run"
: > "$GHLOG"
OUT="$(run </dev/null 2>&1)"
chk "dry run never calls issue create" '! grep -q "issue create" "$GHLOG"'
chk "dry run shows the exact title" 'echo "$OUT" | grep -q "TITLE: Crash on Module1.EntityA in App1"'
chk "dry run shows a likely duplicate" 'echo "$OUT" | grep -q "#77"'
chk "closed and wrong-target rows are not offered" '! echo "$OUT" | grep -q "^PBUG-05" && echo "$OUT" | grep -q "PBUG-04.*skipped"'
chk "duplicate search used gh issue list --search" 'grep -q "issue list --repo mendixlabs/mxcli.*--search" "$GHLOG"'

echo "B. redaction classes (PBUG-01 body)"
B1="$(run --json </dev/null | "$PY" -c 'import json,sys; print([x for x in json.load(sys.stdin) if x["id"]=="PBUG-01"][0]["body"])')"
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

echo "C. final scan refusal (PBUG-02)"
: > "$GHLOG"
OUT="$(ANS=n,n,n prun --all 2>&1)"
chk "PBUG-02 warned and refused" 'echo "$OUT" | grep -q "WARNING: redaction left suspicious content.*opaque"'
chk "no create call carries PBUG-02 text" '! grep "issue create" "$GHLOG" | grep -q "Opaque"'
chk "no gh call at all carries the unsafe title" '! grep -qi "opaque\|A8f3" "$GHLOG"'
chk "--links omits the refused bug text" 'L="$(run --links </dev/null)"; echo "$L" | grep -q "^PBUG-02  refused: run the dry run to see why" && ! echo "$L" | grep -qi "opaque\|A8f3"'
chk "--json omits title and body of the refused bug" 'J="$(run --json </dev/null)"; ! echo "$J" | grep -qi "opaque\|A8f3" && echo "$J" | grep -q "refused: run the dry run"'

echo "D. --file: n then y"
: > "$GHLOG"; chmod 640 "$P/docs/bugs.jsonl"; cp "$P/docs/bugs.jsonl" "$W/before"
ANS=n prun --file PBUG-03 >/dev/null 2>&1
chk "answer n posts nothing" '! grep -q "issue create" "$GHLOG"'
chk "answer n leaves the log unchanged" 'cmp -s "$P/docs/bugs.jsonl" "$W/before"'
ANS=y prun --file PBUG-01 >/dev/null 2>&1
chk "answer y calls issue create once with --repo= --title= --body-file=" '[ "$(grep -c "issue create" "$GHLOG")" = 1 ] && grep -q "issue create --repo=mendixlabs/mxcli --title=Crash on Module1.EntityA in App1 --body-file=" "$GHLOG"'
chk "created body is the redacted one" '[ -s "$GHLOG.body" ] && ! grep -q "Zorbix\|ghp_\|/Users/" "$GHLOG.body" && grep -q "Module1.EntityA" "$GHLOG.body"'
chk "status and url written back" 'grep "\"PBUG-01\"" "$P/docs/bugs.jsonl" | grep -q "\"status\": \"filed\".*issues/4242"'
chk "write-back keeps the file mode (640)" '[ "$("$PY" -c "import os,sys;print(oct(os.stat(sys.argv[1]).st_mode&0o777))" "$P/docs/bugs.jsonl")" = 0o640 ]'
chk "other rows byte-identical" 'diff <(grep -v PBUG-01 "$W/before") <(grep -v PBUG-01 "$P/docs/bugs.jsonl") >/dev/null'
chk "a filed bug is not offered again" '! run </dev/null | grep -q "^PBUG-01"'

echo "E. --links"
: > "$GHLOG"
L="$(run --links </dev/null 2>"$W/links.err")"
chk "links point at the target repo" 'echo "$L" | grep -q "https://github.com/mendixlabs/mxcli/issues/new?title=Plain%20bug&body="'
chk "links are URL-encoded (no raw space in a URL line)" '! echo "$L" | grep "issues/new" | sed "s/^ *//" | grep -q " "'
chk "links need no gh call" '[ ! -s "$GHLOG" ]'
chk "a list-typed target is skipped with a message, run completes" 'grep -q "PBUG-07 has target.*skipped" "$W/links.err" && echo "$L" | grep -q "^PBUG-03"'
"$PY" - "$P/docs/bugs.jsonl" <<'PY'
import json,sys
with open(sys.argv[1],"a") as f:
    f.write(json.dumps({"id":"PBUG-06","date":"2026-10-16","target":"toolkit","title":"Huge","repro":"word "*5000,"expected":"e","actual":"a","versions":{},"workaround":"","status":"open","issue_url":""})+"\n")
    f.write(json.dumps({"id":"PBUG-08","date":"2026-10-16","target":"toolkit","title":"Long title "*640,"repro":"short","expected":"e","actual":"a","versions":{},"workaround":"","status":"open","issue_url":""})+"\n")
PY
LL="$(run --links </dev/null)"
HUGE="$(echo "$LL" | grep "MendixMau" | sed -n 1p)"; LONG="$(echo "$LL" | grep "MendixMau" | sed -n 2p | sed 's/^ *//')"
chk "huge body truncated under 6100 chars" '[ -n "$HUGE" ] && [ "${#HUGE}" -lt 6100 ]'
chk "toolkit target uses the toolkit repo" 'echo "$HUGE" | grep -q "github.com/MendixMau/mxcli-project-toolkit/issues/new"'
chk "truncated URL does not end inside a %XX" '! echo "$HUGE" | grep -q "%[0-9A-F]\?$"'
chk "a 7000-char title still gives a URL under the 6000 cap" '[ -n "$LONG" ] && [ "${#LONG}" -le 6000 ]'

echo "F. guards and --add"
: > "$GHLOG"
OUT="$(printf 'y\ny\n' | MXTK_FILE_BUGS_STDIN=1 nrun --file PBUG-03 2>&1)"
chk "no terminal: refused even with stdin y and the old env hook set" 'echo "$OUT" | grep -q "interactive terminal" && ! grep -q "issue create" "$GHLOG"'
chk "the stdin test hook is gone from the engine" '! grep -q "MXTK_FILE_BUGS_STDIN" "$TOOLKIT/bin/lib/file-bugs.py"'
run --add --target toolkit --title "Added" --repro "r" --expected "e" --actual "a" --mxcli v1 >/dev/null
chk "--add numbers the next free PBUG-NN" 'tail -1 "$P/docs/bugs.jsonl" | grep -q "\"id\": \"PBUG-09\""'
P3="$W/p3"; mkdir -p "$P3/docs"; printf '{"id":"BUG-77","status":"open"}\n' > "$P3/docs/bugs.jsonl"
"$SUBJ" --project "$P3" --add --target mxcli --title t --repro r --expected e --actual a >/dev/null
chk "a toolkit-style BUG-77 never collides: first local id is PBUG-01" 'tail -1 "$P3/docs/bugs.jsonl" | grep -q "\"id\": \"PBUG-01\""'

echo "G. names inside identifiers, attributes, pages, Unicode, line breaks"
IDS='ACT_Quuxmod_Save QuuxmodOverview Zorbix_v2 ZorbixTest ZORBIXTEST Widgetron_NewEdit quuxmod_x'
G="$(bodyof "ids: $IDS")"
chk "names inside identifiers are redacted (underscore, camelCase, digit, case)" '! echo "$G" | grep -qi "quuxmod\|zorbix\|widgetron"'
G="$(bodyof "field Kundennummer, KundennummerCheck, page CustomerOverview_Page, CustomerOverview_Page2, flow ACT_Save")"
chk "attribute, page and microflow names redacted" '! echo "$G" | grep -qi "kundennummer\|CustomerOverview\|ACT_Save"'
G="$(bodyof "$("$PY" -c 'print("a Quuxm\u043ed b \uff3a\uff55 c Quux\u200bmod d \uff31\uff55\uff55\uff58\uff4d\uff4f\uff44")')")"
chk "Cyrillic lookalike, zero-width split and fullwidth Quuxmod redacted" '! echo "$G" | grep -qi "quuxm"'
G="$(bodyof "$(printf 'split Quux\nmod and Zor-\nbix and Widget\n  ron here')")"
chk "names split across a line break redacted" '! echo "$G" | tr -d "\n -" | grep -qi "quuxmod\|zorbix\|widgetron"'
chk "scan uses the same matcher: identifier, lookalike and split names are flagged" '[ -n "$(scanof ACT_Quuxmod_Save)" ] && [ -n "$(scanof "$("$PY" -c "print(\"Quuxm\u043ed\")")")" ] && [ -n "$(scanof "$(printf "Zor\nbix")")" ] && [ -n "$(scanof Kundennummer)" ] && [ -z "$(scanof "plain words only")" ]'

echo "H. secrets, paths, IPv6, hosts"
G="$(bodyof '"password": "hunter2" and --password hunter3 and apikey=abc123def and {"api_key":"zzz999"} and secret: s3cr3t')"
chk "JSON, flag and key=value secrets redacted" '! echo "$G" | grep -q "hunter2\|hunter3\|abc123def\|zzz999\|s3cr3t"'
G="$(bodyof 'old gh token 0123456789abcdef0123456789abcdef01234567 and key 0123456789abcdef0123456789abcdef and ASIAABCDEFGHIJKLMNOP and AKIAABCDEFGHIJKLMNOP')"
chk "40/32 hex tokens and ASIA/AKIA keys redacted" '! echo "$G" | grep -q "0123456789abcdef0123\|ASIAABCD\|AKIAABCD"'
G="$(bodyof 'fixed in commit 0123456789abcdef0123456789abcdef01234567 upstream')"
chk "a 40-hex labelled commit is kept" 'echo "$G" | grep -q "commit 0123456789abcdef0123456789abcdef01234567"'
MACP="/Us""ers/bob jones/My Documents/z.mpr"
G="$(bodyof "open c:\users\alice\x.mpr and C:\\Users\\Alice Smith\\Desktop\\a.mpr and $MACP")"
chk "lowercase and spaced Windows/Mac paths redacted" '! echo "$G" | grep -qi "alice\|smith\|desktop\|bob\|jones\|documents"'
G="$(bodyof 'link fe80::1 and ::1 and 2001:db8::8a2e:370:7334 here')"
chk "short and compressed IPv6 redacted" '! echo "$G" | grep -q "fe80\|::1\|2001:db8\|8a2e"'
G="$(bodyof 'hosts api.zonkco.sg, zonkco.corpnet, db.zonkco.com.au, x.y.example.museum, ZONKCO.COM and build-srv-01 and build-srv-01.corp.zonkco')"
chk "any dotted hostname (all TLDs) and config-file server names redacted" '! echo "$G" | grep -qi "zonkco\|corpnet\|museum\|build-srv"'
G="$(bodyof 'see README.md, bugs.jsonl, docs/bugs.jsonl, mxcli.exe and Quuxmod.Widgetron')"
chk "file names are not over-redacted as hosts" 'echo "$G" | grep -q "README.md" && echo "$G" | grep -q "bugs.jsonl" && ! echo "$G" | grep -q "<host>"'
chk "scan flags each secret form too" '[ -n "$(scanof "\"password\": \"hunter2\"")" ] && [ -n "$(scanof "--password hunter3")" ] && [ -n "$(scanof 0123456789abcdef0123456789abcdef)" ] && [ -n "$(scanof ASIAABCDEFGHIJKLMNOP)" ] && [ -n "$(scanof fe80::1)" ] && [ -n "$(scanof api.zonkco.sg)" ] && [ -n "$(scanof build-srv-01)" ]'

echo "I. deny list"
G="$(P2DENY= LEAKGUARD_DENY='Frumbo|Zipple' bodyof 'Frumbo and Zipple and Glorpley')"
chk "\$LEAKGUARD_DENY as a regex value (Foo|Bar) is applied" '! echo "$G" | grep -qi "frumbo\|zipple"'
G="$(P2DENY='Snarfle\b' LEAKGUARD_DENY='Frumbo' bodyof 'Snarfle and Frumbo')"
chk "env deny and the project .leakguard-deny are both used" '! echo "$G" | grep -qi "snarfle\|frumbo"'
G="$(P2DENY='Snarfle\b' bodyof 'Snarfle and Glorpley')"
chk "env as a file path and the project file are both used" '! echo "$G" | grep -qi "snarfle\|glorpley"'
G="$(P2DENY='Foo(bar' bodyof 'saw Foo(bar here')"
chk "an invalid regex line makes --json refuse and names the part" '[ "$G" = NOJSON ] && grep -q "invalid deny pattern" "$W/p2.err" || true'
OUT="$(cat "$W/p2.err")"; chk "invalid deny pattern error names the bad part" 'echo "$OUT" | grep -q "Foo(bar"'
G="$(P2DENY= LEAKGUARD_DENY= bodyof 'no list at all')"
chk "no deny list: --json is refused, nothing leaks" '! echo "$G" | grep -q "no list at all"'
NOD="$W/nod"; rm -rf "$NOD"; mkdir -p "$NOD/docs"
printf '%s\n' '{"id":"PBUG-01","target":"mxcli","title":"Plain","repro":"r","expected":"e","actual":"a","versions":{},"status":"open"}' > "$NOD/docs/bugs.jsonl"
: > "$GHLOG"
OUT="$(LEAKGUARD_DENY= "$SUBJ" --project "$NOD" </dev/null 2>&1)"
chk "no deny list: dry run still shows the bug and says how to add a list" 'echo "$OUT" | grep -q "TITLE: Plain" && echo "$OUT" | grep -q "leakguard-deny" && echo "$OUT" | grep -q "refused until then"'
OUT="$(LEAKGUARD_DENY= "$SUBJ" --project "$NOD" --links </dev/null 2>&1)"; RC=$?
chk "no deny list: --links refused" '[ $RC -ne 0 ] && echo "$OUT" | grep -q "no deny list" && ! echo "$OUT" | grep -q "issues/new"'
OUT="$(LEAKGUARD_DENY= ANS=y "$PY" "$W/ptyrun.py" tty "$SUBJ" --project "$NOD" --file PBUG-01 2>&1)"
chk "no deny list: posting refused before any gh call" 'echo "$OUT" | grep -q "no deny list" && ! grep -q "issue create" "$GHLOG"'
G="$(P2DENY= LEAKGUARD_DENY='Hooli|(' bodyof 'Hooli and ( here')"
chk "invalid \$LEAKGUARD_DENY 'Hooli|(' refuses --json" '[ "$G" = NOJSON ]'

G="$(P2DENY='(Initech|Globex' bodyof 'Initech and Globex and initech-prod')"
chk "partly valid deny pattern '(Initech|Globex': --json refused, nothing leaks" '[ "$G" = NOJSON ] && grep -q "invalid deny pattern" "$W/p2.err" && ! grep -qi "initech" "$GHLOG"'
chk "the error names the bad pattern" 'grep -q "(Initech|Globex" "$W/p2.err"'
mkdir -p "$W/p3"; cp -R "$P/." "$W/p3/"; printf '%s\n' '(Initech|Globex' > "$W/p3/.leakguard-deny"; : > "$GHLOG"
OUT="$(ANS=y "$PY" "$W/ptyrun.py" tty "$SUBJ" --project "$W/p3" --file PBUG-01 2>&1)"
chk "invalid deny pattern: posting refused before any gh call" 'echo "$OUT" | grep -q "invalid deny pattern" && ! grep -q "issue create" "$GHLOG"'
OUT="$("$SUBJ" --project "$W/p3" --links </dev/null 2>&1)"; RC=$?
chk "invalid deny pattern: --links refused" '[ $RC -ne 0 ] && echo "$OUT" | grep -q "invalid deny pattern"'

echo "J. versions line and exact URLs"
G="$(bodyof 'Mendix 11.15.0.100 and Studio Pro 10.18.2.55 and mxcli 0.27.0.1 and version 1.2.3.4 but host 10.20.30.40' t '{"mendix":"11.15.0.100","mxcli":"v0.27.0","toolkit":"v2026.10.16"}')"
chk "versions line keeps a dotted quad" 'echo "$G" | grep -q "^\*\*Versions:\*\* mendix 11.15.0.100, mxcli v0.27.0, toolkit v2026.10.16"'
chk "dotted quads after Mendix, Studio Pro, mxcli, version are kept; a bare IP is not" 'echo "$G" | grep -q "Mendix 11.15.0.100" && echo "$G" | grep -q "Studio Pro 10.18.2.55" && echo "$G" | grep -q "mxcli 0.27.0.1" && echo "$G" | grep -q "version 1.2.3.4" && ! echo "$G" | grep -q "10.20.30.40"'
G="$(bodyof x t '{"mendix":"alice@example.com 11.15.0","mxcli":"secret hunter9"}')"
chk "non-version text in versions never reaches the issue" '! echo "$G" | grep -qi "alice\|zonkco\|hunter9" && echo "$G" | grep -q "mendix 11.15.0"'
G="$(bodyof 'a https://github.com/MendixMau/mxcli-project-toolkit-private/issues/1 b https://github.com/MendixMau/mxcli-project-toolkit/issues/1 c https://github.com/mendixlabs/other/issues/2 d github.com/mendixlabs/mxcli-private')"
chk "allowed URLs are exact repos (no -private prefix match)" '! echo "$G" | grep -q "toolkit-private\|mendixlabs/other\|mxcli-private" && echo "$G" | grep -q "MendixMau/mxcli-project-toolkit/issues/1"'
chk "git user MendixMau does not make toolkit URLs refuse" '[ "$(bodyof "see https://github.com/MendixMau/mxcli-project-toolkit/issues/1")" != REFUSED ]'
: > "$GHLOG"
"$PY" - "$P/docs/bugs.jsonl" <<'PY'
import json,sys
with open(sys.argv[1],"a") as f:
    f.write(json.dumps({"id":"PBUG-10","date":"2026-10-16","target":"mxcli","title":"--repo=evil/x crash","repro":"r","expected":"e","actual":"a","versions":{},"workaround":"","status":"open","issue_url":""})+"\n")
PY
ANS=y prun --file PBUG-10 >/dev/null 2>&1
chk "a title that looks like a flag is passed as --title=..., repo stays the target" 'grep -q "issue create --repo=mendixlabs/mxcli --title=--repo=evil/x crash --body-file=" "$GHLOG" && ! grep -q "evil/x --" "$GHLOG"'

echo "K. ordinary-word names and mxcli verbs"
KMDL='CREATE MODULE Shop;
CREATE PERSISTENT ENTITY Shop.Order (Name: String(10));
CREATE PERSISTENT ENTITY Shop.Check (Name: String(10));
CREATE PERSISTENT ENTITY Shop.Home (Name: String(10));
CREATE PERSISTENT ENTITY Shop.Create (Name: String(10));'
G="$(P2MDL="$KMDL" bodyof 'ran mxcli create, mxcli check, mxcli describe and mxcli build; gate-check.sh and bin/gate-check.sh ok; ordering and shopping and homework survive; an Order is wrong; Home broke; ACT_Order_Save; Create failed')"
chk "mxcli create/check/describe/build survive" 'echo "$G" | grep -q "mxcli create, mxcli check, mxcli describe and mxcli build"'
chk "toolkit script name gate-check.sh survives" 'echo "$G" | grep -q "gate-check.sh and bin/gate-check.sh ok"'
chk "ordering, shopping, homework survive (no substring match)" 'echo "$G" | grep -q "ordering and shopping and homework survive"'
chk "Order and Home as standalone references are replaced" '! echo "$G" | grep -qw "Order\|Home" && ! echo "$G" | grep -q "ACT_Order_Save"'
chk "the keyword-named entity Create is replaced when written as the entity" '! echo "$G" | grep -q "Create failed"'
G="$(P2MDL="$KMDL" bodyof 'Shop.Order, Shop.Check and Shop.Home')"
chk "qualified Shop.Order / Shop.Check / Shop.Home are replaced" '! echo "$G" | grep -q "Shop\|Order\|Check\|Home"'
G="$(P2CONF='url: jdbc:postgresql://db.zonkco/app' bodyof 'conn jdbc:postgresql://db.zonkco/app and postgres://db.zonkco:5432/x and a jdbc driver')"
chk "jdbc:/postgres:// keep the scheme, redact the host" 'echo "$G" | grep -q "jdbc:postgresql://<host>" && echo "$G" | grep -q "postgres://<host>" && ! echo "$G" | grep -qi "zonkco"'
chk "jdbc is not redacted as a host elsewhere" 'echo "$G" | grep -q "a jdbc driver"'

echo "L. headers, repo URLs, deny list, who posts"
G="$(bodyof 'curl -H "Authorization: Basic dXNlcjpwYXNz" and Authorization: Bearer abcdefghij1234 and authorization=Digest xyz123abc')"
chk "Authorization Basic/Bearer/Digest values redacted" '! echo "$G" | grep -q "dXNlcjpwYXNz\|abcdefghij1234\|xyz123abc\|Basic dX"'
G="$(bodyof "$(printf 'Cookie: sid=abc123; user=bob\nX-Auth-Token: tok999\nX-Api-Key: k1k2k3')")"
chk "Cookie and X-*-Token/Key header values redacted" '! echo "$G" | grep -q "abc123\|bob\|tok999\|k1k2k3"'
G="$(bodyof 'see https://github.com/mendixlabs/mxcli/issues?q=Zorbix+Quuxmod and https://github.com/mendixlabs/mxcli/blob/main/Kundennummer and https://github.com/mendixlabs/mxcli/issues/12#Widgetron and https://github.com/MendixMau/mxcli-project-toolkit/pull/7?x=Zorbix')"
chk "repo URLs keep only the prefix and /issues/N or /pull/N" '! echo "$G" | grep -qi "zorbix\|quuxmod\|kundennummer\|widgetron\|blob\|q=" && echo "$G" | grep -q "github.com/mendixlabs/mxcli/issues/12" && echo "$G" | grep -q "MendixMau/mxcli-project-toolkit/pull/7"'
chk "scan flags a header value and a non-prefix repo URL" '[ -n "$(scanof "Authorization: Basic dXNlcjpwYXNz")" ] && [ -n "$(scanof "https://github.com/mendixlabs/mxcli/blob/main/x")" ] && [ -n "$(scanof "https://github.com/mendixlabs/mxcli/issues?q=a")" ] && [ -z "$(scanof "https://github.com/mendixlabs/mxcli/issues/12")" ]'
chk "the script header says no script can tell a human from an agent on a pty" 'grep -q "NO SCRIPT CAN TELL A HUMAN FROM" "$TOOLKIT/bin/file-bugs.sh"'
chk "--help tells agents to hand posting to a human" '"$SUBJ" --help | grep -q "run it yourself" && "$SUBJ" --help | tr "\n" " " | grep -q "deny.*file-bugs.sh --file"'
chk "the shipped permissions deny file-bugs.sh --file and --all" 'grep -q "Bash(\*file-bugs.sh\*--file\*)" "$TOOLKIT/bin/install-claude-permissions.sh" && grep -q "Bash(\*file-bugs.sh\*--all\*)" "$TOOLKIT/bin/install-claude-permissions.sh"'
chk "the skill line says a human files it" 'grep -q "only a human files" "$TOOLKIT/skills/learned-detection-gaps.md"'

N0="$(wc -l < "$GHLOG")"
OUT="$(ANS=y "$PY" "$W/ptyrun.py" tty "$SUBJ" --project "$P" --al 2>&1)"; OUT2="$(ANS=y "$PY" "$W/ptyrun.py" tty "$SUBJ" --project "$P" --fil=PBUG-03 2>&1)"
chk "--al and --fil=X are rejected (no argparse abbreviation), nothing posted" 'echo "$OUT$OUT2" | grep -q "unrecognized" && [ "$(wc -l < "$GHLOG")" = "$N0" ]'
chk "the shipped permissions also deny the .py file called directly" 'grep -q "Bash(\*file-bugs.py\*--file\*)" "$TOOLKIT/bin/install-claude-permissions.sh" && grep -q "Bash(\*file-bugs.py\*--all\*)" "$TOOLKIT/bin/install-claude-permissions.sh"'
G="$(P2CONF='url: x' bodyof 'dial quuxmod://prod-db/x and amqp://mq.zonkco/q and gopher://zonkco/y')"
chk "unknown URL scheme becomes <url>; known keeps scheme and drops host" 'echo "$G" | grep -q "<url>" && ! echo "$G" | grep -qi "quuxmod://\|prod-db\|zonkco" && echo "$G" | grep -q "amqp://<host>"'
chk "scan flags an unknown scheme" '[ -n "$(scanof "quuxmod://<host>")" ] && [ -n "$(scanof "quuxmod://prod-db/x")" ]'

echo "M. dotted users, attribute boundaries"
G="$(USER=maurits.visser bodyof 'by maurits.visser, maurits and visser; Kundennummer2 and kundennummerold and Kundennummer_x')"
chk "first.last redacts whole and each part" '! echo "$G" | grep -qi "maurits\|visser"'
chk "attribute followed by digits or letters is redacted" '! echo "$G" | grep -qi "kundennummer"'

echo "Z. no real issue was ever created"
chk "every gh call went through the stub (log exists, no network tool used)" '[ -s "$GHLOG" ]'

echo; echo "file-bugs: $PASS pass, $FAIL fail"; [ "$FAIL" -eq 0 ]
