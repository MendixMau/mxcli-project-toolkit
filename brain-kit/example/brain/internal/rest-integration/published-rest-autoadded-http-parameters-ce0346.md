---
title: Auto-added httpRequest/httpResponse parameters cause errors (CE0346) in a published REST microflow
topic: rest-integration
kind: pitfall
applies_to: general
versions: "any"
keywords: [CE0346, httpResponse parameter, httpRequest parameter, published REST microflow, consistency error, return HttpResponse, auto-generated parameter]
sources:
  - {title: "Publish a REST Service", url: "https://docs.mendix.com/refguide/publish-a-rest-service/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
Errors in a new operation microflow, including **CE0346**, when the microflow creates and returns its own `HttpResponse`.

**Root cause**
When you create the microflow from the operation dialog, `httpRequest` and/or `httpResponse` parameters may be added automatically. They conflict with a microflow that builds and returns a new `HttpResponse` object.

**Fix**
- Remove the auto-added `httpRequest` parameter if you do not use it.
- Remove the `httpResponse` parameter when the microflow returns a newly created `HttpResponse`.

**Status**
Described in the official how-to. It is not stated why `httpRequest` itself errors.
