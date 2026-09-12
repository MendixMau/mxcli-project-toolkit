# Module: CoreAuth

**Layer:** Common  
**Responsibility:** User authentication, session management, and role-based access control.

## Entities

| Entity | Persistent? | Key attributes | Notes |
|--------|------------|-----------------|-------|
| User | Yes | UserId (PK), Email, PasswordHash, FullName, IsActive | All users in the system; authenticates via email+password |
| Session | Yes | SessionId (PK), UserId (FK), Token, ExpiresAt | Created on successful login; expires after 24 hours |

## Key Microflows

| Microflow | Kind | Purpose |
|-----------|------|---------|
| ACT_Login_Validate | VAL_ | Validate email/password credentials against User table |
| ACT_Session_Create | ACT_ | Create session token after authentication |
| ACT_Logout | ACT_ | Invalidate session and clear token |

## Pages / Snippets

| Page | Type | Source screen |
|------|------|---------------|
| Login | NewEdit | User login form (email + password) |

## Security

- **Module roles:** None (core auth is transparent to other modules)
- **User roles mapped:** Anonymous → Login access; Authenticated → all other modules
- **Authentication:** JWT tokens; passwords hashed with bcrypt (salt rounds 10+)

## Dependencies

- **Imports:** None (foundation module)
- **Exposes:** ACT_Login_Validate, ACT_Session_Create, ACT_Logout (called by UI layer on login/logout)
- **Cross-module associations:** None
