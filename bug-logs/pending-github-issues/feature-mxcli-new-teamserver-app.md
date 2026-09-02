**Repo:** `mendixlabs/mxcli`
**Type:** Feature request
**Source:** probed on mxcli **v0.20.0** (2026-08-28T13:22:53Z build) while designing a
Team-Server-first git topology for agent-driven projects (toolkit
`skills/handoff-to-studio-pro.md` §10)
**Status:** DRAFT — not yet filed

---

# `mxcli new`: optionally create the app on the Mendix platform (Team Server repo included)

## The gap

`mxcli new` builds a complete local project — MxBuild download, `mx create-project`, theme,
owned layout, AI tooling, first build — but stops one step short of the platform: there is no
way to create the **platform app** (and the Team Server git repo that comes with it) from the
CLI. Probed on v0.20.0: `mxcli new --help` has no platform/Team Server flag, and no other
command provisions apps (`mxcli auth` manages PATs for marketplace/catalog APIs only).

## Why it matters

For teams pairing an agent-driven build loop (mxcli in a container, GitHub remote) with
colleagues in Studio Pro (Team Server remote), the clean topology is **Team-Server-first**:
create the app on the platform, clone its repo, mirror to GitHub — the two remotes then share
one history and every later sync is ordinary git. Today that first step is a Portal click, the
only non-scriptable step in an otherwise fully headless setup. A container session can build,
verify and push an entire app but cannot give it the platform home Studio Pro colleagues and
sandbox Publish need.

## The ask

Either shape works:

1. `mxcli new MyApp --version 11.12.1 --platform` — create the app via the platform API using
   the stored PAT (`mxcli auth`), clone its Team Server repo, then run the existing scaffold
   (theme, layout, init, first build) **inside that clone** and commit, so the very first
   commit of real content is already on Team Server.
2. A standalone `mxcli platform create-app <name> --version <v>` returning the app id and git
   URL, composable with the existing `mxcli new --output-dir`.

The platform capability exists: the Mendix Platform SDK's `createNewApp` provisions an app
with its Team Server repository programmatically, so this is surfacing an existing API through
the CLI's already-present PAT auth, not new platform ground.

## Workaround today

Create the app in the Mendix Portal by hand, clone `https://git.api.mendix.com/<app-id>.git`,
then run `mxcli init` / `add-tool` over the clone. Works, but is the one manual step in an
otherwise scriptable birth — and the step most often skipped, which is how projects end up
GitHub-born with a Team Server history they can never merge with.
