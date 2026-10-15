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
#   .env and .env.*            KEY=VALUE where KEY looks like PASSWORD / SECRET / TOKEN / KEY / PAT
#   .mxcli/run-local.json      every string in bootConfig whose key looks like one of those
#   $MXTK_SECRET_VALUES_FILE   optional: one literal value per line (name shown as "extra")
# Values shorter than 6 characters are ignored (a scan for "1" would match everything).
# Example files (.env.example, .env.sample, .env.template) are not sources.
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
SRC="$(mktemp "${TMPDIR:-/tmp}/mxtk-secrets.XXXXXX")"; trap 'rm -f "$SRC"' EXIT
chmod 600 "$SRC"

# name<TAB>value, one per line.
for f in .env .env.*; do
  [ -f "$f" ] || continue
  case "$f" in *.example|*.sample|*.template) continue ;; esac
  sed -E 's/^[[:space:]]*export[[:space:]]+//' "$f" | while IFS= read -r line; do
    case "$line" in \#*|"") continue ;; esac
    k="${line%%=*}"; v="${line#*=}"; [ "$k" = "$line" ] && continue
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    printf '%s' "$k" | grep -qiE "$NAMEPAT" || continue
    printf '%s\t%s\n' "$f:$k" "$v"
  done >> "$SRC"
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
if [ -n "${MXTK_SECRET_VALUES_FILE:-}" ] && [ -f "$MXTK_SECRET_VALUES_FILE" ]; then
  while IFS= read -r v; do [ -n "$v" ] && printf 'extra\t%s\n' "$v"; done < "$MXTK_SECRET_VALUES_FILE" >> "$SRC"
fi

n=0
while IFS="$(printf '\t')" read -r name value; do
  [ "${#value}" -ge 6 ] && n=$((n + 1))
done < "$SRC"
if [ "$n" -eq 0 ]; then echo "check-staged-secrets: no secret values found to scan for (no .env secrets, no run-local.json bootConfig) — nothing checked."; exit 0; fi

if [ "$MODE" = tree ]; then FILES="$(git ls-files)"; else FILES="$(git diff --cached --name-only --diff-filter=ACMR)"; fi
hits=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ "$MODE" = tree ]; then blob="$(git show "HEAD:$f" 2>/dev/null | LC_ALL=C tr -d '\000')"; else blob="$(git show ":$f" 2>/dev/null | LC_ALL=C tr -d '\000')"; fi
  [ -n "$blob" ] || continue
  while IFS="$(printf '\t')" read -r name value; do
    [ "${#value}" -ge 6 ] || continue
    if printf '%s' "$blob" | grep -qF -- "$value"; then
      echo "  ✗ $f holds the value of $name"
      hits=$((hits + 1))
    fi
  done < "$SRC"
done <<EOF2
$FILES
EOF2
if [ "$hits" -gt 0 ]; then
  echo "✗ check-staged-secrets: $hits secret value(s) in $MODE blobs. Values are not shown."
  echo "  → Unstage the file (git rm --cached <file>), ignore it, keep the template without the value."
  echo "  → A value that reached a remote or a transcript is spent: rotate it. Removing the commit does not."
  exit 1
fi
echo "✓ check-staged-secrets: no secret value in the $MODE blobs ($n value(s) checked)."
