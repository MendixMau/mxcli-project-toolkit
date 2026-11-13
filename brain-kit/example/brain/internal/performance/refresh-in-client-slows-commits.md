---
title: Refresh in client on bulk change/commit slows the app
topic: performance
kind: pitfall
applies_to: general
versions: "any"
keywords: [Refresh in client, slow commit, change object, commit activity, browser refresh, nested data views, bulk commit]
sources:
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
- Committing large numbers of rows is slow.

**Root cause**
- With **Refresh in client** on, the client tries to update thousands of values in the browser.
- One refresh can trigger more refreshes down the line, for example with nested data views.

**Fix**
- Turn off **Refresh in client** on the change or commit activity where possible.

**Status**
- Documented guidance. No version bounds are given.
