**Repo:** `mendixlabs/mxcli`
**Type:** Feature request
**Source:** toolkit `bin/doctor.sh` (14 probes, field-run on macOS, Linux containers and Windows Git Bash since 2026-08); the failures it catches are listed below with the incident that motivated each
**Status:** NOT YET FILED
**Suggested labels:** enhancement, dx
**Duplicate check:** searched `doctor diagnose health` 2026-09-03 — nothing.

---

# `mxcli doctor`: one command that says what this machine is missing before a pipeline stage discovers it

## The gap

mxcli has `check`, `lint`, `report`, `test` for the model, and `setup mxbuild` for one dependency. There is no command that probes the *machine* and says, in plain language, what will fail and why. Every environment assumption is discovered halfway through a build, where it reads as "mxcli is broken" rather than "my machine is missing something".

## What it should probe (each line is a real incident)

| Probe | Incident it would have caught |
|---|---|
| mxbuild **executes** (not just `--version` exits 0; exit 126/127 = wrong platform) | A Linux ELF mxbuild cached on macOS/arm64: the build gate reported "0 errors" for multiple commits without running anything. Also: a current Studio Pro mxbuild dropped `--version`, so a naive probe read a healthy binary as broken. |
| Java present and the version mxbuild wants | `run --local` on Mendix 11.14 under JDK 25 fails the version check |
| Split-model `.mpr` (`mprcontents/` with N units) vs monolithic | `run --local` and `marketplace install` collapse a split model; users need to know which they have before either command |
| Process-spawn latency (25 forks, ms each) | 152 ms per fork on a Defender-managed Windows laptop turns any script-heavy step into a 5–15 minute "hang" |
| Path under OneDrive/Dropbox, path contains spaces, path length vs the 259-char MxToolset limit | sync fighting model writes; `mxcli new` hangs on an over-length path |
| CRLF checkout of shell scripts / `core.autocrlf` | every script fails on line 1 under Git Bash |
| WSL detected | WSL cannot see Studio Pro or a Windows mxbuild |
| Docker or substitute (Rancher, Podman, colima) reachable | `docker check` / `test` silently unavailable on corporate machines |
| Node present | Playwright / page tooling |
| Studio Pro holding the `.mpr` open (`.mpr.lock` with a live PID) | split-brain writes while Studio Pro has the project open |

Output: `ok` / `WARN` / `FAIL` per line, a verdict, exit 0/1/2. `--install` may offer to fetch mxbuild via the existing `setup mxbuild`.

## Why in mxcli rather than around it

Half of this is knowledge only mxcli has (which mxbuild it will use, which Java, what a valid split model looks like). Every consumer is otherwise re-deriving it in shell, and the shell versions cannot run where mxcli is invoked from Node or Windows without Git Bash.

## Prior art

The toolkit's `bin/doctor.sh` is a working reference implementation of every row above (POSIX shell, no dependencies, `--install` behind a printed plan and `[y/N]`); happy to contribute it as the spec.
