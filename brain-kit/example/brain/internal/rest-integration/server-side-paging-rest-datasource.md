---
title: Server-side paging, sorting and search for a data grid backed by a REST call
topic: rest-integration
kind: procedure
applies_to: general
versions: "Studio Pro 8.2.0 and above"
keywords: [server-side paging, microflow data source, Paging entity, PageNumber, SortAttribute, SortAscending, IsSortable, data grid REST, Use React client, Call REST location template]
sources:
  - {title: "Server-Side Paging and Sorting for a Microflow Data Source", url: "https://docs.mendix.com/refguide/server-side-paging/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
A data grid shows REST data, and you want to fetch one page at a time instead of everything.

**Steps**
1. Build a microflow that runs Call REST service with an import mapping and returns the list. See [[call-rest-json-structure-import-mapping]].
2. Use it as the microflow data source of a **Data grid**.
3. Answer **Yes** to "automatically fill the contents".
4. Answer **Yes** to "generate controls for microflow source parameters". This adds a **Paging** parameter, a data view, widgets and nanoflows.
5. Add the page number to the location template using the API's own query syntax, for example `?_limit=5&_page={1}`, with `{1}` = `toString($Paging/PageNumber)`.
6. Add sorting, for example `&_sort={2}&_order={3}`:
   - `{2}` = `toLowerCase($Paging/SortAttribute)`
   - `{3}` = `if $Paging/SortAscending then 'asc' else 'desc'`
7. Add search from the generated input fields, for example `&name_like={4}` with `if $Paging/Name = empty then '' else $Paging/Name`.
8. Set defaults in the data source nanoflow's Create object:
   - `SortAttribute` sets the default sort.
   - `IsSortable = false` disables header sorting.

**Checks**
The paging bar and header clicks trigger new REST calls.

**Watch out**
- This data grid is a Dojo widget: set **Use React client** = **No** to see it in the Toolbox.
- The query syntax depends on the remote API.
