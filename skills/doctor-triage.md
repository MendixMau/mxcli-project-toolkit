# doctor.sh is red — triage before you propose a fix

**Applies to:** any mxcli project, on any platform — macOS, Windows/Git Bash, Linux, container, cloud.
**Purpose:** turn a red `bin/doctor.sh` line into the right response. Three different things produce
red — *my environment is wrong*, *the toolkit's own self-check is wrong*, *this line does not apply
in my lane* — and they get conflated, because from the report text they look identical.

**Why this file exists (field incident, 2026-09-22).** Four people spent an afternoon in one Slack
thread on macOS setup. Three distinct failures were treated as one, and the first confident answer
from a knowledgeable human — *"install Studio Pro 10.24.18"* — could not have fixed any of them.
Meanwhile one colleague was correctly shipping with two FAILs open, and nobody else knew which two
were ignorable, so everyone else read all red as blocking.

---

## Step 1 — Read the machine, not the message

The report text is a hypothesis about your machine. **A wrong-platform binary, a wrong-architecture
binary and a missing binary all render the same way** — `mxbuild not found/executable` versus
`mxbuild exists but cannot run (exit 126)` are one line apart in the output and worlds apart in the
fix. Never propose a fix from the string alone.

Run the full report against the project (not `--quick`), keep the output, then establish the facts
it was guessing at. Find the actual things; do not recall them:

```bash
bin/doctor.sh <project-dir> 2>&1 | tee /tmp/doctor.txt   # the full report, kept
uname -sm                                                 # OS + arch of the machine RUNNING this
ls -d /Applications/Mendix\ Studio\ Pro*.app 2>/dev/null  # macOS: which installs actually exist
ls -d "/c/Program Files/Mendix"/* 2>/dev/null             # Git Bash: same question
```

Then, for each install found, ask whether it carries a bundled `mx` at all — `<install>/Contents/modeler/mx`
on macOS, `<install>/modeler/mx.exe` on Windows — and for every binary the report named a path for,
ask what kind of file it is:

```bash
file "<the exact path doctor printed>"    # Mach-O / PE / "ELF ... aarch64" — the whole answer
```

**Done when:** for every FAIL and WARN in the report you can state three things — the exact path
doctor resolved, whether that path exists, and what `file` says it is. N red lines, N complete
answers. A line answered from the report wording is not answered.

## Step 2 — Put each red line in one of three classes

| Class | The tell | Response |
|---|---|---|
| **A — my environment is wrong** | The path doctor printed is absent, or `file` says a format this OS/arch cannot run | Fix the environment, in the lane you are actually on (Step 4) |
| **B — the check itself is wrong** | The message describes the *checker* failing, not the thing checked. Anything of the shape "the gate cannot read…", "cannot resolve…", "no answer within N s" | Do not touch your machine yet. Reproduce, then log it (`upstream-feedback.md`, `bug-submission-checklist.md`) |
| **C — does not apply in this lane** | The capability is genuinely unavailable *and unnecessary* here, or is provided by a different tool than the one probed | Record with the reason; change nothing |

**Show the failure — Class B misread as Class A.** Until `c0ea53c`, doctor's gate self-test copied
the model into a scratch dir under a renamed basename while copying `mprcontents/` verbatim beside
it. `mprcontents/` carries an internal record of the real basename, so mxbuild bailed *before*
writing any error file, and the self-test printed:

```
  FAIL  gate self-test: gate cannot read mxbuild's error file (baseline run) — a real error would go unseen
```

That string means **the gate is broken**. The gate was fine; the self-test was broken. It sent
people to audit their Studio Pro, their Java and their model.

**Show the failure — Class A answered by inference.** A Mac reported the standalone mxbuild as
unable to run. The answer *"install Studio Pro 10.24.18"* arrived in about two minutes, and no
Studio Pro version on earth would have fixed it: that binary is a Linux ELF (Step 4). One `file`
call would have closed the question before the thread started. **An instant confident answer to a
setup failure is the signature of inference from the message text.**

## Step 3 — Decide which reds block you, and say so for all of them

Do not keep a list of ignorable FAILs; it goes stale the next time doctor grows a section. Derive it
per line, with three questions:

1. **What does this check protect?** Doctor states the consequence in its own `note` lines — read
   them; they name what stops working, not what is missing.
2. **Is that on the critical path of my next stage action?** Not of the project — of the next thing
   you are about to do.
3. **Does another lane give me the same guarantee?** (Step 4 — a bundled `mx`, a container build,
   `mxcli docker check`.) If yes, this red is an inconvenience, not a block.

No to (2) or yes to (3) → not blocking. **One exception that always blocks, regardless:** anything
that would make the mxbuild gate *skip silently* or read a broken model as clean. A gate that cannot
fail is worse than no gate, because it is counted as evidence.

**Done when:** the report's own counts are matched line for line. If it ends `N FAIL, M WARN`, your
note carries N+M lines, each marked `blocking` / `not-blocking, because …` / `waived, because …`.
A line you did not mention is not "fine" — it is undispositioned. This is exactly what the 2026-09-22
thread lacked: two FAILs were correctly ignored by the one person who knew why, and nothing on disk
said which two.

## Step 4 — Know which of the three toolchain lanes you are on

Every mxbuild/`mx` red belongs to exactly one lane, and the fix is lane-specific.

| Lane | Where the binary comes from | Runs on | What red means |
|---|---|---|---|
| **Studio Pro bundled** | the install's own `modeler/mx` (`Contents/modeler/mx` on macOS, `modeler/mx.exe` on Windows) | macOS, Windows | The install is missing, or is a build that ships no bundled `mx` — list the installs and look for the file |
| **Standalone CDN toolchain** | `mxcli setup mxbuild` / `doctor.sh --install`, cached under `~/.mxcli/mxbuild/` | **Linux only** — it is an ELF | On macOS or Windows this lane is simply unavailable; no Mendix version changes that |
| **Container** | the same Linux toolchain, inside a container | anywhere a container runtime runs | See the limitation below before believing this one |

**macOS: Mendix 11 is a platform requirement, not a toolkit preference.** macOS Studio Pro was Beta
throughout 10.x and those builds ship **no** bundled `mx`; Mendix 11 is the first macOS build that
carries one. So on a Mac, the bundled-`mx` lane does not exist below 11 — and the CDN lane never
existed there at all. Verify by listing the installs and testing for the file (Step 1), **never**
from a remembered version number: version lists rot, and two people in the 2026-09-22 thread had the
toolkit itself checked out at two different paths.

**The container lane is runtime-agnostic; doctor's probe is not.** Docker, Podman, Rancher Desktop
and colima all serve this lane. This team cannot use Docker Desktop for licensing reasons and runs
Podman — and `doctor.sh` currently probes only the `docker` command, so such a machine gets
`WARN  docker is not installed` while the lane is in fact available. Read that WARN as Class C,
confirm the lane by running your own runtime's `info`, and leave it: a separate in-flight fix is
widening the probe. **Do not patch doctor from inside a triage.**

## Step 5 — Check that your findings are about the machine you mean

If the session is running in a VM, container or mounted sandbox, every binary finding is about
*that* environment. Compare the `uname -sm` from Step 1 against the host you are actually setting
up; if OS or arch differ, **none of your binary findings transfer** — a missing or `exec format
error` `mx` inside a Linux ARM64 VM mounting a Mac folder says nothing about what the Mac can run.
That is precisely what one colleague hit in the 2026-09-22 thread.

**Done when:** every finding you report carries the OS/arch it was measured on, or is not reported.

## Step 6 — Write the disposition down

Put the Step 3 list — all N+M lines — in the project's `PROJECT.md` or session notes, with the
toolkit commit the report came from. That is the artifact the next person reads instead of asking
the thread. A red line classed **B** additionally goes upstream per `upstream-feedback.md`; a red
line classed **C** carries its reason, because an unexplained ignored FAIL is indistinguishable from
an unnoticed one.

**Related:** `tool-output-is-not-ground-truth.md` (the general form: run a control before reporting
an absence) · `cloud-dev-environment.md` (the container lane as a working setup) ·
`handoff-to-studio-pro.md` (when a human has to open the model) ·
`mpr-corruption-and-sp-load-errors.md` (the model is broken, not the toolchain).
