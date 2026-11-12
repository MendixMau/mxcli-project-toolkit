---
title: Security levels (Off, Prototype/demo, Production) and where each is allowed
topic: security
kind: reference
applies_to: general
versions: "any"
keywords: [security level, Production security, Prototype/demo, security off, licensed Mendix Cloud, Free App, Development mode, app status incomplete, module status]
sources:
  - {title: "App Security", url: "https://docs.mendix.com/refguide/app-security/", author: "unknown", date: "2026-09-25"}
  - {title: "Security", url: "https://docs.mendix.com/refguide/security/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
| Level | Applied | To configure |
|---|---|---|
| Off | Nothing. No sign-in; users can access everything | None |
| Prototype/demo | Sign-in, forms, microflows. All data is accessible | Admin, anonymous access, user roles, form and microflow security |
| Production | Full security. By default nobody can access anything until you grant it | The above + entities and reports |

**Where each level is allowed**
- Licensed Mendix Cloud nodes must use **Production**.
- **Off** and **Prototype/demo** are allowed only in these cases:
  - local testing
  - Free Apps
  - non-Mendix-Cloud environments set up with **Development mode**

**Production-only settings**
- Check security
- Strict page URL checking
- Strict mode (React client)
- Security Overview

**Status displays**
- App status: **Complete** or **Incomplete**.
- The Module Status tab shows configured items against the total.
  - Prototype/demo shows page and microflow access.
  - Production also shows entity and dataset access.

**Check security** (Production only)
- For each role, Studio Pro checks that the attributes and associations on reachable forms are accessible.
- These errors appear only when there are no other consistency errors.
