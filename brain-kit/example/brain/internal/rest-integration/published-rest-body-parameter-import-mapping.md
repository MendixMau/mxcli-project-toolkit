---
title: Body parameters in published REST operations need an import mapping and a Content-Type
topic: rest-integration
kind: reference
applies_to: general
versions: "any"
keywords: [body parameter, import mapping, 400 Bad Request, Content-Type missing, If no object was found, commit without events, Decide this at the place where the mapping gets used, published REST, FileDocument body]
sources:
  - {title: "Published REST Operation", url: "https://docs.mendix.com/refguide/published-rest-operation/", author: "unknown", date: "2026-09-25"}
  - {title: "Operation Parameters for Published REST", url: "https://docs.mendix.com/refguide/published-rest-operation-parameter/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Basic rules**
- An operation has 0 or 1 body parameters.
- Object and list parameters can only come from the body.
- Every object or list parameter needs an import mapping, except FileDocument (or subtypes) and images. Those are filled with the raw body and can also be used as form parameters.
- Requests must have a `Content-Type` header. An unsupported content type returns **400 Bad Request**.
- A mapping that supports both XML and JSON (message definition based) accepts both formats.

**Commit options**

| Option | Effect |
|---|---|
| Yes | Commit and trigger events such as validation rules |
| Yes without events | Commit without events |
| No | Commit yourself in the microflow, for example after extra checks |

**If no object was found**
Configurable per operation only when the mapping has **Decide this at the place where the mapping gets used** checked. Otherwise the import mapping sets the behaviour.

| Option | Behaviour | Typical use |
|---|---|---|
| Create | Create an object | POST |
| Ignore | Skip the element and continue | |
| Error | Stop parsing and throw an error | PUT, PATCH |

**Primitive-parameter mappings**
An import mapping with a primitive parameter needs exactly one path parameter of that type, and receives its value. The parameter page says that with no path parameter, an empty value is passed.

**Which methods have no body**
The sources conflict:
- The operation page lists GET, HEAD and DELETE as having no body parameter.
- The parameter page says GET, HEAD and OPTIONS should not have one.
