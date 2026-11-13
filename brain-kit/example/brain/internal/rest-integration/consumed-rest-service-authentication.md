---
title: 'Authentication in the Consumed REST Service document: basic only, others via headers'
topic: rest-integration
kind: procedure
applies_to: general
versions: "any"
keywords: ["Consumed REST Service", "basic authentication", "Authorization header", "bearer token", "API key header", "constant username password", "dynamic token", "headers tab"]
sources:
  - {title: "Consumed REST Service", url: "https://docs.mendix.com/refguide/consumed-rest-service/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
Requests in a Consumed REST Service document need authentication.

**Steps**
1. For basic auth:
   1. Click **Authentication**.
   2. Select **Basic authentication**.
   3. Select or create constants for **Username** and **Password** (**Select** > **New**).
   4. Click **OK**.
2. For any other scheme:
   1. Open **Headers** and click **Add header**.
   2. Pick or type the key, for example `Authorization`.
   3. Set the value.
3. For a dynamic token, put a `{parameter}` in the header value. It appears in the parameters grid and can be set in the Send REST request activity.

**Checks**
Click **Send** to test.

**Watch out**
- Authentication applies to all requests in the document.
- Parameters are not supported in the Authentication section, so use a header for dynamic credentials.
