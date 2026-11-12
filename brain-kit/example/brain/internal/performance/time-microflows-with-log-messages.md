---
title: Time microflows and activities with timestamps or TimeMeasureStart/End
topic: performance
kind: procedure
applies_to: general
versions: "any"
keywords: [microflow timer, execution time, milliseconds, Log message, Create variable, TimeMeasureStart, TimeMeasureEnd, Community Commons, slow activity]
sources:
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
- The debugger does not reveal which microflow or activity is slow.

**Steps**
1. As the first activity, add **Create variable** that stores the current time.
2. Before the end, add **Log message** at info level that writes the milliseconds between the start variable and now.
3. Run the app. Each execution writes its duration to the console.
4. Add timers until you find the slow microflow, then add timers inside it to find the slow activity.

**Checks**
- The console shows one duration line per execution.

**Watch out**
- Alternative: use the Community Commons Java actions **TimeMeasureStart** and **TimeMeasureEnd**.
  - They work across sub-microflows, so you do not need to pass the start time along.
- Always pair every TimeMeasureEnd with a TimeMeasureStart. Otherwise a runtime error occurs.
