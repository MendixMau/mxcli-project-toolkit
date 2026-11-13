---
title: Implicit System.User access from manageable roles is ignored when a microflow applies entity access
topic: security
kind: pitfall
applies_to: general
versions: "any"
keywords: [Apply entity access, manageable roles, System.User, implicit entity access rules, user management microflow, access denied, create user microflow]
sources:
  - {title: "User Roles", url: "https://docs.mendix.com/refguide/user-roles/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
A role can manage users in the client. A microflow with **Apply entity access** enabled still does not give that role the same access to **System.User**.

**Root cause**
Mendix turns the user management (manageable roles) settings into *implicit* entity access rules on **System.User**. A microflow with **Apply entity access** enabled checks only *explicitly* configured entity access rules. It therefore ignores the implicit ones.

**Fix**
The source states the behaviour but does not give a fix.
- If the microflow must apply entity access, the access has to come from explicit access rules.
- The source does not say which explicit rules to add.

**Status**
Documented behaviour, in an info note in the reference guide.
