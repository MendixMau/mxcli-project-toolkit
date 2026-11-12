---
title: Rules for path and query parameters in published REST operations
topic: rest-integration
kind: reference
applies_to: general
versions: "any"
keywords: [path parameter, query parameter, operation path, curly braces, case sensitive, ISO-8601, empty value, Boolean default false, published REST, microflow parameter type]
sources:
  - {title: "Published REST Path Parameters", url: "https://docs.mendix.com/refguide/published-rest-path-parameters/", author: "unknown", date: "2026-09-25"}
  - {title: "Published REST Query Parameters", url: "https://docs.mendix.com/refguide/published-rest-query-parameters/", author: "unknown", date: "2026-09-25"}
  - {title: "Published REST Operation", url: "https://docs.mendix.com/refguide/published-rest-operation/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
| Rule | Path | Query |
|---|---|---|
| Syntax | `{name}` in the operation path, only between slashes | `?name=John&age=42` |
| Types | Primitive only | Primitive only |
| Duplicates | The same name cannot be used twice in a path; names cannot contain `{` or `}` | |
| Case | | Case sensitive |
| Date and time | ISO-8601, for example `2018-12-31T09:00:00` | ISO-8601 |
| Missing value | | `empty`; Boolean defaults to `false` |

Notes:
- A microflow parameter that is not in the path and is not an object is treated as a query parameter.
- When you generate a microflow from the operation editor, every path parameter becomes a **String**. Change the type in the microflow if needed.
- A path parameter value can go to the microflow, the import mapping, or both.
- Header parameters come from the HTTP headers of the request.

Status: Rules are taken directly from the Mendix reference guide pages for path parameters, query parameters and published REST operations; not verified in a running app.
