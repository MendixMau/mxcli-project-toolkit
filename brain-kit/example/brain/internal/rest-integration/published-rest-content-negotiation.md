---
title: How a published REST operation chooses JSON or XML output (Content-Type and Accept)
topic: rest-integration
kind: reference
applies_to: general
versions: "any"
keywords: [content negotiation, Accept header, Content-Type, application/json, application/xml, +json, +xml, export mapping, message definition, XML or JSON]
sources:
  - {title: "Published REST Operation", url: "https://docs.mendix.com/refguide/published-rest-operation/", author: "unknown", date: "2026-09-25"}
  - {title: "Publish a REST Service", url: "https://docs.mendix.com/refguide/publish-a-rest-service/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
These rules apply when the export mapping supports both XML and JSON, for example a mapping based on a message definition.

**Recognised media types**

| Media type | Recognised as |
|---|---|
| application/xml, text/xml, `*+xml` | XML |
| application/json, `*+json` | JSON |

**Output rules**

| Situation | Output |
|---|---|
| Microflow sets `Content-Type` on the `HttpResponse` to an XML type | XML |
| Microflow sets `Content-Type` to anything else | JSON |
| No `Content-Type` set | The first recognised type in the request `Accept` header decides. The response gets `Content-Type` application/xml or application/json. |
| No `Accept` header, or no recognisable type in it | JSON, application/json |

The same table applies to requests: import mappings understand these media types (see [[published-rest-body-parameter-import-mapping]]).

The "Publish a REST Service" how-to says an export mapping is optional. You can return the list of objects from the microflow, and Studio Pro exports it in the format the `Accept` header asks for. This contradicts the Published REST Operation reference, which says an object or list result *must* have an export mapping. The sources do not resolve this. Verify the behaviour in your version.
