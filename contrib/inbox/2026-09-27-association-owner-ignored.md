# mxcli: `create or modify association` ignores an owner change

**Source:** marketplace-rnd, guest-groups best-practices work (2026-09-27). mxcli v0.23.0, Mendix 11.12.2.
**Status:** unreviewed inbox drop.

## Symptom
`create or modify association UserGroups.GuestGroup_App ... owner Both;` on an existing
association (owner Default) reports "Modified", yet `DESCRIBE ASSOCIATION` still shows owner
Default. The owner change is dropped without a message.

## Why the obvious workaround is worse
`drop association` + `create association ... owner Both` does set the owner, but mints a new
association ID: existing DB links are lost, and every entity access rule's member right on that
association resets to None (GuestGroup's ReadWrite/ReadOnly rights were lost). On a cross-module
association into a module-owned entity it also gave CE0066.

## Workaround used
A direct patch of the association unit in the MPR (SQLite `Unit` table, BSON `Contents`): flip
`Owner` to `Both` in place (same ID), append a `DomainModels$MemberAccess` (None) for the
association to every access rule of the other entity, recompute `ContentsHash`
(base64 sha256 of Contents). Proven on a scratch copy: mxbuild succeeded, `mx check` 0 errors.
Script: marketplace-rnd `mdlsource/guest-groups/14-one-to-one-guestgroup-app.py`.

## Ask
Either apply the owner in `create or modify`, or refuse with an error that names the limitation.
