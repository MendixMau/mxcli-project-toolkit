# Dispatching — override four harness defaults on every call
**Applies to:** any mxcli project where the lead (main session) starts subagents.
**Purpose:** *How* to word a dispatch. *When* to dispatch and on which tier is
`conversion-runbook.md` §1c; setting agents up is `agent-roles.md`.

**Trigger:** you are about to start a subagent, send one a fix round, or are reading an
agent-stop notice.

**Harness note.** Forks, resumes, task notices and per-call model naming are Claude Code concepts.
On other harnesses (Copilot, Cursor, Windsurf) the equivalent of every override below is **a fresh
session per task**, opened with a written brief, on the model you chose for it.

Every default below is what the harness does when the call says nothing. In a 20-task,
89-subagent UX-fix run (2026-10-12, 663.6M tokens, #288) none was overridden, and each one
shows up in the bill:

| Harness default | What it cost in that run | Override |
|---|---|---|
| The subagent inherits the lead's model | 15 of the 21 subagents on the most capable model got it by inheritance alone: read-only lint planners, a severity judge, a root-cause investigator, a PR drafter. 48.1M tokens, 7.2% of everything | 1 |
| A scan is started as a fork | 6 forks started at 178–210k tokens of inherited context: 37.5M, 7.7% of subagent tokens. Three read-only scan forks made 2–7 tool calls each | 2 |
| A fix round resumes the implementer | 15 resumes cost 46.6M (9.5%), 3.1M each, because a resumed agent re-reads its 120–215k context on every turn. The narrow re-reviews in the same run cost 0.2–1.2M each | 3 |
| Every notice gets a turn | 130 task notices to the lead: 96 of the turns after them made no tool call, 19.9M. 20 notices reached subagents that had already reported | 4 |

1. **Name the model on every call.** A stub carries `model:` in its frontmatter
   (`sync-project.sh --pin-models` repairs drift in a completed one); an ad-hoc call carries
   nothing and silently runs at the lead's price. Pick the tier from §1c's tier table and write
   it on the call. Read-only planning, judging, root-cause reading and drafting a PR or report
   are **mid**: their output is checked by the lead or a gate. Transcriptions and `SHOW` dumps
   followed by a check are **cheap**. Only §1c's strong rows get the most capable model.
2. **Scans start fresh, with a written brief — never as a fork.** A fork carries everything the
   lead has read; a scan needs a question, the paths to read and the file to write. The brief
   says: the question, the files or globs, the output file and its shape, the model, and "you are
   a dispatched helper: skip the session-start ritual". If you cannot write the brief without
   the conversation, a fact the scan needs lives only in chat — write it into `PROJECT.md`
   first, then dispatch.
3. **A fix round goes to a fresh, narrow fixer — not the resumed implementer.** Its brief is the
   review file (each finding with file and line), the commit range (`git diff <base>..<head>`),
   the module brief, and the gate to re-run. *What is lost:* the implementer's discarded
   attempts and any reason it never wrote down. *How the brief covers it:* the review file
   carries the evidence, the diff carries the work, and the implementer's returned report must
   list every choice the brief did not dictate — require that line in every implementer brief.
   **Every brief that drives the app or its tests also says:** "read `.mxcli/project-facts.md` first" (made by `bin/project-facts.sh --out .mxcli/project-facts.md` just before dispatch: ports, reset and restart scripts, e2e helper libs, secret key names, screenshot folders). It stops each helper re-discovering them.
   Resume only when a finding needs the implementer's unwritten reasoning, and say why in the
   dispatch. A fresh fixer has not been measured head-to-head against a resume yet; the first
   run that does both records the numbers in `process/`.
4. **Coalesce notices per lane; a notice that needs nothing gets no turn of reply.** Dispatch a
   lane's independent units in one message as parallel foreground calls, so N results arrive in
   one turn instead of N notices. With background agents, a notice whose result the next step
   does not need yet gets no reply; read the lane's files when its last unit lands. Never send a
   message to an agent that has already reported — that restarts it at its full context.
   A report ending in `question` blocks always needs its turn: render the blocks for the user per
   `interview-protocol.md` §3 → "Asking from a subagent" (`AskUserQuestion` on Claude Code), then
   end the turn — never relay them as prose. A question returned in prose instead (an older stub)
   gets the same treatment: build the options from it.

**Parallel by default for work that never touches the model; one writer per `.mpr`.**
Dispatch these as one batch, not one after another: wireframes (one agent per screen, after the
design system exists), BRD drafts (`bin/facts-lock.sh`, `brd-generation.md`), journey drafts,
follow-up docs, page review and defect diagnosis against the running app (read-only), and MDL
scripts for the ready set drafted as text (wireframe-built pages excepted, below). Exactly one agent per `.mpr` applies scripts to it (`exec.sh`) and owns
its running app (a multi-app project has one writer per app); parallel authors hand over scripts,
never a model.
- Shared parts (access grants, navigation, theme/SCSS, seed data) get one named owner before the
  batch starts; authors list what they need in a notes file and never write "someone else adds it".
- Pages built to a wireframe or design are drafted and applied one at a time: the author must run
  and look at its own page before handing over, and parallel authors cannot. Simple CRUD pages in
  the low-risk ready set, and non-page rows (entities, microflows, security), follow "draft the
  ready set in parallel, apply one at a time" in `iterative-build-loop.md`.
- Read-only agents on the running app log out after each login — `ui-loop.md`.

*Measured (#732):* 4 wireframe-built pages from parallel authors who could not run their page, plus one executor,
took 40 min against 16 serial; first journey run 10/31 (two microflows with no access grant, one
reserved widget name chosen twice, three pages broken on screen that passed `mxcli check`).

Done when: the batch names its N drafts; each of the 4 shared parts (access grants, navigation,
theme/SCSS, seed data) has 1 named owner; there is 1 writer per `.mpr`.

**App restarts: the implementer restarts its own app, through one script only.** Write this into
every implementer brief: "When `exec.sh` prints `restart needed`, or `unknown — restart if
behaviour looks stale` and it does, run `./bin/app-restart.sh` yourself and carry on; never
stop or start an app another way (no `pkill`, no second `run --local`) or touch another lane's
app." The helper stops only the pid that `run --local` recorded for that project and refuses
otherwise (`ui-loop.md` § "What watch picks up"). Why the old lead-only rule went: `process/baseline-incident-history.md` § DP1. If the
helper refuses (exit 3), the app does not come back (exit 1), a process it did not record
holds the app or admin port (exit 4, nothing started; the recorded app may already be stopped), or the stop left a live
MxTest after-startup in place (exit 5, nothing started), the implementer reports
`BLOCKED NEEDS_RESTART` with its output, as before.

**STOP: a per-row brief carries only the per-row checks of the project's `Pipeline mode:`**
(balanced: the exec gate; on a page row one 1280 LOOK and one run of the journeys that reach it;
`.test.mdl` only when the module's Unit is yes and the `Every change` row opts in). The full journey
set, second personas and the 390 + 1280 LOOK go in the module-close brief. Journey-demanding
row briefs took 36–41 min; a batch brief without one applied two rows in ~10 min (#686).

**Stub check.** Before the
first dispatch of an agent run `bin/check-stubs-filled.sh <project-root> [agent]`: exit 3 names the
unfilled `{{...}}` slots, and the stub refuses its first row until they are filled (a dispatch that
skipped this burned 125k tokens on the refusal). It only reads, so filling the stub is never blocked.

**Prefix you do not control.** Every subagent turn also carries the harness's skill listing,
tool and MCP notes and the instruction chain — 47–48k tokens in that run before the brief was
read, about 40% of subagent volume. Each installed skill and plugin adds to it on every turn of
every subagent: disable the ones a project does not use. The toolkit keeps its own share short
(`CLAUDE.local.md`'s session-start ritual is main-session only and does not repeat what
`gate-check.sh` prints).

**Done when**, for each dispatch batch: N of N calls name a model; 0 scans started as forks;
every fix round names its review file and commit range; 0 messages sent to agents that already
reported. After a run, `bin/context-audit.sh --project <dir>` section 1 gives the subagent start
size (median, p90, max): a p90 near the lead's own context means a fork slipped through.
