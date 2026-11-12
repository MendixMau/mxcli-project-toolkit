# Processes (EXAMPLE)

E2E-16 control fixture: every confirmed process below except P13 must come out INVALID with its reason, none dropped.
P13 compiles and fixes the role order User -> Administrator, which P11 then contradicts. Starter Kit home cards
(fixtures/actions/t2-home-cards.json); invented, no real user or customer behind them.

## P12: Role acts again
status: confirmed
roles: Administrator, User
source: control
steps:
1. [Administrator] Click the "Widgets" card
2. [User] Click the "How To" card
3. [Administrator] Click the "Contents" card
expect text: "x"

## P13: Reverse order
status: confirmed
roles: Administrator, User
source: control
steps:
1. [User] Click the "How To" card
2. [Administrator] Click the "Widgets" card
expect text: "x"

## P11: Administrator hands over to a user
status: confirmed
roles: Administrator, User
source: control
steps:
1. [Administrator] Click the "Links And Infos" card
2. [User] Click the "How To" card
expect text: "How"

## P14: No click path
status: confirmed
roles: Administrator
source: control
steps:
1. Click "New"
expect text: "x"

## P15: No such action
status: confirmed
roles: User
source: control
steps:
1. Click the "Contents" card
2. Click "card"
expect text: "x"

## P17: Outcome without the run id
status: confirmed
roles: Administrator
source: control
steps:
1. Click the "Widgets" card
expect: StarterKit.Widget where Name = "fixed"

## P18: Candidate not picked
status: confirmed
roles: Administrator
source: control
steps:
1. Click the "Widgets" card  => ?
   candidates: StarterKit.Home_Gallery.container13
expect text: "x"
