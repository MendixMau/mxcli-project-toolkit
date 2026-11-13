---
title: Anonymous users - name the role "Anonymous" and keep its access minimal
topic: security
kind: practice
applies_to: general
versions: "any"
keywords: [anonymous users, Allow anonymous users, anonymous user role, no sign in, public access, data exposure, guest user]
sources:
  - {title: "Anonymous Users", url: "https://docs.mendix.com/refguide/anonymous-users/", author: "unknown", date: "2026-09-25"}
  - {title: "App Security", url: "https://docs.mendix.com/refguide/app-security/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
- Name the user role used for anonymous users `Anonymous`.
- Give that role only limited entity and microflow access across the whole app.

**Why**
- **Allow anonymous users = Yes** lets anyone use the app without signing in.
- The **Anonymous user role** is the role that end-users have when they are not signed in. The app applies it automatically to anonymous users who access the app.
- Without limited access on that role, data can be exposed unintentionally.
- The name `Anonymous` makes the role's purpose clear to all users.

**How to apply**
1. Go to **App Security** > **Anonymous users** tab.
2. Set **Allow anonymous users** to **Yes**. A role can be selected only after this.
3. Select the anonymous user role.
4. Restrict that role's entity access and microflow access.
