#!/usr/bin/env bash
# demo-login-tiles.sh -- demo sign-in tiles on the app's sign-in page, on localhost only (#736).
#
#   ./bin/demo-login-tiles.sh                  read the demo users, patch the sign-in page, write the data file
#   ./bin/demo-login-tiles.sh --remove         (alias --no-demo) empty the block, delete the data file:
#                                              the step BEFORE an app leaves the machine
#   ./bin/demo-login-tiles.sh --check          0 = safe (no tiles, or data file ignored and untracked)
#   options: --host <name>                     one extra host that shows tiles (phone demo through a tunnel)
#            --crew <port>=<user1,user2,...>   repeatable: that port shows only these users
#            --model-users <file>              a saved `show demo users` table instead of asking mxcli
#
# WHAT IT DOES. Reads `create demo user` / `drop demo user` statements from mdlsource/ (recursive, files in
# path order, later statement for the same user wins) and writes
#   theme/web/demo-login.local.js   the user list WITH passwords; added to .gitignore; never committed
#   theme/web/login.html            only an empty container and a loader between the markers
#                                   <!-- DEMO-LOGIN-BEGIN --> ... <!-- DEMO-LOGIN-END -->
# Markers absent: they are added after the sign-in form's closing tag. Everything outside them is never
# touched, so any branded page works; a second run changes nothing. The loader does NOTHING on a host that
# is not localhost / 127.0.0.1 / [::1] / --host (it does not even request the data file), and fails silently
# when the data file is missing (a build from a clean clone). The tile sets usernameInput + passwordInput
# and clicks loginButton: Mendix's own login.js does the sign-in. The page holds NO name or password.
# Crew: with no --crew / .claude/loop/demo-crew.tsv (lines: port<TAB>user1,user2) every port shows every
# user; with a crew, a port that is listed shows only its users, a port that is not listed shows all.
# The data file is plain JavaScript in the deployed web folder: run --remove before the app leaves the machine.
#
# The model is asked (`show demo users`) only to WARN when scripts and model disagree. A password is never
# printed: output lists names and roles only.
#
# Exit codes: 0 done, or nothing to do · 1 --check failed (a password-bearing file would be committed, or
# the page block holds credentials) · 2 usage · 3 could not run (no sign-in page, a required id missing,
# no demo users found, data file already tracked by git): nothing was changed.
# Layouts: <root>/theme/web and <root>/app/theme/web (model under app/) -- the page is looked up beside the
# .mpr first, then under the project root. Bash 3.2 / Git Bash safe (no sed -i, no mapfile).
# Producer: none by design -- run by hand or from the build steps (skills/poc-build.md); nothing calls it
# automatically yet. Golden input: tests/wave2/fixtures/demo-login-tiles/ (verbatim page + statements).
set -uo pipefail
_sd="${0%/*}"; [ "$_sd" != "$0" ] || _sd=.
. "$_sd/_common.sh"

MODE=patch; EXTRA_HOST=""; MODEL_USERS=""; CREW_ARGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --remove|--no-demo) MODE=remove; shift ;;
    --check) MODE=check; shift ;;
    --host) EXTRA_HOST="${2:-}"; shift 2 || { echo "usage: --host needs a name" >&2; exit 2; } ;;
    --crew) [ -n "${2:-}" ] || { echo "usage: --crew <port>=<user1,user2,...>" >&2; exit 2; }
            CREW_ARGS="$CREW_ARGS
$2"; shift 2 ;;
    --model-users) MODEL_USERS="${2:-}"; shift 2 || exit 2 ;;
    -h|--help) sed -n 2,34p "$0"; exit 0 ;;
    *) echo "usage: demo-login-tiles.sh [--remove|--check] [--host <name>] [--crew <port>=<users>]..." >&2; exit 2 ;;
  esac
done
case "$EXTRA_HOST" in
  *[!A-Za-z0-9.:_\[\]-]*) echo "usage: --host '$EXTRA_HOST' is not a plain host name" >&2; exit 2 ;;
esac

BEGIN_M='<!-- DEMO-LOGIN-BEGIN -->'; END_M='<!-- DEMO-LOGIN-END -->'
MPR="$(find_mpr 2>/dev/null || true)"
if [ -n "$MPR" ]; then APPDIR="${MPR%/*}"; else APPDIR="$PROJECT_ROOT"; fi

PAGE=""
for d in "$APPDIR" "$PROJECT_ROOT"; do [ -f "$d/theme/web/login.html" ] && { PAGE="$d/theme/web/login.html"; break; }; done
if [ -n "$PAGE" ]; then DATA="${PAGE%/*}/demo-login.local.js"; else DATA="$APPDIR/theme/web/demo-login.local.js"; fi
REL="${DATA#"$PROJECT_ROOT"/}"
GITIGNORE="$PROJECT_ROOT/.gitignore"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/demo-tiles.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
cant() { echo "demo-login-tiles: $* -- nothing was changed." >&2; exit 3; }

is_tracked() { [ -n "$(git -C "$PROJECT_ROOT" ls-files -- "$REL" 2>/dev/null)" ]; }
is_ignored() {
  if git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then git -C "$PROJECT_ROOT" check-ignore -q -- "$REL" 2>/dev/null
  else [ -f "$GITIGNORE" ] && grep -Fxq "/$REL" "$GITIGNORE"; fi
}

# --- locate the block: prints "begin end" line numbers, rc 0 found, 1 absent, 2 malformed -----------
find_block() {
  awk -v b="DEMO-LOGIN-BEGIN" -v e="DEMO-LOGIN-END" '
    index($0,"<!-- " b " -->"){nb++; bl=NR}
    index($0,"<!-- " e " -->"){ne++; el=NR}
    END{ if(nb==0&&ne==0) exit 1; if(nb!=1||ne!=1||el<bl) exit 2; print bl, el }' "$1"
}

# --- --check ----------------------------------------------------------------------------------------
if [ "$MODE" = check ]; then
  bad=0; present=0
  if [ -f "$DATA" ]; then
    present=1
    if is_tracked; then echo "CHECK FAIL: $REL is tracked by git (it holds passwords): git rm --cached it"; bad=1
    elif ! is_ignored; then echo "CHECK FAIL: $REL exists and is not git-ignored (it holds passwords): run bin/demo-login-tiles.sh to add it to .gitignore"; bad=1; fi
  fi
  if [ -n "$PAGE" ] && blk="$(find_block "$PAGE")"; then
    set -- $blk
    [ "$(( $2 - $1 ))" -gt 1 ] && present=1
    if sed -n "$(($1+1)),$(($2-1))p" "$PAGE" | grep -Eq '__DEMO_LOGIN__[[:space:]]*=[[:space:]]*[{[]|"p"[[:space:]]*:[[:space:]]*"'; then
      echo "CHECK FAIL: the block in ${PAGE#"$PROJECT_ROOT"/} contains credentials"; bad=1
    fi
  fi
  if [ "$bad" -eq 0 ]; then
    [ "$present" -eq 1 ] && echo "demo-login-tiles --check: tiles present; data file is git-ignored and not tracked" || echo "demo-login-tiles --check: no tiles"
    exit 0
  fi
  exit 1
fi

# --- build the replacement block text (needs no users, so --remove shares the splice) -----------------
splice() {  # splice <page> <blockfile|-> : replace the interior between the markers; writes to $TMP/page.new
  local page="$1" blockfile="$2" line cr="" nonl=0 inside=0 indent="" first=1 seen_b=0
  : > "$TMP/page.new"
  # CRLF page: inserted lines get a CR too
  [ "$(head -c 4096 "$page" | tr -cd '\r' | wc -c | tr -d ' ')" -gt 0 ] && cr=$'\r'
  while :; do
    if IFS= read -r line; then nonl=0; else [ -n "$line" ] || break; nonl=1; fi
    if [ "$inside" -eq 0 ]; then
      case "$line" in
        *"$BEGIN_M"*)
          indent="${line%%[![:space:]]*}"
          printf '%s\n' "$line" >> "$TMP/page.new"; inside=1
          if [ "$blockfile" != "-" ]; then
            while IFS= read -r b || [ -n "$b" ]; do
              if [ -n "$b" ]; then printf '%s%s%s\n' "$indent" "$b" "$cr"; else printf '%s\n' "$cr"; fi
            done < "$blockfile" >> "$TMP/page.new"
          fi ;;
        *) if [ "$nonl" -eq 1 ]; then printf '%s' "$line" >> "$TMP/page.new"; else printf '%s\n' "$line" >> "$TMP/page.new"; fi ;;
      esac
    else
      case "$line" in *"$END_M"*) inside=0; if [ "$nonl" -eq 1 ]; then printf '%s' "$line" >> "$TMP/page.new"; else printf '%s\n' "$line" >> "$TMP/page.new"; fi ;; esac
    fi
    [ "$nonl" -eq 1 ] && break
  done < "$page"
}
# insert fresh markers + block after the first </form> line
insert_after_form() {  # insert_after_form <page> <blockfile>
  local page="$1" blockfile="$2" line nonl=0 done_=0 cr="" indent=""
  : > "$TMP/page.new"
  [ "$(head -c 4096 "$page" | tr -cd '\r' | wc -c | tr -d ' ')" -gt 0 ] && cr=$'\r'
  while :; do
    if IFS= read -r line; then nonl=0; else [ -n "$line" ] || break; nonl=1; fi
    if [ "$nonl" -eq 1 ]; then printf '%s' "$line" >> "$TMP/page.new"; else printf '%s\n' "$line" >> "$TMP/page.new"; fi
    if [ "$done_" -eq 0 ]; then case "$line" in *"</form>"*)
      done_=1; indent="${line%%[![:space:]]*}"
      [ "$nonl" -eq 1 ] && printf '\n' >> "$TMP/page.new"
      { printf '%s%s%s\n' "$indent" "$BEGIN_M" "$cr"
        while IFS= read -r b || [ -n "$b" ]; do
          if [ -n "$b" ]; then printf '%s%s%s\n' "$indent" "$b" "$cr"; else printf '%s\n' "$cr"; fi
        done < "$blockfile"
        printf '%s%s%s' "$indent" "$END_M" "$cr"; } >> "$TMP/page.new"
      [ "$nonl" -eq 0 ] && printf '\n' >> "$TMP/page.new"
      ;; esac; fi
    [ "$nonl" -eq 1 ] && break
  done < "$page"
}
install_page() {  # keep the original when nothing changed (mtime, bytes)
  if cmp -s "$TMP/page.new" "$PAGE"; then return 1; fi
  cp "$TMP/page.new" "$PAGE"; return 0
}

# --- --remove -----------------------------------------------------------------------------------------
if [ "$MODE" = remove ]; then
  changed=0
  if [ -f "$DATA" ]; then rm -f "$DATA"; echo "removed $REL"; changed=1; fi
  # a build copies theme/web into deployment/web: the passwords must not stay behind in that copy
  for dd in "$APPDIR/deployment/web/demo-login.local.js" "$PROJECT_ROOT/deployment/web/demo-login.local.js"; do
    [ -f "$dd" ] && { rm -f "$dd"; echo "removed ${dd#"$PROJECT_ROOT"/}"; changed=1; }
  done
  if [ -n "$PAGE" ] && blk="$(find_block "$PAGE")"; then
    set -- $blk
    if [ "$(( $2 - $1 ))" -gt 1 ]; then
      splice "$PAGE" -
      install_page && { echo "emptied the demo block in ${PAGE#"$PROJECT_ROOT"/} (markers kept)"; changed=1; }
    fi
  fi
  [ "$changed" -eq 1 ] && echo "demo sign-in tiles removed. Rebuild/redeploy so deployment/web drops the copy too." || echo "demo-login-tiles --remove: nothing to remove"
  exit 0
fi

# --- patch: preconditions ------------------------------------------------------------------------------
[ -n "$PAGE" ] || cant "no sign-in page (looked for theme/web/login.html beside the .mpr and under $PROJECT_ROOT)"
for id in loginForm usernameInput passwordInput loginButton loginMessage; do
  grep -Eq "id=[\"']$id[\"']" "$PAGE" || cant "${PAGE#"$PROJECT_ROOT"/} has no element with id=\"$id\" (Mendix login.js needs loginForm, usernameInput, passwordInput, loginButton, loginMessage)"
done
bstate=0; find_block "$PAGE" >/dev/null || bstate=$?
[ "$bstate" -ne 2 ] || cant "${PAGE#"$PROJECT_ROOT"/} has a broken marker pair (need exactly one $BEGIN_M before one $END_M)"
if [ "$bstate" -eq 1 ]; then grep -q '</form>' "$PAGE" || cant "no markers and no </form> to place them after"; fi
if is_tracked; then cant "$REL is already tracked by git and would put passwords in history. Run: git rm --cached $REL  (then re-run)"; fi

# --- the demo users --------------------------------------------------------------------------------------
: > "$TMP/files"
for d in "$PROJECT_ROOT/mdlsource" "$APPDIR/mdlsource"; do
  [ -d "$d" ] && find "$d" -type f -name '*.mdl' 2>/dev/null
done | LC_ALL=C sort -u > "$TMP/files"
[ -s "$TMP/files" ] || cant "no *.mdl files under mdlsource/"
set --; while IFS= read -r f; do set -- "$@" "$f"; done < "$TMP/files"
awk -v sq="'" -v dq='"' -f /dev/stdin "$@" > "$TMP/users.raw" <<'AWK'
function qstr(s, i,   q, v, c) {
  q = substr(s, i, 1); v = ""
  for (i = i + 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == q) { if (substr(s, i + 1, 1) == q) { v = v q; i++; continue } QEND = i; return v }
    v = v c
  }
  QEND = i; return v
}
function stmt(s,   t, low, rest, n, i, c, nt, k, name, pw, roles, d, j, haspw) {
  t = s; gsub(/[ \t\r]+/, " ", t); sub(/^ /, "", t); low = tolower(t)
  if (match(low, /^create (or modify )?demo user /)) d = "C"
  else if (match(low, /^drop demo user (if exists )?/)) d = "D"
  else return
  rest = substr(t, RLENGTH + 1)
  nt = 0; n = length(rest); i = 1
  while (i <= n) {
    c = substr(rest, i, 1)
    if (c == " ") { i++; continue }
    if (c == sq || c == dq) { nt++; TT[nt] = "S"; TV[nt] = qstr(rest, i); i = QEND + 1; continue }
    if (c ~ /[(),:;]/) { nt++; TT[nt] = "P"; TV[nt] = c; i++; continue }
    k = i; while (k <= n && substr(rest, k, 1) !~ /[ (),:;'"]/) k++
    nt++; TT[nt] = "W"; TV[nt] = substr(rest, i, k - i); i = k
  }
  if (nt < 1 || TT[1] != "S") return
  name = TV[1]
  if (d == "D") { ALIVE[name] = 0; return }
  pw = ""; haspw = 0
  for (j = 2; j <= nt; j++) if (TT[j] == "W" && tolower(TV[j]) == "password") {
    k = j + 1; if (TV[k] == ":" && TT[k] == "P") k++
    if (TT[k] == "S") { pw = TV[k]; haspw = 1 }
    break
  }
  roles = ""; k = 0
  for (j = 2; j <= nt; j++) if (TT[j] == "W" && tolower(TV[j]) == "userroles") { k = j; break }
  if (k == 0) { for (j = nt; j >= 2; j--) if (TT[j] == "P" && TV[j] == "(") { k = j - 1; break } }
  if (k > 0) {
    j = k + 1; if (TV[j] == ":" && TT[j] == "P") j++
    if (TV[j] == "(" && TT[j] == "P") {
      for (j = j + 1; j <= nt && !(TT[j] == "P" && TV[j] == ")"); j++)
        if (TT[j] != "P") roles = roles (roles == "" ? "" : ",") TV[j]
    }
  }
  if (!haspw) { print "W\t" name; return }
  if (!(name in SEEN) || ALIVE[name] == 0) { ORD[++no] = name }   # (re)created after a drop: new position
  SEEN[name] = 1; ALIVE[name] = 1; PW[name] = pw; RL[name] = roles
}
FNR == 1 { buf = ""; inq = ""; inb = 0 }
{
  line = $0; n = length(line)
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1); two = substr(line, i, 2)
    if (inb) { if (two == "*/") { inb = 0; i++ } continue }
    if (inq != "") {
      buf = buf c
      if (c == inq) { if (substr(line, i + 1, 1) == inq) { buf = buf inq; i++ } else inq = "" }
      continue
    }
    if (two == "--" || two == "//") break
    if (two == "/*") { inb = 1; i++; continue }
    if (c == sq || c == dq) { inq = c; buf = buf c; continue }
    if (c == ";") { stmt(buf); buf = ""; continue }
    buf = buf c
  }
  buf = buf " "
}
END { for (i = 1; i <= no; i++) { nm = ORD[i]; if (ALIVE[nm] == 1 && !(nm in PRINTED)) { PRINTED[nm] = 1; print "U\t" nm "\t" PW[nm] "\t" RL[nm] } } }
AWK
grep '^W	' "$TMP/users.raw" | while IFS="$(printf '\t')" read -r _ nm; do echo "WARN: demo user '$nm' has no parseable password in the scripts; skipped" >&2; done
grep '^U	' "$TMP/users.raw" > "$TMP/users.tsv" || : > "$TMP/users.tsv"
NUSERS="$(wc -l < "$TMP/users.tsv" | tr -d ' ')"
[ "$NUSERS" -gt 0 ] || cant "no demo users found in the $(wc -l < "$TMP/files" | tr -d ' ') *.mdl file(s) under mdlsource/ (create demo user '<name>' (Password: '<pw>', UserRoles: (<Role>)); )"
echo "$NUSERS demo users found:"
TAB="$(printf '\t')"
while IFS="$TAB" read -r _ nm _ rl; do printf '  %s  (%s)\n' "$nm" "${rl:-no role}"; done < "$TMP/users.tsv"

# --- model comparison (warn only) -------------------------------------------------------------------------
MU="$TMP/model-users.txt"; have_model=0
if [ -n "$MODEL_USERS" ]; then [ -r "$MODEL_USERS" ] && cp "$MODEL_USERS" "$MU" && have_model=1
elif [ -n "$MPR" ]; then
  MXCLI="$(find_project_mxcli 2>/dev/null || true)"
  if [ -n "$MXCLI" ] && "$MXCLI" -p "$MPR" -c "show demo users" > "$MU" 2>/dev/null; then have_model=1; fi
fi
if [ "$have_model" -eq 1 ]; then
  grep -E '^[[:space:]]*\|' "$MU" | tr -d '\r' | sed 's/^[[:space:]]*|//; s/|[[:space:]]*$//' | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}' | grep -v -E '^(User Name|-+)$' | LC_ALL=C sort -u > "$TMP/model.names"
  cut -f2 "$TMP/users.tsv" | LC_ALL=C sort -u > "$TMP/script.names"
  comm -23 "$TMP/script.names" "$TMP/model.names" | while IFS= read -r n; do echo "WARN: '$n' is in the scripts but not in the model (scripts not applied yet?); its tile would fail"; done
  comm -13 "$TMP/script.names" "$TMP/model.names" | while IFS= read -r n; do echo "WARN: '$n' is in the model but in no script; no tile for it"; done
else
  echo "note: model not compared (no mxcli / .mpr / table)"
fi

# --- crew -------------------------------------------------------------------------------------------------
CREWFILE="$PROJECT_ROOT/.claude/loop/demo-crew.tsv"
{ [ -f "$CREWFILE" ] && tr -d '\r' < "$CREWFILE" | grep -v '^[[:space:]]*\(#\|$\)'
  printf '%s\n' "$CREW_ARGS" | grep -v '^$'; } 2>/dev/null | sed 's/[[:space:]=][[:space:]=]*/ /; s/[[:space:]]*,[[:space:]]*/,/g' > "$TMP/crew.txt"
: > "$TMP/crew.json"
while read -r port users; do
  case "$port" in ''|*[!0-9]*) echo "usage: crew port '$port' is not a number" >&2; exit 2 ;; esac
  [ -n "$users" ] || { echo "usage: crew for port $port lists no users" >&2; exit 2; }
  echo "$users" | tr ',' '\n' | while IFS= read -r cu; do
    cut -f2 "$TMP/users.tsv" | grep -Fxq -- "$cu" || echo "WARN: crew for port $port names '$cu', who is in no script"
  done
  printf '%s\t%s\n' "$port" "$users"
done < "$TMP/crew.txt" > "$TMP/crew.last"
# later line for the same port wins
awk -F'\t' '{c[$1]=$2; if(!($1 in o)){o[$1]=++n; k[n]=$1}} END{for(i=1;i<=n;i++) print k[i] "\t" c[k[i]]}' "$TMP/crew.last" > "$TMP/crew.tsv"

jsesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/</\\u003c/g'; }
# --- the data file ------------------------------------------------------------------------------------------
{
  echo '// Generated by bin/demo-login-tiles.sh. Local demo sign-in data: CONTAINS PASSWORDS. Git-ignored. Never commit or deploy; bin/demo-login-tiles.sh --remove deletes it.'
  echo 'window.__DEMO_LOGIN__ = {'
  echo ' "users": ['
  n=0
  while IFS="$TAB" read -r _ nm pw rl; do
    n=$((n+1)); roles=""
    if [ -n "$rl" ]; then
      OLDIFS="$IFS"; IFS=','; for r in $rl; do roles="$roles${roles:+,}\"$(jsesc "$r")\""; done; IFS="$OLDIFS"
    fi
    sep=","; [ "$n" -eq "$NUSERS" ] && sep=""
    printf '  {"u":"%s","p":"%s","r":[%s]}%s\n' "$(jsesc "$nm")" "$(jsesc "$pw")" "$roles" "$sep"
  done < "$TMP/users.tsv"
  echo ' ],'
  printf ' "crew": {'
  n=0; total="$(wc -l < "$TMP/crew.tsv" | tr -d ' ')"
  while IFS="$TAB" read -r port users; do
    n=$((n+1)); list=""
    OLDIFS="$IFS"; IFS=','; for u in $users; do list="$list${list:+,}\"$(jsesc "$u")\""; done; IFS="$OLDIFS"
    sep=","; [ "$n" -eq "$total" ] && sep=""
    printf '"%s":[%s]%s' "$port" "$list" "$sep"
  done < "$TMP/crew.tsv"
  echo '}'
  echo '};'
} > "$TMP/data.js"

# --- the block --------------------------------------------------------------------------------------------------
if [ -n "$EXTRA_HOST" ]; then HOSTS="[\"$EXTRA_HOST\"]"; else HOSTS='[]'; fi
cat > "$TMP/block.tpl" <<'BLOCK'
<!-- Generated by bin/demo-login-tiles.sh (#736). Holds no names or passwords: they live in the git-ignored demo-login.local.js. Local hosts only. Run bin/demo-login-tiles.sh --remove before the app leaves the machine. -->
<style>
  .demo-login { margin-top: 1.5rem; padding-top: 1rem; border-top: 1px solid rgba(128, 128, 128, 0.4); font: inherit; color: inherit; }
  .demo-login[hidden] { display: none; }
  .demo-login-title { font-size: 0.8em; opacity: 0.7; margin-bottom: 0.5rem; }
  .demo-login-tiles { display: flex; flex-wrap: wrap; gap: 0.5rem; }
  .demo-login-tile { font: inherit; color: inherit; background: transparent; border: 1px solid currentColor; border-radius: 6px; padding: 0.4rem 0.7rem; text-align: left; cursor: pointer; opacity: 0.85; min-width: 0; max-width: 100%; overflow-wrap: anywhere; }
  .demo-login-tile:hover { opacity: 1; }
  .demo-login-tile:focus-visible { outline: 2px solid currentColor; outline-offset: 2px; opacity: 1; }
  .demo-login-name { display: block; }
  .demo-login-role { display: block; font-size: 0.75em; opacity: 0.7; }
</style>
<div id="demoLogin" class="demo-login" hidden></div>
<script>
(function () {
  var extra = __EXTRA_HOSTS__;
  var local = ["localhost", "127.0.0.1", "[::1]"].concat(extra);
  if (local.indexOf(location.hostname) < 0) { return; }
  var box = document.getElementById("demoLogin");
  if (!box) { return; }
  function setValue(el, v) { el.value = v; el.dispatchEvent(new Event("input", { bubbles: true })); }
  function show(cfg) {
    if (!cfg || !cfg.users || !cfg.users.length) { return; }
    var port = location.port || (location.protocol === "https:" ? "443" : "80");
    var crew = cfg.crew && cfg.crew[port];
    var list = document.createElement("div");
    list.className = "demo-login-tiles";
    var n = 0;
    cfg.users.forEach(function (x) {
      if (crew && crew.indexOf(x.u) < 0) { return; }
      var b = document.createElement("button");
      b.type = "button";
      b.className = "demo-login-tile";
      var name = document.createElement("span");
      name.className = "demo-login-name";
      name.textContent = x.u;
      var role = document.createElement("span");
      role.className = "demo-login-role";
      role.textContent = (x.r || []).join(", ");
      b.appendChild(name);
      b.appendChild(role);
      b.addEventListener("click", function () {
        var u = document.getElementById("usernameInput");
        var p = document.getElementById("passwordInput");
        var go = document.getElementById("loginButton");
        if (!u || !p || !go) { return; }
        setValue(u, x.u);
        setValue(p, x.p);
        go.click();
      });
      list.appendChild(b);
      n++;
    });
    if (!n) { return; }
    var title = document.createElement("div");
    title.className = "demo-login-title";
    title.textContent = "Demo sign-in (local only)";
    box.appendChild(title);
    box.appendChild(list);
    box.hidden = false;
  }
  var s = document.createElement("script");
  s.src = "demo-login.local.js";
  s.onload = function () {
    var cfg = window.__DEMO_LOGIN__;
    try { delete window.__DEMO_LOGIN__; } catch (e) { window.__DEMO_LOGIN__ = undefined; }
    show(cfg);
  };
  s.onerror = function () {};
  document.head.appendChild(s);
})();
</script>
BLOCK
tpl="$(cat "$TMP/block.tpl")"; printf '%s\n' "${tpl/__EXTRA_HOSTS__/$HOSTS}" > "$TMP/block.html"

# --- write: .gitignore, data file, page -----------------------------------------------------------------------
if [ -f "$GITIGNORE" ] && grep -Fxq "/$REL" "$GITIGNORE"; then :; else
  { [ -s "$GITIGNORE" ] && [ -n "$(tail -c1 "$GITIGNORE")" ] && printf '\n'
    printf '# demo-login-tiles.sh: local demo sign-in data (holds passwords)\n/%s\n' "$REL"; } >> "$GITIGNORE"
  echo "added /$REL to .gitignore"
fi
if [ -f "$DATA" ] && cmp -s "$TMP/data.js" "$DATA"; then echo "$REL unchanged"; else cp "$TMP/data.js" "$DATA"; echo "wrote $REL"; fi
if [ "$bstate" -eq 0 ]; then
  splice "$PAGE" "$TMP/block.html"; where="between the existing markers"
else
  insert_after_form "$PAGE" "$TMP/block.html"; where="new markers after the sign-in form's closing </form>"
fi
if install_page; then echo "patched ${PAGE#"$PROJECT_ROOT"/} ($where)"; else echo "${PAGE#"$PROJECT_ROOT"/} unchanged"; fi
echo "a running app serves the old page until it is rebuilt/restarted"
if [ -n "$EXTRA_HOST" ]; then echo "tiles also show on host $EXTRA_HOST"; fi
exit 0
