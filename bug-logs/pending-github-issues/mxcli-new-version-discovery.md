**Repo:** `mendixlabs/mxcli`
**Source:** field run 2026-11-16 — Windows 11, mxcli **v0.32.0**, an agent setting up an empty folder. Code read on `main` at 121c9b5.
**Status:** NOT YET FILED
**Severity:** Low — feature request; a first-time user (or agent) has no way to find a valid `--version`.

---

# `mxcli new`: no way to discover a valid `--version`

## Observed (verbatim)

```
Error: --version is required (e.g., --version 11.8.0)
Error: no MxBuild archive published for Mendix 99.0.0 (tried https://cdn.mendix.com/runtime/mxbuild-99.0.0.tar.gz and a CDN listing of mxbuild-99.0.0.*)
```

The agent only got past this by trying a version it found in an unrelated example. `new` already
lists published releases when the *major.minor* exists (`CDNReleasesFor`), but prints nothing when
it does not, and there is no command that lists them up front.

## Requested

- `mxcli new --list-versions` (or `mxcli versions`): the releases the CDN publishes, newest first.
- `--version latest` / `--version lts`, resolved through the same listing.
- When the major.minor is unknown, print the newest published majors instead of nothing.
