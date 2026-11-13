---
title: Strict mode breaks File Uploader delete, Take picture, and save/cancel buttons in layouts
topic: security
kind: pitfall
applies_to: general
versions: "any"
keywords: [strict mode, File Uploader delete not working, Take picture, Web Actions, Save Changes, Cancel Changes, layout consistency error, snippet, data.remove, data.commit]
sources:
  - {title: "Strict Mode", url: "https://docs.mendix.com/refguide/strict-mode/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
After you enable strict mode (React client), one or more of these happens:
- The File Uploader delete action does nothing.
- The Web Actions **Take picture** action fails.
- A consistency error appears for a save or cancel button placed in a layout.

**Root cause**
- File Uploader delete uses `data.remove`, which strict mode blocks.
- Take picture uses `data.commit` to create the object, which strict mode blocks.
- In strict mode, Studio Pro checks that save and cancel actions affect only entities in editable widgets. It does not analyse layouts, so these buttons are not allowed in a layout.

**Fix**
- File Uploader: build a custom button that runs a nanoflow to delete the file object. See *Enable Custom Buttons* in the File Uploader docs.
- Save/cancel: move the buttons from the layout into a snippet.
- Take picture: the source gives no workaround.

**Status**
Documented limitations.
