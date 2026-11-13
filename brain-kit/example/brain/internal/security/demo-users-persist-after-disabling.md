---
title: Disabling demo users does not remove them or block their sign-in
topic: security
kind: pitfall
applies_to: general
versions: "any"
keywords: [demo users, Enable demo users, demo user still logs in, demo password, Free App, local users, user switcher, Select user]
sources:
  - {title: "Demo Users", url: "https://docs.mendix.com/refguide/demo-users/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
You set **Enable demo users** to **No**, yet people can still sign in with demo user credentials.

**Root cause**
- Demo users are created automatically on first start, but only when the app runs locally or in a Free App.
- After creation they are ordinary local users.
- They are never removed from the database automatically.
- Disabling the feature only stops you from adding, editing or deleting them in Studio Pro.

**Fix**
Remove or block these users in the app's database or user management. The source does not describe how to do this.

**Background**
- Demo users are enabled by default when security is on.
- Their passwords are generated and cannot be changed.
- The user name must be unique and must differ from the administrator name.
- Their entity must be System.User or a specialization of it.

**Status**
Documented behaviour, with a warning in the reference guide.
