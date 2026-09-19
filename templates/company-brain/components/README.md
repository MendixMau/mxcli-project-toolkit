# components/ — approved MPKs

One `.mpk` plus one manifest `.md` with the same basename, from `TEMPLATE.md`. The manifest is
what a session reads; the binary is what it installs. A component without a manifest is not
approved, whatever the file next to it says.

**Using one from a project.** The install step is version-specific: probe the binary you have
(`./mxcli --help`, `./mxcli import --help` or the current equivalent) before deciding whether the
import is CLI, MCP or Studio Pro. Never lead with "manual" from memory. Once imported, the
component is a module in the model — decisions about *using* it anchor in the project's
`docs/brain/` as `@<ModuleName>.<Element>`; the manifest here stays the catalog entry.
