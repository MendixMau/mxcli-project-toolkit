# Architecture Blueprint — Puffin Dashboard Publishing

## High-Level Architecture

Puffin is a single-app dashboard publishing system with three core modules:

```
[Users] → [AccessControl] → [Dashboard Core] → [Widget Library]
                                    ↓
                            [Data Persistence]
```

## Entities

### User
- id (PK)
- email (unique)
- password_hash
- role (admin | editor | viewer)

### Dashboard
- id (PK)
- owner_id (FK → User)
- name
- description
- status (draft | published)
- created_at, updated_at

### Widget
- id (PK)
- dashboard_id (FK → Dashboard)
- widget_type (e.g., chart, table, metric)
- config (JSON - widget-specific configuration)
- position_x, position_y

### DashboardShare
- id (PK)
- dashboard_id (FK → Dashboard)
- user_id (FK → User)
- permission (view | edit)
- created_at

## Security Model

- JWT token-based authentication
- Role-based access control: admin (all), editor (create/edit), viewer (read)
- Dashboard-level sharing with explicit permissions
- Owned dashboards: creator has full control, can share with other users

## Integration Points

- Frontend-to-Backend: REST API (`/api/dashboards/*`)
- Backend-to-Database: Sequelize ORM
- No external integrations

## Data Volumes & Performance

- Workshop reference implementation
- Scaling considerations: indexing on owner_id, dashboard_id
- Dashboard list pagination recommended (no limit specified in source)

## Non-Functional Requirements

- Security: JWT token validation on every endpoint
- Availability: Single-tier app, standard Mendix deployment
- Concurrency: No special handling; rely on Mendix session management

Approved by: autonomous analysis w2-puffin-b on 2026-09-09
