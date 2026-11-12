---
title: Microflow allowed roles are only checked when the client calls the microflow
topic: security
kind: pitfall
applies_to: general
versions: "any"
keywords: [microflow access, Allowed roles, sub-microflow, called microflow, client call, role check, nanoflow access]
sources:
  - {title: "Module Security", url: "https://docs.mendix.com/refguide/module-security/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
A role that lacks access to microflow B can still run B's logic, because B is called from microflow A, which the role can run.

**Root cause**
Microflow **Allowed roles** are checked only when the client executes the microflow. One microflow may always call another, and no role check happens then.

**Fix**
The source does not give a fix. It states that access to data and logic must be expressed through entity access and microflow access.

**Status**
Documented behaviour.
