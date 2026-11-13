---
title: Administrator user role changes in the cloud apply only after the admin password is changed
topic: security
kind: pitfall
applies_to: general
versions: "any"
keywords: [Administrator user role, MxAdmin role not updated, Mendix Cloud, change admin password, Environment Details actions, System.Administrator, user license exceeded]
sources:
  - {title: "Administrator", url: "https://docs.mendix.com/refguide/administrator/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
You change the Administrator account's user role in **App Security** > **Administrator** and deploy, for example to Mendix Cloud. The admin account keeps its old role.

**Root cause**
When the app is not running locally, changes to the Administrator user role are applied only once the Administrator password is changed.

**Fix**
Change the admin password through the **Actions** on Environment Details.

**Background**
- The default role is `Administrator`. It has System.Administrator and all manageable roles.
- It can be changed or deleted like any other role.
- If you exceed your user license, you can sign in as any user with this role to manage end-users.
- In Free Apps, the user who created the app gets the Administrator role by default.

**Status**
Documented behaviour.
