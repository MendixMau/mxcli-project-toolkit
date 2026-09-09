# Module Brief: AccessControl

## Overview
User authentication, authorization, and role-based access control for Puffin dashboards.

## Entities
- User (id, email, password_hash, role: admin | editor | viewer)
- SecurityModel (role definitions and permissions)

## Microflows
- AuthenticateUser: Validate credentials and issue session
- ValidateToken: Check JWT token validity
- UpdateUserRole: Change user role (admin only)

## Pages
- LoginPage: Email/password input, submit to authenticate
- UserProfilePage: Display current user, edit settings (admin: manage all users)

## Interface
- Input: Login credentials (email, password)
- Output: User session, auth token
- Integration: Mendix security model

## Coverage
- Domain: ✓ Entities from schema
- Processes: ✓ Login flow defined
- Rules: ✓ Role constraints specified
- UI: ✓ Login page, profile page
- Security: ✓ Token validation required

## Success Criteria
- [ ] Login with valid credentials creates session
- [ ] Invalid credentials rejected
- [ ] Roles enforced on dashboard operations
- [ ] Session timeout handled

Owner: ba-agent (Stage 4 assignment)
Build order: Phase 1
