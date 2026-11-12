# Upgrade proposal: 10.24.1 -> 11.12.6

<!-- proposal inputs-hash: 0000000000000000000000000000000000000000000000000000000000000000 -->

## 1. Summary

- From 10.24.1 to 11.12.6. App size: 12 modules, 40 pages.

## 2. Done by the toolkit

- module update Gridmod 1.4.0 -> 2.0.0 (before the convert)
- module update Gridmod 2.0.0 -> 2.3.0 (after the convert)

## 3. Needs your decision before we start

- [P-1] module: Cartkit
  - evidence: kept at its version by the update step: local edits refuse the update (kept.txt)
  - options: keep old version (kept list) | replace with the Marketplace equivalent (replacements.tsv row) | hand to a named person
  - recommendation: keep old version (kept list); the stop rule keeps it unattended; effort M; risk: behaviour of local edits is lost on update
  - answer: keep old version (kept list); the stop rule keeps it unattended (ASSUMED (unattended))
- [P-2] theme: Themepack style files
  - evidence: 4 style files were deleted in the module (localedits.json)
  - options: update and delete the files again | keep the old version
  - recommendation: update and delete the files again; effort S; risk: the look can change
  - answer: update and delete the files again (ASSUMED (unattended))

## 4. Needs a person anyway

- go-live decision on every INVALID journey that remains: owner: a named person

## 6. Sign-off

A person writes exactly one of these two lines below (an agent never does):

`Signed-off: <name> <yyyy-mm-dd>`   or   `Status: PAUSED <reason>`

Status: open
