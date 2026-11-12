# Upgrade proposal: 10.24.1.1 -> 11.1.0

<!-- proposal inputs-hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -->

## 1. Summary

- From 10.24.1.1 to 11.1.0. App size: 3 modules, 20 pages.

## 2. Done by the toolkit

- module update Widgetpack 1.0.0 -> 2.0.0 (before the convert)
- module update Themepack 3.0.0 -> 4.0.0 (after the convert)

## 3. Needs your decision before we start

- [P-1] module: Gridmod
  - evidence: local edits refuse the update (localedits.json / kept.txt)
  - options: keep old version (kept list) | replace with the Marketplace equivalent | hand to a named person
  - recommendation: keep old version (kept list); effort M; risk: edits lost on update
  - answer: keep old version (kept list) (ASSUMED (unattended))
- [P-2] theme: Themepack styles
  - evidence: edited files in themesource
  - options: replay as is (S) | use design properties (M)
  - recommendation: use design properties; effort S; risk: look only
  - answer: use design properties (ASSUMED (unattended))

## 4. Needs a person anyway

- go-live actions
  - outside the toolkit

## 6. Sign-off

A person writes exactly one of these two lines below (an agent never does):

`Signed-off: <name> <yyyy-mm-dd>`   or   `Status: PAUSED <reason>`

Status: open
