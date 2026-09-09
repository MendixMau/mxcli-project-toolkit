# Module Brief: DashboardCore

## Overview
Dashboard lifecycle management: create, edit, view, publish, and delete dashboards. Core value delivery.

## Entities
- Dashboard (id, name, description, owner_id, status: draft | published, created_at, updated_at)
- Entity relationships: Dashboard → User (owner)

## Microflows
- CreateDashboard: New dashboard, draft status, assigned to creator
- UpdateDashboard: Edit dashboard details (owner only)
- PublishDashboard: Transition draft → published
- DeleteDashboard: Remove dashboard (owner only)
- ListDashboards: Return dashboards owned by or shared to user
- RetrieveDashboard: Get dashboard by ID with permission check

## Pages
- DashboardListPage: List user's dashboards, create/edit/delete actions
- DashboardEditorPage: Create/edit form, save and publish
- DashboardViewPage: Read-only view of published dashboard

## Interface
- Input: Dashboard data (name, description, widgets)
- Output: Dashboard list, dashboard detail
- Integration: DashboardShare (permissions), WidgetLibrary (embedded widgets)

## Coverage
- Domain: ✓ Schema extracted
- Processes: ✓ CRUD flow defined
- Rules: ✓ Status lifecycle, ownership
- UI: ✓ List, editor, view pages
- Security: ✓ Owner checks, share permissions

## Success Criteria
- [ ] Create dashboard in draft status
- [ ] Edit dashboard details
- [ ] Publish dashboard (state → published)
- [ ] Delete only owned dashboards
- [ ] List respects permissions
- [ ] Status lifecycle enforced

Owner: ba-agent (Stage 4 assignment)
Build order: Phase 2
