# Module Brief: SecurityMgmt

Foundation module for role-based access control.

## Entities
- **UserRole** — Role definitions (SuperAdmin, Officer, Inspector, BookingAgent, FinanceUser)
- **RoleAccess** — Module-level access grants

## Microflows
- ACT_UserRole_Create
- ACT_UserRole_Update

## Pages
- UserRole_Mgmt (CRUD interface)

## Dependencies
- None (prerequisite for all others)

## Build Order
- Entities first (UserRole, RoleAccess)
- Microflows next (create/update)
- Pages last (CRUD UI)

## Test Cases
- Create role, verify persistence
- Assign access, verify grants apply
- Delete role, verify cascade behavior
