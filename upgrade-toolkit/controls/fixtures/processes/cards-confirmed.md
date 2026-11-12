# Processes (EXAMPLE)

E2E-16 control fixture on the Starter Kit home cards (fixtures/actions/t2-home-cards.json). Invented processes, as a
key user would have confirmed them; no real user or customer behind them.

## P10: Read the contents
status: confirmed
roles: Administrator
source: control
steps:
1. Open "Home" in the menu
2. Click the "Contents" card
expect text: "Contents"

## P11: Administrator hands over to a user
status: confirmed
roles: Administrator, User
source: control
steps:
1. [Administrator] Click the "Links And Infos" card
2. [User] Click the "How To" card
expect text: "How"

## P16: Not agreed yet
status: draft
roles: User
source: control
steps:
1. [User] Click the "How To" card
expect: ?
