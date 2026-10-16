# A second language — the four decisions that decide whether a user ever sees the translations

**Applies to:** any mxcli project.
**Purpose:** adding a language to a Mendix app built with MDL: which language is the source, which
are enabled, which one a user starts in, and a language switch that works for a non-admin role.
Read it before the first translation script, and the moment a language picker errors, shows a blank
label, or changes nothing.
**Source:** field run 2026-10-09, a regulatory-QA demo app (Mendix 11.15.0, mxcli v0.25.0) authored
in Spanish, with Spanish and Portuguese added as a change request. Writing the strings went cleanly
(418 per language, `create or modify translations without marketplace`). Everything around them
failed — four separate failures, each green on `mxcli check`, `exec.sh` (mxbuild 0 errors) and
`mxcli lint`. Writing the strings themselves is mxcli's `translations` skill; this file is the rest.

---

## The one-line finding

> The translations were correct the whole time. What the user saw was decided by the source
> language, the user's language and the switch — none of which a gate looks at.

| What the user saw | What was actually wrong | § |
|---|---|---|
| Picking a language raised an error and nothing changed | The Marketplace LanguageSelector writes `System.User_Language` from the browser; a normal role could not, and on this project no grant route was found | 4 |
| The picker showed no text at all | The demo users were on `en_US`, which this project's picker configuration left out of its list | 3 |
| There is no English to offer | Captions were authored in Spanish under the default `en_US` | 1 |
| The login page stayed Spanish | `theme/web/login.html` is outside the translation system | 5 |

---

## 1. Decide the source language before the first caption

Every caption is stored under the project's **default language**, whatever language it is written
in. This app's captions were authored in Spanish under the default `en_US`, so `en_US` *is* Spanish
— a user on `en_US` sees Spanish, and there is no English to offer without retranslating.

Changing the default later moves no text and nothing warns (`mx check` is 0 errors either way).
mxcli's own fix for a wrong source is to change `DefaultLanguageCode` and re-run the `create`
statements that wrote the captions — workable while the scripts are the whole source of truth.
So, at Stage 3, ask the user one question and record the answer in `PROJECT.md`: *which language
are captions written in, and is that the language users get, or a hidden source?*

When the authored language is not the default (the common case on a project that started from
`mxcli new`): keep the default as a hidden source, enable the real languages, and give the authored
language a translation that **copies its strings verbatim**. That same file is where Mendix's own
English platform texts — validation messages, paging, confirmation buttons — are translated;
otherwise they stay English in the Spanish UI.

```sql
mdl 1;
alter settings language add or modify 'es_ES' ( CheckCompleteness: false );
alter settings language add or modify 'pt_PT' ( CheckCompleteness: false );

create or modify translations without marketplace for es_ES (
  'Guardar' as 'Guardar',                              -- authored in Spanish: copied as is
  'Go to first page' as 'Ir a la primera página'       -- Mendix platform text: translated
);
```

Settings writes work from the CLI (`learned-mdl-preflight.md` STOP #2, retired 2026-09-30), so
this needs no stop-and-ask. Keep the dictionary in one generator (a small script that writes one `.mdl` per language),
not in hand-edited MDL: a renamed caption has to change in one place, and the scripts are
re-applied after every caption change — this project re-applied both the same day it wrote them, after the switch's captions changed.

**Probe:** `./mxcli -p <app>.mpr -c "DESCRIBE SETTINGS" | grep -E "DefaultLanguageCode|LANGUAGE add"`
— the default and the enabled list. `describe translations for <code>` ends with
`N source string(s), M translated, K to go`.

## 2. Agree what is not translated

Captions are model text; **data is not**. Product names, imported documents, generated rule
explanations, certificate and CSV contents stay in the language they were stored in. Ask the user
before translating (this project: *data stays Spanish*, recommended in chat, not contested) and
record it — or the first review reports a half-translated app.

## 3. Start users in a language they can see

A user's language is `System.User_Language`. A user on no language or on the hidden source gets
source text, and a picker whose list leaves that language out has nothing to show as the current
one. That was this project's blank label — observed with this widget configuration: the list was
`System.Language` filtered `[Code != 'en_US']`, so the demo users' own language was not in it.

Set it where accounts are created; for seeded demo accounts, in after-startup, leaving a choice the
user already made alone:

```sql
retrieve $Spanish from System.Language where Code = 'es_ES' first;
retrieve $Demo from Administration.Account
  where [Name = 'demo.user@example.com' and not(System.User_Language/System.Language[Code != 'en_US'])] first;
if $Spanish != empty and $Demo != empty then
  change $Demo (System.User_Language = $Spanish) commit without events;
end if;
```

## 4. The language switch: do not use the Marketplace LanguageSelector for a normal role

**What failed.** LanguageSelector v1.1.3 reads `System.User_Language` from the session user and
commits a new value **from the browser**. For this project's non-admin role the pick raised an
error and changed nothing, and **on this project no grant route was found**:

- **mxcli** — `grant read (User_Language) on entity Administration.Account …` *passes `check`*
  and is refused by `exec`, verbatim (recorded 2026-10-09, v0.25.0):
  `entity Administration.Account has no member(s) User_Language`. The qualified
  `System.User_Language` does not parse there (`mismatched input '.' expecting {',', ')'}`).
  This is deliberate in mxcli: its access-rule walk stops at `System.User`, so a platform member
  listed in a rule on a specialization is CE0066.
- **Studio Pro** — the first fix was written as a Studio Pro hand step (Account → access rule →
  tick `User_Language`). The user tried it: **Studio Pro does not offer that member.** The hand
  step was impossible, and a script had already shipped describing it.

What is **not** established is that a normal user can never write their own `User_Language`: that
member is governed by the System module's own access rules, which a user role receives through the
`System.User` module role. So before replacing the widget, run one probe:

- `./mxcli -p <app>.mpr -c 'DESCRIBE USER ROLE "<Role>"'` — does `ModuleRoles` include `System.User`?
  (On this project it did, for both roles, and the pick still failed.)
- Is the picker reading the session user (`System.User`) rather than a specialization such as
  `Administration.Account`? This widget takes no user binding; it uses the session user.

If both hold and the pick still fails, do not write the Account hand step and do not spend a session
on the access rule. Replace the widget — the recipe below works either way.

**What works.** A microflow applies no entity access, so it may set the signed-in user's own
language; Mendix applies a language when the client loads, so the button reloads afterwards.

```sql
mdl 1;
/** Sets the signed-in user's language to the System.Language with this code. Only touches the current user; ignores an unknown code. */
create or modify microflow MyModule.SUB_SetLanguage ($Code: String)
begin
  retrieve $Language from System.Language where Code = $Code first;
  if $Language != empty and $currentUser != empty then
    change $currentUser (System.User_Language = $Language) commit;
  end if;
end;

/** ES button: switch the user to Spanish, then reload so the language applies. */
create or modify nanoflow MyModule.ACT_LanguageES ()
begin
  call microflow MyModule.SUB_SetLanguage(Code = 'es_ES');
  call javascript action NanoflowCommons.Reload();
end;

grant execute on microflow MyModule.SUB_SetLanguage to MyModule.User;
grant execute on nanoflow MyModule.ACT_LanguageES to MyModule.User;
```

One nanoflow per language, two buttons in the layout's top bar (`alter layout … { replace
<selector> with { container … { actionbutton … } } }` swaps the widget in place). Needs
NanoflowCommons for `Reload`. Label the buttons in their own words (`ES`, `PT`), not with
`System.Language.Description`, which is whatever the runtime stored and is usually English.
`mxcli lint` flags the nanoflow — CONV010, *"ACT_ microflows should only contain UI actions and
sub-microflow calls"*, raised here on the JavaScript `Reload` call; accept it in the baseline with
that reason, or name the nanoflow without the `ACT_` prefix.

Highlight the active language from **`<html lang>`**, which Mendix writes from the user's language
— no data read, so no access question at all:

```scss
html[lang^="es"] .lang-switch-es,
html[lang^="pt"] .lang-switch-pt { background: var(--color-primary); color: var(--color-on-primary); }
```

**Probe:** in the running app, after switching, `document.documentElement.lang` starts with the new
code. Measured here: `pt` after switching to `pt_PT`, with the menu reading *Histórico*.

## 5. The login page is yours to translate

`theme/web/login.html` is a static file: no Mendix translation reaches it and there is no user
language before sign-in. This project gave it `data-i18n` keys, a small inline script swapping them
and an `ES | PT` toggle remembered in `localStorage`. It does not set the user's language after
sign-in — §3 and §4 do.

## 6. Verify in the running app — per language, per role

A green gate proves none of §1–§5. **Sign in as a non-admin user** — the §4 failure does not
reproduce as an administrator — and for each enabled language:

1. Switch; the page reloads in that language: menu, page titles, buttons, grid headers, and one
   Mendix platform text (a validation message or the paging bar).
2. The active button is highlighted (`<html lang>` changed).
3. Sign out and in again: the choice persisted.
4. A page with data shows the data in its stored language (§2).

**Done means** 4 of 4 checks, for every enabled language × every user role, written down with a
screenshot each (this project: 2 languages × 2 roles, the screenshots in its demo guides). A
language showing source text everywhere is an enabled-language question first
(`describe settings`), before anything is re-translated.
