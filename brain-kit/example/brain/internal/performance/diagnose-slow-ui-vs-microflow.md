---
title: 'Triage a slow page: UI-centric or microflow-centric'
topic: performance
kind: procedure
applies_to: general
versions: "any"
keywords: ["slow page", "unresponsive page", "slow UI", "browser developer tools", "Chrome DevTools", "network tab", "slow retrieve", "microflow debugger", "performance troubleshooting"]
sources:
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
- An action takes too long, or a page loads slowly.

**Steps**
1. Classify the problem:
   - A slow initial load, or slowness after clicking a microflow button, most likely means a microflow.
   - Glitchy or slow UI after the page has loaded means a UI-centric issue.
2. For slow UI, open the browser developer tools (for example Chrome DevTools or Firefox Developer Edition) and inspect the network requests.
3. Decide whether you have too many loads ([[nested-views-and-too-many-loads]]) or slow individual loads.
4. Slow load:
   - Slow network for little data: involve a system administrator.
   - Slow retrieve: check for complex XPath, missing indexes, and combined security rules from multiple user roles.
   - Slow microflow: continue below.
5. List the microflows the page runs: data sources, sub-microflows, on-change handlers, and domain model event handlers.
6. Set breakpoints in the microflow debugger and step through them. This gives a quick but subjective result.
7. If the cause is still unclear, measure objectively. See [[time-microflows-with-log-messages]] and [[log-slow-queries-logminduration]].

**Checks**
- You can name the slowest microflow and the slowest activity in it before you optimize.

**Watch out**
- Performance issues are highly context-sensitive. There is no single cure.
- Server monitoring graphs and logs in Apps can also help.
