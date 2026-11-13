---
title: Commit a variable once, and place create/update/delete near the end of the microflow (MXP012, MXP014)
topic: performance
kind: practice
applies_to: general
versions: "any"
keywords: [MXP012, MXP014, repeated commit, long-running transaction, database lock, commit late, locking, scheduled event, chunks]
sources:
  - {title: "Recommendations from Best Practice Recommender", url: "https://docs.mendix.com/refguide/performance-best-practices/", author: "unknown", date: "2026-09-25"}
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
- Commit each variable only once in a flow (MXP012).
- Place Create/Update/Delete activities close to the end event (MXP014).
- Commit as late as possible.

**Why**
- Repeated commits of the same variable can cause longer-running transactions.
- Early create/update/delete makes the database acquire locks or resources earlier than needed.
- A commit locks the record or records. Other users or logic that commit the same object must wait until the transaction finishes.

**How to apply**
- Refactor the microflow so that the variable is committed once.
- Move data-changing activities toward the end event.
- Scheduled events that commit data should do so in small chunks, so that data is not locked for long periods.
