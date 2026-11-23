**Repo:** `mendixlabs/mxcli`
**Source:** field run 2026-11-16 — Windows 11, Git Bash, mxcli **v0.32.0**, no Studio Pro, no Docker, an empty project folder under OneDrive. Code read on `main` at 121c9b5 (2026-11-15).
**Status:** NOT YET FILED by the toolkit — upstream duplicate: mendixlabs/mxcli#1605 (ledger `BUG-DRAFT-mxcli-new-linux-mxbuild-on-macos`)
**Severity:** Medium — no data loss; costs an ~800 MB download and a session, and ends without a reason.

---

# `mxcli new` on Windows/macOS without Studio Pro downloads the Linux mxbuild, which cannot run there

## Summary

`mxcli new <Name> --version X.Y.Z` resolves `mx` through `docker.ResolveMxForNewProject`, which
falls back to `DownloadMxBuild` when no local Studio Pro of that version exists. The Mendix CDN
publishes **Linux** mxbuild only, so on Windows and macOS that download can never yield a
runnable `mx`. `mxcli setup mxbuild` and `run --local` already know this
(`NativeMxBuildForSetup`, issue #916) and refuse up front with a clear hint; `new` does not.

## Observed

`mxcli new <Name> --version 11.11.0 --output-dir "$PWD"` started the MxBuild download, stopped
with no further step output and no error line, and left a partial cache
(`~/.mxcli/mxbuild/11.11.0`, 373 MB) and an empty folder. Whether the stop was the agent
harness ending the command or mxcli itself is **not proven**; either way the run could not have
succeeded, because what it was downloading is a Linux ELF.

## Expected

On a non-Linux host with no Studio Pro of the requested version, fail before downloading, with
the same guidance `setup mxbuild` gives: install Studio Pro X.Y.Z, or `--mxbuild-path`, or run
inside the Dev Container / a Linux host.

## Suggested fix

In `ResolveMxForNewProject`, call `NativeMxBuildForSetup(runtime.GOOS, version)` before
`DownloadMxBuild` and return its error + guidance on non-Linux hosts (the pattern
`resolveMxBuildForLocalOn` already uses).
