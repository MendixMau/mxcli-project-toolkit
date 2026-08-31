# Cloud development environment — setup and loop

**Applies to:** any mxcli project | migration | requirements-driven | greenfield — whenever the
work happens in an **ephemeral cloud container** (Claude Code on the web/mobile, a devcontainer,
a CI runner) instead of a local machine with Studio Pro.

**Purpose:** the one-time sequence that turns an empty git repo into a working cloud workspace,
and the per-session loop that keeps work durable when the container is not. Companion:
`personal-toolkit/prompts/full-e2e-cloud-run.prompt.md` is the field-run variant of the same
setup with a sealed persona and a frozen toolkit; this skill is the plain development version.

**Field run:** a dashboard-publishing migration project, 2026-08-31 — empty private repo to pushed scaffold (mxcli
v0.20.0, toolkit @ `94f4037`) in one session, following exactly the steps below.

## The two facts that shape everything here

1. **The container is ephemeral.** It is reclaimed after idle time. The git remote — not the
   filesystem — is the workspace; anything not committed *and pushed* when the session ends is
   gone. Every decision below (what to commit, when to push, what to re-download) follows from
   this.
2. **The container is Linux, and that is the good case.** The whole pipeline runs headless:
   the build gate is `mxbuild`, a plain binary; `mxcli new` creates a project, `mxcli run
   --local --hub` serves it at a public URL, `mxcli playwright`/`oql`/`test --local` exercise
   it. The CDN route that derives `mx` from the MxBuild download is Linux-only — exactly what
   a cloud container is. Nothing in the critical path needs Studio Pro or a GUI. (Established
   2026-08-21; do not re-derive it.)

## One-time setup — empty repo to working workspace

Order matters: `mxcli init` **overwrites**, `init-project.sh` adds alongside, and
`bootstrap-project.md` (later, once an app exists) **merges**. Run them in that order and
never re-run `mxcli init` afterwards.

1. **Clone the project repo and the toolkit**, side by side. Record the toolkit SHA
   (`git -C <toolkit> log -1 --format=%H`) — it goes in `PROJECT.md` as `Toolkit commit:`.
2. **Download the latest mxcli into the project root** (it is a single static binary):

   ```bash
   cd <project-root>
   ARCH=$(uname -m); [ "$ARCH" = x86_64 ] && ARCH=amd64; [ "$ARCH" = aarch64 ] && ARCH=arm64
   curl -fsSL "https://github.com/mendixlabs/mxcli/releases/latest/download/mxcli-linux-${ARCH}" -o ./mxcli
   chmod +x ./mxcli && ./mxcli --version
   ```

   The binary (~90MB) is gitignored by `mxcli init`'s own `.gitignore`, on purpose — the
   devcontainer's `postCreateCommand` re-downloads it, and every later session does the same
   (step 1 of the loop below). Do not commit it.
3. **`./mxcli init`** in the project root. Creates `.gitignore`, `AGENTS.md`/`CLAUDE.md`,
   `.ai-context/skills/`, `.devcontainer/`. Fine to run before any `.mpr` exists — a
   migration workspace has no app until Stage 5. If Stage 5 later creates the app with
   `mxcli new`, that command runs init itself: **never run `mxcli init` again after either**
   — it overwrites `CLAUDE.md` without merging.
4. **`<toolkit>/bin/init-project.sh <project-root>`** — intake.md, PROJECT.md,
   `CLAUDE.local.md` (toolkit wiring + baseline routing), agent stubs, the dashboard. It ends
   with a doctor report: on a bare cloud container, mxbuild/mx/docker warnings are **expected
   until Stage 5** (nothing before the build loop uses them) — read them, note them, move on.
5. **Decide where the legacy source lives — explicitly.** `mxcli init` gitignores `sources/`
   by default because source drops are routinely client-owned and live elsewhere. In a cloud
   workspace that default is usually wrong: if the container is the only place the source
   was copied to, an ignored `sources/` evaporates with the container. If the source may be
   committed (your own code, or the client agreed), remove the `sources/` line from
   `.gitignore` **with a dated comment saying why**; if it may not, leave the ignore and
   record in intake Q2 where the durable copy lives. Either way the decision is written
   down, never inherited silently.
6. **Import the source into `sources/<system>/`** — only the declared scope, recording what
   was taken and what was left (intake Q1/Q2).
7. **Commit with explicit paths and push**: `git push -u origin <branch>`. The scaffold plus
   the source baseline is the first commit(s); a wrong scope boundary is cheap to fix now
   and expensive after Stage 1.

**Setup is done when all four hold:** `./mxcli --version` prints; `bin/gate-check.sh
<project-root>` runs (verdicts may be PENDING — that is a working gate, not a failure);
`git status --porcelain` is empty; and the remote shows the push. Three of four is not done.

## The session loop — every subsequent session

1. **Re-establish the container**: clone the project repo if absent; re-download mxcli into
   the project root if absent (it is gitignored, so a fresh clone never has it).
2. **Session-start ritual** per the project's `CLAUDE.local.md`: `git -C <toolkit> pull
   --ff-only`, then `bin/gate-check.sh <project-root>` — it reports protocol freshness and
   where the project actually stands. Never infer position from memory of a previous session.
3. **Work stage-by-stage per `conversion-runbook.md`** — live checklist in chat, gates
   paste-proven, questions asked then the turn ended. Cloud changes none of this.
4. **Push before going idle — every time.** Commit at every gate passed, every module
   done-marked, and before ending any turn that might be the session's last; the container
   does not survive, the remote does. Work that exists only in the container when it is
   reclaimed did not happen.

## Stage 5+ on a cloud container — what to expect

- `mxcli new <App> --version <V> --output-dir ./app` downloads MxBuild (~800MB) from the
  Mendix CDN — it needs network and minutes, and `which mx` returning nothing afterwards is
  normal (`mx` is derived from that download, never installed separately). Confirm the
  version with the user first; everything downstream inherits it.
- `mxcli run --local --hub --test-endpoint` serves the app and `--hub` yields a public URL —
  post it in chat so the user can click through from a phone. Verify "up" from the boot log
  or `mxcli docker status`, never from the absence of an error.
- Docker may be absent or its daemon stopped. Then `exec.sh`'s mxbuild gate reports
  `gate=skipped` and every exec is **UNVERIFIED** — say so in the checklist and treat the
  first working build gate as the point where those scripts get re-verified. Never report
  green on a gate that was skipped.
