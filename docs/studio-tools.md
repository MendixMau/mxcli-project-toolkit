# `studio_*` tools — reference pointer

**Status:** experimental — routed but not yet proven. No project has a field run with this
tool family yet, so this file stays a short pointer until one exists.

## What these are

`studio_*` is a family of MCP tool names, distinct from the `pg_*`/`ped_*` family documented in
`skills/learned-mcp-patterns.md`. Like that family, a `studio_*` tool talks to a running Mendix
Studio Pro instance over MCP rather than writing `.mpr`/`mprcontents/` files directly — so the
same hard rules apply: in-memory writes need an explicit save, MCP-mode and `mxcli exec` are
mutually exclusive for the same unit of work, and any handoff between them goes through a
commit first. Read `skills/learned-mcp-patterns.md` in full before touching a `studio_*` tool —
this file does not repeat that skill, it only adds the missing name.

## When to reach for one

Only when the operation is one `learned-mdl-preflight.md`'s STOP table already routes to MCP,
and the specific `pg_*`/`ped_*` tool that table names does not cover the case. Confirm that gap
against the live MCP tool list available in the session before assuming a `studio_*` tool is
the right one — this file does not enumerate individual tool names or signatures, because none
have been exercised against a real project yet, and a name list nobody has run against real
output is exactly the "imagined input" failure `CLAUDE.md`'s instrument-shipping rule warns
against.

## Where they live

`studio_*` tools are provided by whatever MCP server is configured for the session — the same
place the `pg_*`/`ped_*` tools come from. This toolkit does not ship, install, or configure that
server; it only documents how to use the tools once they are present. There is no toolkit-owned
binary or path for them.

## Field-proofing this row

This row and this file exist to make the tool family discoverable and routable without
asserting anything about it yet — per `CLAUDE.md`'s "Shipping an instrument" rules, that
assertion (real names, real behavior, a cited field run) belongs in a follow-up that has
actually run a `studio_*` tool against a real project. Until then this stays `tier: experimental`
in `bin/lib/skill-routing.tsv`, which keeps it out of every gate's critical path by design.
