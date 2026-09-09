# Build Plan — Puffin Dashboard Application

## Module Build Order

### Phase 1: Foundation (Sprint 1)
**AccessControl Module**
- Entities: User, SecurityModel configuration
- Microflows: Authenticate User, Validate Token
- Pages: Login page
- Pages: User profile (admin only)
- Estimated effort: 5 days
- Completion criteria: Login flow working, JWT pattern established, role model in place

### Phase 2: Core Functionality (Sprint 2-3)
**DashboardCore Module**
- Entities: Dashboard, owner relationship, status lifecycle
- Microflows: Create Dashboard, Update Dashboard, Publish Dashboard, Delete Dashboard, List Dashboards
- Pages: Dashboard list (with create action), Dashboard editor
- Pages: Dashboard view (read-only)
- Associations: Dashboard → User (owner)
- Estimated effort: 10 days
- Completion criteria: Full CRUD operations, list view with pagination, publish workflow

### Phase 3: Extended Features (Sprint 4)
**WidgetLibrary Module**
- Entities: Widget, config storage
- Microflows: Add Widget, Configure Widget, Remove Widget
- Pages: Widget configuration form, widget preview
- Associations: Widget → Dashboard (contains)
- Estimated effort: 8 days
- Completion criteria: Basic widget types (chart, table, metric), config serialization

**Dashboard Sharing Feature**
- Entities: DashboardShare
- Microflows: Share Dashboard, Update Permission, Remove Share
- Pages: Dashboard share dialog
- Estimated effort: 5 days
- Completion criteria: Role-based sharing (view/edit), permission enforcement

## Key Decisions

1. **Single Mendix App**: All modules in one application (not split across multiple apps)
2. **Database**: Use Mendix built-in database (no external DB connection for workshop POC)
3. **Frontend**: React-to-Mendix pages manual migration (extract screens from React, rebuild in Mendix UI)
4. **Authentication**: Adapt JWT pattern to Mendix security model
5. **Widget Config**: Implement JSONB-like storage using Mendix serialization or string field

## Build Plan Summary

| Phase | Module | Effort | Dependencies | Status |
|-------|--------|--------|--------------|--------|
| 1 | AccessControl | 5d | None | Ready |
| 2 | DashboardCore | 10d | AccessControl | Ready |
| 3a | WidgetLibrary | 8d | DashboardCore | Ready |
| 3b | Sharing | 5d | DashboardCore | Ready |

**Total Estimate**: 28 days (4 weeks)

## Risk & Mitigation

- **Risk**: Widget config serialization complexity
  - Mitigation: Start with simple JSON string storage, enhance later
- **Risk**: Performance on large dashboards
  - Mitigation: Implement pagination, lazy-load widgets
- **Risk**: React-to-Mendix page migration effort
  - Mitigation: Prioritize critical screens; defer nice-to-haves

Approved by: autonomous analysis w2-puffin-b on 2026-09-09
