---
title: Manageable roles - which users a role can manage and which fields it can change
topic: security
kind: reference
applies_to: general
versions: "any"
keywords: [manageable roles, grantable roles, user management, (No user roles), SubAdministrator, Blocked, Active, User_TimeZone, User_Language, UserRoles]
sources:
  - {title: "User Roles", url: "https://docs.mendix.com/refguide/user-roles/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Which users a role can manage**

A user role can manage an end-user only when **all** of that end-user's roles are manageable roles for it.

Example: SubAdministrator has only `User` selected as a manageable role.

| End-user has roles | SubAdministrator can manage? |
|---|---|
| `User` | Yes (it can grant or remove `User` only) |
| `SubAdministrator` | No |
| `User` + `SubAdministrator` | No (`SubAdministrator` is not manageable) |

**Options**

| Option | Effect |
|---|---|
| **(No user roles)** | Allows managing end-users without any role, for example newly created ones |
| **Select / deselect all** | Selects or clears all roles; see [[manageable-roles-select-all-auto-grants-new-roles]] |

**Fields a managing user can change**

| Field | Limit |
|---|---|
| UserRoles | Only the roles selected under **User management** |
| Name | none stated |
| User_TimeZone | none stated |
| Blocked | none stated |
| Active | none stated |
| User_Language | none stated |
