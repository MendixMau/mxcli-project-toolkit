---
title: Deeply nested data/list views and busy pages cause too many requests (MXP011)
topic: performance
kind: pitfall
applies_to: general
versions: "any"
keywords: [MXP011, nested list view, nested data view, slow page, too many loads, many requests, data grids, reference selectors, tabs, conditional visibility]
sources:
  - {title: "Recommendations from Best Practice Recommender", url: "https://docs.mendix.com/refguide/performance-best-practices/", author: "unknown", date: "2026-09-25"}
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
- A page fires many retrieves on load. The source's example has 26 XPath retrieves for one page.
- The page loads slowly.

**Root cause**
- Common causes:
  - Many data grids.
  - Many nested data views, especially nesting of two or more levels (MXP011).
  - Many reference selectors.
  - Many tabs.
  - Many widgets.
- Each extra source adds requests and transferred data.

**Fix**
- Restructure the page, for example by moving part of it to a pop-up page.
- Split large pages. Think of mobile app logic rather than all-in-one-screen logic.
- Avoid multiple identical data sources. Each one loads the object again.
- Minimize conditional visibility.
- Minimize the data sent to the client, for example through chunking or security.
- To find the culprit, remove objects from the page until it speeds up.

**Status**
- Documented guidance.
- BPR flags nesting of two or more levels.
