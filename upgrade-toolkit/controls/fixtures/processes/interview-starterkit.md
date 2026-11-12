# Key-user interview: processes (EXAMPLE)

Example notes for the E2E-16 controls, written on templates/process-interview.md. Invented: no real user, customer or
interview behind it. App: the Opcenter EX Starter Kit home cards (fixtures/actions/t2-home-cards.json).

## Roles

- Administrator: maintains the kit and its links
- User: reads the how-to pages

## Top 5 daily tasks

1. [User] Read the how-to
   1. Click the "How To" card
2. [Administrator] Check the links page
   1. Open "Home"
   2. Click the "Links And Infos" card

## Most critical process

Name: Configure a client

1. [Administrator] Open "Home"
2. [Administrator] Click "New"
3. [Administrator] Click "Save"

expect: EXFN_Authentication.ClientConfiguration where Alias = "Plant ${RUN_ID}"

## What breaking looks like

The configuration grid stays empty after Save.

## Sample data

- one client configuration row
