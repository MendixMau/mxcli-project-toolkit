Repo: mendixlabs/mxcli
Source: toolkit issue #360; `bug-logs/mxcli-bugs.md` BUG-DRAFT-qual004-dg2-datasource
Status: **NOT FILED.** Reduce to a blank app first: one page, one Data grid 2 on a `DS_` microflow, `mxcli lint`, then the same with a classic list view.

--- everything above this line is stripped before filing ---

**Title:** QUAL004 flags a microflow used only as a Data grid 2 datasource as "not called from anywhere"

## Environment

- mxcli **v0.26.0**
- Mendix **11.15.0**
- macOS

A microflow whose only reference is the `DataSource: microflow` of a Data grid 2 is reported by
QUAL004 ("is not called from anywhere. Remove if unused"). `describe page` prints the datasource,
and the app works. `orphaned_elements.star` already lists `datasource` in `MICROFLOW_ENTRY_KINDS`,
so the catalog probably records no `datasource` ref for a pluggable widget's datasource.

Ask: record a pluggable widget's microflow/nanoflow datasource as a `datasource` ref, the same as a
classic data view or list view. Following the rule's suggestion deletes a live datasource.
