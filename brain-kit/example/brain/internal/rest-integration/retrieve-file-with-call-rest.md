---
title: Download a file or image from a REST endpoint into a FileDocument
topic: rest-integration
kind: procedure
applies_to: general
versions: "any"
keywords: [Call REST service, Store in a file document, download file REST, retrieve image, FileDocument, System.Image, binary response, Image widget URL]
sources:
  - {title: "Publish and Retrieve Images and Files with REST", url: "https://docs.mendix.com/refguide/send-receive-files-rest/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
Your app must fetch a binary file from any REST service, Mendix or not, and store it.

**Steps**
1. Create an entity (for example RetrievedFile) that generalises System.Image (images) or System.FileDocument (PDFs and other files).
2. Add a **Call REST service** action. On **General**, set the **Location** to the file URL.
3. On **Response**, set:
   - **Response handling** to **Store in a file document**
   - **Store in variable** to Yes
   - **Type** to your entity
4. For images to display: add **Change object** on the result with **Refresh in client** = Yes.

**Checks**
The file appears in the entity, for example via an image viewer.

**Watch out**
Alternatives without a microflow:
- The Marketplace **Image** widget with Image URL.
- The **HTML/JavaScript Snippet** widget with an `<embed src=...>` for PDFs.
