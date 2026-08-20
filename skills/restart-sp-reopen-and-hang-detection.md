# Restarting Studio Pro: the reopen bug, the port bug, and detecting a real hang

Written 2026-08-04 while hardening `bin/restart-sp.sh` (now also in
`mxcli-project-toolkit`'s `project-bin/restart-sp.sh` + `check-sp-health.sh`). Three
separate, independently-verified findings from one debugging session.

**Applies to:** any mxcli/MCP project with Studio Pro on macOS.
**Companion:** `mpr-corruption-and-sp-load-errors.md` (a different failure class — SP refusing
to *load* a project vs. SP failing to *reopen* or hanging after it launches).

---

## Finding 1: `open -a "Mendix Version Selector" <file>` fails silently

The naive "reopen the project" one-liner is:

```bash
open -a "Mendix Version Selector" "$MPR"
```

This launches the Version Selector process, which then quits within a few seconds —
**no window, no error, no project opened.** It looks like a timing issue or a stale lock,
and is easy to misdiagnose as either.

**Root cause, confirmed via the unified log** (not guessed):

```bash
log show --last 2m --predicate 'eventMessage contains "AppleEvents"' | grep -i versionselector
```

surfaces a `tccd` denial: `Prompting policy for hardened runtime; service:
kTCCServiceAppleEvents requires entitlement ... missing for ... com.mendix.versionselector`.

`open -a <App> <file>` (no `--args`) delivers the path via an **"open documents" Apple
Event**. `Mendix Version Selector.app`'s own code signature is missing the
`com.apple.security.automation.apple-events` entitlement needed to receive it. The process
launches, never receives the project path, and exits. **This is a bug in Mendix's app
bundle** — not a TCC permission you can grant, not a stale-lock issue, not fixable by
retrying.

**Fix:** bypass Version Selector and launch the resolved Studio Pro app directly with
`--args`, which passes the path as a plain argv argument — no Apple Events involved:

```bash
open -a "$SP_APP" --args "$MPR"
```

Proven correct by inspecting how the *already-running, working* Studio Pro process had
actually been launched (`pgrep -fl studiopro` shows the `.mpr` path as a literal argv
entry, not delivered via Apple Events).

If you need "whichever Studio Pro version this project wants" instead of a hardcoded path,
`mxcli-project-toolkit/project-bin/_common.sh`'s `find_sp_app` already resolves the newest
installed version (override with `$MENDIX_APP`) — same version-selection tradeoff the
toolkit's `find_mxbuild` already accepts elsewhere, not a new risk introduced here.

---

## Finding 2: the runtime port is not reliably 8081

An older `restart-sp.sh` only killed port 8081 before reopening. On one project,
the project's own generated `.launch` file set `MXCONSOLE_RUNTIME_PORT=8080` (the real native
"Run Locally" port); `8081` only showed up in that project's *Docker-mode* logs
(`ApplicationRootUrl=http://localhost:8081/`). Killing only 8081 left the actual runtime
process alive, so "restart" silently didn't restart anything.

**Fix:** kill both 8080 and 8081 unconditionally before reopening — cheap insurance, no
downside — plus an env var (`MENDIX_RUNTIME_PORT`) for a project that genuinely uses a
third port. Don't trust a single hardcoded port number for this across projects.

---

## Finding 3: CPU% alone cannot tell "hung" from "idle"

Wanted an automated "is SP actually stuck?" check. The obvious idea — "0% CPU sustained =
dead" — **produces false positives on the exact data that motivated it**:

- A genuinely hung instance (confirmed via `sample`, see below): sat near 0% CPU.
- A healthy instance that had just *finished* loading normally: went 102.7% → 93.9% →
  0.2% CPU as it settled into idle. Same near-zero number, opposite meaning.

CPU% cannot distinguish "done and idle, waiting for input" from "deadlocked mid-operation."
Both look identical on that one metric.

**What actually works:** `sample <pid> <seconds> -file <path>` for a few seconds, then look
at whether the *heaviest single call path* in the resulting tree is one of the well-known
"waiting for work" system primitives (`_BlockUntilNextEventMatchingListInMode`,
`mach_msg_trap`, `kevent`, `__psynch_*`, etc.) or something else entirely.

- **Healthy idle**: dominant call path is a normal event-loop/kernel wait — expected, since
  there's genuinely nothing to do.
- **Hung**: dominant call path is deep inside a specific operation and doesn't move. The
  live case caught this way was a Xamarin/.NET cross-thread synchronous call —
  `performSelector:onThread:withObject:waitUntilDone:` → an app-specific `ActionWrapper` —
  which is not a "waiting for work" frame at all; it's mid-call, permanently.

Confirmed on the real hang: `sample` over a 3-second window returned an **identical stack
trace across effectively the entire window** — proof of zero forward progress, not "slow."

Implemented as `check-sp-health.sh`: skip judgment during a load grace period, treat CPU >2%
as unambiguously active, and only when CPU is low *and* past the grace window take the
`sample` and apply the idle-primitive check above. `check-sp-health.ps1` (Windows) only
implements the CPU-threshold half — there's no cheap `sample` equivalent on Windows in this
port, so it reports "unknown, check manually" instead of a real verdict when CPU is low.
That gap is real and undocumented risk if someone assumes parity with the macOS version.

---

## Reusable pattern: ask by default, `AUTO_SP=1` to skip

Force-quitting a GUI app is disruptive enough that a script should ask before doing it —
but that makes the script useless for unattended/scripted runs. Landed on: interactive
confirmation by default, one env var (`AUTO_SP=1`) to skip both the reopen confirmation and
the post-hang auto-retry gate. Mirrors the existing `FORCE_EXEC=1` pattern in
`mxcli-project-toolkit/project-bin/exec.sh` — same shape, different script, kept the naming
distinct since they gate different actions.
