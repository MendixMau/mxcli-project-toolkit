---
title: A user role is a set of module roles and should include System.User
topic: security
kind: practice
applies_to: general
versions: "any"
keywords: [user role, module role, System.User, System.Administrator, App Security, User roles tab, reusable module, Marketplace module]
sources:
  - {title: "User Roles", url: "https://docs.mendix.com/refguide/user-roles/", author: "unknown", date: "2026-09-25"}
  - {title: "Security", url: "https://docs.mendix.com/refguide/security/", author: "unknown", date: "2026-09-25"}
  - {title: "Module Security", url: "https://docs.mendix.com/refguide/module-security/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
- Define security inside each module in terms of that module's own module roles.
- Define user roles at app level, each as a combination of module roles.
- Every user role needs at least **System.User**.

**Why**
- Splitting roles this way keeps each module self-contained. The module can then be reused in other apps or published to the Marketplace.
- An end-user gets the combined access rights of all their user roles, and through them all the linked module roles.
- End-users only see user role names. Module role names and their documentation are visible only in Studio Pro.

**How to apply**
1. Go to **App Explorer** > **App** > **Security** > **User roles** tab.
2. Double-click a user role and add its module roles.
3. Example: user role TeamMember = ProjectManagement.TeamMember + System.User. User role TeamLeader = ProjectManagement.TeamMember + ProjectManagement.TeamLeader + System.User + System.Administrator.
4. You can turn off **Check security** for a user role that never signs in to the client. Web-service-only roles are an example.
