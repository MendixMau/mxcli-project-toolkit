# Module: WidgetLib

**Layer:** Domain + Logic  
**Responsibility:** Widget type definitions, widget instances, data source configuration, and widget rendering orchestration.

## Entities

| Entity | Persistent? | Key attributes | Notes |
|--------|------------|-----------------|-------|
| WidgetInstance | Yes | WidgetInstanceId (PK), WidgetType (string), DashboardId (FK), Configuration (JSON), DataSourceId (FK) | Represents one instantiated widget on a dashboard |
| DataSource | Yes | DataSourceId (PK), Name, Type (SQL/API/Static), Query, ConnectionString | Reusable data sources shared across widgets |

## Key Microflows

| Microflow | Kind | Purpose |
|-----------|------|---------|
| ACT_Widget_Configure | ACT_ | Update widget configuration (data source, display options) |
| ACT_Widget_LoadData | GET_ | Execute data source query and fetch widget data |
| ACT_DataSource_Validate | VAL_ | Test data source connectivity and query validity |

## Pages / Snippets

| Page | Type | Source screen |
|------|------|---------------|
| WidgetPicker | Popup | Modal showing available widget types with previews |
| WidgetConfigPanel | Popup | Configuration form for data source and display options |

## Security

- **Module roles:** None (inherits from parent DashboardMgmt)
- **User roles mapped:** Creators can configure widgets; viewers see only rendered output
- **Data access:** Queries execute with dashboard owner's data context (no cross-user data leaks)

## Dependencies

- **Imports:** DashboardMgmt (Dashboard, DashboardWidget entities); DataViz (rendering orchestration)
- **Exposes:** WidgetInstance, DataSource entities and configuration microflows
- **Cross-module associations:** WidgetInstance → DataSource (FK); WidgetInstance → Dashboard (FK via DashboardMgmt)
