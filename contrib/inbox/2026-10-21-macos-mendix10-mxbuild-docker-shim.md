# macOS + Mendix 10: no native mxbuild, so the gate needs a Docker shim, and doctor.sh reads a shim that exits 3 on `--version` as broken

**From:** a field project (anonymised) — a Mendix 10.24.18 app changed with mxcli v0.27.0 and this toolkit, on an Apple Silicon Mac
**Date:** 2026-10-21
**Kind:** learning
**Field evidence:** `exec.sh`'s mxbuild gate and the microflow tests both ran on this Mac only
through a Docker shim; each fact below was re-checked on 2026-10-21.
Toolkit master 393d253. Related: MendixMau/mxcli-project-toolkit#525.
**Proposed target:** a "Mendix 10 on macOS" row in the lane table of `skills/doctor-triage.md`
(line 100 says the CDN toolchain is Linux-only), and the probe note in `bin/doctor.sh`

---

## What is true on this Mac

- The Studio Pro 10.24.18 app bundle has no `mx` or `mxbuild` (its `Contents/modeler` holds 502
  files, none of them named `mx` or `mxbuild`).
- The cached 10.24.18 build in `~/.mxcli/mxbuild/` is a Linux ELF (`file`: ELF, ARM aarch64). `mxcli test --local` (v0.27.0) stops with "mxbuild from the Mendix CDN
  is a Linux binary and cannot run natively on darwin".
- Mendix 11 differs here. The Studio Pro 11.12.4 bundle holds `mx` and `mxbuild` as Mach-O arm64
  (`file`), and #525 reports a Mach-O mxbuild in the 11.14.0 cache. So doctor-triage's "Linux only"
  is right for Mendix 10 on a Mac and wrong for the 11 builds #525 looked at. Not run: the toolkit's gate on Mendix 11 here.

## The shim

`find_mxbuild` honours `MXBUILD_PATH` (`project-bin/_common.sh:557`), so a script there replaces
mxbuild. The toolkit calls it as `mxbuild --java-home=… --java-exe-path=… --write-errors=<file>
--target=deploy <mpr>` (`_common.sh:909-910`) and reads the file's `problems[]` (severity `Error`) and
`errors[]` (why nothing was checked). Name the file for the model version: `_common.sh:1044-1047`
warns when the path doesn't contain it.

A working one is about 100 lines of bash:

1. Take `--write-errors=` and the one argument not starting with `--` (the .mpr); ignore the rest.
2. Read the version from the .mpr: `select _ProductVersion from _MetaData`. Require the matching
   Linux `mx` in the mxcli cache; otherwise stop (a different version gives a false green).
3. Start a throwaway container with that `mx` and the project mounted read-only, copy the project
   in, run `mx check <mpr> -j check.json`.
4. Convert `check.json` to `{"errors":[],"problems":[{"severity":"Error","errorCode","message",
   "locations"}]}`, and compare its count with the line `The app contains: N errors`.
5. Exit 0 clean, 1 errors, 3 not run. Every failure to check (Docker down, wrong version, timeout,
   count mismatch) exits 3 and writes `{"errors":[{"message":"…"}],"problems":[]}`: the gate reads
   non-zero exit with no problems as "not verified" (`_common.sh:949`).

It does no deploy build (no Java compile, no theme bundling). On a 10.24.18 test app it printed
`The app contains: 0 errors.`, exit 0, in 52 s. A sibling script runs `mxcli test --local
--skip-app-startup` in a container with the same 0/1/3 exits; in the field it ran 110 tests, all
passed, exit 0 (hsqldb instead of PostgreSQL, the after-startup microflow not run).

## The doctor probe

`probe_runs` (`bin/doctor.sh:145-166`) runs `<mxbuild> --version`, then `--help`; exit 126/127 means
a wrong-platform binary, and any other non-zero exit with both is "cannot run". `doctor.sh:892-899`
then reports "mxbuild exists but cannot run (exit 3)" and sets `GATE_OK=0`. A shim that wants an
.mpr and exits 3 without one fails this. Checked by running the extracted function on two stubs:
one without special handling returned 3; one answering `--version`/`--help` with exit 0 and a line of
text returned 0 (`how=--version`). So a shim should answer both with exit 0 before it looks for an
.mpr or starts Docker.
