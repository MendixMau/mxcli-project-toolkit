# Iterative Build Loop — BRD to Running Mendix App
**Applies to:** any mxcli project (migration and greenfield alike).
**Requires:** bash and Python 3 — this skill runs toolkit shell scripts. Run `bin/doctor.sh` once on a new machine; it names anything missing and how to get it. Windows: use Git Bash, and see the Prerequisites section of `conversion-runbook.md`.
**Purpose:** Per-module build discipline for mxcli-assisted Mendix development. Replaces bulk MDL generation with a verified, iterative gate per module.
**Companion skills:** `brd-to-build-plan.md` (upstream — produces the plan this loop executes), `migration-pipeline.md`, `conversion-runbook.md` (Stage 5 — where the coverage checklist below gets confirmed with the user, not just self-extracted), `mdl-cookbook-microflows.md`, `bug-logs/mxcli-bugs.md`

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
4. The module's **business-rule coverage checklist** passes — not just extracted, but confirmed with the user at Stage 5 kickoff (`conversion-runbook.md`) as the actual definition of "done," and verified by `gate-agent` alongside Gate: BUILD, not left as a step someone might skip under time pressure.

A page with a stub banner and no data below it is a missing feature, not a stub. **CE-error-free ≠ done — the coverage checklist is what "done" means.**

**Corollary — MDL is drafted just-in-time, never stockpiled.** Scripts for phase N are written only
after phase N−1 has passed this gate. A backlog of pre-written, never-executed scripts is a defect,
not a head start: each one encodes assumptions about a model state that the intervening gates may
have changed (see `brd-to-build-plan.md`, "The build plan contains no MDL").

### Marking a script DONE (completed-implemented-tested)

Once — and only once — a script has passed the **full** gate above (0 CE / mxbuild-clean **+** happy-path verified **+** coverage checklist), rename it with a `done-` filename prefix so the working set always shows *what's left to build*:

```
git mv mdlsource/<NN-name>.mdl mdlsource/done-<NN-name>.mdl
```

- **A script named `<NN-name>.mdl` = still pending or in-flight. A script named `done-<NN-name>.mdl` = executed, mxbuild-clean, and verified.** The filename itself is the "which MDL is finished" signal (no separate folder); git commits per phase remain the authoritative history.
- Rename in the **same commit** as the phase gate pass (so "done" and "committed" are atomic).
- The file stays in place and re-runnable — if a later phase invalidates it, rename back (drop the `done-` prefix), fix, re-exec, re-done.
- Do **not** rename a script that only passed `mxcli check` or only exec'd without the happy-path/coverage check — `done-` means the *feature* works, not just that the MDL ran (mirrors the Core Principle: CE-error-free ≠ done).

`build-plan.html` phase status and the `done-` prefixes should agree — when every script for a phase is `done-`, that phase flips to ✓ in the tracker.

### Reopening Studio Pro and proposing to run the app

**An `mxcli` write never reaches a *running* Studio Pro.** SP holds the model in memory, so until it reopens, the change exists on disk and nowhere the user can see. That makes the reopen part of the gate, not an afterthought — and it is the step that turns "the MDL ran" into "the feature works," which the DONE rule above already insists on.

`project-bin/exec.sh` closes this automatically on gate pass:

| `SP_RESTART` | Behaviour |
|---|---|
| `1` | reopen without asking — agent turns, CI, chained scripts |
| `0` | print the hint only (pre-2026-08-11 behaviour) |
| unset | prompt when interactive; print the hint when there is no TTY |

It delegates to `restart-sp.sh`, which targets **only** the SP holding this project's `.mpr` (via `lsof`) — two projects open at once is normal, and killing the wrong one loses unsaved work. Defaults are conservative: no TTY means nothing is touched.

**Never end a build turn with "Studio Pro needs a restart" as a note for the user to action** — offer it, and on a yes, do it.

Two mechanics worth knowing before automating this yourself:

- **A synthesized `Cmd+Q` does not register on Studio Pro.** Use `osascript -e 'tell application "Mendix Studio Pro <version>" to quit'`; SP then releases its own lock file cleanly. Verify with `pgrep -f studiopro` and confirm `*.mpr.lock` is gone **before** any mxcli write — the standing rule that mxcli must never touch a `.mpr` while SP has it open applies to reads too.
- `restart-sp.sh` prompts for confirmation by default; pass `AUTO_SP=1` when calling it from a script or an agent turn, which cannot answer it.

The loop, end to end: **close SP → exec → gate → `done-` rename → reopen SP → propose Run Locally.**

---

## Requirements Drift-Sync Rule — BRDs stay live, not just historical

BRDs (`analysis/knowledge-base/brd/*.brd.json` or the project's equivalent) are the source of truth
every downstream stage reads from — `mdl-agent` synthesizes scripts from them, `gate-agent` checks
coverage against them, a future `ba-agent` module-brief pass inherits whatever they say. `PROJECT.md`'s
Decisions table is an **append-only log** of what was decided and why — it is not itself the current
definition of behavior. If a later-stage decision (an architecture refinement, a build-time judgment
call, a bug found mid-scripting) changes what a BRD asserts and the BRD is never updated, the two
diverge silently. Nobody notices until a future agent reads the stale BRD and inherits a wrong
assumption.

**Trigger — sync immediately, same session, when a confirmed decision does any of:**
- Resolves or contradicts an `openQuestions` entry already recorded in a BRD
- Changes the documented `purpose`, `returns`, `notes`, or `validations` of a microflow/page a BRD
  already specs
- Adds or changes a business rule a BRD's behavior section already encodes

**Do not trigger** for decisions a BRD never made a claim about (internal naming, layout choice, an
enum's internal value set) — there's nothing to drift, and syncing anyway is noise.

**Wireframes follow the same trigger, filtered further:** only re-render a wireframe when the decision
changes something visually observable (new field, new button, changed flow, different state/color) —
not for logic/microflow changes invisible in the UI.

**Mechanism:** whichever agent confirms the decision (`ba-agent`, `architect-agent`, `mdl-agent`,
`gate-agent`) names which BRD/wireframe file(s) the decision touches at the moment it logs the
decision to `PROJECT.md`. If none, say so explicitly ("no BRD touched — internal/architectural only")
— a conscious skip, not a silent one.

**Marker convention + enforcement** (ownership and cadence live in `conversion-runbook.md` §3b):
tag the decision's `PROJECT.md` Notes cell `[sync: <files> UNSYNCED]` when it's pending, and `ba-agent`
flips it to `[sync: <files> synced <YYYY-MM-DD>]` after re-syncing. `bin/gate-check.sh` greps for the
`UNSYNCED` marker and **blocks every stage gate** until it's flushed — this is the mechanical backstop
that makes the rule stick, not just this prose. `[sync: none]` records a conscious "nothing to sync".

**Don't batch by a fixed count** ("sync every N decisions"). The cost that matters is the drift
*window*, not the sync *frequency* — a stale BRD sitting for "N more decisions" is exactly how drift
becomes invisible. The actual sync is usually a small, targeted diff (one purpose string, one
validations entry, one openQuestions status flip) — cheap enough to do the moment the decision lands.

This rule closes a real gap: nothing in the stage-forward pipeline (BRD → architecture → build)
naturally flows *backward* when a later stage changes something an earlier BRD claimed. It was
written after live drift was found on a real project (a PLM parts-flow project, 2026-07-21): a Stage-3
workflow refinement changed a microflow's query behavior and added a new validation, but the BRD
still had the old (wrong) description and two already-resolved open questions still marked "Open."

---

## Pre-Module Checklist (before writing any MDL)

> **Live visibility rule:** the moment this checklist is confirmed, post it — plus the build
> sequence below — in the chat with status marks, and keep it updated as each item lands. See
> `conversion-runbook.md` §1b (Live Checklist Protocol). The user must never have to ask
> "what are we doing right now?" mid-module.

Run this before scripting each module:

- [ ] **Module brief exists and passes its ready-check.** `architecture/modules/<Module>/module-brief.md` must exist (authored by `ba-agent` translation mode, per `module-brief.md`) with every ready-check box ticked: every screen has a wireframe, the access table covers every element, no open business question blocks this phase, write mode chosen for every STOP-row element. **No brief, or an unchecked ready-check item touching this phase → STOP.** Produce/complete the brief first — do not let the `mdl-agent` synthesize the module from raw BRDs. This is the just-in-time gate: mechanical `gate-check.sh` cannot enforce it (briefs don't all exist at Stage 4), so it is enforced here, manually, per module.
- [ ] Read source screenshots for this module top-to-bottom
- [ ] Read the feature doc (F-doc or BRD) for this module
- [ ] Extract the build checklist from the feature doc:
  - **Mandatory fields** → widget `Required` settings
  - **System-derived / read-only fields** → `Editable: Never`
  - **Conditional visibility** → container `Visible` expressions
  - **Validation rules** → `VAL_` microflows to implement **and a visible validation message on the page** — the rule firing server-side is not enough; the user must see why a save failed (a silent 4xx/5xx is a P1 in the UI review loop)
  - **Enumerations / lookups** → correct widget type (combobox, radiobuttons) — set from the start, not patched later
- [ ] **Confirm this checklist with the user before scripting, not after.** This is the per-module business-rule coverage checklist `conversion-runbook.md` Stage 5 asks the user to confirm — the item that decides whether the module is actually done. `ba-agent` owns getting the confirmation; `gate-agent` owns verifying it was met, alongside Gate: BUILD (below), before the module is marked done. A checklist nobody signed off on is just a private To-Do — it doesn't count as the definition of done.
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

The two scripts above are printed to show what they do. **`project-bin/snapshot-mpr.sh` and
`project-bin/restore-mpr.sh` are the authoritative copies** — install them with
`bin/init-project.sh` rather than pasting from here.

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

### There is no template to copy — `bin/init-project.sh` installs the real one

**The script lives at `project-bin/exec.sh` in this toolkit, and that copy is the only one.**
`bin/init-project.sh` installs it (with `_common.sh`, `snapshot-mpr.sh`, `restore-mpr.sh`,
`restart-sp.sh`, `save-sp.sh`) into the project's `bin/`. Do not hand-write one, and do not paste
one out of a document.

This section used to carry a 130-line copy of that script, and the copy is what broke:

- Its gate branched on `[[ -f "$ERRORS_FILE" && -s "$ERRORS_FILE" ]]`. But `--write-errors` writes
  the file **always** — `{"problems":[]}` on success, which is non-empty — so a *clean* build took
  the restore branch, printed `✗ mxbuild: 0 error(s) found — restoring snapshot`, exited 1, and
  rolled back good work. The `else` branch commented "Exit 0, no errors file → model is clean" was
  unreachable in the normal case.
- `project-bin/exec.sh` had the correct `CE_COUNT = 0` test from 2026-07-29. The fix reached the
  shipped script and never reached the document people paste from, and the broken copy was the
  authoritative-looking one.
- The same drift hit the SP-reopen logic: `fcf5ad0` taught `project-bin/exec.sh` to reopen Studio
  Pro, while the copy here still ended with "Please close the project in Studio Pro" — the exact
  line that commit was written to delete.

Two copies of a 140-line script is the numbering bug with a bigger blast radius. Read
`project-bin/exec.sh` when you need the detail; what follows is what the script guarantees, which
is the part worth stating twice.

**Gate invariants — true of `project-bin/exec.sh`, and the acceptance criteria for any change to it:**

| Invariant | Why |
|---|---|
| Branch on the **parsed error count**, never on the errors file's existence or size | `--write-errors` writes `{"problems":[]}` on success; "file is non-empty" reports every clean build as broken |
| `mxbuild` exit ≠ 0 **with no errors file** is a distinct failure — bad args, JVM crash, missing Java home | Treating it as "no file ⇒ clean" lets an unverified model through |
| `mxcli exec`'s status is **captured**, never allowed to trip `set -e` | mxcli is not transactional across statements; aborting skips the gate, the restore and the log while partial changes are already live |
| The pre-exec `mxcli check … --references` runs **before** the snapshot | The only gate that can reject a script before it mutates the `.mpr` |
| Every outcome writes exactly one build-log row, carrying an ISO-8601 stamp and an explicit gate verdict | A clean build that logs nothing makes "no row" mean nothing at all — see the build log section below |
| `last-mxbuild-errors.json` is cleared at the **start** of a run, not on success | An interrupted run must not leave a previous failure's file looking like its own report |
| Studio Pro is never auto-killed; the reopen is offered, then done on a yes | See the SP Lifecycle Rule above |

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

- [ ] Run `bin/init-project.sh <project-root>` — it installs `exec.sh`, `_common.sh`,
      `snapshot-mpr.sh`, `restore-mpr.sh`, `restart-sp.sh` and `save-sp.sh` from `project-bin/`,
      already executable and with nothing to edit: the `.mpr`, the Studio Pro version and the
      mxbuild path are all discovered at runtime by `_common.sh`
- [ ] Confirm `bin/exec.sh` really came from `project-bin/` (`diff` them). `init-project.sh`
      deliberately never overwrites an existing `bin/exec.sh`, so a project initialised months ago
      is frozen at whatever the template was that day — every hand-edited copy found so far was
      strictly older and missing a fix
- [ ] Add `.mpr-snapshots/` to `.gitignore` (snapshot scripts use this directory — do not also create `build/snapshots/`)
- [ ] Add rule to `CLAUDE.md`: the uncommitted-MPR guard — required sequence before any exec
- [ ] Add rule to `CLAUDE.md`: never auto-restart SP; always tell the user to close and reopen manually

---

## The Build Loop

Repeat for each module. **This is a list, not a code block** — it was fenced for most of its life,
which is why nobody saw that its steps and its gates had drifted out of order. Gates are named, not
numbered: a gate inserted in the middle used to leave every ordinal behind it wrong, silently.

1.  Read source screenshots top-to-bottom (not the data model outward)
2.  Read feature doc section for this module
3.  Extract build checklist (mandatory, read-only, conditional, validation)
4.  Sketch page data-view nesting → derive microflow signatures
5.  Create stub pages/microflows for any forward references (separate script, apply first)
6.  **Gate: SYNTAX — `mxcli check --references` (mandatory, never skip):**
    Runs **inside `bin/exec.sh`**, before the snapshot and before `mxcli exec`, on every apply in
    the steps below. You do not run it as a separate command; `SKIP_CHECK=1` disables it and needs
    a reason written down.

    It is the **only** gate that can reject a script *before* it mutates the `.mpr`. Everything
    after it recovers by snapshot-restore, which is a rollback, not a prevention. For most of this
    loop's life the discipline was mandated in prose and enforced nowhere — `exec.sh` went
    snapshot → exec → mxbuild — so a reference error `mxcli check` catches in two seconds instead
    reached `exec`, mutated the model, and cost a full restore cycle.

    It validates MDL grammar and references only. It does **not** catch BSON corruption; that is
    Gate: BUILD's job, and neither substitutes for the other.
7.  Write + apply microflows
8.  Write + apply pages (following screenshot top-to-bottom)
9.  **Gate: BUILD — mxbuild / BSON validation (mandatory, never skip):**
    This runs **automatically inside `bin/exec.sh`** — the local `mxbuild` binary compiles the MPR
    with `--target=deploy --write-errors` right after `mxcli exec`, and auto-restores the pre-exec
    snapshot on any *new* error. You do not run a separate command; a clean exec.sh run *is*
    Gate: BUILD passing. `mxbuild` (Studio Pro's own compiler) is the reliable gate because
    `mxcli check` validates MDL grammar only and does **not** catch BSON corruption.

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
        **This fallback is mandatory — never mark a script DONE without Gate: BUILD passing.**
      - **Read the verdict, not the exit code.** Every run appends one row to `docs/BUILD-LOG.md`
        with an ISO-8601 stamp and a `gate` cell: `pass` · `fail` · `skipped` · `unverified` ·
        `not-run`. Only `pass` means anything looked at the model. Full error detail for the most
        recent *failing* run is at `.mpr-snapshots/last-mxbuild-errors.json`, which is cleared at
        the start of every run — if it is absent, this run did not fail, and if it is present it
        belongs to this run and no other.
10. **Grant completeness check (mandatory before happy-path):** for every page and microflow built in this phase, verify grants exist for the module roles that compose each user role. Run:

    ```
    show user roles;
    show security matrix in Module;
    show access on page Module.PageName;
    show access on microflow Module.MFName;
    ```

    For each user role, trace which module roles it composes (`show user roles`), then confirm those module roles appear in the access list of every element that user role needs to reach. A page or microflow with no grants shows a blank result — fix before proceeding. The demo user is only the login vehicle; the access check is on module roles, not the demo user account. mxbuild will not catch missing grants; only the running app reveals them otherwise.
11. If GRANT scripts were applied → Studio Pro "Update security" → Cmd+S
12. **Update the project's progress tracker** (e.g. `MIGRATION-PROGRESS.md` or equivalent) —
    mark this script/module as built and gate-verified, right after Gate: BUILD passes and Studio Pro
    is confirmed to open/run without errors. Do this BEFORE the testing steps below — a build that
    passed its gate is progress worth recording even if testing hasn't run yet; don't let the two
    get conflated or let tracker updates wait on a separate testing pass.
13. Walk the happy path as a non-admin demo user:
      - After exec.sh completes, tell the user to close and reopen the project in SP, then Run Locally
      - Wait for the user to confirm SP is running — never assume
      - Confirm the app is actually serving the new build: `curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login.html` → `200`. The browser shows the old JS bundle until SP recompiles; screenshots taken before this check show stale state.
      - Log in as demo user (not Administrator)
      - **Navigate by clicking the nav item / button — not a direct URL** (this exercises real navigation; an overlay or stray toggle can silently swallow every click on one page)
      - Fill minimum required fields
      - Click save / next
      - Confirm record created or navigation succeeded — **and confirm the demo user actually reached the page** (a blank screen or unclickable nav is a failure, not a pass)
14. **Gate: UI — the review loop (mandatory, per module):** run `ui-review-loop.md` scoped to the pages this module built. This is not "take a screenshot" — it is the functional + visual verification that mxbuild and "record created" cannot do. At minimum, for each page this module added:
      - **Every displayed field shows its value** — especially DateTime/enum/calculated fields. A blank where data must exist (e.g. a system `createdDate`) is a render bug (P1), not missing data — confirm the binding in MDL, then treat a persistent blank as a finding.
      - **Every grid/gallery** shows rows or a proper empty-state message — never nothing.
      - **Every action/View button** points at the *current* page, not a superseded one (`DESCRIBE PAGE`).
      - **Required-field validation surfaces a visible message** — a silent 4xx/5xx save is a P1.
      - **Built StyleGallery components are actually used** on this page (badges/steppers/empty-states), not reimplemented as plain text.
      - **Wireframe-vs-live** compare where a wireframe exists; degrade loudly (log it) where one doesn't — see the review loop's degradation table.

      Diagnostic only: findings go to the punch-list, fixes are a separate approved pass.
15. **Gate: COVERAGE — business-rule coverage checklist (mandatory, never skip):** `gate-agent` walks the confirmed checklist from the Pre-Module Checklist step — every mandatory/read-only/conditional/validation item — against the built module, item by item. A module with 0 CE errors and a working happy path but an unchecked validation rule is **not done**. Document any gap as an explicit sub-task; don't mark the module done with open items on this list.
16. Mark module done ✅ — only if Gate: UI's per-module review produced no open P1.

Everything from Gate: SYNTAX onward is the phase gate; the writing steps without it mean the page
may be built and still wrong. **Grant completeness (step 10) and Gate: UI are the two checks mxbuild
is blind to** — a missing grant and a blank-rendering field both pass mxbuild silently. Gate:
COVERAGE closes the gap `process-learnings.md` §C flagged and left open ("who owns the coverage
checklist review?") — `gate-agent` does, in the same pass as Gate: BUILD, not as a separate optional
step.

> **Older ordinals, for anyone arriving from a document that still cites them:** Gate 2 = Gate:
> BUILD, Gate 3 = Gate: COVERAGE, Gate 4 = Gate: UI. There was never a Gate 1 — the pre-exec
> `mxcli check` was the unwritten first gate, which is why the numbering started at 2, and it is
> now Gate: SYNTAX and actually enforced. The ordinals are retired: they ran 2 → 4 → 3 in document
> order for months because a gate was inserted in the middle and nothing renumbered.

### Trivial-change fast path (don't run the full loop on a mechanical script)

The full loop is for a build unit that adds/alters a **rendered or user-facing surface** — a
page, widget, or a microflow a user triggers. A genuinely mechanical script has no such surface and
does not need the UI passes:

| Change | Skip | Still required |
|--------|------|----------------|
| Forward-reference stub, added enum value, rename, constant, a pure domain-attribute add with no page | The happy-path walk and Gate: UI — nothing renders to verify | `learned-mdl-preflight.md` STOP check · **Gate: SYNTAX** and **Gate: BUILD** (never skip either) · grant completeness if it added a grantable element |

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
