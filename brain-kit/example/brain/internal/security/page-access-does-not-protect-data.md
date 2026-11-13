---
title: Page access hides pages but does not stop deep links or forced-visible buttons
topic: security
kind: pitfall
applies_to: general
versions: "any"
keywords: [page access, Visible for, deeplink, deep link, page URL, forced visible button, navigation, entity access, microflow access, unauthorized access]
sources:
  - {title: "Module Security", url: "https://docs.mendix.com/refguide/module-security/", author: "unknown", date: "2026-09-25"}
  - {title: "App Security", url: "https://docs.mendix.com/refguide/app-security/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
A role without page access can still open the page. This happens through a deep link or a button that is forced to be visible.

**Root cause**
Page access, set with the **Visible for** property or in the **Page access** matrix, only does two things:
- It hides the page from navigation.
- It stops **Open Page** buttons from rendering by default.

It does not block other routes to the page.

**Fix**
- Protect data and logic with **entity access** and **microflow access**. Do not rely on page access for this.
- Keep **Strict page URL checking** enabled. See [[strict-page-url-checking-skips-deep-links]].

**Status**
Documented behaviour.
