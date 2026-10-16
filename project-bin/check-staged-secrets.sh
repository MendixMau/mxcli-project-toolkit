#!/usr/bin/env bash
# check-staged-secrets.sh — fail when a secret VALUE from this project's own secret-bearing files
# is about to be committed (staged blobs) or is already in the tracked tree. Prints the file and
# the NAME of the key that matched. It never prints a value.
#
# WHY THIS EXISTS (field run, five apps, mxcli v0.26.0). A demo password reached git through a
# rendered login page, and several lane transcripts through `.mxcli/run-local.json`, whose
# bootConfig holds database and API passwords in clear. `.gitignore` does not help once a file is
# tracked, and `git commit -- <path>` re-adds an ignored tracked file at commit time. The one
# check that sees what git will actually store is a scan of the blobs, against the real values.
#
# Where the values come from (read here, never echoed):
#   .env  .env.*               at the project root and in .docker/, docker/, .devcontainer/ (the
#                              `mxcli docker` layout keeps M2EE_ADMIN_PASS and DB_PASSWORD in
#                              .docker/.env). KEY=VALUE where KEY looks like PASSWORD / SECRET /
#                              TOKEN / KEY / PAT. CRLF, `KEY = value`, quotes and an unquoted
#                              trailing ` # comment` are normalised.
#   .mxcli/run-local.json      every string in bootConfig whose key looks like one of those
#                              Exception: a bootConfig.MicroflowConstants value that is already in
#                              the committed model (HEAD, *.mpr or mprcontents/). `run --local` writes
#                              EVERY constant's model default there, so a placeholder default such as
#                              `your-api-key-here` is the model's own text, not a leak, and unstaging
#                              cannot fix it. A real credential in a model default is already
#                              committed: that is bin/constants-audit.sh's job, not this script's. A
#                              constant passed with a value that is NOT in the model is still a source.
#   $MXTK_SECRET_VALUES_FILE   optional: one literal value per line (name shown as "extra");
#                              the filters below do NOT apply, you named it a secret
# What is NOT treated as a secret, and why (this is a leak detector, not a password-strength
# check; a weak demo password is not protected by it):
#   - values under 8 characters: too short to scan for without matching ordinary text;
#   - well-known development defaults (mendix, password, admin, postgres, changeme, ...): every
#     mxcli project carries `mendix` as the database password, so it sits in thousands of tracked
#     files (model blobs, java sources, docs) and would fail every commit. A check that is red on
#     every commit gets switched off, which is worse than not guarding a published default;
#   - a value equal to the same key's value in a sibling .env.example/.sample/.template file:
#     that value is already published on purpose.
# Example files are never sources.
#
# Speed: one `git grep -l -F -f <600 temp file>` per value, over the staged paths (--cached) or
# HEAD, instead of a process per file per value. The value goes through a mode 600 file, never
# argv, so `ps` cannot show it.
#
# Usage:
#   bin/check-staged-secrets.sh            # staged blobs (what the next commit stores)
#   bin/check-staged-secrets.sh --tree     # every tracked file at HEAD (the "already pushed?" check)
# Hook it yourself (it is NOT wired into the generated pre-commit):
#   "$(git rev-parse --show-toplevel)/bin/check-staged-secrets.sh" || exit 1
#
# Exit: 0 clean (or no sources found) · 1 a secret value is in the scanned blobs · 2 not a git repo
set -u
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$PROJECT_ROOT" || { echo "check-staged-secrets: cannot cd to $PROJECT_ROOT" >&2; exit 2; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "check-staged-secrets: not a git repository" >&2; exit 2; }
MODE=staged; [ "${1:-}" = "--tree" ] && MODE=tree
PY="$(command -v python3 || command -v python || true)"

NAMEPAT='(PASS|SECRET|TOKEN|KEY|PAT$|CREDENTIAL)'
MINLEN=8
# Well-known development defaults, lowercase. Compared case-insensitively.
DEFAULTS=" mendix password passw0rd admin administrator postgres postgresql changeme change-me change_me secret root test testing demo example default "
SRC="$(mktemp "${TMPDIR:-/tmp}/mxtk-secrets.XXXXXX")"
VF="$(mktemp "${TMPDIR:-/tmp}/mxtk-secval.XXXXXX")"
trap 'rm -f "$SRC" "$VF"' EXIT
chmod 600 "$SRC" "$VF"

# name<TAB>value, one per line, before filtering.
for f in .env .env.* .docker/.env .docker/.env.* docker/.env docker/.env.* .devcontainer/.env .devcontainer/.env.*; do
  [ -f "$f" ] || continue
  case "$f" in *.example|*.sample|*.template) continue ;; esac
  d="$(dirname "$f")"; ex=""
  for e in "$d/.env.example" "$d/.env.sample" "$d/.env.template"; do [ -f "$e" ] && ex="$ex $e"; done
  # shellcheck disable=SC2086
  awk -v NAMEPAT="$NAMEPAT" -v SRCF="$f" '
    function trim(x) { sub(/^[ \t\r]+/, "", x); sub(/[ \t\r]+$/, "", x); return x }
    function parse(line, kv,   k, v, i) {
      sub(/\r$/, "", line); line = trim(line)
      if (line == "" || substr(line, 1, 1) == "#") return 0
      sub(/^export[ \t]+/, "", line)
      i = index(line, "="); if (i == 0) return 0
      k = trim(substr(line, 1, i - 1)); v = trim(substr(line, i + 1))
      if (v ~ /^"/) { sub(/^"/, "", v); sub(/".*$/, "", v) }
      else if (v ~ /^\x27/) { sub(/^\x27/, "", v); sub(/\x27.*$/, "", v) }
      else { sub(/[ \t]+#.*$/, "", v); v = trim(v) }
      kv[1] = k; kv[2] = v; return 1
    }
    FNR == 1 { isex = (FILENAME != SRCF) }
    { split("", kv); if (!parse($0, kv)) next
      if (isex) { exv[kv[1]] = kv[2]; next }
      if (toupper(kv[1]) !~ NAMEPAT) next
      if ((kv[1] in exv) && exv[kv[1]] == kv[2]) next
      printf "%s:%s\t%s\n", SRCF, kv[1], kv[2] }
  ' $ex "$f" >> "$SRC"
done
if [ -f .mxcli/run-local.json ] && [ -n "$PY" ]; then
  "$PY" -I - "$NAMEPAT" >> "$SRC" 2>/dev/null <<'PYEOF'
import json, re, sys
pat = re.compile(sys.argv[1], re.I)
try:
    data = json.load(open(".mxcli/run-local.json"))
except Exception:
    sys.exit(0)
def walk(o, path=""):
    if isinstance(o, dict):
        for k, v in o.items():
            yield from walk(v, path + "." + k if path else k)
    elif isinstance(o, str) and "bootConfig" in path:
        yield path, o
for p, v in walk(data):
    if pat.search(p.rsplit(".", 1)[-1]) and "\t" not in v and "\n" not in v:
        print(".mxcli/run-local.json:" + p.split("bootConfig.", 1)[-1] + "\t" + v)
PYEOF
fi

# Filter: length and known defaults (lowercased compare). Then the explicit extra values.
FILT="$(mktemp "${TMPDIR:-/tmp}/mxtk-secfilt.XXXXXX")"; chmod 600 "$FILT"; trap 'rm -f "$SRC" "$VF" "$FILT"' EXIT
skipped=0
while IFS="$(printf '\t')" read -r name value; do
  [ -n "$name" ] || continue
  lv="$(printf '%s' "$value" | tr 'A-Z' 'a-z')"
  case "$DEFAULTS" in *" $lv "*) skipped=$((skipped + 1)); continue ;; esac
  [ "${#value}" -ge "$MINLEN" ] || { skipped=$((skipped + 1)); continue; }
  case "$name" in
    .mxcli/run-local.json:MicroflowConstants.*)
      printf '%s\n' "$value" > "$VF"
      if git grep -q -F -f "$VF" HEAD -- '*.mpr' 'mprcontents/' 2>/dev/null; then skipped=$((skipped + 1)); continue; fi ;;
  esac
  printf '%s\t%s\n' "$name" "$value" >> "$FILT"
done < "$SRC"
if [ -n "${MXTK_SECRET_VALUES_FILE:-}" ] && [ -f "$MXTK_SECRET_VALUES_FILE" ]; then
  while IFS= read -r v; do v="${v%$(printf '\r')}"; [ -n "$v" ] && printf 'extra\t%s\n' "$v"; done < "$MXTK_SECRET_VALUES_FILE" >> "$FILT"
fi
sort -u "$FILT" -o "$FILT"
n="$(wc -l < "$FILT" | tr -d ' ')"
if [ "$n" -eq 0 ]; then
  echo "check-staged-secrets: no secret values to scan for (none found, or $skipped skipped as known defaults / under $MINLEN chars) — nothing checked."
  exit 0
fi

if [ "$MODE" = staged ]; then
  STAGED="$(git diff --cached --name-only -z --diff-filter=ACMR | tr '\0' '\n' | head -c 1)"
  if [ -z "$STAGED" ]; then echo "✓ check-staged-secrets: nothing staged ($n value(s) would be checked)."; exit 0; fi
fi
hits=0
while IFS="$(printf '\t')" read -r name value; do
  printf '%s\n' "$value" > "$VF"
  if [ "$MODE" = tree ]; then
    files="$(git grep -l -F -f "$VF" HEAD 2>/dev/null | sed 's/^HEAD://')"
  else
    files="$(git diff --cached --name-only -z --diff-filter=ACMR | xargs -0 git --literal-pathspecs grep --cached -l -F -f "$VF" -- 2>/dev/null)"
  fi
  [ -n "$files" ] || continue
  while IFS= read -r f; do
    echo "  ✗ $f holds the value of $name"
    hits=$((hits + 1))
  done <<EOF2
$files
EOF2
done < "$FILT"
if [ "$hits" -gt 0 ]; then
  echo "✗ check-staged-secrets: $hits secret value(s) in $MODE blobs. Values are not shown."
  echo "  → Unstage the file (git rm --cached <file>), ignore it, keep the template without the value."
  echo "  → A value that reached a remote or a transcript is spent: rotate it. Removing the commit does not."
  exit 1
fi
echo "✓ check-staged-secrets: no secret value in the $MODE blobs ($n value(s) checked, $skipped skipped as defaults / under $MINLEN chars)."
