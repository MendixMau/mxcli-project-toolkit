# lint-rules/ — own Starlark rules

Company rules, installed into projects beside the toolkit's stock rules. Each file carries the
`# mxtk-lint-rule:` header the toolkit's installer expects, so a project can tell stock, company
and locally-edited rules apart by hash. Authoring guide: the `write-lint-rules` skill bundled
with mxcli.
