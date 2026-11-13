---
title: Best Practice Recommender performance rules MXP001 to MXP016
topic: performance
kind: reference
applies_to: general
versions: "any"
keywords: [Best Practice Recommender, BPR, MXP001, MXP007, MXP015, MXP016, performance rule, View menu, Studio Pro, recommendations]
sources:
  - {title: "Recommendations from Best Practice Recommender", url: "https://docs.mendix.com/refguide/performance-best-practices/", author: "unknown", date: "2026-09-25"}
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
Open the recommender in Studio Pro via **View** > **Best Practice Recommender**.

| Code | Flags | Note |
|---|---|---|
| MXP001 | Calculated attribute used on a page | [[calculated-attributes-slow-retrieves]] |
| MXP002 | Unused calculated attribute | [[calculated-attributes-slow-retrieves]] |
| MXP003 | Sort-order attribute without index | [[index-xpath-and-sort-attributes]] |
| MXP004 | Create/Change object committing in a loop | [[commit-lists-outside-loops]] |
| MXP005 | Commit activity in a loop | [[commit-lists-outside-loops]] |
| MXP006 | Microflow convertible to nanoflow | [[convert-microflow-to-nanoflow]] |
| MXP007 | XPath attribute without index | [[index-xpath-and-sort-attributes]] |
| MXP008 | Caching non-persistable entity | [[cache-only-persistable-data]] |
| MXP009 | Too many inheritance levels | [[inheritance-levels-performance]] |
| MXP010 | Duplicated access rules | [[access-rules-performance]] |
| MXP011 | Data/list views nested 2+ levels | [[nested-views-and-too-many-loads]] |
| MXP012 | Variable committed repeatedly | [[commit-once-and-late]] |
| MXP013 | Negating XPath access rules | [[access-rules-performance]] |
| MXP014 | Create/Update/Delete near start event | [[commit-once-and-late]] |
| MXP015 | Expensive XPath parts left of `and` | [[xpath-ordering-and-negation]] |
| MXP016 | OData key on non-indexed attribute | [[index-xpath-and-sort-attributes]] |
