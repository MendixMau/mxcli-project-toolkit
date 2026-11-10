#!/usr/bin/env bash
# persona-preflight.sh — before a journey batch: does every persona the journeys log in as exist?
#
#   ./bin/persona-preflight.sh [--mpr <app.mpr>] <journey.json | journeys-dir>...
#   ./bin/persona-preflight.sh --demo-users <file> [--user-roles <file>] <journey.json>...   (fixtures)
#
# Speed-night experiment B (2026-11-09): 11 per-row journey runs each logged in as a persona that is
# not a demo user in the model, each waited out the login (~104 s) and failed "The username or
# password you entered is incorrect" -- 19 minutes, and nothing flagged it: the runs "failed as
# expected" for a half-built module. This check costs ~1 s (`mxcli show demo users`) and fails the
# batch before the first browser opens, ONE NAMED LINE PER MISSING PERSONA.
#
# What is checked, per distinct persona (the journey's top-level `persona`; when no journey names
# one, $TEST_USER, which is who the runner will sign in as):
#   MISSING  the persona is not a demo user name (exact, case-sensitive: the login form is)
#   ROLE     the demo user does not carry the role the journey expects. The expected role is the
#            journey's optional `personaRole`; without it, the user role named like the persona
#            (case-insensitive: persona `requester` -> role `Requester`) when the model has one;
#            with neither, only existence is asserted and the summary line says so.
# Last line is always the denominator: "persona preflight: P persona(s) from J journey(s): E exist,
# R role(s) asserted, N problem(s)". Silence is never a pass.
#
# Exit 0 all present · 1 at least one MISSING/ROLE line · 2 could not measure (no mxcli/node, no
# demo-user table, unreadable journey): never green-by-absence.
# Producer: verify-module.sh runs it before the journey step; the per-row/close harness calls it
# before a batch (journey-proof.md). Golden input: tests/wave2/fixtures/persona-preflight/ (verbatim
# `mxcli show demo users` / `show user roles`, v0.28.0).
set -uo pipefail
_sd="${0%/*}"; [ "$_sd" != "$0" ] || _sd=.

MPR_ARG=""; DU_FILE=""; UR_FILE=""; INPUTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --mpr) MPR_ARG="${2:-}"; shift 2 ;;
    --demo-users) DU_FILE="${2:-}"; shift 2 ;;
    --user-roles) UR_FILE="${2:-}"; shift 2 ;;
    -h|--help) sed -n 2,26p "$0"; exit 0 ;;
    *) INPUTS+=("$1"); shift ;;
  esac
done
[ "${#INPUTS[@]}" -gt 0 ] || { echo "usage: persona-preflight.sh [--mpr <app.mpr>] <journey.json|dir>..." >&2; exit 2; }
command -v node >/dev/null 2>&1 || { echo "persona preflight: UNMEASURED -- node not installed" >&2; exit 2; }

. "$_sd/_common.sh"
FILES=()
for i in "${INPUTS[@]}"; do
  if [ -d "$i" ]; then
    while IFS= read -r f; do FILES+=("$f"); done < <(find "$i" -name '*.journey.json' -type f | sort)
  elif [ -f "$i" ]; then FILES+=("$i")
  else echo "persona preflight: UNMEASURED -- no such journey file or directory: $i" >&2; exit 2; fi
done
[ "${#FILES[@]}" -gt 0 ] || { echo "persona preflight: UNMEASURED -- no *.journey.json under the given paths" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/persona-pf.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
if [ -z "$DU_FILE" ]; then
  MXCLI="$(find_project_mxcli 2>/dev/null || true)"
  [ -n "$MXCLI" ] || { echo "persona preflight: UNMEASURED -- no project mxcli (looked for \$PROJECT_ROOT/mxcli[.exe])" >&2; exit 2; }
  MPR="${MPR_ARG:-$(find_mpr)}" || exit 2
  DU_FILE="$TMP/demo-users.txt"; UR_FILE="$TMP/user-roles.txt"
  "$MXCLI" -p "$MPR" -c "show demo users" > "$DU_FILE" 2>&1 || { echo "persona preflight: UNMEASURED -- 'show demo users' failed:" >&2; tail -3 "$DU_FILE" >&2; exit 2; }
  "$MXCLI" -p "$MPR" -c "show user roles" > "$UR_FILE" 2>&1 || : > "$UR_FILE"
fi
[ -r "$DU_FILE" ] || { echo "persona preflight: UNMEASURED -- cannot read $DU_FILE" >&2; exit 2; }

NF=(); for f in "${FILES[@]}"; do NF+=("$(native_path "$f")"); done
export PF_DU="$(native_path "$DU_FILE")" PF_UR="$( [ -n "$UR_FILE" ] && native_path "$UR_FILE" || true)"
node -e '
const fs = require("fs");
const rows = (txt) => txt.replace(/\r/g, "").split("\n").filter(l => /^\s*\|/.test(l))
  .map(l => l.trim().replace(/^\||\|$/g, "").split("|").map(c => c.trim()))
  .filter(r => !r.every(c => /^-+$/.test(c)));   // drop the |---|---| rule
const du = rows(fs.readFileSync(process.env.PF_DU, "utf8"));
const head = du.shift();
if (!head || !/user name/i.test(head[0] || "")) { console.error("persona preflight: UNMEASURED -- no demo-user table in the mxcli output (are demo users enabled in the model?)"); process.exit(2); }
const users = new Map(du.map(r => [r[0], (r[1] || "").split(/[,;]/).map(s => s.trim()).filter(Boolean)]));
let roles = [];
try { if (process.env.PF_UR) { const ur = rows(fs.readFileSync(process.env.PF_UR, "utf8")); ur.shift(); roles = ur.map(r => r[0]); } } catch (_) {}
const byPersona = new Map(); let nj = 0;
for (const f of process.argv.slice(1)) {
  let j; try { j = JSON.parse(fs.readFileSync(f, "utf8")); } catch (e) { console.error(`persona preflight: UNMEASURED -- ${f}: ${e.message}`); process.exit(2); }
  for (const x of (Array.isArray(j) ? j : [j])) {
    nj++;
    const p = x.persona || process.env.TEST_USER || "";
    if (!p) continue;
    if (!byPersona.has(p)) byPersona.set(p, []);
    byPersona.get(p).push({ id: x.id || f, role: x.personaRole || null });
  }
}
let problems = 0, exist = 0, asserted = 0, unasserted = [];
const have = [...users.keys()].join(", ");
for (const [p, js] of byPersona) {
  const ids = js.map(x => x.id).join(", ");
  if (!users.has(p)) {
    problems++;
    const near = [...users.keys()].find(u => u.toLowerCase() === p.toLowerCase());
    console.log(`PERSONA MISSING: "${p}" (${ids}) is not a demo user in the model${near ? ` -- "${near}" exists; names are case-sensitive` : ""}. Demo users: ${have}`);
    continue;
  }
  exist++;
  const held = users.get(p);
  const declared = js.find(x => x.role);
  const want = declared ? declared.role : roles.find(r => r.toLowerCase() === p.toLowerCase());
  if (!want) { unasserted.push(p); continue; }
  asserted++;
  if (!held.includes(want)) {
    problems++;
    console.log(`PERSONA ROLE: demo user "${p}" (${ids}) holds role ${held.join("/") || "none"}, expected ${want}${declared ? "" : " (the user role named like the persona)"}`);
  }
}
console.log(`persona preflight: ${byPersona.size} persona(s) from ${nj} journey(s): ${exist} exist, ${asserted} role(s) asserted, ${problems} problem(s)` +
  (unasserted.length ? ` -- role NOT asserted for: ${unasserted.join(", ")} (declare personaRole on the journey)` : ""));
process.exit(problems ? 1 : 0);
' "${NF[@]}"
