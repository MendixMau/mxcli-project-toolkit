# Processes

Purchase Request (public sample app), real run D52. Format: templates/processes.example.md.

## P04: Attach a file to a workflow instance
status: confirmed
roles: Administrator
source: model: actions.json, WorkflowAttachment_New (fileManager1) from the admin workflow instance view; D52
steps:
1. [Administrator] Fill "fileManager1" with "upg-seed.jpeg"
2. [Administrator] Click "Save"  => WorkflowCommons.WorkflowAttachment_New.actionButton3
expect text: "upg-seed.jpeg"
