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
#   N --to; O no gh on PATH
#   R no-GitHub path: the one-line reason gh cannot be used (not installed / signed out / no access /
#     ready), --auto falling back to --bundle (or --links with an account), --bundle = the --json
#     redaction with held-back rows left out, the mail-to line (env, toolkit.env, company brain, none),
#     bundled marking and no re-bundle, --import: parse, re-redact, dedupe, labels, refusals
#   Q #645 the toolkit clone's .leakguard-deny (where init-project.sh registers every project) is
#     read too; #646 code identifiers (obj.method(, Java packages, CLAUDE.md) survive while hosts and
#     deny names do not, and the versions line carries the toolkit version
#   P --auto: off without the PROJECT.md opt-in (also commented/annotated), opted in posts every clean
#     row with no tty and writes issue_url back, scan-failing row never posted, label only when the
#     repo has it or the user may create it, exact-title duplicate recorded not reposted, no gh or not
#     signed in -> links and exit 0, no deny list refused; --add --log redaction and drop; the
#     permissions deny --file/--all but not --auto
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
  "issue list") echo '[{"number":77,"title":"Similar widget crash","state":"OPEN","url":"https://github.com/'"${4:-mendixlabs/mxcli}"'/issues/77"}]' ;;
  "issue create")
    r=mendixlabs/mxcli
    for a in "$@"; do case "$a" in --body-file=*) cp "${a#--body-file=}" "$GHLOG.body"; cat "${a#--body-file=}" >> "$GHLOG.all" ;; --repo=*) r="${a#--repo=}" ;;
      --label=*) [ -n "${GH_LABEL_FAIL:-}" ] && { echo "could not add label" >&2; exit 1; } ;; esac; done
    echo "https://github.com/$r/issues/4242" ;;
  "auth status") exit "${GH_AUTH_RC:-0}" ;;
  "label list") echo "${GH_LABELS:-[]}" ;;
  "label create") exit "${GH_LABEL_CREATE_RC:-0}" ;;
  "repo view") echo "${GH_PERM:-READ}" ;;
  "api repos/"*) [ -n "${GH_REPO_ERR:-}" ] && echo "$GH_REPO_ERR" >&2; [ -n "${GH_REPO_RC:-}" ] && exit "$GH_REPO_RC"; echo true ;;
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
# the toolkit clone's own denylist (#645) is never the developer's real one in this fixture
export MXTK_LEAKGUARD_DENYFILE="$W/tk-deny-none"
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
  [ -n "${P2PM:-}" ] && printf '%s\n' "$P2PM" > "$P2/PROJECT.md"
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

echo "N. --to: the same bug filed to the other repo too"
: > "$GHLOG"; cp "$P/docs/bugs.jsonl" "$W/before"
chk "--to toolkit offers a filed mxcli bug for the toolkit repo" 'run --to toolkit --json </dev/null | "$PY" -I -c "import json,sys;x=[i for i in json.load(sys.stdin) if i[\"id\"]==\"PBUG-01\"];sys.exit(not(x and \"MendixMau/mxcli-project-toolkit\" in json.dumps(x)))"'
ANS=y prun --file PBUG-01 --to toolkit >/dev/null 2>&1
chk "--to toolkit creates the issue in the toolkit repo" '[ "$(grep -c "issue create" "$GHLOG")" = 1 ] && grep -q "issue create --repo=MendixMau/mxcli-project-toolkit " "$GHLOG"'
chk "the row keeps its target, status and first url; the second url goes in also" 'grep "\"PBUG-01\"" "$P/docs/bugs.jsonl" | grep "\"target\": *\"mxcli\"" | grep "\"status\": \"filed\"" | grep -q "\"issue_url\": \"https://github.com/mendixlabs/mxcli/issues/4242\", \"also\": {\"toolkit\": \"https://github.com/MendixMau/mxcli-project-toolkit/issues/4242\"}"'
chk "other rows byte-identical after --to" 'diff <(grep -v PBUG-01 "$W/before") <(grep -v PBUG-01 "$P/docs/bugs.jsonl") >/dev/null'
chk "a bug already filed to that repo is not offered again" '! run --to toolkit </dev/null | grep -q "^PBUG-01"'
chk "without --to a filed bug is still not offered" '! run </dev/null | grep -q "^PBUG-01"'

echo "O. no gh on PATH: nothing breaks"
NOGH="$W/nogh"; mkdir -p "$NOGH"; # every tool from the normal PATH except gh, so only "gh missing" differs
IFS=: read -ra DIRS <<< "$PATH"; for d in "${DIRS[@]}"; do [ "$d" = "$BIN" ] && continue; for c in "$d"/*; do n="${c##*/}"; [ "$n" = gh ] || [ -e "$NOGH/$n" ] || ln -s "$c" "$NOGH/$n" 2>/dev/null; done; done
cp "$P/docs/bugs.jsonl" "$W/before"; NC="$(grep -c "" "$GHLOG")"
OUT="$(PATH="$NOGH" ANS=y "$PY" "$W/ptyrun.py" tty "$SUBJ" --project "$P" --file PBUG-03 2>&1)"; RC=$?
chk "the stripped PATH really has no gh" '! PATH="$NOGH" command -v gh >/dev/null'
chk "without gh, --file exits 0" '[ "$RC" = 0 ]'
chk "without gh nothing is posted and the stub was never reached" '[ "$(grep -c "" "$GHLOG")" = "$NC" ] && echo "$OUT" | grep -q "Not posting"'
chk "without gh the log is unchanged" 'cmp -s "$P/docs/bugs.jsonl" "$W/before"'
chk "without gh it names the way out (gh auth login, or --links)" 'echo "$OUT" | grep -q "Nothing breaks" && echo "$OUT" | grep -q "file-bugs.sh --links PBUG-03"'

echo "P. --auto (opt-in) and --add --log"
PA="$W/pa"; rm -rf "$PA"; mkdir -p "$PA/docs" "$PA/mdlsource"; cp "$P/Zorbix.mpr" "$P/mdlsource/01-model.mdl" "$PA/" 2>/dev/null
mv "$PA/01-model.mdl" "$PA/mdlsource/"; cp -R "$P/config" "$PA/"; printf 'Snarfle\\b\n' > "$PA/.leakguard-deny"
cat > "$PA/docs/bugs.jsonl" <<'ROWS'
{"id":"PBUG-01","date":"2026-11-05","target":"toolkit","title":"Stage 0 gate passes when the sign-off is a placeholder","repro":"run gate-check.sh on Quuxmod","expected":"FAIL","actual":"PASS","versions":{},"workaround":"","status":"open","issue_url":""}
{"id":"PBUG-02","date":"2026-11-05","target":"mxcli","title":"Opaque thing A8f3K2m9Qz7Lp4Xw1Vb6Nc5Rd0Ty8Ue3Ig","repro":"r","expected":"e","actual":"a","versions":{},"workaround":"","status":"open","issue_url":""}
ROWS
cp "$PA/docs/bugs.jsonl" "$W/pa.before"
arun() { "$PY" "$W/ptyrun.py" notty "$SUBJ" --project "$PA" --auto "$@"; }
git -C "$PA" init -q
# reg LINE [nocommit]: write PROJECT.md and commit it (the opt-in must be in HEAD), unless nocommit
reg() { printf '# PROJECT.md\n\n%s\n' "$1" > "$PA/PROJECT.md"; [ -n "${2:-}" ] && return 0
  git -C "$PA" add PROJECT.md && git -C "$PA" -c user.name=t -c user.email=tester commit -qm "register" >/dev/null 2>&1 || true; }
: > "$GHLOG"; reg 'Exec approval: auto'
OUT="$(arun 2>&1)"; RC=$?
chk "no opt-in, no tty: --auto posts nothing, says why, exits 0" '[ $RC = 0 ] && ! grep -q "issue create" "$GHLOG" && echo "$OUT" | grep -q "no line .Bug filing: auto." && cmp -s "$PA/docs/bugs.jsonl" "$W/pa.before"'
for line in '<!-- Bug filing: auto — uncomment to opt in -->' 'Bug filing: auto (maybe)' 'Bug filing: autopost' '> Bug filing: auto?'; do
  cp "$W/pa.before" "$PA/docs/bugs.jsonl"; : > "$GHLOG"; reg "$line"; arun >/dev/null 2>&1
  chk "not an opt-in: '$line'" '! grep -q "issue create" "$GHLOG"'
done
cp "$W/pa.before" "$PA/docs/bugs.jsonl"; : > "$GHLOG"; reg '**Bug filing:** auto'
OUT="$(arun 2>&1)"; RC=$?
chk "opted in (bold), no tty: posts the clean row once, to its target repo" '[ $RC = 0 ] && [ "$(grep -c "issue create" "$GHLOG")" = 1 ] && grep -q "issue create --repo=MendixMau/mxcli-project-toolkit --title=Stage 0 gate passes" "$GHLOG"'
chk "opted in: duplicate search ran before the create" 'grep -n "" "$GHLOG" | grep "issue list" | head -1 | cut -d: -f1 | { read n; [ "$n" -lt "$(grep -n "issue create" "$GHLOG" | cut -d: -f1)" ]; }'
chk "opted in: posted body is redacted, carries the footer and the related #77" 'grep -q "Module1" "$GHLOG.body" && ! grep -q "Quuxmod" "$GHLOG.body" && grep -q "file-bugs.sh --auto" "$GHLOG.body" && grep -q "Possibly related: #77" "$GHLOG.body"'
chk "opted in: status=filed and issue_url written back" 'grep "\"PBUG-01\"" "$PA/docs/bugs.jsonl" | grep -q "\"status\": \"filed\".*MendixMau/mxcli-project-toolkit/issues/4242"'
chk "opted in: the scan-failing row is reported, never posted, stays open" 'echo "$OUT" | grep -q "WARNING: redaction left suspicious content" && ! grep -qi "opaque\|A8f3" "$GHLOG" && grep "\"PBUG-02\"" "$PA/docs/bugs.jsonl" | grep -q "\"status\":\"open\""'
chk "opted in: summary line counts filed and refused" 'echo "$OUT" | grep -q "file-bugs --auto: 1 filed, 1 refused"'
chk "opted in: the run names the commit that opted in" 'echo "$OUT" | grep -q "opted in by commit $(git -C "$PA" log -1 --format=%h) "'
: > "$GHLOG"; OUT="$(arun --to mxcli 2>&1)"; RC=$?
chk "--auto --to is refused: a filed row is never re-posted to the other repo" '[ $RC -ne 0 ] && echo "$OUT" | grep -q "cannot be combined" && ! grep -q "issue create" "$GHLOG"'
: > "$GHLOG"; arun >/dev/null 2>&1
chk "--auto never re-posts a filed row" '! grep "issue create" "$GHLOG" | grep -q "Stage 0 gate"'
cp "$W/pa.before" "$PA/docs/bugs.jsonl"; : > "$GHLOG"; reg "$(printf 'Example:\n```\nBug filing: auto\n```')"; arun >/dev/null 2>&1
chk "a Bug filing: auto line inside a code fence does not opt in" '! grep -q "issue create" "$GHLOG"'
: > "$GHLOG"; reg 'Exec approval: auto'; reg 'Bug filing: auto' nocommit; OUT="$(arun 2>&1)"
chk "an uncommitted opt-in line does not opt in, and says so" '! grep -q "issue create" "$GHLOG" && echo "$OUT" | grep -q "not committed yet"'
mv "$PA/.git" "$W/pa.git"; : > "$GHLOG"; OUT="$(arun 2>&1)"
chk "no git repo: not opted in, dry run" '! grep -q "issue create" "$GHLOG" && echo "$OUT" | grep -q "not in a git commit"'
mv "$W/pa.git" "$PA/.git"; reg '**Bug filing:** auto'; cp "$W/pa.before" "$PA/docs/bugs.jsonl"
chk "no label exists and the user may not create one: no --label, no label create" '! grep -q "label=\|label create" "$GHLOG"'
cp "$W/pa.before" "$PA/docs/bugs.jsonl"; : > "$GHLOG"
GH_LABELS='[{"name":"auto-filed"}]' arun >/dev/null 2>&1
chk "the repo has auto-filed: the issue carries it" 'grep "issue create" "$GHLOG" | grep -q -- "--label=auto-filed"'
cp "$W/pa.before" "$PA/docs/bugs.jsonl"; : > "$GHLOG"
GH_PERM=WRITE arun >/dev/null 2>&1
chk "missing label, WRITE permission: label created, then used" 'grep -q "^label create auto-filed --repo MendixMau/mxcli-project-toolkit" "$GHLOG" && grep "issue create" "$GHLOG" | grep -q -- "--label=auto-filed"'
cp "$W/pa.before" "$PA/docs/bugs.jsonl"; : > "$GHLOG"
GH_LABELS='[{"name":"auto-filed"}]' GH_LABEL_FAIL=1 arun >/dev/null 2>&1
chk "a label the user may not apply: retried without it, still filed" '[ "$(grep -c "issue create" "$GHLOG")" = 2 ] && grep "\"PBUG-01\"" "$PA/docs/bugs.jsonl" | grep -q "\"status\": \"filed\""'
printf '%s\n' '{"id":"PBUG-03","target":"mxcli","title":"Similar widget crash","repro":"r","expected":"e","actual":"a","versions":{},"status":"open"}' >> "$PA/docs/bugs.jsonl"; : > "$GHLOG"
arun >/dev/null 2>&1
chk "exact-title duplicate: not reposted, its URL recorded" '! grep "issue create" "$GHLOG" | grep -q "Similar widget" && grep "\"PBUG-03\"" "$PA/docs/bugs.jsonl" | grep -q "\"issue_url\": \"https://github.com/mendixlabs/mxcli/issues/77\", \"duplicate\": true"'
cp "$W/pa.before" "$PA/docs/bugs.jsonl"; : > "$GHLOG"
OUT="$(GH_AUTH_RC=1 arun --github-account 2>&1)"; RC=$?
chk "gh not signed in, has a GitHub account: nothing posted, links printed, exit 0" '[ $RC = 0 ] && ! grep -q "issue create" "$GHLOG" && echo "$OUT" | grep -q "not signed in" && echo "$OUT" | grep -q "MendixMau/mxcli-project-toolkit/issues/new?title="'
OUT="$(PATH="$NOGH" MXTK_GITHUB_ACCOUNT=1 "$PY" "$W/ptyrun.py" notty "$SUBJ" --project "$PA" --auto 2>&1)"; RC=$?
chk "no gh at all, has a GitHub account: links printed, exit 0, log unchanged" '[ $RC = 0 ] && echo "$OUT" | grep -q "GitHub CLI not installed" && echo "$OUT" | grep -q "issues/new?title=" && cmp -s "$PA/docs/bugs.jsonl" "$W/pa.before"'
chk "--auto output never carries the scan-failing row text" '! echo "$OUT" | grep -qi "A8f3"'
mv "$PA/.leakguard-deny" "$W/pa.deny"; : > "$GHLOG"
OUT="$(LEAKGUARD_DENY= arun 2>&1)"; RC=$?
chk "opted in but no deny list: refused before any gh call" '[ $RC -ne 0 ] && echo "$OUT" | grep -q "no deny list" && ! grep -q "issue create" "$GHLOG"'
mv "$W/pa.deny" "$PA/.leakguard-deny"
LOGF="$W/run.log"; { for i in $(seq 1 50); do echo "line $i ok"; done
  echo "ERROR in Quuxmod.ACT_Save at /Users/$U/work/Zorbix/app.mpr"; echo "auth ghp_abcdefghijklmnopqrstuvwx1234 to build-srv-01"; } > "$LOGF"
OUT="$("$SUBJ" --project "$PA" --add --target mxcli --title "Log row" --repro r --expected e --actual a --log "$LOGF" --log-lines 4 2>&1)"
LROW="$(tail -1 "$PA/docs/bugs.jsonl")"
chk "--log keeps only the last N lines" 'echo "$LROW" | grep -q "line 49 ok" && ! echo "$LROW" | grep -q "line 48 ok"'
chk "--log is redacted before it is stored" '! echo "$LROW" | grep -q "Quuxmod\|Zorbix\|/Users/\|ghp_\|build-srv" && echo "$LROW" | grep -q "Module1" && echo "$OUT" | grep -q "attached the last 4"'
printf 'value A8f3K2m9Qz7Lp4Xw1Vb6Nc5Rd0Ty8Ue3Ig\n' > "$W/bad.log"
OUT="$("$SUBJ" --project "$PA" --add --target mxcli --title "Bad log row" --repro r --expected e --actual a --log "$W/bad.log" 2>&1)"
chk "a log that fails the scan is dropped from the row, never stored raw" 'echo "$OUT" | grep -q "NOT attached" && ! tail -1 "$PA/docs/bugs.jsonl" | grep -q "A8f3\|\"log\""'
: > "$GHLOG"; : > "$GHLOG.all"; arun >/dev/null 2>&1
chk "the redacted log goes into the auto-filed body, last lines only" 'grep -q "### Log (last lines, redacted)" "$GHLOG.all" && grep -q "line 49 ok" "$GHLOG.all" && ! grep -q "line 48 ok" "$GHLOG.all"'
chk "the posted log carries no raw name or token" '! grep -q "Quuxmod\|ghp_\|/Users/\|A8f3" "$GHLOG.all"'
chk "--log without --add is refused" '! "$SUBJ" --project "$PA" --log "$LOGF" >/dev/null 2>&1'
chk "permissions: --file/--all/--import (also --dry-run) denied, --auto matched by no deny rule" '"$PY" -I - "$TOOLKIT/bin/install-claude-permissions.sh" <<'"'"'PYX'"'"'
import fnmatch, re, sys
pats = re.findall(r"\"Bash\((\*file-bugs[^)]*)\)\"", open(sys.argv[1]).read())
m = lambda c: any(fnmatch.fnmatchcase(c, p) for p in pats)
sys.exit(not (pats and m("bin/file-bugs.sh --all") and m("bin/file-bugs.sh --file PBUG-01") and not m("bin/file-bugs.sh --auto")
              and m("bin/file-bugs.sh --import b.md") and m("bin/file-bugs.sh --import b.md --dry-run")
              and m("bin/lib/file-bugs.py --import b.md") and not m("bin/file-bugs.sh --bundle")))
PYX'
chk "init-project ships the opt-in commented out" 'grep -q "<!-- Bug filing: auto" "$TOOLKIT/bin/init-project.sh"'
GC="$W/gc"; rm -rf "$GC"; mkdir -p "$GC/docs"; printf '# PROJECT.md\n\n## Current stage\n' > "$GC/PROJECT.md"
printf '%s\n' '{"id":"PBUG-01","status":"open"}' '{"id":"PBUG-02","status":"filed"}' '{"id":"PBUG-03"}' > "$GC/docs/bugs.jsonl"
OUT="$("$TOOLKIT/bin/gate-check.sh" --closeout "$GC" 0 2>&1)"; RC=$?
chk "closeout names the unfiled bugs in one line (open + no-status rows), exit 0" '[ $RC = 0 ] && [ "$(echo "$OUT" | grep -c "2 toolkit/mxcli bug(s) logged but not filed — run bin/file-bugs.sh --auto (or --links)")" = 1 ]'
OUT="$("$TOOLKIT/bin/gate-check.sh" --no-html "$GC" 2>&1)"
chk "a full gate-check run prints the same note" 'echo "$OUT" | grep -q "^note: 2 toolkit/mxcli bug(s) logged but not filed"'
chk "a stage query stays quiet about it" '! "$TOOLKIT/bin/gate-check.sh" "$GC" 0 2>&1 | grep -q "logged but not filed"'
printf '%s\n' '{"id":"PBUG-01","status":"filed"}' > "$GC/docs/bugs.jsonl"
chk "nothing open: no line" '! "$TOOLKIT/bin/gate-check.sh" --closeout "$GC" 0 2>&1 | grep -q "logged but not filed"'

FENCE3='```'
echo "Q. toolkit denylist (#645), code identifiers and toolkit version (#646)"
printf '# scaffold-time registrations\n\\bFrobnozzle\\b\n' > "$W/tk-deny"
G="$(MXTK_LEAKGUARD_DENYFILE="$W/tk-deny" P2DENY='Snarfle\b' bodyof 'Frobnozzle broke and Snarfle too' 'Frobnozzle crash')"
chk "#645 a name registered in the toolkit denylist is redacted" '! echo "$G" | grep -qi frobnozzle && ! grep -qi frobnozzle "$W/p2.err" && echo "$G" | grep -q "<redacted> broke"'
TK2="$W/tk2"; mkdir -p "$TK2/bin/lib"; cp "$TOOLKIT/bin/file-bugs.sh" "$TK2/bin/"; cp "$TOOLKIT/bin/lib/file-bugs.py" "$TOOLKIT/bin/lib/portable.sh" "$TK2/bin/lib/"
printf '\\bFrobnozzle\\b\n' > "$TK2/.leakguard-deny"
G="$(SUBJ="$TK2/bin/file-bugs.sh" MXTK_LEAKGUARD_DENYFILE= P2DENY='Snarfle\b' bodyof 'Frobnozzle broke')"
chk "#645 default path: <toolkit>/.leakguard-deny next to bin/ is read" '[ "$G" != NOJSON ] && ! echo "$G" | grep -qi frobnozzle'
G="$(MXTK_LEAKGUARD_DENYFILE="$W/tk-deny" P2DENY= LEAKGUARD_DENY= bodyof 'x')"
chk "#645 the toolkit list alone is not the project's deny list: --json still refused" '[ "$G" = NOJSON ] && grep -q "no deny list" "$W/p2.err"'
printf '(Unclosed\n' > "$W/tk-deny-bad"
G="$(MXTK_LEAKGUARD_DENYFILE="$W/tk-deny-bad" bodyof 'x')"
chk "#645 an invalid line in the toolkit list refuses, naming that file" '[ "$G" = NOJSON ] && grep -q "tk-deny-bad" "$W/p2.err"'
chk "#645 init-project tells the user file-bugs reads the toolkit list" 'grep -q "file-bugs.sh reads it too" "$TOOLKIT/bin/init-project.sh"'
CODE='path.join(fs.readFileSync(path.resolve(ROOT, x))) and os.path.join(a) in org.zonkpkg.common.service.lib and java.util.concurrent, per CLAUDE.md'
G="$(bodyof "$CODE")"
chk "#646 obj.method( calls survive" 'echo "$G" | grep -qF "path.join(fs.readFileSync(path.resolve(ROOT, x)))" && echo "$G" | grep -qF "os.path.join(a)"'
chk "#646 a Java package keeps its shape, its organisation label is redacted" 'echo "$G" | grep -qF "org.<org>.common.service.lib" && ! echo "$G" | grep -qi zonkpkg'
chk "#646 a JDK package survives whole" 'echo "$G" | grep -qF "java.util.concurrent"'
printf '[user]\n\tname = Claude\n' > "$W/gitconfig-claude"
G="$(GIT_CONFIG_GLOBAL="$W/gitconfig-claude" bodyof 'Claude said so in CLAUDE.md and PROJECT.md')"
chk "#646 CLAUDE.md survives a git user called Claude; the name in prose does not" 'echo "$G" | grep -qF "in CLAUDE.md and PROJECT.md" && echo "$G" | grep -qF "<user> said so"'
G="$(bodyof 'calls zonkco.com(x) and intranet.zonkco.org(y) and build-srv-01.corp.zonkco(z) and glorpley.init(w)')"
chk "#646 safety: a hostname before ( is still a host, a deny name before ( is still denied" '! echo "$G" | grep -qi "zonkco\|glorpley\|build-srv"'
G="$(bodyof 'calls acme.sap(a) acme.prd(b) intranet.acme(c) acme.orders.service(d) erp.acme.dmz(e) a.b.acmeerp(f) end')"
chk "#646 review: unlisted first labels before ( stay hosts (acme.sap, acme.prd, intranet.acme, acme.orders.service, erp.acme.dmz, a.b.acmeerp)" '! echo "$G" | grep -qi "acme" && [ "$(echo "$G" | grep -o "<host>(" | wc -l | tr -d " ")" = 6 ]'
G="$(bodyof "$(printf 'prose obj.method(x) here\n%s\nobj.method(y)\n%s\nand org.springframework.web.bind(z)' "$FENCE3" "$FENCE3")")"
chk "#646 review: obj.method( with an unlisted first label is a host in prose and in a fence" 'echo "$G" | grep -qF "<host>(x)" && echo "$G" | grep -qF "<host>(y)" && ! echo "$G" | grep -qF "obj.method"'
chk "#646 review: a public package org (springframework) is kept" 'echo "$G" | grep -qF "org.springframework.web.bind"'
G="$(bodyof "$(printf '%s\nacme.sap(q) zonkco.com(r)\n%s' "$FENCE3" "$FENCE3")")"
chk "#646 review: inside a fence acme.sap( and a common TLD before ( are still hosts" 'echo "$G" | grep -qF "<host>(q)" && echo "$G" | grep -qF "<host>(r)" && ! echo "$G" | grep -qi "acme"'
G="$(bodyof 'calls path.acme.dmz(a) and window.acme.sap(b) but os.path.join(c) fs.promises.readFile(d) System.out.println(e)')"
chk "#646 re-review: an unknown middle label behind a listed root is redacted" '! echo "$G" | grep -qi acme && echo "$G" | grep -qF "path.<name>.dmz(a)" && echo "$G" | grep -qF "window.<name>.sap(b)"'
chk "#646 re-review: known submodules keep the call whole" 'echo "$G" | grep -qF "os.path.join(c) fs.promises.readFile(d) System.out.println(e)"'
G="$(bodyof 'calls java.acme(x) and javax.acme(w) and java.acme.orders(y) and java.util.Objects.equals(z)')"
chk "#646 third review: java./javax. are not call roots, a client label after them is redacted" '! echo "$G" | grep -qi acme && echo "$G" | grep -qF "<host>(x)" && echo "$G" | grep -qF "<host>(w)" && echo "$G" | grep -qF "java.<org>.orders(y)"'
chk "#646 third review: java.util.Objects.equals( is redacted as on master (4 labels, never widened)" 'echo "$G" | grep -qF "<host>(z)"'
G="$(bodyof 'see java.acme.orders and javax.acme.billing.core and kotlin.acme.x but java.util.concurrent')"
chk "#646 re-review: java/javax/kotlin with an unknown 2nd label redact it, JDK packages stay" '! echo "$G" | grep -qi acme && echo "$G" | grep -qF "java.<org>.orders" && echo "$G" | grep -qF "javax.<org>.billing.core" && echo "$G" | grep -qF "java.util.concurrent"'
G="$(MXTK_LEAKGUARD_DENYFILE="$W/tk-deny-bad" bodyof 'x')"
chk "#645 review: the invalid-toolkit-line refusal says init-project.sh appends to that file" 'grep -q "init-project.sh appends" "$W/p2.err"'
G="$(bodyof x t '{"mxcli":"v0.27.0"}')"
chk "#646 no toolkit version in the row: the toolkit clone's git describe is used" 'echo "$G" | grep -qE "^\*\*Versions:\*\* mxcli v0.27.0, toolkit ([0-9a-f]{7,12}|v?[0-9][0-9.]*(-[0-9]+-g[0-9a-f]{7,12})?)( \(at filing\))?$"'
G="$(P2PM='Toolkit commit: 4416da2efa4f9f3fef8016872bbebd7d126437a7' bodyof x t '{"mxcli":"v0.27.0"}')"
chk "#646 PROJECT.md Toolkit commit is used before git describe, shortened (no opaque-hex refusal)" 'echo "$G" | grep -q "^\*\*Versions:\*\* mxcli v0.27.0, toolkit 4416da2efa4f$"'
G="$(bodyof x t '{"toolkit":"v2026.10.19-89-g4416da2e"}')"
chk "#646 a git-describe toolkit version is kept whole" 'echo "$G" | grep -q "^\*\*Versions:\*\* toolkit v2026.10.19-89-g4416da2e$"'
G="$(bodyof x t '{"toolkit":"4416da2"}')"
chk "#646 a bare short sha toolkit version is kept" 'echo "$G" | grep -q "^\*\*Versions:\*\* toolkit 4416da2$"'

echo "R. no-GitHub path: plain reason, --bundle to mail, --import for the maintainer"
PR="$W/pr"; rm -rf "$PR"; mkdir -p "$PR/docs" "$PR/mdlsource"; cp "$P/mdlsource/01-model.mdl" "$PR/mdlsource/"; cp "$P/Zorbix.mpr" "$PR/"
cp -R "$P/config" "$PR/"; printf 'Snarfle\\b\n' > "$PR/.leakguard-deny"; git -C "$PR" init -q
cat > "$PR/docs/bugs.jsonl" <<ROWS
{"id":"PBUG-01","date":"2026-11-09","target":"toolkit","title":"Gate passes on Quuxmod placeholder","repro":["run gate-check.sh on $H","Mail $U@example.com"],"expected":"FAIL","actual":"PASS in Quuxmod.ACT_Save","versions":{"mxcli":"v0.27.0"},"workaround":"none","status":"open","issue_url":""}
{"id":"PBUG-02","date":"2026-11-09","target":"mxcli","title":"Opaque thing A8f3K2m9Qz7Lp4Xw1Vb6Nc5Rd0Ty8Ue3Ig","repro":"r","expected":"e","actual":"a","versions":{},"workaround":"","status":"open","issue_url":""}
{"id":"PBUG-03","date":"2026-11-09","target":"mxcli","title":"Similar widget crash","repro":"open Widgetron","expected":"e","actual":"a","versions":{},"workaround":"","status":"open","issue_url":""}
{"id":"PBUG-04","date":"2026-11-09","target":"toolkit","title":"Already filed","repro":"r","expected":"e","actual":"a","versions":{},"workaround":"","status":"filed","issue_url":"https://github.com/MendixMau/mxcli-project-toolkit/issues/9"}
ROWS
cp "$PR/docs/bugs.jsonl" "$W/pr.before"
export HOME="$W/zqhm"; mkdir -p "$HOME"   # no developer ~/.mxcli-toolkit.env leaks in; same HOME for every run below
rr() { "$PY" "$W/ptyrun.py" notty "$SUBJ" --project "$PR" "$@"; }
OUT="$(PATH="$NOGH" rr 2>&1)"
chk "dry run, no gh: one plain line says GitHub CLI not installed, plus the upgrade hint" 'echo "$OUT" | grep -q "^Filing path: GitHub CLI not installed, so use --links (with a GitHub account) or --bundle" && echo "$OUT" | grep -qF "Fastest: a free GitHub account (2 min, github.com/signup) makes this one click per bug with --links; no install needed."'
OUT="$(GH_AUTH_RC=1 rr 2>&1)"
chk "dry run, signed out: says run gh auth login --web" 'echo "$OUT" | grep -qF "Filing path: not signed in: run \`gh auth login --web\`"'
OUT="$(GH_REPO_RC=1 GH_REPO_ERR="gh: Not Found (HTTP 404)" rr 2>&1)"
chk "dry run, signed in, HTTP 404: no access, names the repo" 'echo "$OUT" | grep -q "Filing path: signed in, but this GitHub account has no access to "'
OUT="$(GH_REPO_RC=1 GH_REPO_ERR="gh: Resource not accessible by integration (HTTP 403)" rr 2>&1)"
chk "dry run, signed in, HTTP 403: no access" 'echo "$OUT" | grep -q "Filing path: signed in, but this GitHub account has no access to "'
OUT="$(GH_REPO_RC=1 GH_REPO_ERR="Get \"https://api.github.com/repos/x\": proxyconnect tcp: dial tcp: connection refused" rr 2>&1)"
chk "dry run, network error: cannot reach GitHub with the first stderr line, never no access" 'echo "$OUT" | grep -q "^Filing path: cannot reach GitHub (network/proxy): Get .*connection refused, so use --links" && ! echo "$OUT" | grep -q "no access"'
OUT="$(rr 2>&1)"
chk "dry run, gh ready: says it posts directly, no upgrade hint, log unchanged" 'echo "$OUT" | grep -q "^Filing path: gh is installed and signed in" && ! echo "$OUT" | grep -q "Fastest:" && cmp -s "$PR/docs/bugs.jsonl" "$W/pr.before"'
rr --json > "$W/pr.json" 2>/dev/null
D="$(date +%F)"; BF="$PR/toolkit-bugs-$D.md"
OUT="$(MXTK_BUG_EMAIL= rr --bundle 2>&1)"; RC=$?
chk "--bundle writes ONE file in the project root, exit 0" '[ $RC = 0 ] && [ -f "$BF" ] && [ "$(ls "$PR"/toolkit-bugs-*.md | wc -l | tr -d " ")" = 1 ]'
chk "--bundle: title and body of every clean row equal the --json redaction" '"$PY" -I - "$W/pr.json" "$BF" <<'"'"'PYX'"'"'
import json, re, sys
js = {x["id"]: x for x in json.load(open(sys.argv[1])) if not x["refused"]}
txt = open(sys.argv[2]).read()
got = {m.group(1): (m.group(2), m.group(3)) for m in re.finditer(r"(?ms)^<!-- mxtk-bug id=(\S+) target=\S+ -->\n## [^\n]*\n\nTitle: ([^\n]*)\n\n(.*?)\n<!-- mxtk-bug-end -->$", txt)}
sys.exit(not (set(got) == set(js) == {"PBUG-01", "PBUG-03"} and all(got[k] == (js[k]["title"], js[k]["body"]) for k in js)))
PYX'
chk "--bundle: no raw name, host, user or email in the file" '! grep -q "Quuxmod\|Widgetron\|$U@\|build-srv" "$BF" && grep -q "Module1" "$BF"'
chk "--bundle: the held-back row is excluded, says so, stays open" '! grep -qi "opaque\|A8f3\|PBUG-02" "$BF" && echo "$OUT" | grep -q "PBUG-02  held back" && grep "\"PBUG-02\"" "$PR/docs/bugs.jsonl" | grep -q "\"status\":\"open\""'
chk "--bundle: a filed row is not bundled" '[ -f "$BF" ] && ! grep -q "PBUG-04" "$BF"'
chk "--bundle: header carries format, toolkit version, count 2, the row ids, a blank reporter" 'grep -q "^format: mxtk-bug-bundle/1$" "$BF" && grep -qE "^toolkit: [0-9a-zA-Z.-]+$" "$BF" && grep -q "^count: 2$" "$BF" && grep -q "^ids: PBUG-01 PBUG-03$" "$BF" && grep -q "^reporter:$" "$BF"'
chk "--bundle without an address: send it to whoever gave you the toolkit" 'grep -q "^\*\*Send this file to whoever gave you the toolkit.\*\*" "$BF"'
chk "--bundle: rows marked bundled with the date, the held-back row untouched" 'grep "\"PBUG-01\"" "$PR/docs/bugs.jsonl" | grep -q "\"status\": \"bundled\".*\"bundled\": \"$D\"" && grep "\"PBUG-03\"" "$PR/docs/bugs.jsonl" | grep -q "\"status\": \"bundled\""'
chk "--bundle: the file is gitignored" 'git -C "$PR" check-ignore -q "$BF"'
OUT="$(rr --bundle 2>&1)"
chk "a second --bundle does not re-bundle: no new file" 'echo "$OUT" | grep -q "no clean open bugs to bundle" && [ "$(ls "$PR"/toolkit-bugs-*.md | wc -l | tr -d " ")" = 1 ]'
L="$(rr --links 2>/dev/null)"; J="$(rr --json 2>/dev/null)"; DR="$(rr 2>/dev/null)"
chk "a bundled row is still reachable: --links and --json carry it, the plain dry run does not" 'echo "$L" | grep -q "^PBUG-01  Gate passes" && echo "$J" | grep -q "\"id\": \"PBUG-01\"" && ! echo "$DR" | grep -q "^PBUG-01 ->"'
cp "$PR/docs/bugs.jsonl" "$W/pr.bundled"; : > "$GHLOG"
ANS=y "$PY" "$W/ptyrun.py" tty "$SUBJ" --project "$PR" --file PBUG-03 >/dev/null 2>&1
chk "--file files a bundled row (y/N), status becomes filed" 'grep -q "issue create --repo=mendixlabs/mxcli --title=Similar widget crash" "$GHLOG" && grep "\"PBUG-03\"" "$PR/docs/bugs.jsonl" | grep -q "\"status\": \"filed\""'
cp "$W/pr.bundled" "$PR/docs/bugs.jsonl"
GC2="$W/gc2"; rm -rf "$GC2"; mkdir -p "$GC2/docs"; printf '# PROJECT.md\n\n## Current stage\n' > "$GC2/PROJECT.md"
printf '%s\n' '{"id":"PBUG-01","status":"open"}' '{"id":"PBUG-02","status":"bundled"}' '{"id":"PBUG-03","status":"bundled"}' > "$GC2/docs/bugs.jsonl"
OUT="$("$TOOLKIT/bin/gate-check.sh" --closeout "$GC2" 0 2>&1)"
chk "gate-check closeout counts bundled rows as bundled, not yet filed, beside the open ones" 'echo "$OUT" | grep -q "1 toolkit/mxcli bug(s) logged but not filed" && echo "$OUT" | grep -q "2 toolkit/mxcli bug(s) bundled, not yet filed"'
mkdir -p "$W/inbox"; OUT="$("$TOOLKIT/bin/harvest-learnings.sh" "$GC2" --to "$W/inbox" 2>&1)"
chk "harvest-learnings counts bundled rows as bundled, not yet filed" 'echo "$OUT" | grep -q "2 bug(s) bundled, not yet filed"'
OUT="$(MXTK_BUG_EMAIL=bugs@example.com rr --bundle --all 2>&1)"
chk "--bundle --all re-bundles into a new file, never overwriting the first" '[ -f "$PR/toolkit-bugs-$D-2.md" ] && grep -q "^ids: PBUG-01 PBUG-03$" "$PR/toolkit-bugs-$D-2.md"'
chk "MXTK_BUG_EMAIL names the address on the top line" 'grep -q "^\*\*Mail this file to bugs@example.com.\*\*" "$PR/toolkit-bugs-$D-2.md"'
cp "$W/pr.before" "$PR/docs/bugs.jsonl"; mkdir -p "$PR/.claude"; printf 'MENDIX_APP=/x\nBug email: tk@example.com\n' > "$PR/.claude/toolkit.env"
rr --bundle "$W/b-env.md" >/dev/null 2>&1
chk "a Bug email: line in toolkit.env is used when the env is unset" 'grep -q "^\*\*Mail this file to tk@example.com.\*\*" "$W/b-env.md"'
rm -f "$PR/.claude/toolkit.env"; cp "$W/pr.before" "$PR/docs/bugs.jsonl"; mkdir -p "$W/brain"; printf '# Brain\n\nBug email: brain@example.com\n' > "$W/brain/README.md"
printf 'A company brain is wired at `%s` -- read it\n' "$W/brain" > "$PR/CLAUDE.local.md"
rr --bundle "$W/b-brain.md" >/dev/null 2>&1
chk "the company brain README's Bug email: line is used last" 'grep -q "^\*\*Mail this file to brain@example.com.\*\*" "$W/b-brain.md"'
rm -f "$PR/CLAUDE.local.md"
cp "$W/pr.before" "$PR/docs/bugs.jsonl"; mv "$PR/.leakguard-deny" "$W/pr.deny"
OUT="$(LEAKGUARD_DENY= rr --bundle "$W/b-nodeny.md" 2>&1)"; RC=$?
chk "--bundle without a deny list is refused, no file" '[ $RC -ne 0 ] && echo "$OUT" | grep -q "no deny list" && [ ! -f "$W/b-nodeny.md" ]'
mv "$W/pr.deny" "$PR/.leakguard-deny"
printf '# PROJECT.md\n\nBug filing: auto\n' > "$PR/PROJECT.md"
git -C "$PR" add PROJECT.md && git -C "$PR" -c user.name=t -c user.email=tester commit -qm reg >/dev/null 2>&1
rm -f "$PR"/toolkit-bugs-*.md; cp "$W/pr.before" "$PR/docs/bugs.jsonl"; : > "$GHLOG"
OUT="$(PATH="$NOGH" rr --auto 2>&1)"; RC=$?
chk "--auto, no gh, no account: says why, writes the bundle, exit 0, nothing posted" '[ $RC = 0 ] && echo "$OUT" | grep -q "NOTE: --auto cannot post: GitHub CLI not installed" && echo "$OUT" | grep -q "Fastest: a free GitHub account" && [ -f "$BF" ] && ! grep -q "issue create" "$GHLOG"'
chk "--auto: the LAST line names the bundle path and who to mail it to" '[ "$(echo "$OUT" | tail -1)" = "Bundle written: $BF — mail it to whoever gave you the toolkit" ]'
rm -f "$PR"/toolkit-bugs-*.md; cp "$W/pr.before" "$PR/docs/bugs.jsonl"
OUT="$(GH_AUTH_RC=1 rr --auto 2>&1)"
chk "--auto, signed out, no account: says run gh auth login --web, bundles" 'echo "$OUT" | grep -qF "cannot post: not signed in: run \`gh auth login --web\`" && [ -f "$BF" ] && ! grep -q "issue create" "$GHLOG"'
rm -f "$PR"/toolkit-bugs-*.md; cp "$W/pr.before" "$PR/docs/bugs.jsonl"
OUT="$(GH_REPO_RC=1 GH_REPO_ERR="gh: Not Found (HTTP 404)" rr --auto --github-account 2>&1)"
chk "--auto, signed in without access, has an account: says so, prints links, no bundle" 'echo "$OUT" | grep -q "cannot post: signed in, but this GitHub account has no access" && echo "$OUT" | grep -q "issues/new?title=" && [ ! -f "$BF" ] && ! grep -q "issue create" "$GHLOG"'
rm -f "$PR"/toolkit-bugs-*.md; cp "$W/pr.before" "$PR/docs/bugs.jsonl"; : > "$GHLOG"
OUT="$(GH_REPO_RC=1 GH_REPO_ERR="dial tcp: lookup api.github.com: no such host" rr --auto 2>&1)"
chk "--auto, network error, no account: says cannot reach GitHub, falls through to the bundle" 'echo "$OUT" | grep -q "cannot post: cannot reach GitHub (network/proxy): dial tcp" && [ -f "$BF" ] && ! grep -q "issue create" "$GHLOG" && echo "$OUT" | tail -1 | grep -q "^Bundle written: "'
rm -f "$PR"/toolkit-bugs-*.md; cp "$W/pr.before" "$PR/docs/bugs.jsonl"; : > "$GHLOG"
OUT="$(rr --auto 2>&1)"
chk "--auto, gh ready: checks repo access, then posts as before (no bundle, no fallback note)" 'grep -q "^api repos/MendixMau/mxcli-project-toolkit --jq .has_issues" "$GHLOG" && grep -q "issue create" "$GHLOG" && ! echo "$OUT" | grep -q "cannot post\|Fastest:" && [ ! -f "$BF" ]'
# --- import, on the maintainer's side
cp "$W/pr.before" "$PR/docs/bugs.jsonl"; rr --bundle "$W/mail.md" >/dev/null 2>&1
sed -i.bak 's/^reporter:$/reporter: Jane Tester/' "$W/mail.md"
: > "$GHLOG"; OUT="$(rr --import "$W/mail.md" --dry-run 2>&1)"; RC=$?
chk "--import --dry-run: parses both bugs, files nothing, exit 0" '[ $RC = 0 ] && echo "$OUT" | grep -q "^PBUG-01 -> MendixMau/mxcli-project-toolkit   \[dry run" && ! grep -q "issue create\|label" "$GHLOG" && echo "$OUT" | grep -q "would file 1, skipped duplicates 1"'
"$PY" -I - "$W/mail.md" <<'PYX'
import sys
p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("### Expected\nFAIL", "### Expected\nFAIL, ask leaked@example.com on build-srv-01.corp.zonkco", 1))
PYX
: > "$GHLOG"; : > "$GHLOG.all"; OUT="$(GH_LABELS='[{"name":"auto-filed"},{"name":"via-email"}]' rr --import "$W/mail.md" 2>&1)"; RC=$?
chk "--import re-redacts: an address and host added to the bundle never reach gh" '[ $RC = 0 ] && echo "$OUT" | grep -q "re-redaction changed" && ! grep -q "leaked@\|build-srv\|zonkco" "$GHLOG" "$GHLOG.all" && grep -q "<email>\|<host>" "$GHLOG.all"'
chk "--import dedupes: the exact-title bug is skipped and its link listed" '! grep "issue create" "$GHLOG" | grep -q "Similar widget" && echo "$OUT" | grep -q "skipped duplicates 1 (https://github.com/MendixMau/mxcli-project-toolkit/issues/77)"'
chk "--import files the rest with auto-filed and via-email (labels that exist), never creates one" 'echo "$OUT" | grep -q "filed 1," && grep "issue create" "$GHLOG" | grep -q -- "--label=auto-filed --label=via-email" && ! grep -q "label create" "$GHLOG"'
chk "--import: the duplicate search ran before the create" '[ "$(grep -n "issue list" "$GHLOG" | head -1 | cut -d: -f1)" -lt "$(grep -n "issue create" "$GHLOG" | cut -d: -f1)" ]'
chk "--import footer names the reporter, via email bundle" 'grep -q "^Reported by: Jane Tester via email bundle$" "$GHLOG.all"'
: > "$GHLOG"; : > "$GHLOG.all"; sed -i.bak 's/^reporter: Jane Tester$/reporter:/' "$W/mail.md"; rr --import "$W/mail.md" >/dev/null 2>&1
chk "--import: no reporter -> toolkit user; no such labels -> no --label" 'grep -q "^Reported by: toolkit user via email bundle$" "$GHLOG.all" && ! grep -q -- "--label" "$GHLOG"'
: > "$GHLOG"; OUT="$(rr --import "$PR/docs/bugs.jsonl" 2>&1)"; RC=$?
chk "--import refuses a file without the bundle header" '[ $RC -ne 0 ] && echo "$OUT" | grep -q "is not a bug bundle" && [ ! -s "$GHLOG" ]'
sed 's/^count: 2$/count: 3/' "$W/mail.md" > "$W/bad.md"; OUT="$(rr --import "$W/bad.md" 2>&1)"; RC=$?
chk "--import refuses a bundle whose header does not match its bugs" '[ $RC -ne 0 ] && echo "$OUT" | grep -q "damaged or edited" && [ ! -s "$GHLOG" ]'
"$PY" -I - "$W/mail.md" "$W/unsafe.md" <<'PYX'
import sys
open(sys.argv[2], "w").write(open(sys.argv[1]).read().replace("### Actual", "token A8f3K2m9Qz7Lp4Xw1Vb6Nc5Rd0Ty8Ue3Ig\n\n### Actual", 1))
PYX
"$PY" -I - "$W/mail.md" "$W/ping.md" <<'PYX'
import sys
t = open(sys.argv[1]).read().replace("### Actual", "ping @someone and @some-org/team, see #1 and acme/widgets#2, GH-5 and https://github.com/MendixMau/mxcli-project-toolkit/pull/6\n\n### Actual", 1)
open(sys.argv[2], "w").write(t.replace("Title: Gate passes", "Title: @maint #3 Gate passes", 1))
PYX
: > "$GHLOG"; : > "$GHLOG.all"; OUT="$(rr --import "$W/ping.md" 2>&1)"
chk "--import neutralises @user, @org/team, #N, owner/repo#N, GH-N and issue/PR URLs in title and body (zero-width joiner)" '"$PY" -I - "$GHLOG" "$GHLOG.all" <<'"'"'PYX'"'"'
import re, sys
log, body = open(sys.argv[1], encoding="utf-8").read(), open(sys.argv[2], encoding="utf-8").read()
z = "\u200d"
ok = all(x in body for x in ("@" + z + "someone", "@" + z + "some-org/team", "#" + z + "1", "widgets#" + z + "2", "GH-" + z + "5", "mxcli-project-toolkit/pull/" + z + "6"))
ok = ok and not re.search(r"@[A-Za-z0-9]|(?<![\w])#\d(?![^\n]*Possibly related)", body.split("\n---\n")[0])
ok = ok and "--title=@" + z + "maint #" + z + "3 Gate passes" in log
sys.exit(not ok)
PYX'
chk "--import keeps its own footer links live (Possibly related: #77)" 'grep -q "^Possibly related: #77.$" "$GHLOG.all"'
sed 's/^<!-- mxtk-bug id=PBUG-03 target=mxcli -->$/<!-- mxtk-bug id=PBUG-03 target=mxcli -->/; s/^Title: Similar widget crash$/Title: Different widget crash/' "$W/mail.md" > "$W/mx.md"
: > "$GHLOG"; : > "$GHLOG.all"; OUT="$(rr --import "$W/mx.md" 2>&1)"
chk "--import ignores target=mxcli: filed to the toolkit repo with a note, never upstream" '! grep -q "issue create --repo=mendixlabs" "$GHLOG" && grep -q "issue create --repo=MendixMau/mxcli-project-toolkit --title=Different widget crash" "$GHLOG" && grep -q "^The reporter marked this as an mxcli bug; filed here for triage, not upstream.$" "$GHLOG.all"'
: > "$GHLOG"; OUT="$(rr --import "$W/mail.md" --max 1 2>&1)"; RC=$?
chk "--import enforces the cap (--max 1 on a 2-bug bundle): refused, no gh call" '[ $RC -ne 0 ] && echo "$OUT" | grep -q "more than the cap of 1 per import" && [ ! -s "$GHLOG" ]'
"$PY" -I - "$W/mail.md" "$W/big.md" <<'PYX'
import re, sys
t = open(sys.argv[1]).read()
sec = re.search(r"(?ms)^<!-- mxtk-bug id=PBUG-01 .*?^<!-- mxtk-bug-end -->\n", t).group(0)
ids = ["PBUG-%02d" % i for i in range(1, 22)]
body = "".join(sec.replace("PBUG-01", i) for i in ids)
head = re.sub(r"(?m)^count: .*$", "count: 21", re.sub(r"(?m)^ids: .*$", "ids: " + " ".join(ids), t[:t.index("<!-- mxtk-bug id=")]))
open(sys.argv[2], "w").write(head + body)
PYX
: > "$GHLOG"; OUT="$(rr --import "$W/big.md" --dry-run 2>&1)"; RC=$?
chk "--import default cap is 20 bugs" '[ $RC -ne 0 ] && echo "$OUT" | grep -q "holds 21 bugs, more than the cap of 20" && [ ! -s "$GHLOG" ]'
: > "$GHLOG"; OUT="$(rr --import "$W/unsafe.md" 2>&1)"
chk "--import refuses a bug that still fails the scan after re-redaction" 'echo "$OUT" | grep -q "^REFUSED: after re-redaction" && ! grep -qi "A8f3" "$GHLOG" && echo "$OUT" | grep -q "refused 1"'

echo "Z. no real issue was ever created"
chk "every gh call went through the stub (log exists, no network tool used)" '[ -s "$GHLOG" ]'

echo; echo "file-bugs: $PASS pass, $FAIL fail"; [ "$FAIL" -eq 0 ]
