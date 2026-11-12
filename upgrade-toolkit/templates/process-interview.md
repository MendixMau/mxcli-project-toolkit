# Key-user interview: processes (15 minutes)

E2E-16. One key user per role group, before the baseline run. You need their words, not a design: what they do every
day, in the order they do it, and what tells them it worked. Write the answers straight into this file under the
headings below; `bin/draft_processes.py --interview <this file>` reads these headings and drafts one process per task.
Do not tidy the wording: the step text is matched to buttons and menu items, so their captions are best.

Before the call: run `draft_processes.py --actions actions.json --out processes.md` (model drafts) and have the app's
menu open, so you can point at screens.

## Roles

_2 minutes. Which roles use the app, and which one is this user? One line each: `- Role: what they do`.
Use the role names of the app's security (the drafts list them)._

- 

## Top 5 daily tasks

_5 minutes. "What do you do in this app on a normal day?" One numbered line per task, with `[Role]` in front if it is not
this user's role. Under each task, indent the clicks as they describe them ("click New", "fill Subject", "Save").
Name buttons and fields as they appear on screen; put typed values in quotes._

1. [Role] Task name
   1. Open "Menu item"
   2. Click "New"
   3. Fill "Field" with "a value ${RUN_ID}"
   4. Click "Save"

## Most critical process

_4 minutes. "Which process must work on day one after the upgrade?" Usually a hand-off between roles (request,
approve). Write `Name: ...`, then every step with its `[Role]`, and the outcome as a row that must exist:
`expect: Module.Entity where Attribute = "the value typed ${RUN_ID}"`._

Name: 

1. [Role] ...
2. [Other role] ...

expect: 

## What breaking looks like

_2 minutes. "How would you notice it is broken?" An error message, a missing status, an email that does not arrive,
a number that is wrong. This goes to the critical process's notes and decides its expect line._

## Sample data

_2 minutes. Which records must exist for the tasks to start (a supplier, a product, an open request)? Names only, no
personal or customer data. These become seeds or fixture rows (steps/journeys.md, fixture preflight), not steps._

- 

---

After the call: rerun `draft_processes.py ... --interview <this file>`, walk the drafts with the user (5 minutes, or
async), pick a candidate for every `=> ?`, then set `status: confirmed` on the ones they agree with. Only confirmed
processes are compiled and run, on the old app first.
