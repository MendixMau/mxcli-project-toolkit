# Module: DashboardMgmt

**Layer:** Domain + Logic  
**Responsibility:** Dashboard lifecycle management (create, edit, publish), ownership, and state transitions.

## Entities

| Entity | Persistent? | Key attributes | Notes |
|--------|------------|-----------------|-------|
| Dashboard | Yes | DashboardId (PK), Title, Description, OwnerId (FK→User), State, CreatedAt, PublishedAt | Owned by creator; states: Draft, Published, Archived |
| DashboardWidget | Yes | WidgetId (PK), DashboardId (FK), WidgetType, Position, Width, Height, Config | Containment; one Dashboard has many DashboardWidgets |

## Key Microflows

| Microflow | Kind | Purpose |
|-----------|------|---------|
| ACT_Dashboard_Create | ACT_ | Create new dashboard record in Draft state |
| ACT_Dashboard_Publish | ACT_ | Change state from Draft to Published, record timestamp |
| ACT_Widget_Add | ACT_ | Add widget instance to dashboard |
| ACT_Dashboard_Save | ACT_ | Persist dashboard and widget layout changes |

## Pages / Snippets

| Page | Type | Source screen |
|------|------|---------------|
| DashboardList | Overview | List of user's dashboards with state badges |
| DashboardEditor | NewEdit | Grid-based editor with widget canvas |
| DashboardView | View | Read-only dashboard rendering (viewer role) |

## Security

- **Module roles:** MxRole_Creator (edit access), MxRole_Viewer (read-only access)
- **User roles mapped:** Creators can create/edit own dashboards; viewers see published dashboards only
- **Authorization:** DashboardEditor restricted to dashboard owner

## Dependencies

- **Imports:** CoreAuth (User entity via OwnerId FK)
- **Exposes:** Dashboard, DashboardWidget entities and CRUD microflows to WidgetLib
- **Cross-module associations:** Dashboard → User (owner) — FK (owned by DashboardMgmt)
