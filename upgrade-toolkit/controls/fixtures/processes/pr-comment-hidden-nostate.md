# Processes

Purchase Request, the comment box of the task page (PRF-1, owner decision D5): its field sits under State = InProgress.
Golden actions: fixtures/actions/pr-comment-hidden.json (two actions of the real model's actions.json).

## P09: Approver writes a comment
status: confirmed
roles: Approver
source: model: actions.json, Comments_TaskInbox Submit
steps:
1. [Approver] Fill "Content" with "Note ${RUN_ID}"
2. [Approver] Click "Submit"  => PurchaseApprovals.Comments_TaskInbox.actionButton1
expect text: "Note ${RUN_ID}"
