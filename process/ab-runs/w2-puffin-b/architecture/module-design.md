# Module Design — Puffin Dashboard Application

## Module Boundaries

Puffin extracts into 3 core modules based on business capabilities:

### Module 1: DashboardCore
- **Responsibility**: Dashboard lifecycle management (CRUD, publish)
- **Entities**: Dashboard (id, name, description, status, owner_id, created_at, updated_at)
- **Microflows**: Create Dashboard, Update Dashboard, Publish Dashboard, Delete Dashboard
- **Associations**: Dashboard → User (owner), Dashboard → Widget (contains)

### Module 2: WidgetLibrary
- **Responsibility**: Widget configuration and embedding in dashboards
- **Entities**: Widget (id, dashboard_id, widget_type, config, position_x, position_y)
- **Microflows**: Add Widget, Configure Widget, Remove Widget

### Module 3: AccessControl
- **Responsibility**: User authentication, authorization, dashboard sharing
- **Entities**: User (id, email, password_hash, role), DashboardShare (id, dashboard_id, user_id, permission)
- **Microflows**: Authenticate User, Share Dashboard, Update Permission

## Design Principles
- Single Mendix app (no multi-app decomposition)
- Role-based access control (viewer, editor, admin)
- Data ownership: Dashboard owned by creator, sharable to other users
- Widget configuration stored as JSON in config field

Approved by: autonomous analysis w2-puffin-b on 2026-09-09
