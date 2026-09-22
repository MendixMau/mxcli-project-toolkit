# components/ — approved MPKs

One `.mpk` plus one manifest `.md` with the same basename, from `TEMPLATE.md`. The manifest is
what a session reads; the binary is what it installs. A component without a manifest is not
approved, whatever the file next to it says.

**Using one from a project — CLI first, headless.** This toolkit builds headlessly: the write
modes are CLI (`./mxcli exec`) and MCP, chosen by the shape of the work
(`skills/learned-mdl-preflight.md` Step 0). **Studio Pro is not one of them** — it is where a
human opens a finished model (`skills/handoff-to-studio-pro.md`), not a step an agent picks. MCP
mode also needs Studio Pro *running*, so on a headless machine the CLI is the only mode there is.

So: probe the binary you have (`./mxcli --help`, then the import subcommand's own help) and do
the import from the CLI. Never lead with "manual" or "open Studio Pro" from memory — that prior
has misfired twice in this toolkit's history. A CLI that genuinely cannot import a component on
your version is a defect to record in the manifest and log against the tool, not a reason to
reach for the GUI.

Once imported, the component is a module in the model — decisions about *using* it anchor in the
project's `docs/brain/` as `@<ModuleName>.<Element>`; the manifest here stays the catalog entry.
