Repo: mendixlabs/mxcli
Source: toolkit issue #241 (173 of 759 findings on one toolkit-built project were CUSTOM002/QUAL004 on the toolkit's own prefixes)
Status: **NOT FILED.**

--- everything above this line is stripped before filing ---

**Title:** Let projects set QUAL004's entry-point prefixes and CUSTOM002's valid prefixes via lint-config.yaml

## Environment

- mxcli **v0.25.0 / v0.26.0** (the `orphaned_elements.star` and `example_microflow.star` that `mxcli init` writes)

`orphaned_elements.star` (QUAL004) hard-codes `ENTRY_POINT_PREFIXES = ["ACT_", "SCH_", "WS_", "REST_", "OData_"]`
and `example_microflow.star` (CUSTOM002) hard-codes `VALID_PREFIXES`. Neither calls `get_option()`, so
a project can only change them by editing the seeded file, which the next `mxcli init` overwrites without
warning. On one project 84 QUAL004 findings (83 of them `TEST_` helpers called only from
`tests/*.test.mdl`) and 121 CUSTOM002 findings (`TEST_` 90, `GET_` 25, `PRS_` 4) were conventions,
not defects.

Asks:
1. Read both lists with `get_option()` (one comma-separated text, since list options arrive as `None`), keeping today's values as defaults.
2. QUAL004: count a microflow named in `tests/**/*.test.mdl` as called, or exempt a configurable test prefix.
