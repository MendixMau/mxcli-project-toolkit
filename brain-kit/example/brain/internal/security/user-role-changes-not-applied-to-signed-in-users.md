---
title: User role changes do not take effect for end-users who are already signed in
topic: security
kind: pitfall
applies_to: general
versions: "any"
keywords: [user role change, role not applied, wrong pages shown, session revalidation, sign out sign in, dynamic UI, persistent sessions, UserRoles]
sources:
  - {title: "User Roles", url: "https://docs.mendix.com/refguide/user-roles/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
After an end-user's user roles change, the app still shows that user the wrong pages or data.

**Root cause**
Role changes are not applied right away to end-users who are signed in. The roles are reapplied only when the session is revalidated. Sessions are persistent.

**Fix**
- Ask affected end-users to sign out and sign in again. This makes sure they have the correct user roles.
- Do not build a dynamic UI by changing user roles at runtime. Mendix advises against it because the changes do not take effect immediately.

**Status**
Documented behaviour, with a warning in the reference guide. The source does not say how often sessions are revalidated.
