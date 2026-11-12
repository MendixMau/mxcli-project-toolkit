---
title: Setting HttpResponse.ReasonPhrase has no effect on the sent response
topic: rest-integration
kind: pitfall
applies_to: general
versions: "any"
keywords: [ReasonPhrase, HttpResponse, custom reason phrase, status text, HTTP/2, published REST, status line]
sources:
  - {title: "HttpRequest and HttpResponse System Entities", url: "https://docs.mendix.com/refguide/http-request-and-response-entities/", author: "unknown", date: "2026-09-25"}
  - {title: "Published REST Operation", url: "https://docs.mendix.com/refguide/published-rest-operation/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
You set a custom `ReasonPhrase` on the `HttpResponse` of a published REST operation. Clients still see the default phrase for the status code.

**Root cause**
- HTTP/2 removed reason phrases.
- The web server used by the Mendix Runtime only allows the default reason phrase for a status code. This also applies to HTTP/1.x, which technically allows custom phrases.

**Fix**
Treat `ReasonPhrase` as read-only. To communicate details to the client, use `StatusCode`, `Content` or headers instead.

**Status**
Documented behaviour. No change is announced.
