---
title: Run work the user need not wait for asynchronously, and show progress
topic: performance
kind: practice
applies_to: general
versions: "any"
keywords: [asynchronous, background microflow, task queue, Community Commons, progress indicator, sending email, integration, slow button]
sources:
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
- Do not make the user wait in the UI for work they do not need the result of.
- Examples: sending mails, or updating other apps over an interface.

**Why**
- It keeps the UI responsive.
- A task queue controls load and prevents peaks in background work.

**How to apply**
- Use the Community Commons options to run microflows in the background, or use a task queue.
- If something takes more than a few seconds, show a progress indication.
- For big operations that get slower with size, run them asynchronously and add batching. See [[batch-large-operations-memory]].
