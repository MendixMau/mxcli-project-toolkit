# Windows full test-run — paste-able prompt

**Applies to:** the toolkit itself, on a Windows machine with Git Bash (MSYS)
**Purpose:** one prompt you paste into a fresh Claude Code (or any agent) session on Windows.
The session clones the toolkit, runs every guard, both fixture suites, the Windows-specific
fixtures with their correct subjects, and a field run on a **scratch copy** of a real Mendix
project. It writes one results file and stops. You read the file, not the transcript.

Why this exists: `CLAUDE.md` → "Shipping an instrument" rule 3 ("Both platforms") and rule 2
("Both layouts") are asserted by fixtures that were written on macOS and Linux. Nobody has run
the whole set on the platform they claim to cover. This is that run.

**Before you paste.** Fill in the two placeholders in the prompt:

| Placeholder | What to put there |
|---|---|
| `<PROJECT-ROOT>` | An existing Mendix project on this machine that uses the toolkit (has `.mpr`, `./mxcli`, `mdlsource/`). It is copied; the original is never touched. Leave as-is to skip the field run. |
| `<TOOLKIT-REF>` | `master`, a tag (`v2026.09.22`), or a branch. Default `master`. |

Expected wall time: 20–40 minutes, most of it `bin/doctor.sh --install` and the wave2 suite.

---

## The prompt (copy from here to the end of the file)

````text
You are running the full Windows test run of the mxcli-project-toolkit. Work unattended:
do not ask me anything, do not stop for approval, do not open a browser tab. If a step
fails, record it and continue with the next step. When every step has run, write the
results file and stop.

RULES
- Platform is Windows with Git Bash (MSYS). Run everything with `bash <script>` from a Git
  Bash shell. Use forward slashes. Never use PowerShell for the toolkit scripts.
- Never modify the real project at <PROJECT-ROOT>. Every field step runs on a copy under
  ~/mxtk-win-run/. Never touch a real `.mpr` outside that copy.
- Commit nothing, push nothing, open no PR. The clone is disposable.
- Export these before the first script and keep them for the whole run:
    export LEAKGUARD_ALLOW_NO_DENYLIST=1     # fresh clone has no denylist file
    export MXTK_DOCTOR_SKIP_DOCKER=1         # docker probe is a separate step below
    export LC_ALL=C                          # word counts must match the maintainers' numbers
- For every step record: step id, exact command, PASS / FAIL / SKIP, the summary line
  (`PASS=n FAIL=m`, exit code, or the first error line), and elapsed seconds.
  SKIP needs a one-line reason. A step that emits nothing is FAIL, not PASS.
- Reading a script to guess its result is not running it. Every PASS cites output.

SETUP (S)
S1  mkdir -p ~/mxtk-win-run && cd ~/mxtk-win-run
    git clone https://github.com/MendixMau/mxcli-project-toolkit.git toolkit
    cd toolkit && git checkout <TOOLKIT-REF> && git rev-parse --short HEAD
    Record the sha. Every later relative path is from this clone root (call it $TK).
S2  Record the environment verbatim:
    uname -s ; uname -m ; bash --version | head -1 ; node --version ; git --version
    where python python3 py 2>/dev/null ; docker --version 2>/dev/null || echo "no docker"
S3  bash bin/doctor.sh --quick
S4  bash bin/doctor.sh
    Record every line that says MISSING, WARN or FAIL. Do not run --install yet.

GUARDS (G) — the same checks CI runs on every PR
G1  bash bin/check-scripts.sh
G2  bash bin/check-portability.sh
G3  LEAKGUARD_ALLOW_NO_DENYLIST=1 bash bin/check-no-client-data.sh
G4  bash bin/check-pr-discipline.sh origin/master
G5  bash bin/render-routing.sh --check
    Record the baseline word count it prints (expect ~72k of the 80k budget; a number over
    80,000 is FAIL even if the exit code is 0).
G6  bash bin/check-skill-routing.sh
G7  bash bin/check-docs-numbering.sh

SUITES (T) — full runs, explicitly wanted for this test
T1  bash tests/run-tests.sh -v
    Self-contained guard-script fixtures (inputs are generated at run time, nothing on disk).
T2  bash tests/wave2/run-all.sh -v
    Runs a bash -n syntax pass over every fixture first, then each fixture with the subject
    its `usage:` line declares. Known state on master: `test-bug06-freshness.sh` reports
    PASS=55 FAIL=1 and the runner still marks the fixture ok — record that as PASS(known).
    Any other fixture with FAIL>0 is a FAIL for this run. Record the runner's final tally.
    Save the full output: bash tests/wave2/run-all.sh -v > ~/mxtk-win-run/wave2.log 2>&1

WINDOWS-FOCUSED FIXTURES (F) — rerun singly so the Windows result is legible on its own.
Each takes its subject as $1; the subject is the path shown.
F1  bash tests/wave2/test-common-windows.sh project-bin/_common.sh
    This is the MSYS fixture: `foo` -> `foo.exe` mapping, `.exe`-first mxcli lookup, CRLF.
F2  bash tests/wave2/test-doctor-gate-selftest.sh bin/doctor.sh
F3  bash tests/wave2/test-doctor-docker-probe.sh bin/doctor.sh
F4  bash tests/wave2/test-bug07-08.sh project-bin/exec.sh
F5  bash tests/wave2/test-model-stamp.sh
    (subject is project-bin/model-stamp.sh, resolved inside the fixture; no argument)
F6  bash tests/wave2/test-dryrun-writes-nothing.sh bin/sync-project.sh
F7  bash tests/wave2/test-bug12-sync.sh bin/sync-project.sh
F8  bash tests/wave2/test-guide-reopen.sh bin/init-project.sh
F9  bash tests/wave2/test-render-routing.sh bin/render-routing.sh
F10 bash tests/wave2/test-routing-tier.sh bin/render-routing.sh
F11 bash tests/wave2/test-bug02-register.sh bin/gate-check.sh
F12 bash tests/wave2/test-source-ledger.sh bin/gate-check.sh
F13 bash tests/wave2/test-obligation-fidelity.sh bin/gate-check.sh
F14 bash tests/wave2/test-wrong-verdicts.sh bin/gate-check.sh
F15 bash tests/wave2/test-build-plan-json.sh project-bin/build-plan-status.sh
F16 bash tests/wave2/test-docs-numbering.sh bin/check-docs-numbering.sh
F17 bash tests/wave2/test-html-to-md.sh bin/html-to-md.sh
    Input is the committed capture tests/wave2/fixtures/html-to-md/Fleet\ Portal\ Requirements.html
    (a filename with a space — that is the point on Windows).
F18 bash tests/wave2/test-page-fidelity-mocks.sh project-bin/page-fidelity.js
    Input is tests/wave2/fixtures/page-fidelity-mocks/ (two wireframes + two MDL files;
    CAPTURE.md there says what is verbatim and what was scrubbed).
F19 bash tests/wave2/test-app-report.sh bin/app-report.sh
F20 bash tests/wave2/test-app-layer-map.sh bin/app-layer-map.sh
    F19/F20 read the committed fixture fixtures/app-analysis/ (app-dossier.md + facts/*.json).
F21 bash tests/wave2/test-assemble-prototype.sh project-bin/assemble-prototype.js
F22 bash tests/wave2/test-prototype-links.sh project-bin/check-prototype-links.js
F23 bash tests/wave2/test-prototype-route.sh project-bin/prototype-route.js
F24 bash tests/wave2/test-wire-agents-kiro.sh bin/wire-agents.sh
F25 bash tests/wave2/test-install-claude-permissions.sh
F26 bash tests/wave2/test-token-burn.sh bin/token-burn.sh
F27 bash tests/wave2/test-harvest-learnings.sh

TOOLS ON COMMITTED INPUTS (I) — direct runs, no fixture harness, so a Windows path or
newline problem shows up as the tool's own error and not a fixture's.
I1  bash bin/app-report.sh --facts fixtures/app-analysis/facts --dossier fixtures/app-analysis/app-dossier.md -o ~/mxtk-win-run/app-report.html
    Then: test -s ~/mxtk-win-run/app-report.html && grep -c '<h' ~/mxtk-win-run/app-report.html
I2  bash bin/app-layer-map.sh --facts fixtures/app-analysis/facts --json > ~/mxtk-win-run/layer-map.json
    Then: node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" ~/mxtk-win-run/layer-map.json
I3  node project-bin/page-fidelity.js --no-log tests/wave2/fixtures/page-fidelity-mocks/grouped-overview.html DemoOverview tests/wave2/fixtures/page-fidelity-mocks/demo-overview.mdl
I4  node project-bin/page-fidelity.js --no-log tests/wave2/fixtures/page-fidelity-mocks/mocked-list.html DemoList tests/wave2/fixtures/page-fidelity-mocks/demo-list.mdl
I5  bash bin/html-to-md.sh "tests/wave2/fixtures/html-to-md/Fleet Portal Requirements.html" > ~/mxtk-win-run/fleet.md
    Then: wc -l ~/mxtk-win-run/fleet.md
I6  bash bin/brd-report.sh --help ; bash bin/triage-report.sh --help ; bash bin/questions-report.sh --help
    (exit 0 and a usage text each = PASS; these are the report tools with no committed input)
I7  bash bin/bug-lookup.sh CE0053
I8  bash bin/token-burn.sh --help
I9  bash bin/sync-labels.sh --dry-run
I10 bash bin/cut-release.sh --dry-run
I11 bash bin/exec-approval.sh --explain
I12 bash bin/interview-mode.sh --help ; bash bin/question-kinds.sh --help ; bash bin/open-questions.sh --help

FIELD RUN ON A SCRATCH COPY (P) — skip the whole block with reason "no project" if
<PROJECT-ROOT> was left unfilled or does not contain a .mpr.
P0  cp -r "<PROJECT-ROOT>" ~/mxtk-win-run/project
    cd ~/mxtk-win-run/project && ls *.mpr ; ls mxcli* ; ls mdlsource | head
    Record whether the .mpr is at the root (single-tree) or under app/ (two-tree).
    Record `./mxcli --version` (Git Bash maps ./mxcli to mxcli.exe; note which file exists).
P1  bash $TK/bin/init-project.sh ~/mxtk-win-run/project
    Then: test -e ~/mxtk-win-run/project/.claude/.guide-shown && echo sentinel-ok
    (the guide may open once here — that is the first-touch rule working; close the tab)
P2  bash $TK/bin/init-project.sh ~/mxtk-win-run/project
    Second run must be idempotent: no new files, no browser tab. Diff the file list before/after.
P3  bash $TK/bin/sync-project.sh ~/mxtk-win-run/project --dry-run
P4  bash $TK/bin/sync-project.sh ~/mxtk-win-run/project --strict
    Record the `Toolkit release:` line it prints.
P5  bash $TK/bin/gate-check.sh ~/mxtk-win-run/project
    Expect PENDING verdicts on a fresh scaffold, no crash, dashboard index.html regenerated.
P6  bash $TK/bin/gate-check.sh ~/mxtk-win-run/project --html --verbose
P7  bash $TK/bin/status.sh ~/mxtk-win-run/project --brief
P8  bash $TK/bin/doctor.sh --install --yes ~/mxtk-win-run/project
    This is the step that fetches mxbuild/Java on demand. Record what it installed and where
    (expect under ~/.mxcli/). Record every WARN.
P9  bash $TK/bin/doctor.sh --gate-selftest ~/mxtk-win-run/project
P10 unset MXTK_DOCTOR_SKIP_DOCKER; bash $TK/bin/doctor.sh --no-docker ~/mxtk-win-run/project; bash $TK/bin/doctor.sh ~/mxtk-win-run/project; export MXTK_DOCTOR_SKIP_DOCKER=1
    Two runs: with and without the docker probe. Record both docker lines.
P11 cd ~/mxtk-win-run/project && bash project-bin/install-project-hooks.sh --check
    (if the project has no project-bin/, use $TK/project-bin/install-project-hooks.sh --check)
P12 bash project-bin/model-stamp.sh fingerprint ; bash project-bin/model-stamp.sh check -q ; echo "exit=$?"
P13 MODEL_UNVERIFIED_OK=1 bash project-bin/model-stamp.sh check -q ; echo "exit=$?"
P14 Write a one-line MDL script that changes nothing:
      printf 'SHOW MODULES;\n' > mdlsource/_win-probe.mdl
    then: bash bin/exec.sh mdlsource/_win-probe.mdl
    (the project's own bin/exec.sh; falls back to $TK/project-bin/exec.sh if absent)
    Expect: snapshot taken, script executed, mxbuild check ran, no restore. Record the
    snapshot directory it created and delete mdlsource/_win-probe.mdl afterwards.
P15 ALLOW_UNVERIFIED=1 MXTK_NO_INSTALL=1 bash bin/exec.sh mdlsource/_win-probe.mdl
    (recreate the probe file first) — the "no install, no verify" path must also complete.
P16 bash project-bin/lint-gate.sh
P17 bash project-bin/app-facts.sh --skip-loops
    Record the facts dir it wrote and `ls` it (expect inventory.json, manifest.json, mdl/).
P18 bash $TK/bin/app-layer-map.sh ~/mxtk-win-run/project -o ~/mxtk-win-run/project-layer-map.html
P19 bash $TK/bin/app-report.sh ~/mxtk-win-run/project
P20 bash $TK/bin/wire-agents.sh ~/mxtk-win-run/project --with-kiro --dry-run
P21 bash $TK/bin/wire-agents.sh ~/mxtk-win-run/project --check
P22 bash $TK/bin/triage.sh ~/mxtk-win-run/project
P23 bash $TK/bin/source-sufficiency.sh init ~/mxtk-win-run/project ; bash $TK/bin/source-ledger.sh ~/mxtk-win-run/project
P24 Two-tree probe (rule 2, "Both layouts"): if the copy is single-tree, make a second copy
    with the .mpr moved under app/:
      cp -r ~/mxtk-win-run/project ~/mxtk-win-run/project-2tree
      mkdir -p ~/mxtk-win-run/project-2tree/app && mv ~/mxtk-win-run/project-2tree/*.mpr ~/mxtk-win-run/project-2tree/app/
    then rerun P5, P7, P12 against ~/mxtk-win-run/project-2tree and record whether each
    still finds the .mpr. If the copy is already two-tree, do the reverse (move the .mpr to
    the root) and rerun the same three.
P25 toolkit.env precedence: printf 'MXCLI_VERSION=0.0.0-probe\n' >> ~/mxtk-win-run/project/.claude/toolkit.env
    then rerun P7 and P12; the output must mention 0.0.0-probe (proves _common.sh reads the
    file on Windows). Remove the line afterwards.

RESULTS FILE
Write ~/mxtk-win-run/mxtk-windows-run-<YYYY-MM-DD>.md with:
1. Header: toolkit sha, <TOOLKIT-REF>, the S2 environment block verbatim, single-tree or two-tree.
2. One table for all steps S/G/T/F/I/P: `| id | command | verdict | summary line | seconds |`.
   Verdicts are exactly PASS, PASS(known), FAIL, SKIP. Nothing else.
3. Totals: PASS n / FAIL m / SKIP k over N steps (N is the number of ids listed above).
4. For every FAIL: the first 20 lines of its output, indented, plus the fixture's own tally.
5. A "Windows-only observations" list: any place Git Bash translated a path (C:\ vs /c/),
   any `.exe` mapping surprise, any CRLF warning, any script that needed `python` instead
   of `python3`, any tool doctor.sh said was missing.
6. Do not summarise, interpret, or propose fixes. Facts only. The maintainer triages.
Then print the totals line and the path of the results file, and stop.
````

---

## After the run

Paste the results file back to the maintainer session as-is. A FAIL there becomes either a
`contrib/inbox/` drop or a direct PR held to the field-proof bar (`CONTRIBUTING.md`); the
file itself is the "one field run, cited" evidence rule 4 asks for.

What this run deliberately does **not** cover: browser-driven tests (`project-bin/test-stack-up.sh`
needs a running app), MCP write sessions, and the pipelines under `pipelines/` (they need a
legacy source tree; run their own `README.md` steps separately if one is available).
