# Scriptable Studio Pro Launch Verification (macOS)

**Applies to:** any mxcli project on macOS
**Purpose:** know whether a `.mpr` actually loads in the *real* Studio Pro GUI loader — not
just `mxcli check` / `mxcli docker check` — without manually opening Studio Pro and
eyeballing it. Typically: verifying a fix for a corruption-class bug
(`StorageLoadException`, `InvalidCastException`, "unloadable"), where headless checks are
known to sometimes pass a project the GUI loader rejects. Companions:
`mpr-corruption-and-sp-load-errors.md`, `bug-logs/mxcli-bugs.md` (BUG-19/BUG-20/BUG-96),
`learned-detection-gaps.md` (the loader is rung 5 of the verification ladder).

**Why this matters:** `mxcli docker check` routes to the same `mx` binary Studio Pro uses,
but is *not proven equivalent* to the GUI loader for BSON-structural corruption — confirmed
2026-08-04 by reproducing BUG-19 where `docker check` reported zero errors on a project
whose BSON was confirmed corrupted by `DESCRIBE PAGE`.

---

## The core trick: launch the binary directly, not via `open`

Invoking the executable inside the bundle — instead of `open -a "Mendix Studio Pro X.app"`
— lets you redirect stdout/stderr to a file, where .NET dumps startup diagnostics and
(sometimes) unhandled exception traces, even though it is a GUI app:

```bash
"/Applications/Mendix Studio Pro <ver>.app/Contents/MacOS/studiopro" <path>.mpr \
  > /tmp/sp_launch_test.log 2>&1 &
disown
```

Validated: even benign runtime messages (assembly-resolution noise) show up in the log, so
the capture path itself is proven.

## Poll for outcome instead of guessing

```bash
for i in $(seq 1 40); do
  if grep -qE "InvalidCastException|NullReferenceException|StorageLoadException|unloadable|Unhandled exception" /tmp/sp_launch_test.log; then
    echo "EXCEPTION FOUND"; break
  fi
  kill -0 <pid> 2>/dev/null || { echo "PROCESS DIED, no exception text matched"; break; }
  sleep 1
done
```

## Checking window/dialog state when text isn't enough

If the process stays alive and CPU drops to idle with no exception text, check whether it
shows a normal window (loaded fine) vs a modal error dialog, via `System Events`.

**Critical gotcha:** with more than one Studio Pro instance running (common — your main
project plus this test instance), addressing `System Events` **by process name**
(`tell process "studiopro"`) is ambiguous and silently picks the wrong instance. Address by
unix pid:

```bash
osascript -e 'tell application "System Events" to tell (first process whose unix id is <pid>) to get name of every window'
osascript -e 'tell application "System Events" to tell (first process whose unix id is <pid>) to get {name, value of attribute "AXModal"} of every window'
```

A single non-modal window named after the project is fairly strong evidence the load
succeeded. `screencapture -x` may fail silently ("could not create image from display")
without Screen Recording permission — the AXModal query is the fallback that needs none.

## Clean shutdown

Kill by the specific pid you launched, never by name — `pkill studiopro` would kill every
instance including the user's real working session:

```bash
kill -TERM <pid>
```

---

## What this technique does NOT prove yet

Tested live against BUG-19 (2026-08-04): the corrupting repro **did not reproduce** as a
load-time crash — SP opened the corrupted project cleanly (idle CPU, single non-modal
window, no exception text) even though `DESCRIBE PAGE` confirmed the corrupted structure in
the BSON. Three explanations, unresolved: (1) the scratch repro diverged from the original
trigger; (2) that particular build silently fixed the codec issue; (3) the corruption only
surfaces on the next *save*, not at load.

**So:** this is a validated way to *capture* Studio Pro's real console output and window
state programmatically. It is **not yet validated as a pass/fail oracle** — a clean launch
proves "no load-time crash", not "no corruption". Never close a corruption-class bug on a
green result from this alone: corroborate with `DESCRIBE`/BSON inspection of the specific
structure the bug touches, and ideally a save-then-reload cycle to rule out explanation 3.

Open follow-up: re-run against BUG-19's *exact original* repro script (not a scratch
reconstruction) to rule out explanation 1 before concluding anything about 2 or 3.
