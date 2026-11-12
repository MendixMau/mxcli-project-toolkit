# Release impact: Mendix 9.24.32.58223 to 10.24.27.128337

## Studio Pro (2 rows)

| # | version | type | area | change | affected | source | handled |
|---|---|---|---|---|---|---|---|
| 1 | 10.20.0 | breaking | security | Published OData/REST services no longer accept web service user credentials. | OData, REST services | [notes](https://docs.mendix.com/) | open: the frozen copy has 0 web service users; production unknown |
| 2 | 10.0.0 | removal | runtime | Removed something the app does not use. | x | [notes](https://docs.mendix.com/) | not relevant: no use in the model |

## Module DataWidgets (2.27.3 to 3.11.7, 3 rows, brain file modules/data-widgets.md by content id 116540)

| # | version | type | change | affected | replaced by | source | handled |
|---|---|---|---|---|---|---|---|
| 3 | 2.27.7 | breaking | Text configurations for empty option, empty selection, input placeholder need review and reconfiguration. | DatagridDropdownFilter |  | [brain](modules/data-widgets.md) | open: the old model had emptyOptionCaption 'Status' on 3 drop-down filters (MyOwn.Overview), the new one is empty |
| 4 | 3.1.1 | breaking | Text configurations for empty option, empty selection, and input placeholder need to be reviewed and reconfigured. | DatagridDropdownFilter |  | [brain](modules/data-widgets.md) |  |
| 5 | 3.0.0 | breaking | Grid-wide filtering is now configurable in the filter widget. | Datagrid |  | [brain](modules/data-widgets.md) | handled: shotdiff-smoke.md pair MyOwn.Overview |
