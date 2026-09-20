# Part B — install discipline, run headlessly in a cloud container, 2026-09-20

Run 1 and run 2 could only test retrieval: no mxcli binary was present. This run downloaded one
and did the whole chain for real. **Nothing here is inferred — every line is a command that ran.**

Environment: Linux cloud container, no Studio Pro, no GUI. mxcli **v0.22.0** from the GitHub
release (`mxcli-linux-amd64`, HTTP 200 — the 403 fallback in `cloud-dev-environment.md` was not
needed today). MxBuild 11.14.0 from `cdn.mendix.com`.

## What was proven

| Step | Command | Result |
|---|---|---|
| Download the CLI | `curl …/releases/latest/download/mxcli-linux-amd64` | ✅ 96 MB, `mxcli version v0.22.0` |
| Create an app headlessly | `./mxcli new UsiThemeProbe --version 11.14.0` | ✅ 9 modules, first build settled, no GUI |
| Read the model | `./mxcli -p UsiThemeProbe.mpr -c "SHOW MODULES"` | ✅ |
| Import the company's theme module | `mx module-import USI_Theme_Module.mpk UsiThemeProbe.mpr` | ❌ **refused, exit 117** |

## The install route, corrected against the binary

**There is no `mxcli import` command.** Run 1's eval sessions invented
`./mxcli import mpk <file> -p <app>.mpr` and I copied it into the manifest without probing. The
binary's actual surface, from `./mxcli --help` and the subcommands' own help:

- **`mxcli marketplace install <content-id> -p app.mpr`** — the preferred route, and the one to
  reach for first. Its help states why: it copies the module's units *with mxcli's own writer*
  rather than shelling out to `mx module-import`, which **rewrites MPR v2 as v1** (collapsing
  `mprcontents/` into one binary `.mpr`, one-way) and **refuses theme modules outright**.
  Requires a Personal Access Token and a marketplace content id — so it does not apply to a
  local `.mpk` sitting in a company brain.
- **`mx module-import <MPK> <MPR>`** — the local-file route, from the MxBuild bundle
  (`~/.mxcli/mxbuild/<version>/modeler/mx`), which `mxcli setup mxbuild` or `mxcli new`
  downloads. Argument order is package first, project second; reversed, it fails with
  `Unknown module package extension: .mpr`.

## The blocker, and it is upstream

```
$ mx module-import USI_Theme_Module.mpk UsiThemeProbe.mpr
The package could not be imported, because it was created with version 10.6.4 of Mendix
Studio Pro. Please open it in any version in the range from 10.21.0 to 10.24.99 first.
exit 117
```

Confirmed independently: the only version string in the package's own `project.mpr` is `10.6.4`.
So the file is a Mendix 10.6.4-vintage export and needs an upgrade hop through 10.21–10.24
before any 11.x app can take it.

**That hop cannot be done in this container.** The Mendix CDN publishes no 10.x MxBuild:

| Version | `cdn.mendix.com/runtime/mxbuild-<v>.tar.gz` |
|---|---|
| 11.14.0, 11.12.0 | HTTP 200 |
| 10.24.2, 10.24.1, 10.24.0, 10.23.0, 10.21.0, 10.18.0 | HTTP 404 |

So a headless upgrade hop has no binary to run. The remaining routes are all off this machine:
open the package once in a Studio Pro between 10.21 and 10.24 and re-export; or obtain a
re-exported package from whoever maintains it; or install it from the marketplace by content id
if it is published there, which is the `marketplace install` path and sidesteps module-import's
theme-module refusal entirely.

**Untested, and worth saying so:** whether module-import would *also* refuse this package for
being a theme module. The version check fired first, so that branch never ran.

## Can an old module package be upgraded headlessly? Yes — within a version window

Asked after the refusal, answered by probing rather than by opinion. **`mx convert` is exactly
the upgrade tool, and it is fully headless** (`mx convert INPUT... OUTPUT`, `-p` for in place).
It takes the **`.mpk`**, not the `.mpr` inside it — pointing it at the extracted project file
fails with `The input file '…project.mpr' is not an mpk file`.

The chain that would work, all CLI, no GUI:

```
mx convert <old>.mpk <new>.mpk        # upgrade the package
mx create-module-package <mpr> <ModuleName>   # or re-export from a converted project
mx module-import <new>.mpk <app>.mpr  # install it
```

**But the converter has a version window, and 10.6.4 is outside 11.14's.**

```
$ mx convert USI_Theme_Module.mpk out/USI_Theme_Module_11.mpk
Unpacking the input mpk file … Found the input mpr file … Checking the version of the mpr file.
Conversion failed: System.InvalidOperationException:
  The version '10.6.4.28084' of the mpr file is not supported.
exit 3
```

Same boundary `module-import` named: 11.14's toolset accepts **10.21.0 – 10.24.99**. So this
package needs a **two-hop** upgrade — first with an `mx` from the 10.21–10.24 line, then with
11.x — and the first hop's binary is what this container cannot get. Every 10.x URL the tooling
uses returns 404 while 11.x returns 200, on five spellings tried:

| URL tried | Status |
|---|---|
| `cdn.mendix.com/runtime/mxbuild-11.14.0.tar.gz` (control) | 200 |
| `…/mxbuild-10.24.2.tar.gz`, `…-10.24.1`, `…-10.24.0`, `…-10.23.0`, `…-10.21.0`, `…-10.18.0` | 404 |
| `…/mxbuild-10.24.2-linux.tar.gz`, `…/mxbuild-10.24.0.9.tar.gz`, `…/mendix-10.24.2.tar.gz` | 404 |
| `cdn.mendix.com/mxbuild/mxbuild-10.24.2.tar.gz` | 403 |

`mxcli setup mxbuild --version 10.24.2 --force --dry-run` confirms it would fetch the 404 URL.

**So the honest answer is not "you cannot upgrade an old module."** You can, headlessly, with
`mx convert` — provided you have an `mx` whose window covers the package's version. Here the
window is missed by one hop and the intermediate binary is not published at the path the tooling
uses. Someone with a 10.21–10.24 toolset (or Studio Pro of that line) converts once, and the
result imports headlessly from then on.

## The app survived the refusal

`mprcontents/` is still present and `SHOW MODULES` still returns the 9 modules, so the refused
import left the project untouched and in MPR v2. The format-rewrite risk the marketplace help
warns about did not materialise, because nothing was written.

## What this changes

1. The component manifest template's install field now asks for **the CLI command that actually
   worked and the mxcli version it was verified on** — this run is why.
2. The company brain's own manifest for this module now carries the verified refusal, the
   version hop it needs, and the CDN gap, so the next project does not spend an afternoon
   rediscovering it. That is the tier earning its keep: the finding is not about any one app.
3. Part B of the rubric is now partly runnable anywhere: "probe before choosing a route" and
   "import from the CLI" can both be graded. "Import succeeds" cannot be graded on this package
   until it is re-exported.
