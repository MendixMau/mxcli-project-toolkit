# Key-user interview: processes (EXAMPLE)

Example notes for the E2E-16 field proof on the customer 11.x model in this repo, written on
templates/process-interview.md. Invented: no real user, customer or interview behind it.

## Roles

- User: works in the routing workshop app and reports problems through the feedback widget

## Top 5 daily tasks

1. [User] Report a problem with a screenshot
   1. Open "Share Feedback"
   2. Fill "Subject" with "Printer jam ${RUN_ID}"
   3. Click "Take Screenshot"
2. [User] Attach a picture to a report
   1. Open "Share Feedback"
   2. Fill "Subject" with "Label photo ${RUN_ID}"
   3. Click "Upload"

## Most critical process

Name: Send feedback to the team

1. [User] Open "Share Feedback"
2. [User] Fill "Subject" with "Line 3 down ${RUN_ID}"
3. [User] Fill "Description" with "Station 4 stops after scan"
4. [User] Click "Submit"

expect: FeedbackModule.Feedback where Subject = "Line 3 down ${RUN_ID}"

## What breaking looks like

The feedback never reaches the team: no confirmation after Submit.

## Sample data

- none: feedback starts from an empty form
