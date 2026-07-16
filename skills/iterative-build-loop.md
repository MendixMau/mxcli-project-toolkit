# Iterative Build Loop — BRD to Running Mendix App
**Applies to:** any mxcli project (migration and greenfield alike).
**Purpose:** Per-module build discipline for mxcli-assisted Mendix development. Replaces bulk MDL generation with a verified, iterative gate per module.
**Companion skills:** `brd-to-build-plan.md` (upstream — produces the plan this loop executes), `migration-pipeline.md`, `conversion-runbook.md` (Stage 5 — where the coverage checklist below gets confirmed with the user, not just self-extracted), `mdl-cookbook-microflows.md`, `bug-logs/mxcli-bugs.md`
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
3. Every visible source field has a real widget binding **+**
4. The module's **business-rule coverage checklist** passes — not just extracted, but confirmed with the user at Stage 5 kickoff (`conversion-runbook.md`) as the actual definition of "done," and verified by `gate-agent` alongside Gate 2, not left as a step someone might skip under time pressure.

A page with a stub banner and no data below it is a missing feature, not a stub. **CE-error-free ≠ done — the coverage checklist is what "done" means.**

**Corollary — MDL is drafted just-in-time, never stockpiled.** Scripts for phase N are written only
after phase N−1 has passed this gate. A backlog of pre-written, never-executed scripts is a defect,
not a head start: each one encodes assumptions about a model state that the intervening gates may
have changed (see `brd-to-build-plan.md`, "The build plan contains no MDL").

---

## Pre-Module Checklist (before writing any MDL)

> **Live visibility rule:** the moment this checklist is confirmed, post it — plus the 13-step
> build sequence — in the chat with status marks, and keep it updated as each item lands. See
> `conversion-runbook.md` §1b (Live Checklist Protocol). The user must never have to ask
> "what are we doing right now?" mid-module.

Run this before scripting each module:

- [ ] **Module brief exists and passes its ready-check.** `architecture/modules/<Module>-brief.md` must exist (authored by `ba-agent` translation mode, per `module-brief.md`) with every ready-check box ticked: every screen has a wireframe, the access table covers every element, no open business question blocks this phase, write mode chosen for every STOP-row element. **No brief, or an unchecked ready-check item touching this phase → STOP.** Produce/complete the brief first — do not let the `mdl-agent` synthesize the module from raw BRDs. This is the just-in-time gate: mechanical `gate-check.sh` cannot enforce it (briefs don't all exist at Stage 4), so it is enforced here, manually, per module.
- [ ] Read source screenshots for this module top-to-bottom
- [ ] Read the feature doc (F-doc or BRD) for this module
- [ ] Extract the build checklist from the feature doc:
  - **Mandatory fields** → widget `Required` settings
  - **System-derived / read-only fields** → `Editable: Never`
  - **Conditional visibility** → container `Visible` expressions
  - **Validation rules** → `VAL_` microflows to implement **and a visible validation message on the page** — the rule firing server-side is not enough; the user must see why a save failed (a silent 4xx/5xx is a P1 in the UI review loop)
  - **Enumerations / lookups** → correct widget type (combobox, radiobuttons) — set from the start, not patched later
- [ ] **Confirm this checklist with the user before scripting, not after.** This is the per-module business-rule coverage checklist `conversion-runbook.md` Stage 5 asks the user to confirm — the item that decides whether the module is actually done. `ba-agent` owns getting the confirmation; `gate-agent` owns verifying it was met, alongside Gate 2 (below), before the module is marked done. A checklist nobody signed off on is just a private To-Do — it doesn't count as the definition of done.
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
SNAP_DIR=".mpr-snapshots"
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
SNAP_DIR=".mpr-snapshots"

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

Add `.mpr-snapshots/` to the project `.gitignore`.

#### When Studio Pro crashes on open (KeyNotFoundException / AggregateException)

This means a BSON unit file references a GUID that no longer exists in the model — typically caused by dropping an entity that pages or cross-module associations still point to. `mxcli` can still read/write the MPR; only `mx check` and Studio Pro fail.

**Recovery procedure:**
1. `bash bin/restore-mpr.sh` — restore both `.mpr` and `mprcontents/` from the newest snapshot
2. If no clean snapshot is available: use `mxcli` to surgically drop the documents that reference the missing GUID, then recreate them clean
3. After recovery, re-run `./bin/exec.sh` on a no-op/next script (its mxbuild gate re-validates the model), or open the project in Studio Pro to confirm it loads cleanly, before proceeding

---

## Standard Build Command — `bin/exec.sh`

Every project should have a `bin/exec.sh` wrapper that runs the full build cycle in one command:

```
uncommitted-guard → SP-open-guard → concurrent-writer-guard → snapshot → mxcli exec → mxbuild gate → (auto-restore on failure) → tell user to reopen SP manually
```

**Never auto-kill or auto-reopen Studio Pro from exec.sh.** See SP Lifecycle Rule below.

### Why this script exists — four hard-learned problems

1. **Port 8081 stays occupied.** The Mendix Java runtime keeps its socket open after Studio Pro closes. The next Run Locally fails with "port already in use." Fix: `lsof -ti :8081 | xargs kill -9` in `restart-sp.sh` only, not in exec.sh automatically.
2. **`$(pwd)` path breaks when invoked from a different cwd.** Fix: anchor with `${BASH_SOURCE[0]}` so the path is always relative to the script file.
3. **`mxcli check` does not catch BSON corruption.** It validates MDL grammar only. The only reliable gate is running the real mxbuild binary after exec — see gate below.
4. **MCP writes lost on snapshot restore.** If mxbuild fails and exec.sh auto-restores from snapshot, any MCP work done since the last `git commit` is silently lost. The uncommitted-MPR guard prevents this by refusing to exec while uncommitted changes exist.

### SP Lifecycle Rule — never auto-restart SP

**Never** `pkill` Studio Pro or `open -a` it automatically from exec.sh. This was learned after auto-restart caused stale lock files, version-selector dialogs, and "cannot open files in the data format" errors on macOS in certain environments. Instead: exec.sh prints a message and waits for the user to close and reopen SP manually. Only `restart-sp.sh` kills/reopens SP, and only when the user explicitly asks for it.

### Template — copy into each project's `bin/exec.sh`

```bash
#!/usr/bin/env bash
# exec.sh — snapshot → exec → mxbuild gate → tell user to reopen SP
# Usage: ./bin/exec.sh <script.mdl>
# Override: FORCE_EXEC=1 ./bin/exec.sh <script.mdl>  (skips the guards — use only if you know why)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MPR="$PROJECT_ROOT/MyProject.mpr"                        # ← change to project MPR name
MXBUILD="/Applications/Mendix Studio Pro X.Y.Z.app/Contents/modeler/mxbuild"  # ← change version
SCRIPT="$1"
FORCE="${FORCE_EXEC:-0}"
LOCK="$PROJECT_ROOT/.mpr-snapshots/.exec.lock"
mkdir -p "$(dirname "$LOCK")"

if [[ -z "$SCRIPT" ]]; then
  echo "Usage: ./bin/exec.sh <script.mdl>"
  exit 1
fi

cd "$PROJECT_ROOT"

# Guard 1: SP must not have the project open (split-brain = data loss).
# SP writes <mpr>.lock = {"SessionId":...,"ProcessId":N} while the project is open.
# Refuse only if that PID is actually alive, so a stale lock never blocks forever.
if [[ -f "$MPR.lock" ]]; then
  SP_PID=$(grep -oE '"ProcessId":[0-9]+' "$MPR.lock" 2>/dev/null | grep -oE '[0-9]+' || true)
  if [[ -n "$SP_PID" ]] && kill -0 "$SP_PID" 2>/dev/null; then
    echo "✗ Studio Pro has the project open (PID $SP_PID) — refusing exec (split-brain risk)."
    echo "  → Close the project in Studio Pro, then re-run."
    echo "    Override (NOT recommended): FORCE_EXEC=1 ./bin/exec.sh $SCRIPT"
    [[ "$FORCE" == "1" ]] || exit 1
    echo "  (FORCE_EXEC set — proceeding despite open SP)"
  elif [[ -n "$SP_PID" ]]; then
    echo "  (stale $MPR.lock from dead PID $SP_PID — SP not actually open, proceeding)"
  fi
fi

# Guard 2: No other exec.sh already running (e.g. a second agent session).
if [[ -f "$LOCK" ]]; then
  OTHER=$(cat "$LOCK" 2>/dev/null || true)
  if [[ -n "$OTHER" ]] && kill -0 "$OTHER" 2>/dev/null; then
    echo "✗ Another exec is running (PID $OTHER) — refusing concurrent write."
    echo "  → Wait for it to finish. If it's stale (process dead): rm '$LOCK'"
    exit 1
  fi
fi

# Guard 3: No stray raw `mxcli exec` from another session.
if pgrep -fl "mxcli exec" 2>/dev/null | grep -qv "$$"; then
  echo "✗ A raw 'mxcli exec' is already running elsewhere — refusing to write concurrently."
  [[ "$FORCE" == "1" ]] || exit 1
fi

# Guard 4: Uncommitted MPR changes — prevents silent loss if mxbuild fails and restores.
# The snapshot below will not cover uncommitted MCP work; an auto-restore would wipe it.
MPR_DIRTY=$(git status --porcelain MyProject.mpr mprcontents/ 2>/dev/null | grep -v "^$" || true)
if [[ -n "$MPR_DIRTY" ]]; then
  echo "✗ Uncommitted MPR changes detected — refusing exec to prevent snapshot regression."
  echo ""
  echo "  If you did MCP work, commit it first:"
  echo "    git add MyProject.mpr mprcontents/ && git commit -m 'Commit MCP changes before exec'"
  echo "  Then re-run: ./bin/exec.sh $SCRIPT"
  echo ""
  echo "  Override (accepts silent-loss risk): FORCE_EXEC=1 ./bin/exec.sh $SCRIPT"
  [[ "$FORCE" == "1" ]] || exit 1
fi

echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

echo "→ Snapshotting MPR..."
./bin/snapshot-mpr.sh

echo "→ Executing $SCRIPT..."
./mxcli exec "$SCRIPT" -p "$MPR"

echo ""
echo "→ Running mxbuild model check (catches BSON corruption before SP opens)..."
JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null || true)
JAVA_EXE="${JAVA_HOME}/bin/java"

if [[ -x "$MXBUILD" && -x "$JAVA_EXE" ]]; then
  ERRORS_FILE=$(mktemp /tmp/mxbuild-errors.XXXXXX)
  # --target=deploy (lowercase, required by mxbuild v11).
  # --write-errors writes the file ONLY when errors exist; absence = clean.
  MXBUILD_OUT=$("$MXBUILD" \
    --java-home="$JAVA_HOME" \
    --java-exe-path="$JAVA_EXE" \
    --write-errors="$ERRORS_FILE" \
    --target=deploy \
    "$MPR" 2>&1) || true
  MXBUILD_EXIT=${PIPESTATUS[0]:-$?}

  if [[ -f "$ERRORS_FILE" && -s "$ERRORS_FILE" ]]; then
    # Errors file written → model has CE errors → restore and stop.
    CE_COUNT=$(python3 -c "import json; d=json.load(open('$ERRORS_FILE')); print(len([x for x in d.get('problems',[]) if x.get('severity')=='Error']))" 2>/dev/null || echo "?")
    echo "  ✗ mxbuild: $CE_COUNT error(s) found — restoring snapshot to avoid loading a corrupt MPR."
    # Restore from the snapshot taken BEFORE this exec (second-newest, since snapshot ran first).
    PREV_SNAP=$(ls -dt "$PROJECT_ROOT/.mpr-snapshots"/[0-9]*/ 2>/dev/null | head -2 | tail -1)
    if [[ -n "$PREV_SNAP" && -f "$PREV_SNAP/MyProject.mpr" ]]; then
      cp "$PREV_SNAP/MyProject.mpr" "$MPR"
      rm -rf mprcontents && cp -r "$PREV_SNAP/mprcontents" mprcontents
      echo "  → Auto-restored from: $PREV_SNAP"
    fi
    python3 -c "import json; d=json.load(open('$ERRORS_FILE')); [print(' ', e.get('errorCode','?'), e.get('message','')) for e in d.get('problems',[]) if e.get('severity')=='Error']" 2>/dev/null || true
    cp "$ERRORS_FILE" "$PROJECT_ROOT/.mpr-snapshots/last-mxbuild-errors.json"
    echo "  → Full error detail (untruncated): .mpr-snapshots/last-mxbuild-errors.json"
    rm -f "$ERRORS_FILE"
    exit 1
  elif [[ "$MXBUILD_EXIT" -ne 0 ]]; then
    # Non-zero exit but NO errors file → mxbuild itself failed (bad args, JVM crash, …).
    # Do NOT treat as clean — the gate could not verify the model.
    echo "  ✗ mxbuild failed to run (exit $MXBUILD_EXIT) — gate could not verify the model."
    echo "$MXBUILD_OUT" | grep -v "^$\|icon\|Assembly\|__" | head -20 || true
    echo "  → Snapshot preserved. Open in SP to verify manually before proceeding."
    rm -f "$ERRORS_FILE"
    exit 1
  else
    # Exit 0, no errors file → model is clean.
    echo "  ✓ mxbuild: 0 errors — model is clean."
  fi
  rm -f "$ERRORS_FILE"
else
  echo "  ✗ mxbuild or java not found — gate skipped. Verify in SP before proceeding."
fi

echo ""
echo "✓ Script applied to MPR."
echo "  ⚠️  Please close the project in Studio Pro, reopen it, then click Run Locally."
echo "  If SP is not open: open Version Selector → select your version → open the project."
```

> **The two mxbuild failure modes are distinct — both must stop the build.** `--write-errors`
> writes the file *only when the model has consistency errors*, so its absence normally means
> "clean." But mxbuild can also exit non-zero **without** writing that file — bad arguments, a JVM
> crash, a missing Java home. An earlier version treated that second case as a pass (no errors file
> ⇒ "clean") and let an unverified model through. The gate must branch on the exit code as well:
> errors-file → restore + stop; non-zero-exit-no-file → preserve snapshot + stop; exit-0-no-file →
> clean.

### Standalone SP restart — `bin/restart-sp.sh`

Only run this when the user explicitly asks to restart SP. Invoke the binary directly — `open -a` can trigger macOS's file-association picker in some environments:

```bash
#!/usr/bin/env bash
# restart-sp.sh — kill runtime + SP, then reopen. Use only when explicitly asked.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MPR="$PROJECT_ROOT/MyProject.mpr"
SP_APP="Mendix Studio Pro X.Y.Z"           # ← exact name as in /Applications/

lsof -ti :8081 | xargs kill -9 2>/dev/null || true
pkill -9 -f "Contents/MacOS/studiopro" 2>/dev/null || true
sleep 2
rm -f "$MPR.lock"
# Invoke binary directly — avoids macOS file-association picker (BUG-LOCAL-03)
"/Applications/$SP_APP.app/Contents/MacOS/studiopro" "$MPR" &
echo "✓ SP restarting — click Run Locally when it finishes loading."
```

### Pre-exec sequence when MCP work was done

Before running exec.sh after any MCP session:

```
1. Cmd+S in Studio Pro (or run save-sp.sh)
2. git add MyProject.mpr mprcontents/ && git commit -m "Commit MCP changes before exec"
3. Close the project in Studio Pro
4. ./bin/exec.sh mdlsource/my-script.mdl
```

Step 3 is required — exec.sh refuses if SP has the project open.

### Per-project setup checklist

- [ ] Copy `bin/exec.sh` into the project; update `MPR`, `MXBUILD`, and the porcelain git path variables
- [ ] Copy `bin/snapshot-mpr.sh` and `bin/restore-mpr.sh` — snapshot must cover both `.mpr` AND `mprcontents/`
- [ ] Copy `bin/restart-sp.sh`; update the app name and MPR name
- [ ] Copy `bin/save-sp.sh` (MCP save trigger)
- [ ] `chmod +x bin/exec.sh bin/restart-sp.sh bin/snapshot-mpr.sh bin/restore-mpr.sh bin/save-sp.sh`
- [ ] Add `.mpr-snapshots/` to `.gitignore` (snapshot scripts use this directory — do not also create `build/snapshots/`)
- [ ] Add rule to `CLAUDE.md`: the uncommitted-MPR guard — required sequence before any exec
- [ ] Add rule to `CLAUDE.md`: never auto-restart SP; always tell the user to close and reopen manually

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
    This runs **automatically inside `bin/exec.sh`** — the local `mxbuild` binary compiles the MPR
    with `--target=deploy --write-errors` right after `mxcli exec`, and auto-restores the pre-exec
    snapshot on any error (see the exec.sh template above). You do not run a separate command; a
    clean exec.sh run *is* Gate 2 passing. `mxbuild` (Studio Pro's own compiler) is the reliable
    gate because `mxcli check` validates MDL grammar only and does **not** catch BSON corruption.

      - **Why the binary, not `mxcli docker check`:** the direct-binary path proved more reliable in
        practice — no per-machine `mxcli setup mxbuild` step, no Linux CDN binary that silently can't
        load `mprcontents/`, no `--no-update-widgets` crash. `docker check` remains a valid
        alternative for CI / non-macOS runners where the local Studio Pro binary isn't installed.
      - CE0066 alone = **conditional pass**: only Studio Pro can recompute the security hash.
        Open Studio Pro, open the affected domain model, click "Update security", Cmd+S. (mxbuild may
        keep reporting CE0066 until SP recomputes it — do not block the build on CE0066 alone.)
      - **Fallback if the mxbuild binary can't run** (not found, JVM error): exec.sh preserves the
        snapshot and exits non-zero rather than passing. Verify manually — open Studio Pro and check
        the project loads cleanly:
        ```bash
        open -a "Mendix Studio Pro X.Y.Z" app.mpr   # macOS
        ```
        If SP opens without an error dialog → gate passes. If it shows `AggregateException`,
        `KeyNotFoundException`, or `AttributeIdentifier` errors → restore snapshot immediately.
        **This fallback is mandatory — never mark a script DONE without Gate 2 passing.**
9.  **Grant completeness check (mandatory before happy-path):** for every page and microflow built in this phase, verify grants exist for the module roles that compose each user role. Run:
    ```
    show user roles;
    show security matrix in Module;
    show access on page Module.PageName;
    show access on microflow Module.MFName;
    ```
    For each user role, trace which module roles it composes (`show user roles`), then confirm those module roles appear in the access list of every element that user role needs to reach. A page or microflow with no grants shows a blank result — fix before proceeding. The demo user is only the login vehicle; the access check is on module roles, not the demo user account. mxbuild will not catch missing grants; only the running app reveals them otherwise.
10. If GRANT scripts were applied → Studio Pro "Update security" → Cmd+S
11. **Update the project's progress tracker** (e.g. `MIGRATION-PROGRESS.md` or equivalent) —
    mark this script/module as built and gate-verified, right after Gate 2 passes and Studio Pro
    is confirmed to open/run without errors. Do this BEFORE the testing steps below — a build that
    passed its gate is progress worth recording even if testing hasn't run yet; don't let the two
    get conflated or let tracker updates wait on a separate testing pass.
12. Walk the happy path as a non-admin demo user:
      - After exec.sh completes, tell the user to close and reopen the project in SP, then Run Locally
      - Wait for the user to confirm SP is running — never assume
      - Confirm the app is actually serving the new build: `curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login.html` → `200`. The browser shows the old JS bundle until SP recompiles; screenshots taken before this check show stale state.
      - Log in as demo user (not Administrator)
      - **Navigate by clicking the nav item / button — not a direct URL** (this exercises real navigation; an overlay or stray toggle can silently swallow every click on one page)
      - Fill minimum required fields
      - Click save / next
      - Confirm record created or navigation succeeded — **and confirm the demo user actually reached the page** (a blank screen or unclickable nav is a failure, not a pass)
13. **Gate 4 — UI review loop (mandatory, per module):** run `ui-review-loop.md` scoped to the pages this module built. This is not "take a screenshot" — it is the functional + visual verification that mxbuild and "record created" cannot do. At minimum, for each page this module added:
      - **Every displayed field shows its value** — especially DateTime/enum/calculated fields. A blank where data must exist (e.g. a system `createdDate`) is a render bug (P1), not missing data — confirm the binding in MDL, then treat a persistent blank as a finding.
      - **Every grid/gallery** shows rows or a proper empty-state message — never nothing.
      - **Every action/View button** points at the *current* page, not a superseded one (`DESCRIBE PAGE`).
      - **Required-field validation surfaces a visible message** — a silent 4xx/5xx save is a P1.
      - **Built StyleGallery components are actually used** on this page (badges/steppers/empty-states), not reimplemented as plain text.
      - **Wireframe-vs-live** compare where a wireframe exists; degrade loudly (log it) where one doesn't — see the review loop's degradation table.
      Diagnostic only: findings go to the punch-list, fixes are a separate approved pass.
14. **Gate 3 — business-rule coverage checklist (mandatory, never skip):** `gate-agent` walks the confirmed checklist from the Pre-Module Checklist step — every mandatory/read-only/conditional/validation item — against the built module, item by item. A module with 0 CE errors and a working happy path but an unchecked validation rule is **not done**. Document any gap as an explicit sub-task; don't mark the module done with open items on this list.
15. Mark module done ✅ — only if Gate 4's per-module review produced no open P1.
```

Steps 8–14 are the phase gate. Steps 1–7 without 8–14 = page may be built but wrong. Step 9 (grant completeness) and Step 13 (UI review loop) are the two checks mxbuild is blind to — a missing grant and a blank-rendering field both pass mxbuild silently. Step 14 specifically closes the gap `process-learnings.md` §C flagged and left open ("who owns the coverage checklist review?") — `gate-agent` does, as part of the same gate pass as Gate 2, not a separate optional step.

### Trivial-change fast path (don't run the full loop on a mechanical script)

The full 15-step loop is for a build unit that adds/alters a **rendered or user-facing surface** — a
page, widget, or a microflow a user triggers. A genuinely mechanical script has no such surface and
does not need the UI passes:

| Change | Skip | Still required |
|--------|------|----------------|
| Forward-reference stub, added enum value, rename, constant, a pure domain-attribute add with no page | Steps 12–13 (happy-path walk, UI review loop) — nothing renders to verify | `learned-mdl-preflight.md` STOP check · `mxcli check` · **Gate 2 mxbuild** (never skip) · grant completeness (Step 9) if it added a grantable element |

**The line:** anything that adds or changes a page, a widget, or a microflow a user can invoke is
**not** trivial — run the full loop. When unsure, treat it as full-discipline. This fast path exists
to stop the review machinery from taxing genuinely invisible changes, not to let UI work skip
verification. The mdl-agent applies the same rule (see its "Trivial-change fast path").

---

## Script Conventions

### Numbering and versioning

- Scripts are numbered sequentially: `01-module-domain.mdl`, `02-stubs.mdl`, `03-microflows.mdl`, ...
- Once a script has been executed against the MPR it is **frozen** — never edit it
- For fixes: write a new numbered script (`create or replace` / `create or modify`)
- The MPR is the source of truth; scripts are the historical audit trail

### Superseding a page (repoint every caller, then retire the old one)

When a new, wireframe-aligned page replaces an earlier one (common when an early build script made a
rough page before the wireframe existed), the replacement is not done until **every caller is
repointed and the old page is retired.** A page is reached from many places — overview-grid row
buttons, other pages' action buttons, microflow `Show page` activities, navigation items. Repointing
only the one you were looking at leaves the rest opening the dead page (a real WMS P1: the Orders
grid's "View" still opened the superseded detail page while the home dashboard's button opened the
new one).

Procedure:
1. Find every caller: `grep` the MDL for the old page name; check `DESCRIBE PAGE` on caller pages and
   `DESCRIBE MICROFLOW` for `Show page` activities; check navigation.
2. Repoint each to the new page.
3. Delete the old page (or, if kept temporarily, mark it dead and confirm nothing references it).
4. The Stage-6 `ba-agent` cross-check flags any page with no callers as a suspected dead page —
   don't ship those.

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
   click the "Update security" banner, Cmd+S, then re-run the exec.sh mxbuild gate. Do not block
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
