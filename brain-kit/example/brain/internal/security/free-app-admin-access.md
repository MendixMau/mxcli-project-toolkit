---
title: How to get administrator access in a Free App (no MxAdmin is created)
topic: security
kind: procedure
applies_to: general
versions: "any"
keywords: [Free App, MxAdmin missing, cannot log in as admin, data snapshot, Add Snapshot of Data, demo_administrator, demo users]
sources:
  - {title: "Administrator", url: "https://docs.mendix.com/refguide/administrator/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
A Free App deployment is not given an MxAdmin user automatically.

**Steps (option A: data snapshot)**
This works only if the Free App has never been deployed and its database still needs to be created.
1. Open **App** > **Security**.
2. Set the level to **Production** and open the **Administrator** tab.
3. Change the default admin password.
4. Run the app locally. This creates a local database that includes MxAdmin. Then stop the app.
5. Choose **Version Control** > **Add Snapshot of Data** and click **Yes** to commit it.
6. Deploy the Free App for the first time. The snapshot is restored.

**Steps (option B: demo user)**
1. Open **App** > **Security**, set **Production**, and open the **Demo users** tab.
2. Set **Enable demo users** to **Yes**.
3. Add a demo administrator user with user role **Administrator**.
4. Click **Publish**.
5. Log in as that user and create user accounts.

**Checks**
You can sign in with administrator rights in the deployed Free App.

**Watch out**
- Option A does nothing if the Free App database already exists.

Status: Both options are as described in the Mendix Administrator documentation; not confirmed in a deployed Free App.
