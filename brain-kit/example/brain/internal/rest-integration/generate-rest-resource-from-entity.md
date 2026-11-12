---
title: Generate a published REST resource from an entity (Expose as REST resource)
topic: rest-integration
kind: procedure
applies_to: general
versions: "any"
keywords: [Expose as REST resource, generate REST resource, key attribute, Get all, Get by key, Post, Patch, Delete, message definition, publish microflow as REST operation]
sources:
  - {title: "Generating a Published REST Resource", url: "https://docs.mendix.com/refguide/generate-rest-resource/", author: "unknown", date: "2026-09-25"}
  - {title: "Publishing a Microflow as a REST Operation", url: "https://docs.mendix.com/refguide/publish-microflow-as-rest-operation/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
You want CRUD-style operations for an entity, or want to publish an existing microflow.

**Steps**
1. Start from one of:
   - Right-click the entity, then **Expose as REST resource** (you then choose the service).
   - Drag an entity or message definition onto a service's resource list.
2. Enter a resource name.
3. Select a unique **Key attribute**. It is required for Get by key, Patch and Delete.
4. Check the operations you want: Get all, Get by key, Post, Patch, Delete.
5. Click **OK**.

**Checks**
The following are created:
- the resource and operations
- one microflow per operation
- a message definition
- an import mapping (for Post and Patch)
- an export mapping (for Get all and Get by key)

An existing message definition for the entity, and the mappings based on it, are reused.

**Watch out**
- To publish a microflow, right-click in the microflow editor, then **Publish as REST service operation**.
- A microflow with more than one object or list parameter cannot be published: it gives a consistency error.
- The suggested method is POST when there is an object or list parameter, otherwise GET.
- For file entities, see [[published-rest-return-file-mime-type]].
