# Host-aware display of progress surfaces: research findings

Date: 2026-10-21. Scope: can the toolkit tell which agent host it runs under, and use that to
show its HTML progress surfaces (dashboard `index.html`, progress report, build-plan status,
review pages, `toolkit-guide.html`) in the best available way?

## TL;DR

- **Yes, partly.** A shell script can reliably tell three things cheaply, with no network:
  1. it runs under *some* Claude Code (`CLAUDECODE=1`, documented);
  2. it runs in a Claude Code cloud session (`CLAUDE_CODE_REMOTE=true`, documented);
  3. it has a local GUI or not (`DISPLAY`/`WAYLAND_DISPLAY`, `SSH_*`, `CI`, platform).
  Cursor (`CURSOR_AGENT`) and Copilot in VS Code (`VSCODE_AGENT`, since VS Code 1.121) have
  documented flags too. Telling Claude Code CLI from Desktop from the IDE extension rests on
  the undocumented `CLAUDE_CODE_ENTRYPOINT`. Windsurf and Codex cloud have no documented signal.
- **The best surfaces are agent tools, not commands.** These are the Claude Code Artifact
  publish, file cards and a Simple Browser panel. A script cannot call them. So the design
  splits in two:
  - **The script (an instrument):** decides *local open* vs *no open*, and always prints one
    machine-readable surface line plus a one-line summary.
  - **A skill (the instruction):** tells the agent what to do with that line in its host,
    for example publishing it as an artifact after asking consent once.
- **There is a real bug today, independent of the new feature.** `bin/init-project.sh` tries
  only `open`, then `xdg-open`. It writes the `.guide-shown` sentinel even when neither
  exists, so the guide is never shown:
  - in a cloud session, where neither exists. Observed in this session.
  - on Git Bash for Windows, where neither exists.
  - possibly on Debian/Ubuntu, where `/usr/bin/open` can be `openvt`. Not verified here.

  Separately, `skills/learned-skill-ux-audit.md:290` tells the agent to run a bare
  `open docs/ux-review-*.html`. That is macOS-only.

## 1. Detection

### Observed data point: Claude Code on the web / cloud (this session)

Only variable names are listed, plus three non-secret flag values that are the subject of the
question. No token values were read.

- **Process chain:** `process_api` → `sh` → `environment-man[ager]` → `claude` → `bash` (the Bash tool).
- **Claude-related variable names present:**
  - `CLAUDECODE`
  - `CLAUDE_CODE_REMOTE`
  - `CLAUDE_CODE_REMOTE_SESSION_ID`
  - `CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE`
  - `CLAUDE_CODE_ENTRYPOINT`
  - `CLAUDE_CODE_SESSION_ID`
  - `CLAUDE_CODE_CHILD_SESSION`
  - `CLAUDE_CODE_CONTAINER_ID`
  - `CLAUDE_CODE_EXECPATH`
  - `CLAUDE_CODE_VERSION`
  - `CLAUDE_CODE_MESSAGING_SOCKET`
  - `CLAUDE_CODE_ARTIFACT_ASSETS`
  - `CLAUDE_CODE_SESSION_ATTENDED`
  - `CCR_SESSION_PROFILE`
  - `SESSION_INGRESS_URL`
  - others besides these
- **Flag values read:**
  - `CLAUDECODE=1`
  - `CLAUDE_CODE_REMOTE=true`
  - `CLAUDE_CODE_ENTRYPOINT=remote_desktop`, meaning a cloud session started from the desktop app
- **Absent:** `DISPLAY`, `WAYLAND_DISPLAY`, `TERM_PROGRAM`, `SSH_*`, `BROWSER`. `TERM` is set.
- **No binaries:** `open`, `xdg-open`, `code`, `cursor`, `windsurf` and `codex` are all missing.
- **Network:** outbound access goes through an allow-listing proxy. Several documentation
  hosts were unreachable from the container. So the session has no display, no browser and
  no general internet: `xdg-open` is not merely useless here, it is absent.
- **The agent (not the script) did have the Artifact publish tool in this session.**
  `CLAUDE_CODE_ARTIFACT_ASSETS` may hint at that capability, but it is undocumented. Do not
  rely on it.

### Detection table

| Host | Signal (cheap, no network) | Confidence | Source |
|---|---|---|---|
| Any Claude Code agent shell | `CLAUDECODE=1` in Bash-tool, hook and statusline subprocesses | **High (documented)**. Caveat: IDE extensions also set it in their *integrated terminals*, so a human typing there looks like an agent. | code.claude.com/docs/en/env-vars |
| Claude Code agent subprocess (not a human terminal) | `CLAUDE_CODE_CHILD_SESSION=1` (Bash/PowerShell/Monitor tools, hooks, statusline; not MCP servers) | High (documented). This is the better "an agent is running me" test. | env-vars |
| Claude Code cloud (web/mobile/desktop-launched cloud) | `CLAUDE_CODE_REMOTE=true`; `CLAUDE_CODE_REMOTE_SESSION_ID` (a link back to the session can be built from it) | **High (documented)**. Observed here. `bin/doctor.sh` already uses it for its `cloud` lane. | env-vars; claude-code-on-the-web |
| Claude Code Remote Control (local session driven from phone/web) | `CLAUDE_CODE_BRIDGE_SESSION_ID` while connected | High (documented) | env-vars |
| Claude Code CLI vs Desktop vs VS Code/JetBrains extension | `CLAUDE_CODE_ENTRYPOINT` (observed `remote_desktop` here; other values seen in the wild such as `cli`, `sdk-*`, `claude-vscode`, `claude-desktop`) | **Low (undocumented)**. Not on the env-vars page. A feature request to expose an environment kind to child processes (`CLAUDE_CODE_ENVIRONMENT_KIND`) was closed without confirmation that it shipped. | observation; is-ai-agent crate; claudeissues #43425 |
| Claude Code IDE extension | `TERM_PROGRAM=vscode` plus `CLAUDECODE`; IDE lock/port variables | Medium-low (partly documented) | env-vars (IDE note) |
| GitHub Copilot agent in VS Code | `VSCODE_AGENT` (VS Code 1.121, May 2026); `AI_AGENT=github_copilot_vscode_agent` (third-party report) | Medium. The release-note text came via a search summary; the page was unreachable from this container. `AI_AGENT` is not confirmed by Microsoft. | VS Code 1.121 release notes; is-ai-agent |
| VS Code integrated terminal (any agent or human) | `TERM_PROGRAM=vscode`, `VSCODE_IPC_HOOK_CLI` (lets `code <file>` open in the attached window, also over Remote-SSH/devcontainer), `VSCODE_INJECTION` | Medium. Widely observed; not on a single docs page I could reach. | vscode-docs terminal pages; community |
| Cursor agent | `CURSOR_AGENT` (documented by Cursor for shell-rc detection); `CURSOR_TRACE_ID` (community) | Medium-high for `CURSOR_AGENT`. `TERM_PROGRAM` is reported as both `vscode` and `Cursor`, so it is unreliable. | cursor.com/docs/agent/terminal (via search); Cursor forum |
| Windsurf (Cascade) | No documented signal found. As a VS Code fork it likely sets `TERM_PROGRAM=vscode`. | **None / unknown.** Docs silent. | search turned up only terminal-hang guides |
| OpenAI Codex CLI | `CODEX_SANDBOX=seatbelt` (macOS Seatbelt sandbox only); `CODEX_SANDBOX_NETWORK_DISABLED=1` when the sandbox has no network; `CODEX_THREAD_ID`/`CODEX_CI` (third-party list) | Medium-low. Comes from repo-internal AGENTS.md and test plumbing, not user docs. Linux sandbox behaviour unclear. | openai/codex AGENTS.md (mirror); PR #879; codex issue #13373 |
| OpenAI Codex cloud | No documented signal. Setup-script env does not persist into the agent phase. | **None.** Docs silent. | developers.openai.com Codex cloud env docs; community forum |
| Devcontainer / Codespaces | `REMOTE_CONTAINERS`, `CODESPACES`, `DEVCONTAINER`, `/.dockerenv` | High. Already used by `bin/doctor.sh`. | doctor.sh; VS Code docs |
| SSH session | `SSH_CONNECTION` / `SSH_TTY` | High (OpenSSH) | ssh(1) |
| CI | `CI=true`; `GITHUB_ACTIONS=true` | High | GitHub Actions docs |
| Local GUI available | macOS: true unless SSH. Linux: `DISPLAY` or `WAYLAND_DISPLAY`. Windows Git Bash: true (`cmd //c start "" file` or `explorer.exe`). WSL: `wslview` or `explorer.exe` | High | platform conventions; `mxtk_platform` in `project-bin/_common.sh` |

Prior art: `am-i-vibing` (npm), `@vercel/detect-agent`, `is-ai-agent` (Rust) and
`huggingface_hub/utils/_detect_agent.py` all do exactly this env sniffing. Their lists
disagree in places, which shows how undocumented the field is. A cross-tool `AI_AGENT`/`AGENT`
convention is emerging but is not adopted by every host. All of them warn about false
positives: a human typing in a terminal that an agent host opened.

## 2. Display strategy

The axis that matters is not "which brand", but two questions:
- **(a)** Is there a local GUI the user is sitting at?
- **(b)** Does the *agent* have a richer surface than a browser tab?

| Host | Best surface (who does it) | Fallback |
|---|---|---|
| Claude Code cloud (web/mobile/desktop-launched) | **Agent:** publish the HTML as a private Artifact (republish to the same URL on each refresh), or attach it as a file card. Requires consent once; see Risks. | Agent posts the one-line summary plus the repo path. The pushed branch is the copy that lasts. |
| Claude Code Desktop (local) | **Agent:** Artifact / side-panel file preview, where available. **Script:** `open` works (local macOS/Windows GUI). | `open`/`start` from the script |
| Claude Code CLI in a local terminal | **Script:** `open` / `xdg-open` / `start`. **Optional:** statusline shows `Stage 3 · 4 PASS 1 PENDING` from a cached one-line file (statusline commands get `CLAUDECODE`). | Path plus summary in chat |
| Claude Code in VS Code/JetBrains | **Script:** `open`/`xdg-open` (a local GUI is implied). `code -r <file>.md` for a markdown companion where one exists. **Agent:** the extension's own file links. | Clickable absolute path in chat |
| Copilot / Cursor / Windsurf (VS Code family), local | **Script:** OS browser open. Editor-native (Simple Browser, Live Preview) is a *command-palette* action, not scriptable from a shell. `code`/`cursor`/`windsurf <file>` opens the HTML *source*, which is wrong for a dashboard. | Path plus summary in chat |
| VS Code family over Remote-SSH / devcontainer / Codespaces | `$BROWSER` is set by VS Code Remote to a helper that forwards URLs to the local browser. **But a `file://` path from the remote does not resolve locally.** Needs `python -m http.server` plus port forwarding: an open question, not a default. | Path plus summary in chat; user opens it from the explorer |
| Codex CLI (local) | OS browser open, if not sandboxed against it. The Seatbelt sandbox may block `open`. **Unverified.** | Path plus summary |
| Codex cloud | None: no display, no artifact tool known | Summary in the task output, plus the committed file |
| Plain local terminal | `open` (macOS), `xdg-open` (Linux with a display), `cmd //c start ""` (Git Bash), `wslview`/`explorer.exe` (WSL) | Path |
| SSH / CI / headless | **Never** try to open | Path plus summary. In CI, write it to `$GITHUB_STEP_SUMMARY` |

**What `open`/`xdg-open` actually do:**
- **macOS:** `open` hands the file to LaunchServices and the default browser opens it.
- **Linux with a display:** `xdg-open` does the same through the desktop's MIME handler.
- **Linux without a display:**
  - `xdg-open` fails or falls back to a text browser.
  - On Debian-family systems, `open` may be `openvt` (console switcher). It fails or does
    something unrelated. Unverified on a current image, but historically true.
- **Git Bash:** neither command exists. `start` is a cmd builtin, reached as `cmd //c start "" file`.
- **Cloud container (observed):** neither binary exists, and there is no `DISPLAY`.

## 3. Proposed design (smallest useful)

**One instrument, one instruction, one register line.**

### 3.1 `bin/lib/show.sh <file> [--kind dashboard|report|guide|review] [--summary "<one line>"]`

An instrument in the sense of `skills/skills-over-scripts.md`: it fetches facts and acts on
the OS, and it holds no judgement about *what* to show. It should be about 80 lines of bash
and is sourced or called by `gate-check.sh`, `progress-report.py` (via a subprocess), and
`init-project.sh`.

1. **Detect the lane once.**
   - Lift `doctor.sh`'s existing `ENV_LANE` logic (`cloud | devcontainer | local | local-linux`)
     into a shared `mxtk_env_lane` in `_common.sh`, so detection lives in one place rather
     than two.
   - Add a `display` axis: `gui | headless | ci`, from `CI`, `SSH_*`, `DISPLAY`/`WAYLAND_DISPLAY`,
     `mxtk_platform`.
   - Add an `agent` field: `claude | claude-cloud | copilot | cursor | codex | none`. This is
     informational only and never gates behaviour on an undocumented variable.
   - Cache the result in `$PROJECT/.claude/.host-lane`, keyed by
     `CLAUDE_CODE_SESSION_ID`/`$PPID` so a new session re-detects. Cost: a handful of
     `[ -n ]` tests, no forks beyond `uname`, no network.
2. **Open only when `display=gui` and the lane is not `cloud`/`devcontainer`.** Use the right
   opener per platform:
   - macOS: `open`
   - Linux: `xdg-open`
   - Git Bash: `cmd //c start ""`
   - WSL: `wslview` or `explorer.exe`

   Never use `open` on Linux. `MXTK_NO_OPEN=1` suppresses it (generalising `MXTK_NO_GUIDE`).
3. **Always print one stable, machine-readable line:**
   `MXTK-SURFACE kind=dashboard path=/abs/index.html opened=yes|no lane=cloud summary="Stage 3: 4 PASS · 1 PENDING (gate blocked on CAC-3)"`
   plus a human-readable version. This line is the contract the skill reads.
4. **Report the guide sentinel honestly.** `init-project.sh` writes `.guide-shown` *only when
   something was actually shown*: either a local open succeeded, or the agent will surface it
   (lane `cloud`). It never writes it when no opener exists and the user saw nothing. This
   fixes the bug above without weakening the first-touch rule, which stays the single source
   in `CLAUDE.md`.

### 3.2 Instruction: a short section in `skills/conversion-runbook.md` §1b (Live Checklist Protocol)

This stays prose, because only the agent can call its own tools.

> When a toolkit command prints an `MXTK-SURFACE` line, post its `summary` in the checklist
> update. Then, if `opened=no`:
> - **Claude Code with an artifact/file-card tool:** publish the file. Do this only if
>   `PROJECT.md` has `Display: artifact` CONFIRMED. Ask once at CAC-1 (it is a publish, even
>   though private). Republish to the same URL on later refreshes and reuse the link in the
>   checklist.
> - **Any other host:** give the absolute path as a clickable link, plus the summary.
>
> Never open `toolkit-guide.html` because of this rule. The first-touch rule governs that.

The **Live Checklist Protocol stays the primary channel.** Chat text works on every host and
survives compaction. The surface line just adds a pointer to the richer page at each gate. So
"kept up to date" means:
- the checklist in chat, every item;
- plus a persistent link, the artifact URL or the path, at every gate repost.

### 3.3 Register line

`Display: artifact | local-browser | path-only` is recorded in `PROJECT.md` and asked once as
part of CAC-1. A cloud session cannot see the user's screen, so this is a question for the
user, not an inference.

### 3.4 Optional, Claude-Code-only add-ons (later, opt-in)

- **Statusline:** a `statusLine` command that cats a one-line `.claude/.mxtk-status` written
  by `gate-check.sh`. This keeps progress visible without chat noise. It is cheap and has no
  network.
- **Hook:** a `PostToolUse` hook on `bin/gate-check.sh` runs that re-render the dashboard.
  Probably unnecessary, since gate-check already regenerates it.

### Respecting the toolkit's rules

- **Skills over scripts.** Detection and opening are instruments (row 1: they touch the OS).
  "Publish it / ask consent / where to link" are instructions.
- **Generic first.** Lives in `bin/lib`, not in any pipeline. Works for every entry mode.
- **Field-proof.** Needs captured env dumps (names plus the flag values only) from at least:
  - macOS Terminal
  - Git Bash on Windows
  - a Claude Code cloud session (this one)
  - VS Code with Claude Code
  - VS Code with Copilot agent
  - Cursor agent

  Each goes in as a golden fixture, with one cited field run per CLAUDE.md "Shipping an
  instrument".
- **Blocking guard rules.** Not applicable: `show.sh` never blocks, and a failed open is
  `opened=no`, never an error exit.

## 4. Feasibility and risks

- **Brittle signals.**
  - `CLAUDE_CODE_ENTRYPOINT` is undocumented. So are Copilot's `AI_AGENT` and Windsurf
    anything; Codex's variables are test plumbing.
  - Design rule: **behaviour depends only on documented signals** (`CLAUDE_CODE_REMOTE`,
    `CLAUDECODE`/`CHILD_SESSION`, `CURSOR_AGENT`, `CI`, `SSH_*`, `DISPLAY`, platform).
    Undocumented ones are logged as `agent=` for diagnostics only.
- **False positives.** IDE terminals set agent variables for humans too. That is harmless here,
  because the action depends on GUI availability, not on the agent brand.
- **Privacy.**
  - An Artifact is private by default but is still a **publish**: project and client data
    leaves the machine for claude.ai. It needs explicit, recorded consent (the `Display:`
    register line), never inference. The dashboard can carry client names and BRD content.
  - A cloud session's files are already on Anthropic infrastructure, but publishing creates a
    new, linkable object.
  - Codex/Copilot hosts have no equivalent. Never post content to any host-specific service
    from a script.
- **Performance.** Pure env tests plus a cache file: well under 10 ms, no network.
- **Stale cache.** The lane changes when the same project is opened from cloud vs a laptop.
  Key the cache by session id, or just don't cache: detection is cheap enough.
- **Remote VS Code.** `file://` paths do not cross the SSH boundary. Do not attempt serving by
  default; it opens a port.

## 5. Open questions

1. Will Anthropic document `CLAUDE_CODE_ENTRYPOINT`, or an equivalent "surface" variable, and
   a "has artifact capability" signal for child processes? Would it be worth a feature request?
2. Copilot: confirm `VSCODE_AGENT` (and its value) from the VS Code 1.121 notes or source.
   Does Copilot *cloud* (coding agent in Actions) set anything beyond `GITHUB_ACTIONS`?
3. Windsurf: capture a real env dump from a Cascade-run command.
4. Codex: does the Linux (Landlock) sandbox set `CODEX_SANDBOX`? Does the macOS Seatbelt
   profile allow `open`? What does Codex cloud expose?
5. Is a markdown companion (`index.md` beside `index.html`) worth generating, so VS
   Code-family hosts can show a rendered preview natively (`code -r index.md`, then the user
   presses Ctrl+Shift+V)? `bin/lib/html-to-md.py` already exists.
6. Debian-family `open` → `openvt`: verify on a current Ubuntu image. It decides whether
   today's `init-project.sh` misbehaves on Linux desktops.
7. Does the Claude Code Desktop local session expose its file preview pane to a `Bash`-run
   script in any way? Today it seems agent-tool only.

## 6. Next steps (in order)

1. **Bug fix, small, now.** Make `init-project.sh` write `.guide-shown` only when a surface was
   actually shown. Add the Git Bash opener (`cmd //c start ""`). Skip `open` on non-macOS.
   Fix the bare `open` in `skills/learned-skill-ux-audit.md:290`.
2. **Factor the lane detection.** Move it from `doctor.sh` into `_common.sh`
   (`mxtk_env_lane`, `mxtk_has_gui`).
3. **Add `bin/lib/show.sh` and the `MXTK-SURFACE` line.** Wire it into `init-project.sh` and
   `gate-check.sh` (dashboard) first.
4. **Add the §1b instruction paragraph and the `Display:` question to CAC-1.**
5. **Field run.** Capture env dumps on the six hosts listed above, commit them as golden
   fixtures, and cite the field run.

## Sources

- Claude Code env vars (`CLAUDECODE`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_REMOTE`, `CLAUDE_CODE_REMOTE_SESSION_ID`, `CLAUDE_CODE_BRIDGE_SESSION_ID`): https://code.claude.com/docs/en/env-vars
- Claude Code on the web: https://code.claude.com/docs/en/claude-code-on-the-web
- Feature request, environment kind for child processes: https://claudeissues.com/issue/43425-feature-expose-claude-code-environment-kind-to-child-processes-bash-tool-hooks-p
- VS Code 1.121 release notes (`VSCODE_AGENT`): https://code.visualstudio.com/updates/v1_121
- VS Code terminal docs (shell integration env injection): https://github.com/microsoft/vscode-docs/blob/main/docs/terminal/profiles.md
- Cursor agent terminal (`CURSOR_AGENT`): https://cursor.com/docs/agent/terminal
- Cursor forum (`CURSOR_TRACE_ID`): https://forum.cursor.com/t/cursor-conversation-id-through-environment-variables/160346
- Codex `CODEX_SANDBOX=seatbelt` (AGENTS.md, mirror of openai/codex): https://forge.lthn.ai/core/core-agent-ide/raw/commit/d4533a0bb33f61e8214af3085eb8a95fb159dfd5/AGENTS.md
- Codex `CODEX_SANDBOX_NETWORK_DISABLED` observed in the App: https://github.com/openai/codex/issues/13373
- Codex cloud environments: https://learn.chatgpt.com/codex/environments/cloud-environment
- Prior art:
  - am-i-vibing: https://unpkg.com/am-i-vibing@0.5.0/README.md
  - is-ai-agent: https://docs.rs/is-ai-agent
  - @vercel/detect-agent: https://socket.dev/npm/package/@vercel/detect-agent/diff/1.0.0
- Toolkit references:
  - `bin/init-project.sh` (~L692-715)
  - `bin/doctor.sh` (~L172-208, lane detection)
  - `project-bin/_common.sh` (`mxtk_platform`)
  - `skills/skills-over-scripts.md`
  - `skills/interview-protocol.md` §3
  - `skills/learned-skill-ux-audit.md:290`

Caveat: several pages (cursor.com, code.visualstudio.com, unpkg, agentpatterns.ai) were
unreachable from this cloud container's allow-listing proxy. Their content is cited through
search-result summaries and should be re-checked directly before implementation.
