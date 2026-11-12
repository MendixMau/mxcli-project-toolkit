---
title: Default MxAdmin credentials are public; the model password is used only locally
topic: security
kind: pitfall
applies_to: general
versions: "any"
keywords: [MxAdmin, administrator password, default password, admin user name, change admin password, Environment Details, cloud admin password not updated]
sources:
  - {title: "Administrator", url: "https://docs.mendix.com/refguide/administrator/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
- The administrator account still has its well-known defaults.
- Or: you changed the admin password in Studio Pro, but the cloud environment still uses the old one.

**Root cause**
- The default user name is `MxAdmin` and the default password is `1`. Both are general knowledge.
- The password set in the model (**App Security** > **Administrator**) is used only when the app runs locally. Changing it does not update Cloud environments.

**Fix**
- Change the user name and password to custom values.
- For licensed environments, change the admin password in the Mendix Portal (Environment Details).
- In licensed environments, MxAdmin is created when you change this password for the first time.

**Status**
Documented behaviour.
