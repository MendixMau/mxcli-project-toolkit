# Module: DataViz

**Layer:** UI + Integration  
**Responsibility:** Data query execution, transformation, and rendering of charts, tables, and metrics.

## Entities

| Entity | Persistent? | Key attributes | Notes |
|--------|------------|-----------------|-------|
| (none) | N/A | N/A | DataViz works with transient data; no persistent entities |

## Key Microflows

| Microflow | Kind | Purpose |
|-----------|------|---------|
| ACT_Chart_Render | GET_ | Execute data query and render chart widget |
| ACT_Query_Execute | GET_ | Execute configured SQL/API query with parameterization |
| ACT_DataTransform_ToChart | ACT_ | Transform query results to chart-compatible format (series, categories) |
| ACT_Table_Render | GET_ | Execute query and render paginated table |
| ACT_Metric_Render | GET_ | Execute scalar query and render metric with sparkline |

## Pages / Snippets

| Page | Type | Source screen |
|------|------|---------------|
| ChartWidget | Display | Rendered chart (Bar/Line/Pie) with legend |
| TableWidget | Display | Paginated data table with sort/filter |
| MetricWidget | Display | Large value with trend indicator and sparkline |

## Security

- **Module roles:** None
- **User roles mapped:** Viewers see rendered charts/tables; no data modification possible
- **Query isolation:** All queries execute in context of dashboard owner (no cross-user access)

## Dependencies

- **Imports:** WidgetLib (DataSource configurations, query definitions); DashboardMgmt (Dashboard context for access control)
- **Exposes:** Chart/Table/Metric rendering microflows
- **Cross-module associations:** None (stateless rendering module)

## Technical Notes

- Query timeout: 30 seconds (configurable)
- Chart rendering: client-side via Mendix charting API or Atlas Charts
- Table pagination: 20 rows per page (configurable)
- Sparklines: generated from historical metric snapshots (future enhancement)
