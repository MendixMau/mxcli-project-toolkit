---
title: 'Select / deselect all" manageable roles silently includes every new user role'
topic: security
kind: pitfall
applies_to: general
versions: "any"
keywords: ["manageable roles", "grantable roles", "Select / deselect all", "user management", "new user role", "privilege escalation", "SubAdministrator"]
sources:
  - {title: "User Roles", url: "https://docs.mendix.com/refguide/user-roles/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
You add a new user role, possibly a powerful one. Existing managing roles can now grant it without anyone choosing that.

**Root cause**
A user role may have **Select / deselect all** checked, so all roles are manageable by it. In that case every user role you add later is automatically selected as a manageable role for it.

**Fix**
- Leave at least one role unselected. When any role is not selected, newly added user roles are not selected automatically.
- After adding a user role, review the **User management** section of each managing role.

**Status**
Documented behaviour, with a warning in the reference guide.
