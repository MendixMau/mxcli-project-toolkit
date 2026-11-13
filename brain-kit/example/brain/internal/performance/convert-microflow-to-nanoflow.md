---
title: Convert eligible microflows to nanoflows to avoid network round trips (MXP006)
topic: performance
kind: procedure
applies_to: general
versions: "any"
keywords: [MXP006, nanoflow, microflow, convert, network traffic, offline, $currentUser, $currentSession, $latestHttpResponse, Find usages]
sources:
  - {title: "Recommendations from Best Practice Recommender", url: "https://docs.mendix.com/refguide/performance-best-practices/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
- A microflow qualifies if any of these hold:
  - It holds offline logic.
  - It holds online logic with no database actions (committing Create object, Commit, Retrieve, Rollback).
  - It has at most one database action. The source says this is not the best practice.
- And all its activities must be nanoflow-compatible.
- Nanoflows run on the device or in the browser, so no server round trip is needed.

**Steps**
1. Right-click the module > **Add nanoflow**.
2. Replicate the logic. The result should look almost identical to the microflow.
3. Right-click the microflow > **Find usages**. Replace all usages with the nanoflow.
4. Delete the unused microflow.

**Checks**
- Expressions do not use any of these variables, which nanoflows do not support:
  - `$latestSoapFault`
  - `$latestHttpResponse`
  - `$currentSession`
  - `$currentUser`
  - `$currentDeviceType`
- The current user is authorized for every operation. Nanoflows run as the current user, so otherwise the nanoflow fails.

**Watch out**
- Microflows run server-side, which is generally simpler to fully secure.
- Weigh this if security is critical for your app.
