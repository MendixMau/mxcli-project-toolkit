---
title: OpenAPI shows "type file" unless mappings are based on message definitions
topic: rest-integration
kind: pitfall
applies_to: general
versions: "any"
keywords: [OpenAPI, Swagger, JSON schema, type file, message definition, export mapping, import mapping, public name, definitions, rest-doc]
sources:
  - {title: "JSON Schema for Published REST Operation", url: "https://docs.mendix.com/refguide/published-rest-service-json-schema/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
In the generated OpenAPI/Swagger page, the request body or response shows `{ "type": "file" }` instead of an object schema.

**Root cause**
A JSON schema definition is only generated when the import or export mapping is based on a message definition. No mapping, or a mapping based on something else (such as a JSON structure), produces `type: file`. Some primitive results are also documented as file:

| Primitive result | Schema |
|---|---|
| String, Binary, Date and time, Enumeration | file |
| Boolean | boolean |
| Decimal | number |
| Integer/Long | integer |
| Nothing | none |

**Fix**
- Base the import and export mappings on a message definition.
- The definition name defaults to the message definition name. Set the mapping's public name to change it.
- Attribute types map as follows: Integer is int32; Long and Autonumber are int64; Date and time is string date-time; Enumeration is a string enum.

**Status**
Documented generator behaviour.
