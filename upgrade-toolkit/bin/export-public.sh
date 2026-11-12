#!/usr/bin/env bash
# Export the HARNESS of the upgrade toolkit to a folder that can become a public repo. Whitelist only: a path not
# listed here never leaves. Run data, field notes and research stay in this (private) repo.
# Usage: export-public.sh [DEST]   (default ~/upgrade-toolkit-public). Writes and commits locally; never pushes.
# Refuses when the export holds a private name (bin/private_names.sh, required here), a token, a home-folder path,
# a real deployment or internal hostname, an e-mail address other than example/test/noreply, or an app model, package, archive or .env file.
set -euo pipefail
TK=$(cd "$(dirname "$0")/.." && pwd); ROOT=$(cd "$TK/.." && pwd); DST=${1:-$HOME/upgrade-toolkit-public}
ALLOW=(upgrade-toolkit/bin upgrade-toolkit/steps upgrade-toolkit/playbooks upgrade-toolkit/templates
       upgrade-toolkit/controls upgrade-toolkit/vendor upgrade-toolkit/examples upgrade-toolkit/runs/HISTORY.md
       upgrade-toolkit/SKILL.md upgrade-toolkit/SETUP.md upgrade-toolkit/SETUP-PROMPT.md upgrade-toolkit/PLAN.md
       upgrade-toolkit/READING-THE-VERDICT.md company-brain-test/brain/baseline/versions)
DROP=(upgrade-toolkit/bin/sync_gitlab.sh upgrade-toolkit/bin/export-public.sh upgrade-toolkit/bin/private_names.sh)
source "$TK/bin/private_names.sh"
[ -n "$DENY" ] || { echo "REFUSED: no private names list (UPG_PRIVATE_NAMES); the export cannot be checked" >&2; exit 1; }
TOKENS='ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{10,}|xox[bp]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH|PRIVATE) KEY|sk-[A-Za-z0-9]{20,}'
SL=/   # built up from a variable so this detector's own source text never reads as a literal path
HOMES="${SL}Users${SL}[A-Za-z]|${SL}home${SL}[a-z][a-z0-9_-]+${SL}"
# hosts of real deployments and internal domains; the company's own domains live outside this repo (bin/private_hosts.sh,
# same reasoning as bin/private_names.sh for names) — release-note rows name only the public sandbox.mxapps.io
source "$TK/bin/private_hosts.sh"
HOSTS='[a-z0-9-]+\.(mendixcloud\.com|mxapps\.io)'"${HOSTS_DENY:+|$HOSTS_DENY}"
MAILS='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}'
MAIL_OK='@([a-z0-9.-]+\.)?(example(\.(com|org|invalid))?|test(\.invalid)?|t|noreply\.[a-z.]+|users\.noreply\.github\.com)\b|noreply@'

[ -d "$DST/.git" ] || git init -q -b main "$DST"
find "$DST" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
# committed content only (git archive), never the working tree: untracked files cannot leak in
SHA=$(git -C "$ROOT" rev-parse --short HEAD)
present=(); for p in "${ALLOW[@]}"; do git -C "$ROOT" cat-file -e "HEAD:$p" 2>/dev/null && present+=("$p"); done
git -C "$ROOT" archive HEAD "${present[@]}" | tar -x -C "$DST"
for p in "${DROP[@]}"; do rm -rf "${DST:?}/$p"; done
find "$DST" -name __pycache__ -prune -exec rm -rf {} + ; find "$DST" -name '*.pyc' -delete
cp "$TK/PUBLIC-README.md" "$DST/README.md"; cp "$TK/PUBLIC-LICENSE" "$DST/LICENSE"
cat > "$DST/.gitignore" <<'GI'
*.log
!upgrade-toolkit/controls/fixtures/**/*.log
__pycache__/
.DS_Store
.env
GI

fail=0
hits=$(grep -rInE --exclude-dir=.git "$DENY" "$DST" | cut -c1-200 || true)
[ -z "$hits" ] || { echo "REFUSED: private names:"; echo "$hits" | sed "s|$DST/||" | head -40; fail=1; }
CLOUD_HOME="${SL}home${SL}user${SL}"   # the generic cloud-container home path, not a real person's — exempted below
hits=$(grep -rInE --exclude-dir=.git "$TOKENS|$HOMES" "$DST" | grep -vE "$CLOUD_HOME" | cut -c1-200 || true)
[ -z "$hits" ] || { echo "REFUSED: tokens or home-folder paths:"; echo "$hits" | sed "s|$DST/||" | head -40; fail=1; }
hits=$(grep -rIonE --exclude-dir=.git "$HOSTS" "$DST" | grep -vE ':(sandbox\.mxapps\.io'"${HOSTS_ALLOW:+|$HOSTS_ALLOW}"')$' || true)
[ -z "$hits" ] || { echo "REFUSED: real deployment or internal hostnames:"; echo "$hits" | sed "s|$DST/||" | head -40; fail=1; }
hits=$(grep -rIonE --exclude-dir=.git "$MAILS" "$DST" | grep -vE "$MAIL_OK" || true)
[ -z "$hits" ] || { echo "REFUSED: e-mail addresses:"; echo "$hits" | sed "s|$DST/||" | head -40; fail=1; }
bad=$(find "$DST" -path "$DST/.git" -prune -o \( -name '*.mpr' -o -name '*.mpk' -o -name '*.zip' -o -name '.env' -o -name '*.mda' -o -path '*/internal*' \) -print)
[ -z "$bad" ] || { echo "REFUSED: model, package, archive, env or internal files:"; echo "$bad" | sed "s|$DST/||"; fail=1; }
[ "$fail" = 0 ] || exit 1

cd "$DST"; git add -A
git diff --cached --quiet || git commit -q -m "Export the upgrade toolkit harness (source $SHA, leak checks passed)"
echo "export $DST at $(git rev-parse --short HEAD) from $SHA: $(git ls-files | wc -l | tr -d ' ') files, $(du -sh --exclude=.git . 2>/dev/null | cut -f1 || du -sh . | cut -f1). Not pushed."
