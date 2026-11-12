---
title: Set Content-Type when a published REST operation returns a file or image
topic: rest-integration
kind: procedure
applies_to: general
versions: "any"
keywords: [MIME type, Content-Type, image/png, application/pdf, file document REST, binary response, System.Image, System.FileDocument, Get by key, only see binary]
sources:
  - {title: "Publish and Retrieve Images and Files with REST", url: "https://docs.mendix.com/refguide/send-receive-files-rest/", author: "unknown", date: "2026-09-25"}
  - {title: "Published REST Operation", url: "https://docs.mendix.com/refguide/published-rest-operation/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
A GET operation returns a FileDocument/Image, but clients only see raw binary instead of a displayed image or PDF.

**Steps**
1. Expose the entity that generalises System.Image or System.FileDocument with **Expose as a REST resource**. Generated Get by key returns a file document with no export mapping.
2. In the GET_ByKey microflow, just before the end event, **Create object** `System.HttpHeader` with:
   - `Key` = `'Content-Type'`
   - `Value` = `'image/png'` (or the image type returned) or `'application/pdf'`
   - `System.HttpHeaders` = `$httpResponse`
3. Optionally set `Content-Disposition` for the file name and download-as-attachment behaviour.

**Checks**
Open `/rest-doc/...`, run **Get /myfile/{id}**, then **Try it out**. The image should be displayed.

**Watch out**
Without the MIME type you only get binary.
