# Previewing a running app over the mxcli tunnel-hub

**Applies to:** any mxcli project that needs a browser-reachable preview from a container —
a demo, a stakeholder review, a UI check on a real device.

**Purpose:** get a public URL for a locally-running Mendix app, and get the parts that talk to
the outside world — Mendix Cloud GenAI above all — working *through it*. `mxcli run --hub` is
documented in mxcli's own bundled `run-local` skill; read that first for the flags. This file
covers only what that skill does not, because each item below cost a live debugging round and
none of them announces itself.

---

## The three things that bite, in the order they bite

### 1. `--db-name` defaults to the project name, not to your database

`mxcli run --local` derives the database name from the `.mpr` name. If your data lives anywhere
else, the app boots against a database that does not exist and dies with:

```
Error: starting runtime: start failed: The database to be used does not exist.
```

That message is accurate and still misleading — it sounds like a broken environment rather than
a default you did not know about. Pass the database explicitly, every time:

```bash
mxcli run --hub https://hub.example.org -p app/MyApp.mpr \
  --db-name mendix --db-user mendix --db-password mendix
```

### 2. The Mendix runtime's REST client ignores JVM proxy properties

**This is the expensive one.** A sandboxed container typically routes egress through a local
proxy and advertises it in `JAVA_TOOL_OPTIONS` (`-Dhttps.proxyHost=…`). Every JVM picks that up,
so it is natural to assume the app is covered.

It is not. **A Mendix `Call REST` activity is configured from RUNTIME SETTINGS, not from JVM
system properties.** Without the runtime settings, an outbound call leaves the JVM aimed straight
at the internet.

What you see is not a connection error. Measured 2026-09-02 against Mendix Cloud GenAI:

```
403 - Host not in allowlist: peuc1-compute.services.genai-eu-1a.mendixcloud.com.
Add this host to your network egress settings to allow access.
```

That reads like an egress-policy problem, and it is not — **the host was reachable the whole
time** (`curl` through the same proxy returned 401, i.e. "reached it, needs auth"). The 403 came
back because the request did not go through the proxy at all. Chasing the allowlist wording is a
dead end; the fix is on the caller.

`mxcli run` accepts runtime settings directly:

```bash
mxcli run --hub … \
  --runtime-setting http.proxyHost=127.0.0.1 \
  --runtime-setting http.proxyPort=43675
```

**Why the env-var form is not enough.** A hand-rolled runner (`.docker/run-local.sh` in a
generated project) exports `RUNTIME_PARAMS_HTTP_PROXYHOST/PORT` and `exec`s the runtime, so the
runtime inherits them. `mxcli run` spawns its own runtime and does not forward those, so the same
app works under one runner and 403s under the other with no change to the model. If GenAI works
locally and fails under `--hub`, this is why — and `--runtime-setting` is the supported route.

### 3. Nothing tells you the preview is serving a *stale* app

`--hub` implies `--local`, which builds from the **current `.mpr` on disk**. Two ways that bites:

- A leftover runtime still holds :8080 and the hub tunnels *that* — an old build, served happily
  at a fresh-looking URL. `mxcli run` does at least refuse the port (`port 8080 (app) is already
  in use. Held by pid …`), which is more than most runners do; kill the holder rather than
  switching ports, or you end up tunnelling the wrong process.
- Model changes applied but **not committed** can be reverted out from under you — see the
  companion rule below.

Verify by asking the database for something the new build introduced, never by the HTTP status.
A 200 proves *something* is serving.

---

## The companion trap: restoring the split model discards uncommitted work

Not hub-specific, but this is where it surfaced, so it belongs beside it.

`mxcli docker build` **consolidates** a split `.mpr` — the per-document `mprcontents/*.mxunit`
files disappear. The usual restore is:

```bash
git checkout HEAD -- app/MyApp.mpr app/mprcontents/ && git clean -fdq app/mprcontents/
```

That restores the **committed** model. Anything applied and not yet committed is silently thrown
away, including model changes you made minutes earlier.

> **Commit applied model changes BEFORE any `docker build`. The restore step is only a restore
> if the model is committed; otherwise it is a revert.**

Measured 2026-09-02: two tool microflows were applied, used to build a PAD, then discarded by
exactly this checkout. Nothing failed at the time — the *running* PAD had been built before the
revert, so the end-to-end tests passed against a model the repository no longer held. It surfaced
only later, in the Agent Editor, as **"There is an issue with the Agent Version in Use: Tool
microflow not found"**. A test can pass against an artifact and prove nothing about the source it
was supposedly built from.

---

## A launcher worth keeping

**This toolkit ships one: `bin/run-hub.sh`.** It finds the `.mpr` (root or `app/`, refusing to guess
between two), applies the database and proxy settings below, and prints the reminder to exercise an
outbound call before sharing the URL. Run it from any project:

```bash
MXCLI_HUB_KEY=<key> /path/to/mxcli-project-toolkit/bin/run-hub.sh <project-root>
```

Override with `MXCLI_HUB_URL`, `MXCLI_HUB_PROJECT`, `DB_NAME`/`DB_USER`/`DB_PASSWORD`, or pass
anything else straight through after `--`. **The hub key is a secret: it belongs in the
environment, never in the file.** If you would rather inline it, this is the shape:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${MXCLI_HUB_KEY:?set MXCLI_HUB_KEY in the environment (never commit it)}"

ARGS=(run --hub https://hub.example.org -p app/MyApp.mpr
      --db-name mendix --db-user mendix --db-password mendix)

# The runtime's REST client reads runtime settings, not JVM properties.
_p="${HTTPS_PROXY:-${https_proxy:-}}"
if [ -n "$_p" ]; then
  _hp="${_p#*://}"; _hp="${_hp%/}"
  ARGS+=(--runtime-setting "http.proxyHost=${_hp%%:*}"
         --runtime-setting "http.proxyPort=${_hp##*:}")
fi

exec ./mxcli "${ARGS[@]}"
```

---

## Checklist before you hand out the URL

1. **Commit the model**, then build, then restore the split `mprcontents/`.
2. Kill every stale runtime; confirm nothing holds the app port.
3. Launch with `--db-name` and the proxy runtime settings.
4. Wait for `Preview available at https://…`.
5. **Prove the app is the one you think it is** — query the database for something only the new
   build has, or call a feature that did not exist before.
6. **Exercise one outbound call** (a GenAI chat turn, a REST integration). It is the only way to
   know settings reached the runtime, and it is the thing that fails in front of an audience.
7. Say plainly that the preview lives only while the session runs. It is a tunnel, not a
   deployment.
