# Iterative Build Loop — BRD to Running Mendix App
**Purpose:** Per-module build discipline for mxcli-assisted Mendix development. Replaces bulk MDL generation with a verified, iterative gate per module.
**Companion skills:** `brd-to-build-plan.md` (upstream — produces the plan this loop executes), `migration-pipeline.md`, `mdl-cookbook-microflows.md`, `bug-logs/mxcli-bugs.md`
**Examples:** `../examples/outsystems-migration/build-loop-example.md`

---

## When to Use This Skill

- You have a build plan from `brd-to-build-plan.md` (module dependency order, resolved architecture questions, script sequence) and are ready to execute it in Mendix
- You want to avoid the pattern of "pages built but wrong" — where CE-error-free ≠ functionally correct
- You are working with mxcli + MDL scripting and need to know when to fall back to Studio Pro

---

## Core Principle

The build gate is **not** "0 CE errors." It is:

1. 0 CE errors **+**
2. Happy path verified as a demo user **+**
3. Every visible source field has a real widget binding

A page with a stub banner and no data below it is a missing feature, not a stub.

---

## Pre-Module Checklist (before writing any MDL)

Run this before scripting each module:

- [ ] Read source screenshots for this module top-to-bottom
- [ ] Read the feature doc (F-doc or BRD) for this module
- [ ] Extract the build checklist from the feature doc:
  - **Mandatory fields** → widget `Required` settings
  - **System-derived / read-only fields** → `Editable: Never`
  - **Conditional visibility** → container `Visible` expressions
  - **Validation rules** → `VAL_` microflows to implement
  - **Enumerations / lookups** → correct widget type (combobox, radiobuttons) — set from the start, not patched later
- [ ] Identify all pages/microflows this module will reference that don't exist yet → create stubs first (separate script, apply before the main script)
- [ ] MPR snapshot rotation is in place (see below) — do **not** make ad-hoc copies like `Project.mpr.backup`

### MPR snapshot rotation (the crash net)

Ad-hoc backup copies (`.mpr.backup`, `.mpr.pre-something`) accumulate, rot, and nobody remembers what they were. Use a **bounded, automated rotation** instead:

- Project has a `bin/snapshot-mpr.sh`: copies every root `*.mpr` into a gitignored `.mpr-snapshots/` with a timestamp, then prunes to the **5 newest** per project file.
- **Run it before every `mxcli exec`** (put this rule in the project's CLAUDE.md so every session follows it).
- Git commits per phase gate remain the real history — commit after each verified milestone (`mprcontents/` is tracked, so the model diffs). The rotation only covers mid-session corruption between commits.

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .mpr-snapshots
for f in *.mpr; do
  [ -e "$f" ] || continue
  base="${f%.mpr}"
  cp "$f" ".mpr-snapshots/${base}.$(date +%Y%m%d-%H%M%S).mpr"
  ls -t ".mpr-snapshots/${base}."*.mpr 2>/dev/null | tail -n +6 | while read -r old; do rm -f "$old"; done
done
echo "mpr snapshot ok — $(ls .mpr-snapshots/*.mpr 2>/dev/null | wc -l | tr -d ' ') kept"
```

Add `/.mpr-snapshots/` to the project `.gitignore`.

---

## Standard Build Command — `bin/exec.sh`

Every project should have a `bin/exec.sh` wrapper that runs the full build cycle in one command:

```
snapshot → mxcli exec → kill port 8081 → kill Studio Pro → reopen SP via full path
```

### Why this script exists

Two recurring problems make a bare `mxcli exec` + `open Project.mpr` unreliable:

1. **Port 8081 stays occupied.** The Mendix Java runtime keeps its socket open even after the Studio Pro window closes. The next Run Locally fails with "port already in use." Fix: `lsof -ti :8081 | xargs kill -9` before reopening.
2. **Version selector popup.** `open Project.mpr` without specifying the app triggers macOS's "open with which app?" dialog, which blocks headless sessions. Fix: always use `open -a "Mendix Studio Pro X.Y.Z" "$MPR"` with the fully-qualified app name.
3. **`$(pwd)` path breaks when invoked from a different cwd.** If the terminal is not at the project root, `$(pwd)/Project.mpr` resolves to a wrong path and SP throws "cannot open files in the data format." Fix: anchor with `${BASH_SOURCE[0]}` so the path is always relative to the script file, not the caller's cwd.

### Template — copy into each project's `bin/exec.sh`

```bash
#!/usr/bin/env bash
# exec.sh — safe mxcli exec wrapper: snapshot → exec → restart SP
# Usage: ./bin/exec.sh <script.mdl>  (safe to call from any cwd)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MPR="$PROJECT_ROOT/MyProject.mpr"          # ← change to project MPR name
SP_APP="Mendix Studio Pro 11.12.0 Beta"    # ← change to installed SP version
SCRIPT="$1"

if [[ -z "$SCRIPT" ]]; then
  echo "Usage: ./bin/exec.sh <script.mdl>"
  exit 1
fi

cd "$PROJECT_ROOT"

echo "→ Snapshotting MPR..."
./bin/snapshot-mpr.sh

echo "→ Executing $SCRIPT..."
./mxcli exec "$SCRIPT" -p "$MPR"

echo "→ Restarting Studio Pro..."
lsof -ti :8081 | xargs kill -9 2>/dev/null || true
pkill -9 -f "Contents/MacOS/studiopro" 2>/dev/null || true
sleep 2
rm -f "$MPR.lock"
open -a "$SP_APP" "$MPR"

echo "✓ Done — click Run Locally in Studio Pro when it finishes loading."
```

### Standalone SP restart — `bin/restart-sp.sh`

For cases where you need to restart SP without running a new exec (e.g. after a manual model change or a hung runtime):

```bash
#!/usr/bin/env bash
# restart-sp.sh — kill runtime + SP, then reopen cleanly
# Usage: ./bin/restart-sp.sh  (safe to call from any cwd)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MPR="$PROJECT_ROOT/MyProject.mpr"          # ← change to project MPR name
SP_APP="Mendix Studio Pro 11.12.0 Beta"    # ← change to installed SP version

lsof -ti :8081 | xargs kill -9 2>/dev/null || true
pkill -9 -f "Contents/MacOS/studiopro" 2>/dev/null || true
sleep 2
rm -f "$MPR.lock"
open -a "$SP_APP" "$MPR"
echo "✓ Done — click Run Locally in Studio Pro when it finishes loading."
```

### Usage during the build loop

Replace every manual `./mxcli exec script.mdl -p Project.mpr` call with:

```bash
./bin/exec.sh mdlsource/my-script.mdl
```

After exec.sh completes, Studio Pro opens in the background. Click **Run Locally** and wait for it to finish before taking screenshots or running tests. This is part of the screenshot stale-build gate — never screenshot before Run Locally completes.

### Per-project setup checklist

- [ ] Copy `bin/exec.sh` into the project, update `MPR` and `SP_APP` variables
- [ ] Copy `bin/restart-sp.sh`, update the app name and MPR name
- [ ] `chmod +x bin/exec.sh bin/restart-sp.sh`
- [ ] Add rule to `CLAUDE.md`: never use `open Project.mpr` directly — always use `./bin/exec.sh` or `./bin/restart-sp.sh`
- [ ] Confirm `SP_APP` string matches exactly what appears in `/Applications/` (spaces and all)

---

## The 12-Step Build Loop

Repeat for each module:

```
1.  Read source screenshots top-to-bottom (not the data model outward)
2.  Read feature doc section for this module
3.  Extract build checklist (mandatory, read-only, conditional, validation)
4.  Sketch page data-view nesting → derive microflow signatures
5.  Create stub pages/microflows for any forward references (separate script, apply first)
6.  Write + apply microflows
7.  Write + apply pages (following screenshot top-to-bottom)
8.  mxcli docker check → 0 CE errors
9.  If GRANT scripts were applied → Studio Pro "Update security" → Ctrl+S
10. Walk the happy path as a non-admin demo user:
      - Log in as demo user (not Administrator)
      - Navigate to the page
      - Fill minimum required fields
      - Click save / next
      - Confirm record created or navigation succeeded
11. Screenshot coverage check:
      - Open the source screenshot
      - List every visible field/section
      - Verify each has a widget with a real datasource binding (not a stub banner)
      - Document any gap as an explicit sub-task before marking done
12. Mark module done ✅
```

Steps 8–11 are the phase gate. Steps 1–7 without 8–11 = page may be built but wrong.

---

## Script Conventions

### Numbering and versioning

- Scripts are numbered sequentially: `01-module-domain.mdl`, `02-stubs.mdl`, `03-microflows.mdl`, ...
- Once a script has been executed against the MPR it is **frozen** — never edit it
- For fixes: write a new numbered script (`create or replace` / `create or modify`)
- The MPR is the source of truth; scripts are the historical audit trail

### Stub architecture

External integrations that aren't built yet get a boolean constant gate:

```
CONST_STUB_<Integration> = true
```

The stub branch contains hardcoded or DTO-bound values that make the UI look complete.
A stub banner with nothing below it is invisible in demos — always render at least one data field beneath it.
Mark each stub with the script number that will replace it: `[STUB: Script 44 will replace this section]`.

### Forward references

`mxcli exec` hard-fails if a referenced page or microflow doesn't exist in the MPR. Pattern:

```
15b-stub-pages.mdl   ← create stub targets (apply first)
15-page-overview.mdl ← the real script with forward references (apply second)
```

Use `SHOW PAGES IN Module` / `SHOW MICROFLOWS IN Module` to confirm a target exists before referencing it.

---

## CE Error Triage

When a CE error appears, triage in this order — **never add model elements to silence errors without tracing to requirements first**:

1. **Is it CE0066?** → Studio Pro "Update security" click, then Ctrl+S (see `bug-logs/mxcli-bugs.md` BUG-03)
2. **Is the referenced element missing?** → Create the missing stub, don't patch the error around it
3. **Is it a binding mismatch?** → Check whether the *page is wrong* (bound to wrong attribute/entity) rather than the *model being incomplete*. The page may be the bug.
4. **Requirements justification:** Before adding any attribute, entity, or association to resolve a CE error, trace it to the feature doc. If it's not in the spec, the page binding is wrong — fix the page.
5. **Annotate the fix.** Once the CE error is resolved, add an `@annotation` on the fixed activity recording what was tried and why it changed (e.g. "Was trying to retrieve via association — failed CE0056; now passed as parameter instead"). See `learned-microflow-patterns.md`'s annotation rule — this is the one case annotations are always worth adding, even in an otherwise unannotated microflow, because the next reviewer (human or agent) has no other way to see that this shape was already tried and rejected.

**mxcli itself does not write anything back into the model on a CE error or exec failure** — `mxcli check`/`mxcli exec` only report to stdout/JSON/SARIF. Step 5 is a manual/agent discipline, not a CLI feature — there's no `--annotate-on-error` flag to reach for.

---

## Studio Pro Handoff Points

Some operations cannot be done via mxcli. Plan for these explicitly in each module's schedule:

| When | Action | Estimated time |
|------|--------|---------------|
| After any `GRANT` script | Open Studio Pro → click "Update security" banner → Ctrl+S | 2 min |
| Cross-module associations | Draw in Studio Pro domain model (drag across modules) | 5–10 min per assoc |
| Drop attribute with access rules | Delete in Studio Pro (BUG-01 — mxcli corrupts MPR) | 2 min |
| After `VALIDATION FEEDBACK` activities | Wire `Variable` manually in Studio Pro (BUG CE0639) | 1–2 min per activity |
| After XPath retrieves written by mxcli | Run binary patch script + reload Studio Pro (BUG-15b) | 3 min |

**Cross-module associations must always be created in Studio Pro.** This is non-negotiable (BUG-02 corrupts the MPR silently). Plan a dedicated Studio Pro session for cross-module associations after the mxcli entity scripts are applied.

---

## MDL Syntax Quick Reference

### Patterns that tripped projects

```sql
-- EXTENDS goes BEFORE the opening parenthesis
CREATE PERSISTENT ENTITY Module.Entity EXTENDS System.Image (
  Caption: String(200)
);

-- Fully-qualify Module in RETURNS clause
CREATE MICROFLOW Module.GET_Foo ($Param: Module.Entity)
RETURNS Module.Entity AS $Result
BEGIN ...

-- retrieve from association traversal is NOT supported for persistent entities
-- WRONG: retrieve $X from $obj/Assoc
-- RIGHT: RETRIEVE $X FROM Module.Entity WHERE $X/Module.AssocName = $obj

-- Quote identifiers to avoid reserved keyword conflicts (quotes are stripped automatically)
CREATE PERSISTENT ENTITY Module."Customer" (
  "Name": String(200),
  "Create": DateTime
);

-- Action syntax in pages uses colon, not equals
Action: MICROFLOW Module.ACT_Save(Param: $value)

-- SHOW PAGE params use $ prefix
SHOW PAGE Module.PageName ($Param = $value);

-- CASE/WHEN is not supported — use nested IF
IF condition THEN
  ...
ELSE
  IF condition2 THEN ... END IF;
END IF;
```

### Unsupported — use alternatives

| Unsupported | Alternative |
|-------------|-------------|
| `CASE ... WHEN ... END CASE` | Nested `IF ... ELSE ... END IF` |
| `TRY ... CATCH` | `ON ERROR { ... }` blocks |
| `retrieve $X from $obj/Assoc` (persistent entities) | `RETRIEVE $X FROM Module.Entity WHERE $X/Assoc = $obj` |

---

## Iterative Granularity — Choosing Your Iteration Unit

The build loop runs *per module*, but within a module you need to decide the granularity of each MDL script. Tradeoffs:

| Granularity | Pros | Cons |
|------------|------|------|
| One script per domain (entity + assocs + microflows + pages) | Fewer files | Hard to partially recover; large CE error surface |
| One script per layer (domain / microflows / pages) | Cleaner rollback | 3× the scripts |
| One script per page or page cluster | Smallest blast radius | More forward-reference stubs needed |

**Recommended:** Layer granularity (domain → microflows → pages) for most modules. Drop to per-page granularity for complex multi-section pages where partial recovery is likely.

---

## Architecture Decisions to Resolve Before Scripting

These must be answered at the *architecture* phase, not discovered mid-build:

1. **Iteration granularity** — one script per layer or per page cluster?
2. **Cross-module association ownership** — which module's domain model holds the association? (Always Studio Pro, but which session?)
3. **Stub vs. real for each integration** — what's in scope for this sprint vs. stubbed?
4. **Demo user / role mapping** — which Mendix user roles map to source system roles? Needed before any security script.
