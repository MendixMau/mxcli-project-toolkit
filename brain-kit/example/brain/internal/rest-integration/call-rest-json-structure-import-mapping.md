---
title: Consume a JSON REST API with JSON structure, import mapping and Call REST service
topic: rest-integration
kind: procedure
applies_to: general
versions: "any"
keywords: [Call REST service, JSON structure, import mapping, Map automatically, Apply import mapping, location template, consume REST, set association, input parameter mapping]
sources:
  - {title: "Use Call REST Service Action in a Microflow", url: "https://docs.mendix.com/refguide/integration/use-call-rest-action-in-microflow/", author: "unknown", date: "2026-09-25"}
  - {title: "REST Services", url: "https://docs.mendix.com/refguide/integration/rest-services/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
Calling a REST endpoint that returns JSON and turning the result into entities.

**Steps**
1. Get a sample response and copy the JSON.
2. **Add other** > **JSON structure**. Paste the snippet, click **Refresh**, then **OK**.
3. **Add other** > **Import mapping**. Select the JSON structure, click **Expand all** and **Check all**, then **Map automatically** to generate the entities.
4. Optional: drag a non-persistable input entity onto the mapping as its parameter. On the root object, set **Set association** = Yes so results link to the input.
5. In a microflow, add **Call REST service**:
   - **Location** template with placeholders, for example `.../summary/{1}`, filled by a parameter such as `$Input/Title`.
6. On **Response**:
   - **Response handling** = **Apply import mapping**
   - Select the mapping and its parameter
   - Store the result in a variable

**Checks**
The variable holds the mapped root object.

**Watch out**
- Rename generated entities (for example, Root) as needed.
- Use **Refresh in client** when you change objects shown on a page.
- The REST Services overview says JSON output should declare content type `application/json`.
