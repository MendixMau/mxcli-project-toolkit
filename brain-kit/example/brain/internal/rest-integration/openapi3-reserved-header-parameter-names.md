---
title: Header parameter named Authorization conflicts with OpenAPI 3.0 in Swagger UI
topic: rest-integration
kind: pitfall
applies_to: general
versions: "any"
keywords: [Authorization header parameter, OpenAPI 3.0, reserved header names, Swagger UI, header parameter, published REST]
sources:
  - {title: "Operation Parameters for Published REST", url: "https://docs.mendix.com/refguide/published-rest-operation-parameter/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
A published REST operation defines a header parameter with a reserved name, such as `Authorization`. It conflicts in the OpenAPI 3.0 Swagger UI.

**Root cause**
OpenAPI 3.0 reserves certain header parameter names.

**Fix**
Use an alternative name. The source points to the Swagger documentation, "OpenAPI 3.0: Reserved header parameter names", for alternatives.

**Status**
Per the source, this only affects OpenAPI v3 in Swagger UI, not the actual API endpoint.
