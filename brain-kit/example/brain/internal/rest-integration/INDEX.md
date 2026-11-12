# rest-integration: notes

consuming and publishing REST services, JSON structures, import and export mappings, authentication of REST calls

Generated 2026-11-04 by opus; every note is draft-unreviewed until a person reviews it.

- [[published-rest-microflow-result-types]] reference, any: what an operation microflow may return; empty HttpResponse error; unhandled exception = 500
- [[httpresponse-reasonphrase-has-no-effect]] pitfall, any: custom ReasonPhrase ignored, clients see the default status text
- [[http-request-response-entities]] reference, any: HttpRequest/HttpResponse/HttpHeader attributes and defaults
- [[published-rest-content-negotiation]] reference, any: JSON or XML chosen by Content-Type and Accept; default JSON
- [[published-rest-body-parameter-import-mapping]] reference, any: body needs import mapping; missing Content-Type gives 400; commit and if-no-object options
- [[published-rest-openapi-schema-needs-message-definition]] pitfall, any: Swagger shows "type file" instead of a schema
- [[published-rest-path-and-query-parameters]] reference, any: path/query rules, case sensitivity, ISO-8601, empty defaults
- [[openapi3-reserved-header-parameter-names]] pitfall, any: header parameter named Authorization conflicts in Swagger UI
- [[published-rest-authentication-methods]] reference, any: basic, active session (X-Csrf-Token), custom; order tried; web service users blocked
- [[published-rest-custom-authentication-microflow]] reference, any: custom auth microflow params; return User; empty gives 404
- [[published-rest-cors-settings]] reference, any: allowed origins constant, max age, allow credentials
- [[published-rest-location-and-docs]] reference, any: default rest/name/v1, reserved prefixes, rest-doc openapi.json, REST Publish log node
- [[published-rest-versioning]] practice, any: duplicate for breaking changes, version folders, deprecation
- [[generate-rest-resource-from-entity]] procedure, any: Expose as REST resource, key attribute, generated artifacts, publish microflow limits
- [[published-rest-autoadded-http-parameters-ce0346]] pitfall, any: CE0346 from auto-added httpResponse/httpRequest params
- [[published-rest-error-responses]] procedure, any: return 400/404 JSON errors instead of generic 500
- [[published-rest-return-file-mime-type]] procedure, any: image/PDF endpoint returns only binary; set Content-Type
- [[retrieve-file-with-call-rest]] procedure, any: download a file into a FileDocument with Store in a file document
- [[call-rest-json-structure-import-mapping]] procedure, any: JSON structure, then import mapping, then Call REST service
- [[consumed-rest-service-limitations]] pitfall, any: 201 not mapped, use latestHttpResponse; JSON only; no streaming
- [[consumed-rest-service-authentication]] procedure, any: basic auth via constants; bearer/API key via headers
- [[consumed-rest-service-parameters]] reference, 11.1+ for query table: {param} syntax, dynamic base URL, body entities
- [[consumed-rest-flatten-simplify]] reference, any: flatten/simplify gives fewer entities; clear before Create entity
- [[server-side-paging-rest-datasource]] procedure, 8.2.0+: paging/sorting/search data grid over a REST call

## Gaps

- Call REST service action details are not covered: timeouts, custom headers, authentication options, proxy settings, client certificates, error handling, and how 4xx/5xx responses are handled.
- Consuming OAuth 2.0 or other token flows is not covered. The sources only say "add headers manually".
- JSON structure and export mapping options (null handling, date formats, value mappings) are not described.
- Conflict: the how-to says an export mapping is optional (lists are exported via the Accept header). The operation reference says object/list results must have one.
- Conflict: methods without a body parameter are listed as GET/HEAD/DELETE on one page and GET/HEAD/OPTIONS on another.
- Unclear: the Consumed REST Service "cannot configure parameters in Query Parameters tab" limitation versus the 11.1+ query parameter table.
- Unclear: the how-to says the auto-added httpRequest parameter causes errors, without saying why.
- The legacy-system source uses the Marketplace REST module (RestServices) but gives no usable details. Its relation to the native actions is not explained.
- No version information for most behaviours (for example, when the Consumed REST Service document or OpenAPI 3.0 export became available).
