---
title: What a published REST operation microflow can return and how each result is sent
topic: rest-integration
kind: reference
applies_to: general
versions: "any"
keywords: [published REST operation, microflow return, HttpResponse, export mapping, file document, primitive return, 500 Internal server error, empty HttpResponse, Content attribute]
sources:
  - {title: "Published REST Operation", url: "https://docs.mendix.com/refguide/published-rest-operation/", author: "unknown", date: "2026-09-25"}
  - {title: "Publish and Retrieve Images and Files with REST", url: "https://docs.mendix.com/refguide/send-receive-files-rest/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
| Microflow returns | Response |
|---|---|
| File document | File stream. Set `Content-Type` to the MIME type. Set `Content-Disposition` for the file name and attachment behaviour. No export mapping is needed: binary content is returned. |
| Object or list | You must select an export mapping that converts it to JSON or XML. |
| Primitive (string, integer, Boolean...) | That value is the response. A non-empty value means `HttpResponse.Content` is ignored. An empty value means `HttpResponse.Content` is used. |
| `HttpResponse` | Status code, string content and headers as you set them. Set `Content-Type`. **Never return an empty `HttpResponse`: it always results in an error.** |

Other rules:
- To set the status or headers without returning an `HttpResponse`, add an `HttpResponse` object parameter and set its attributes.
- Add an `HttpRequest` parameter to inspect the URL and headers.
- An unhandled exception gives **500: Internal server error**.
- When security is enabled, the microflow needs at least one role configured to be accessible.
