---
title: Return proper 4xx error responses from a published REST microflow instead of generic 500/404
topic: rest-integration
kind: procedure
applies_to: general
versions: "any"
keywords: [published REST error handling, 500 Internal Server Error, 400 Bad Request, 404 not found, custom with rollback, HttpResponse, error JSON, Content-Type header]
sources:
  - {title: "Publish a REST Service", url: "https://docs.mendix.com/refguide/publish-a-rest-service/", author: "unknown", date: "2026-09-25"}
  - {title: "Version a REST Service", url: "https://docs.mendix.com/refguide/version-rest-service/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
Without error handling, invalid input or a missing object gives a generic 500 or 404 error. Examples of invalid input are text where an integer ID is expected, or a blank ID.

**Steps**
1. On the activity that can fail (for example, parsing the ID), choose **Set error handling** > **Custom with rollback**.
2. On the error flow:
   - Create an `HttpResponse` with a status code and JSON `Content`, for example `'{"Error": "The OrderID can only be an integer"}'`.
   - Add another **Create object** activity that creates an `HttpHeader` object. The source's success-path example sets **Key** `'Content-Type'`, **Value** `'application/json'`, and **System.HttpHeaders** to the response.
3. End the error flow returning that response.
4. For "not found", add a decision `$Order != empty` after the retrieve. On the false exit, create a similar response and header, then return the response.
5. Test in `/rest-doc/` with **Try it out**.

**Checks**
Enter text in the **OrderID** parameter, click **Execute**, and check that the response shows your error.

**Watch out**
- The versioning source treats changing a 500 into a 400 as a non-breaking fix: see [[published-rest-versioning]].
