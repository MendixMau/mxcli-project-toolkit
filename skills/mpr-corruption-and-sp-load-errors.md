# MPR Corruption & Studio Pro Load Errors — Diagnostic Playbook

Written after a live incident on a Mendix project (2026-07-29) where Studio Pro crashed
mid-MCP-session and then refused to reopen the project. Everything below was actually
executed; the dead ends are recorded as dead ends so they aren't repeated.

**Applies to:** any mxcli/MCP project on Mendix 11.x, macOS.
**Companion:** `learned-mcp-patterns.md`.

---

## The situation this covers

Studio Pro throws a `StorageLoadException` on open and will not load the project.
The model is not readable by SP, but **may still be perfectly readable by mxcli** — that
asymmetry is the main lever for repair, and the reason the situation is recoverable at all.

Typical dialog text:

```
Mendix.Modeler.Storage.StorageLoadException:
One or more invalid values were detected while loading the project:
 - <ElementKind> in  has an invalid value '' for property Attribute.
   The text 'Forms$ConditionalVisibilitySettings' is not a valid AttributeIdentifier.
   at Mendix.Modeler.DomainModels.AttributeIdentifier.FromString(String text)
```

Two things to read out of that message immediately:

1. **The `Forms$…` / `Microflows$…` prefix tells you the document class.** `Forms$` is a page,
   not a microflow. This alone eliminates most of the search space.
2. **An empty name in `"… in ␣ has"` means the parent reference is broken too**, not just the
   leaf property. You are looking for a structurally orphaned element, not a typo.

---

## RULE 1: Get a machine oracle before you touch anything

Do not bisect by repeatedly asking a human to open Studio Pro. Get a scriptable pass/fail:

```bash
cd <project-root>
./mxcli docker check -p <Project>.mpr
```

This runs real mxbuild in a Linux container and reproduces the exact same
`StorageLoadException`. It is the gate to loop against.

⚠️ **`docker check` mutates the model.** Its first phase prints
`Updating widget definitions in <Project>.mpr...`. Snapshot or work on a copy before each run.

### The native `mx` binary does not run on macOS

```
$ ~/.mxcli/mxbuild/11.12.0/modeler/mx check Project.mpr
exec format error
$ file ~/.mxcli/mxbuild/11.12.1/modeler/mx
ELF 64-bit LSB pie executable, ARM aarch64
```

`mxcli setup mxbuild` downloads a **Linux ARM64 ELF**. There is no mono/dotnet on a stock
Mac. **Docker is the only route to mxbuild on macOS** — budget for Docker being required.

---

## RULE 2: Build the timeline before choosing a recovery point

The single most useful diagnostic is *when* each artifact changed, cross-referenced against
when the failure first appeared. From the real incident:

| Time  | Event |
|-------|-------|
| 08:36 | SP crashed, flushed model to disk |
| 08:44 | `git commit` — "checkpoint … pre-exec" |
| 08:46 | SP open attempt → `StorageLoadException` |
| 08:49 | SP **wrote 20+ unit files during the failed load** |

The conclusion that mattered: **the error (08:46) predates nothing — it postdates the commit
(08:44), so the commit already contains the corruption.** Restoring that checkpoint would
have wasted a cycle. The last known-good was the commit *before* the MCP session began.

Also note SP rewriting unrelated modules during a *failed* load. **Treat any unit file
modified after a failed open as untrusted** — it is not evidence of your own edits.

```bash
find mprcontents -name "*.mxunit" -newermt "2026-07-29 08:00"
git log --oneline -5 --pretty='%h %ai %s'
```

---

## RULE 3: Never conclude "the work is lost" from a single read

During the incident I read the `.mpr` **while SP was mid-rewrite**, got a truncated model
(6 microflows instead of 13), and told the user all their work was gone. It was not — the
file was simply being written at that instant. Ten minutes of unnecessary panic.

**Always confirm against git before declaring loss:**

```bash
git hash-object <Project>.mpr          # working tree
git rev-parse <commit>:<Project>.mpr   # committed
```

Identical hashes mean the working tree *is* the checkpoint, whatever a stale read said.
Also re-run the query — `mxcli` caches a catalog (`.mxcli/catalog.db`) that can lag.

---

## DEAD END: byte-scanning BSON for the empty property

This looks like the obvious surgical move and **does not work.** Recorded so it isn't retried.

`mprcontents/*.mxunit` files are raw BSON with plain ASCII strings. A BSON string field is
`0x02 <cstring name> <int32 len> <bytes> 0x00`, so an empty string is `len == 1`. Scanning for
an empty `Attribute` field is easy to write — and useless:

- **1193 matches** across the model → empty `Attribute` is *normal* for unset optional references.
- Narrowing to `ConditionalVisibilitySettings` with an empty `Attribute` nearby still gave
  **87 units**, most timestamped from the previous day — i.e. present while the project
  opened perfectly.

**Why it fails:** the invalid element is *structurally* invalid (empty where its context
requires a value), not textually distinctive. Nothing in the bytes distinguishes it from the
hundreds of legal empties. Only the model loader knows the difference — which is why RULE 1
(get the oracle) beats any amount of clever scanning.

### If you do grep .mxunit files, use `grep -a`

Default `grep -r` silently skips these as binary and returns **zero hits for documents that
definitely exist**. That false negative is very easy to misread as "the work is gone".

```bash
grep -ral "MyMicroflowName" mprcontents/     # -a is mandatory
```

Always run a **control** first — grep for something you know exists. If the control returns 0,
your method is broken, not the model.

---

## Repair procedure

1. **Snapshot.** `bin/snapshot-mpr.sh`, or copy `.mpr` + `mprcontents/`.
2. **Establish a floor.** Verify the pre-session commit passes `docker check`. This proves the
   session introduced the fault and gives bisect a known-good end.
3. **Confirm mxcli can still load the model.** If it can (it often can when SP cannot), you can
   repair in place with `DROP …` / `ALTER …` without ever opening SP.
4. **Bisect by suspicion, re-running `docker check` after each removal.** Rank suspects by:
   - documents an agent/tool was **mid-write** on when the crash happened
   - documents of the class named in the error (`Forms$` → pages)
   - documents that are structurally incomplete on inspection
5. **Verify no stale lock** before any `mxcli exec` (see below).

### Prime suspect heuristic: incomplete documents

A document that exists with full metadata but an **empty body** is the signature of a tool that
died mid-write. In the incident, `DS_Chart_MovementTrend_Filtered` had a parameter, a return
type of `List of …`, and a complete docstring — but `begin end;` with zero activities. That is
invalid regardless of the load error and should be dropped on sight.

```bash
./mxcli -p Project.mpr -c "DESCRIBE MICROFLOW Module.Suspect"
```

---

## Stale lock files

A crashed SP leaves `<Project>.mpr.lock` behind, which blocks reopening and makes `mxcli exec`
refuse. It is JSON with the owning PID:

```json
{"SessionId":"9ad3b4ad-…","ProcessId":63659}
```

**Verify the PID is actually dead before removing it** — don't pattern-match a number out of
the file, parse the JSON. In the incident a naive `grep -oE '[0-9]{3,6}'` pulled `726` out of
the *SessionId* and reported the wrong process.

```bash
python3 -c "import json;print(json.load(open('Project.mpr.lock'))['ProcessId'])"
ps -p <pid>     # empty output = dead = lock is stale
```

Back it up rather than deleting outright, and note the file is often mode `r--r--r--`
(needs `chmod u+w` first).

### Check process age before killing anything

Asked to "kill the stale SP", I nearly killed the instance the user had just reopened.
`ps -o etime` showed it was **23 seconds old**. Also note the deno sidecar under
`…/Studio Pro.app/Contents/modeler/tools/deno/…` matches a naive `pgrep studiopro` but is a
*child*, not an orphan — and a Gradle daemon on a nearby port is unrelated to Mendix entirely.

**Always check `etime` and `PPID` before killing a Mendix-looking process.**

---

## Prevention — what actually caused this

The crash trigger: **Run Locally was started while three agents were writing over MCP.** SP was
deploying from the same in-memory model the writes were landing in.

- **Never build/deploy while MCP writes are in flight.** Hold agent work whenever SP is building.
- **MCP writes are memory-only until `Cmd+S`.** There is no atomic unit and no validation until
  a save. A partial write can poison the model with nothing on disk to roll back to.
- **Commit after every increment, not at the end.** The 08:44 checkpoint is the only reason this
  incident was recoverable. It was made by luck, not process.
- Contrast with `mxcli exec` (SP closed): `mxcli check --references` validates the *whole script*
  before touching the model, and `bin/exec.sh` snapshots + auto-restores on mxbuild failure. For
  bulk structural work, that failure profile is strictly better than MCP's.

### `bin/save-sp.sh` lies about success

The stock script is unsafe:

```bash
osascript -e 'tell application "System Events" to keystroke "s" using command down' 2>/dev/null
echo "✓ SP save triggered — MPR flushed to disk."
```

`2>/dev/null` swallows the AppleScript error and the `echo` is unconditional — it prints
success **even when the keystroke never landed** (e.g. accessibility permission denied).
Given that unsaved MCP work is the thing most likely to be lost, this is the worst possible
place for a false green.

**Harden it to check the exit code and assert the `.mpr` mtime advanced**, so it can only claim
success when a save genuinely happened. Test the permission independently with:

```bash
osascript -e 'tell application "System Events" to return name of first process'
```

---

## Quick reference

| Symptom | Check |
|---|---|
| SP won't open, `StorageLoadException` | `./mxcli docker check -p Project.mpr` |
| `mx: exec format error` | Linux ELF binary; use Docker |
| grep finds nothing in `mprcontents/` | missing `-a`; run a control grep |
| "all my work is gone" | `git hash-object` vs `git rev-parse <c>:file`; re-run, catalog may be stale |
| `mxcli exec` refuses | stale `.mpr.lock`; parse JSON for PID, `ps -p` it |
| save-sp.sh says ✓ but nothing saved | it always says ✓; check `.mpr` mtime |

---

## ROOT CAUSE FOUND (2026-07-29, later session): `mxcli exec` repacks v2 → v1

Most of what reads as "the model is gone" in this playbook has one mundane cause. It is not
corruption, and nothing is ever lost.

**Every `mxcli exec` rewrites the project from v2 to v1.**

| Format | `.mpr` | `mprcontents/` |
|---|---|---|
| v2 (normal) | ~356 KB index | ~2,700 `.mxunit` files |
| v1 (after exec) | ~112 MB SQLite blob | **absent** |

`mxcli docker check` does the same thing.

### Why it looks catastrophic

`mprcontents/` disappearing while `git status` reports 2,700+ deletions is indistinguishable, at a
glance, from destroyed work. It is not: the v1 `.mpr` contains everything. Verify before reacting —

```bash
./mxcli -p "$(ls *.mpr | head -1)" -c "SHOW MODULES"
```

If that lists your modules, nothing is lost. (This is RULE 3 of this playbook, and it holds.)

### The three real consequences

1. `git add mprcontents/` → `fatal: pathspec did not match any files`
2. `git add -A` commits a ~108 MB blob **and deletes 2,700 tracked files** in the same commit
3. **Studio Pro refuses to open the project**, throwing

```
System.InvalidOperationException
  at LibGit2RepositoryProvider.WriteBaseFile
```

(3) is the one that wastes the most time, because it looks like model corruption and is not. SP's
git provider asks git for the base revision of `mprcontents/**` files that no longer exist on disk,
gets null, and throws. **It is a git/working-tree mismatch, not a model defect.** mxbuild will
happily report 0 errors on the very same file.

### Diagnosis — one comparison

```bash
# disk
find mprcontents -name '*.mxunit' 2>/dev/null | wc -l
# git
git ls-tree -r HEAD --name-only | grep -c '\.mxunit$'
```

Disk 0 + git thousands ⇒ SP will throw. They must agree before SP can open.

### Recovery

- **Work is committed and you want it back in v2:** `git checkout HEAD -- <project>.mpr mprcontents/`
- **Work is only in the v1 file:** commit the v1 blob so git and disk agree, open in Studio Pro,
  save — SP writes v2 natively — then commit that and the tree is normal again. Note the blob
  stays in history.
- **There is no `mpr-pack` command** in this mxcli build. Studio Pro is currently the only thing
  that converts v1 → v2.

### Prevention

`bin/exec.sh` had an asymmetry that made this invisible:

| Gate outcome | Behaviour | Left in |
|---|---|---|
| fail | restores v2 from snapshot | ✅ v2 |
| **succeed** | nothing | ❌ **v1** |

So only *successful* execs poisoned the tree — the opposite of what anyone would suspect. The
restore also ran `rm -rf mprcontents && cp -r <snap>/mprcontents mprcontents` under `set -e`: the
`rm` always succeeds, so a failing `cp` aborted the script *after* the delete, leaving nothing.

Both are fixed in this project's `bin/exec.sh`: the restore copies to a temp dir and swaps only on
success with a verified unit count, and a post-success guard warns loudly when the tree is left in
v1 and says whether git still agrees with disk.

**Rule: after any successful `mxcli exec`, check the format before `git add`.**

---

## Automating the RULE 1 diagnosis: a pre-commit guard

Written after a second incident on the same project (2026-08-04) where this exact crash recurred and
was manually diagnosed and fixed again — automate the "one comparison" above instead of re-deriving
it by hand each time.

**A dead-end worth recording first:** the first version of this hook checked the *.mpr's size and
whether its `Unit` table had a `Contents` column, on the theory that small-size + no-Contents-column
meant a Studio-Pro-crash-gutted file. That is wrong and **produces false positives on legitimate v2
commits** — verified by extracting a real historical "small" commit and finding genuine BSON
microflow content inside its `mprcontents/*.mxunit` files. A small `.mpr` with no inline `Contents`
column is Studio Pro's *normal* v2 index shape (content lives externally, one file per unit); it is
not evidence of anything wrong. **Do not gate on `.mpr` size or schema.** Gate on the actual proven
failure signature: git's tracked `mprcontents/*.mxunit` count vs. disk's count landing on opposite
sides of zero.

```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit — refuse to commit <Project>.mpr when git's mprcontents/
# tree and the on-disk mprcontents/ disagree drastically (one side 0, other thousands).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

MPR="$(ls *.mpr 2>/dev/null | head -1)"   # exactly one .mpr lives in a Mendix project root
git diff --cached --name-only | grep -qx "$MPR" || exit 0

DISK_COUNT=$(find mprcontents -name '*.mxunit' 2>/dev/null | wc -l | tr -d ' ')
INDEX_COUNT=$(git ls-files -s -- mprcontents 2>/dev/null | grep -c '\.mxunit$' || true)

if { [ "$DISK_COUNT" -eq 0 ] && [ "$INDEX_COUNT" -gt 10 ]; } || \
   { [ "$INDEX_COUNT" -eq 0 ] && [ "$DISK_COUNT" -gt 10 ]; }; then
  echo "✗ REFUSING COMMIT: mprcontents/ mismatch — disk has ${DISK_COUNT} .mxunit files," >&2
  echo "  this commit would leave git tracking ${INDEX_COUNT}. This is the shape that crashes" >&2
  echo "  Studio Pro (LibGit2RepositoryProvider.WriteBaseFile) on next launch." >&2
  exit 1
fi
exit 0
```

Threshold is deliberately loose (`>10` on one side while the other is `0`) — small drift (a few
dozen files differing between disk and index) is normal mid-session and not the failure mode; only
the "one side is empty" case is proven to crash Studio Pro. Install it as the project's
`bin/git-hooks/pre-commit` (tracked) + `.git/hooks/pre-commit` (installed, untracked — `.git/hooks/`
is never version-controlled, so both copies must exist and be kept in sync by hand).

This does not replace RULE 1–3 above for diagnosing an *existing* bad state — it only prevents a
new bad commit from being created in the first place.
