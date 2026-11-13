---
title: Constrain data grid drop-down search on associated attributes
topic: performance
kind: practice
applies_to: general
versions: "any"
keywords: [data grid, drop-down search field, filter, associated entity, XPath constraint, slow filter, non-existing criteria, search field]
sources:
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
- When a data grid drop-down search filters on an attribute of an associated entity, constrain its options.
- Show only objects that are actually associated to entities in the grid.

**Why**
- In some databases, filtering by non-existing criteria is slow, even when all indexes are in place.

**How to apply**
- Example scenario:
  - The grid shows `Order`.
  - The drop-down search filters on `Order_Customer/Customer/Name`.
- Add the XPath constraint `[Order_Customer/Order]` to the drop-down search field.
- Only Customers that have Orders are then offered.
