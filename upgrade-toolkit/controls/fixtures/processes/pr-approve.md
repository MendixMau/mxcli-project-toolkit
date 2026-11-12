# Processes

Purchase Request (public sample app), real run D28. Format: templates/processes.example.md.

## P02: Approve a purchase request
status: confirmed
roles: Approver
source: model: actions.json, Task Inbox "Open tasks" and the Task_Approver task page; D28
steps:
1. [Approver] Click "View"  => PurchaseApprovals.TaskInbox.actionButton7
2. [Approver] Click "Assign to me"  => PurchaseApprovals.Task_Approver.actionButton19
3. [Approver] Click "Approve"  => PurchaseApprovals.Task_Approver.actionButton9
expect text: "Approved"
