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

Ad-hoc backup copies (`.mpr.backup`, `.mpr.pre-something`) accumulate, rot, and nobody remembers what they were. Use a **bounded, automated rotation** instead.

**Critical:** an MPR project is two parts — `Project.mpr` (SQLite index) and `mprcontents/` (BSON unit files holding the actual model data). Snapshotting only the `.mpr` is incomplete. A corrupted `mprcontents/` file cannot be restored from the `.mpr` alone, and Studio Pro will refuse to open the project with a `KeyNotFoundException` referencing a missing GUID. **Always snapshot both.**

- Project has `bin/snapshot-mpr.sh` and `bin/restore-mpr.sh`.
- **`bin/exec.sh` calls `snapshot-mpr.sh` automatically** — use exec.sh as the standard build command. Only run `bash bin/snapshot-mpr.sh` manually if calling `mxcli exec` directly (bypassing exec.sh).
- Keeps 5 newest snapshots, prunes older ones automatically.
- Git commits per phase gate are the real history (`mprcontents/` tracked). Snapshots only cover mid-session corruption between commits.

#### `bin/snapshot-mpr.sh`

```bash
#!/usr/bin/env bash
# Snapshot MPR + mprcontents before a script batch. Prunes to 5 newest.
set -euo pipefail
cd "$(dirname "$0")/.."

MPR="$(ls *.mpr | head -1)"
CONTENTS_DIR="mprcontents"
SNAP_DIR="build/snapshots"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DEST="$SNAP_DIR/$TIMESTAMP"

mkdir -p "$DEST"
cp "$MPR" "$DEST/$MPR"
[ -d "$CONTENTS_DIR" ] && cp -r "$CONTENTS_DIR" "$DEST/$CONTENTS_DIR"

echo "Snapshot saved: $DEST"
ls -dt "$SNAP_DIR"/20* 2>/dev/null | tail -n +6 | while read -r old; do rm -rf "$old"; echo "Pruned: $old"; done
echo "$(ls -d "$SNAP_DIR"/20* 2>/dev/null | wc -l | tr -d ' ') snapshot(s) kept"
```

#### `bin/restore-mpr.sh`

```bash
#!/usr/bin/env bash
# Restore MPR + mprcontents from a snapshot.
# Usage: bash bin/restore-mpr.sh [snapshot-dir]   (defaults to newest)
set -euo pipefail
cd "$(dirname "$0")/.."

MPR="$(ls *.mpr | head -1)"
CONTENTS_DIR="mprcontents"
SNAP_DIR="build/snapshots"

SNAP="${1:-$(ls -dt "$SNAP_DIR"/20* 2>/dev/null | head -1)}"
[ -z "$SNAP" ] && { echo "ERROR: no snapshots in $SNAP_DIR"; exit 1; }
[ ! -f "$SNAP/$MPR" ] && { echo "ERROR: snapshot missing $MPR"; exit 1; }

echo "Restoring from: $SNAP"
cp "$SNAP/$MPR" "$MPR" && echo "  Restored: $MPR"
if [ -d "$SNAP/$CONTENTS_DIR" ]; then
  rm -rf "$CONTENTS_DIR"
  cp -r "$SNAP/$CONTENTS_DIR" "$CONTENTS_DIR"
  echo "  Restored: $CONTENTS_DIR"
else
  echo "  WARNING: snapshot has no $CONTENTS_DIR — MPR index only (may be incomplete)"
fi
echo "Restore complete."
```

Add `build/snapshots/` to the project `.gitignore`.

#### When Studio Pro crashes on open (KeyNotFoundException / AggregateException)

This means a BSON unit file references a GUID that no longer exists in the model — typically caused by dropping an entity that pages or cross-module associations still point to. `mxcli` can still read/write the MPR; only `mx check` and Studio Pro fail.

**Recovery procedure:**
1. `bash bin/restore-mpr.sh` — restore both `.mpr` and `mprcontents/` from the newest snapshot
2. If no clean snapshot is available: use `mxcli` to surgically drop the documents that reference the missing GUID, then recreate them clean
3. After recovery, verify with `./mxcli docker check -p App.mpr --no-update-widgets` before proceeding

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
8.  **Gate 2 — BSON validation (mandatory, never skip):**
    `./mxcli docker check -p app.mpr --no-update-widgets` → 0 CE errors

      - **One-time setup required per machine:** run `./mxcli setup mxbuild -p app.mpr` before the
        first `docker check`. Without it, mxcli uses a Linux CDN binary that cannot load MPRv2
        projects (`mprcontents/`) and crashes before validating anything — silently passing BSON
        corruption that will break Studio Pro on open. The setup command finds your local Studio Pro
        installation and uses its `mx` binary instead.
      - Always use `--no-update-widgets`. Without it, `mx update-widgets` runs first and crashes
        with `AggregateException` on Studio Pro 11.x Beta (path resolution bug).
      - CE0066 alone = **conditional pass**: only Studio Pro can recompute the security hash.
        Open Studio Pro, open the affected domain model, click "Update security", Cmd+S, re-run check.
        Do not block the build on CE0066 alone.
      - **Fallback if `docker check` itself fails to run** (binary missing, path error, etc.):
        open Studio Pro via CLI and verify the project loads cleanly:
        ```bash
        open -a "Mendix Studio Pro X.Y.Z" app.mpr   # macOS
        ```
        If Studio Pro opens without an error dialog → gate passes. If it shows `AggregateException`,
        `KeyNotFoundException`, or `AttributeIdentifier` errors → restore snapshot immediately.
        **This fallback is mandatory — never mark a script DONE without Gate 2 passing.**
9.  If GRANT scripts were applied → Studio Pro "Update security" → Cmd+S
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

1. **Is it CE0066?** → Conditional pass. This is a security hash that only Studio Pro can recompute —
   mxcli GRANT/REVOKE cycling does not clear it. Open the affected module's domain model in Studio Pro,
   click the "Update security" banner, Cmd+S, re-run `docker check --no-update-widgets`. Do not block
   the build on CE0066 alone if all other errors are 0.
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
| Cross-module associations | Use `CREATE ASSOCIATION` via mxcli — BUG-02 fixed in v0.13.0 | — |
| Drop attribute with access rules | Delete in Studio Pro (BUG-01 — mxcli corrupts MPR) | 2 min |
| After `VALIDATION FEEDBACK` activities | Wire `Variable` manually in Studio Pro (BUG CE0639) | 1–2 min per activity |
| After XPath retrieves written by mxcli | Run binary patch script + reload Studio Pro (BUG-15b) | 3 min |

**Cross-module associations can be created via mxcli** using `CREATE ASSOCIATION` — BUG-02 is fixed in v0.13.0. No Studio Pro handoff needed.

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
