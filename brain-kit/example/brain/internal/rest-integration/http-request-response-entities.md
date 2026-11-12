---
title: System.HttpRequest, HttpResponse and HttpHeader attributes and defaults
topic: rest-integration
kind: reference
applies_to: general
versions: "any"
keywords: [HttpRequest, HttpResponse, HttpHeader, HttpHeaders association, StatusCode, Content, Uri, HttpVersion, System entities]
sources:
  - {title: "HttpRequest and HttpResponse System Entities", url: "https://docs.mendix.com/refguide/http-request-and-response-entities/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
| Entity | Attribute | Type | Default |
|---|---|---|---|
| HttpRequest | HttpVersion (inherited from HttpMessage) | String | HTTP/1.1 |
| HttpRequest | Uri (full URI, including the query) | String | empty |
| HttpRequest | Content (body) | String | empty |
| HttpResponse | HttpVersion | String | HTTP/1.1 |
| HttpResponse | StatusCode | Integer | 200 |
| HttpResponse | ReasonPhrase (read-only in effect, see [[httpresponse-reasonphrase-has-no-effect]]) | String | OK |
| HttpResponse | Content | String | empty |
| HttpHeader | Key | String | empty |
| HttpHeader | Value | String | empty |

- Headers of both requests and responses are reached through the `HttpHeaders` association.
- To add a response header, create an `HttpHeader` object with:
  - `Key`, for example `'Content-Type'`
  - `Value`
  - `System.HttpHeaders` set to the response object
- You can almost always ignore `HttpVersion`.
