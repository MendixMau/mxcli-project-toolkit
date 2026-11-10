---
title: "Login loops back to the sign-in page after enabling SSO"
topic: demo
kind: pitfall
applies_to: general
versions: "any"
keywords: ["login loop", "SSO", "redirect", "cookie"]
sources:
  - {title: "Fixture source", url: "https://example.com/fixture", author: "test", date: "2026-11-04"}
status: draft-unreviewed
---
**Symptom**
- After SSO is enabled, users land on the sign-in page again after a successful login, over and over, in every browser we tried.

**Root cause**
- The session cookie is set for a different domain than the one users browse to, so the app never sees the session.

**Fix**
- Set the cookie domain to the public host name and restart. See [[missing-note]].

**Status**
- Seen once in one project.
