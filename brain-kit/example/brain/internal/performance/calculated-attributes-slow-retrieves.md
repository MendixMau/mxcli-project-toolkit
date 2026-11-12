---
title: Calculated attributes run on every retrieve and slow pages and microflows (MXP001, MXP002)
topic: performance
kind: pitfall
applies_to: general
versions: "any"
keywords: [calculated attribute, virtual attribute, MXP001, MXP002, slow page, slow retrieve, data grid, stored attribute, Best Practice Recommender]
sources:
  - {title: "Recommendations from Best Practice Recommender", url: "https://docs.mendix.com/refguide/performance-best-practices/", author: "unknown", date: "2026-09-25"}
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
- Pages with data containers (list view, data view, data grid) load slowly.
- Retrieves are slow even though the attribute value is never shown or used.

**Root cause**
- A calculated attribute's microflow runs each time the object is retrieved or changed.
- For a list retrieve, it runs once per row.
- It runs whether or not the value is used.
- It runs in these places:
  - Retrieve and change object activities in microflows.
  - UI widgets, such as data views and custom widgets.
  - Objects passed from the UI as a microflow parameter.
- If that microflow retrieves other objects or calls integrations, you get chains of extra queries and microflow calls.

**Fix**
- MXP001 (calculated attribute on a page):
  1. In the domain model, change the attribute to stored.
  2. Wherever the object is committed, calculate the value in the relevant microflow.
  3. Migrate existing data. After the change, the database holds only the type's default value.
- MXP002 (unused calculated attribute): delete it.
- Community advice:
  - Minimize calculated attributes.
  - You seldom need them for conditional visibility.

**Status**
- Documented behaviour.
- Best Practice Recommender flags both cases.
