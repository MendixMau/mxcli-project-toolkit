---
title: Consumed REST Service document limitations (non-200 responses, JSON only, streaming)
topic: rest-integration
kind: pitfall
applies_to: general
versions: "any"
keywords: [Consumed REST Service, Send REST request, latestHttpResponse, 201 not mapped, 2xx status, XML response, streaming not supported, macOS beta, OpenAPI import beta]
sources:
  - {title: "Consumed REST Service", url: "https://docs.mendix.com/refguide/consumed-rest-service/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
- A Send REST request returns 201 or another non-200 2xx code, and the response is not mapped.
- Or XML or text responses produce no entities.

**Root cause**
- Response mapping only works for status code `200`.
- Automatic entity creation requires JSON.
- Streaming responses are not supported.

**Fix**
Read `latestHttpResponse` (the `StatusCode` and `Content` attributes) in the microflow and extract the data yourself. For example, use an import mapping for XML.

**Status**
Documented limitations. Release status:
- The document is GA on Windows only; macOS is beta.
- OpenAPI/Swagger contract import is beta.
