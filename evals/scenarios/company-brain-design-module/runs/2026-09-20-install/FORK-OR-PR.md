# Could we build this into the CLI ourselves — fork or upstream?

Asked after proving the install works by hand. Answered by reading the source, not by guessing.
Clone: `github.com/mendixlabs/mxcli`, shallow, 2,630 Go files, **Apache 2.0** (so a fork is legally
fine — the question is whether it is a good idea).

## The architecture already supports it

`cmd/mxcli/cmd_marketplace_install.go` (397 lines) is a thin command over a core that is **already
decoupled from the marketplace**. The signatures decide it:

```go
func PackageProject(ctx, mpkPath, mendixVersion, workDir string, newBackend ...) (string, error)
func PerformInstall(mprPath, referenceMpr, packageMpk, moduleName, version, versionID string,
                    newBackend func() backend.FullBackend) (*UpdateResult, error)
func InstallPackageFiles(mpkPath, projectDir string) (written []string, skipped []SkippedFile, err error)
func moduleNameFromMpk(mpkPath string) (string, error)   // reads package.xml out of the zip
```

Every one takes **plain paths and strings**. No marketplace client, no `*Version` struct, no PAT.
The only marketplace-specific work in the command is: resolve a content id → version, and
`fetchMpkToFile` download it to a temp path. Everything after that already operates on a local
`.mpk`.

`InstallPackageFiles` is the step I performed by hand — it unzips the package's bundled trees
(widgets, themesource, styling, design-property declarations) into the project. **mxcli already
has the code.** It is simply unreachable without a content id.

## So the change is small

Add a file input that skips resolve-and-fetch and passes the given path into the same core. The
one genuine design question is what `StampMarketplaceVersion(mprPath, moduleName, version,
versionID)` should record for a package that came from disk rather than the marketplace — an
empty stamp, a "local" marker, or values read from `package.xml`. That is a maintainer's call,
not a blocker.

**Estimate, honestly labelled:** read from the call graph, not from a built patch. Nobody here
has compiled a change. Treat "small" as "the seams are already in the right place", not as a
line count.

## Recommendation: upstream PR, not a fork

A fork is technically open (Apache 2.0) and this repo already knows what forks cost. Reasons to
send it upstream instead:

1. **The change agrees with the tool's own design.** The help text already argues that this
   writer is the right one because it preserves MPR v2 and handles theme modules. A `--file`
   flag finishes a sentence the tool has already started, rather than diverging from it.
2. **A fork re-merges every release, forever**, for one flag. This toolkit made exactly that
   argument when deciding the company brain would be an overlay rather than a fork of itself.
3. **Fork fragmentation is a known cost here**, on record in this org's own notes about parallel
   RnD/downstream forks and the bakeoff that followed.
4. **The immediate need does not require either.** The hand procedure works today and is proven
   end to end; a wrapper script in the toolkit or a company brain gets the value now, with no
   code ownership at all.

**Order to try:** (a) file the issue with the sizing above; (b) offer the PR — the seams are
already there; (c) ship a wrapper script meanwhile; (d) fork only if upstream declines, and then
as a tracked patch on top, not a permanent divergence.

The wrapper is the one to build first, because it is useful whichever way (a) and (b) go.
