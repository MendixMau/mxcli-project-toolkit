---
title: Strict mode - how to enable it and which client APIs it blocks
topic: security
kind: reference
applies_to: general
versions: "any"
keywords: [strict mode, React client, client API, mx.data.action, data.create, data.commit, data.remove, data.rollback, data.get, JavaScript action, OWASP LCNC-SEC-05]
sources:
  - {title: "Strict Mode", url: "https://docs.mendix.com/refguide/strict-mode/", author: "unknown", date: "2026-09-25"}
  - {title: "App Security", url: "https://docs.mendix.com/refguide/app-security/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Purpose**
Strict mode is a safety net for access rules that are set up wrongly. It makes entities reachable only in the ways the model defines: microflows, nanoflows, widgets and pages. It addresses OWASP LCNC-SEC-05 (Security Misconfiguration).

**Enable**
1. Use the React client. Strict mode exists only there.
2. Set the security level to **Production**.
3. Switch on **Strict mode** in **App Security**.

**Restricted APIs**

| API | Exception |
|---|---|
| data.action | — |
| data.create | — |
| data.commit | — |
| data.remove | — |
| data.rollback | — |
| data.get | GUID and GUIDs lookups are not restricted |

**Effect**
- The APIs are disabled in the Runtime.
- Online apps cannot call them from JavaScript actions or from the browser console.
- If a JavaScript action uses one of them, consider using a nanoflow instead.

Related: [[strict-mode-breaks-widgets-and-layout-buttons]].
