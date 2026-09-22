# Follow-up: could the CLI solve this after all? — **Yes. Proven end to end, headless.**

The earlier conclusion ("blocked, needs a conversion hop on another machine") was true of
`mx module-import` and `mx convert`. It was **not** true of the CLI as a whole. Asked whether
mxcli could do it in theory, we probed instead of reasoning, and it can — today, with no
Studio Pro and no version hop.

Same environment as the parent record: mxcli `v0.22.0`, MxBuild `11.14.0`, Linux container.

## 1. The version gate is `mx`'s, not mxcli's

mxcli reads the 10.6.4 model directly, no complaint:

```console
$ mxcli -p <extracted-from-mpk>/project.mpr -c "SHOW MODULES"
| Module           | Entities | Pages | Microflows | ... |
| System           | 39       | 0     | 0          |     |
| USI_Theme_Module | 0        | 0     | 0          |     |
(2 modules)   exit 0
```

Two facts in one output. **mxcli has no 10.6.4 problem** — the refusal was entirely `mx`'s.
And **the theme module contains zero model documents**: no entities, pages, microflows,
snippets or enums. It is not a model import at all. It is files.

## 2. So "installing" it is a file operation, and it builds

```bash
cp -r <mpk>/themesource/usi_theme_module  <app>/themesource/
cp -n <mpk>/widgets/*.mpk                 <app>/widgets/
mxbuild --java-home=$JH --java-exe-path=$JH/bin/java --target=deploy <app>.mpr
# BUILD SUCCEEDED — log includes "Compiling theme files" / "Exporting a theme"
```

**But the brand colours were absent from the compiled CSS.** Four of the five hexes: zero hits.
A green build with the wrong palette — the false-green class this toolkit already tracks.

## 3. Why, and the step everyone would miss

The module's `web/main.scss` opens with:

```scss
@import '../../../theme/web/custom-variables';
```

It imports the **project's** variables, and `usi-custom-variables.scss` — the file carrying every
USI brand value — **is imported by nothing in the package**. Verified by grep across the module.
It is a *replacement* for the project's `theme/web/custom-variables.scss`, not a partial.

So the module compiled happily against whatever palette the project already had, produced valid
CSS, and reported success. Nothing warns you.

## 4. The complete, working install

```bash
cp -r <mpk>/themesource/usi_theme_module        <app>/themesource/
cp -n <mpk>/widgets/*.mpk                       <app>/widgets/
cp <app>/theme/web/custom-variables.scss        <app>/theme/web/custom-variables.scss.backup
cp <mpk>/themesource/usi_theme_module/web/usi-custom-variables.scss \
   <app>/theme/web/custom-variables.scss        # the step that is easy to miss
mxbuild --java-home=$JH --java-exe-path=$JH/bin/java --target=deploy <app>.mpr
```

Result — every brand colour now in the compiled output:

| Variable | Hex | Compiled files containing it |
|---|---|---|
| `$brand-primary` | `#0c4c8a` | 2 |
| `$brand-danger` | `#e60012` | 2 |
| `$brand-warning` | `#ed6d0f` | 2 |
| `$brand-success` | `#437242` | 2 |
| `$sidebar-bg` | `#24276c` | 3 |

`BUILD SUCCEEDED`, exit 0, no Studio Pro, no conversion, no 10.21–10.24 hop.

## 5. The cost, stated honestly

Replacing `theme/web/custom-variables.scss` **overwrites whatever theme the project had** — here,
the palette `mxcli new` had just installed. On a greenfield app that is the intended outcome. On
an app with an existing theme it is a merge, not a copy, and the two sets of variables have to be
reconciled by someone. Back the file up first; the procedure above does.

Also untested here: the module's `design-properties.json` (the Button Style property) reaching
Studio Pro's property dropdown, and the module appearing as a module in the target `.mpr`. Both
matter for a *model* module; for a pure theme module neither blocks the styling.

## 6. What this changes upstream

It strengthens the feature request rather than replacing it. mxcli can already read a model six
minor versions older than the tool that refuses it, and it already owns a writer that preserves
MPR v2 and handles theme modules. A local-`.mpk` install path would let it do all of the above —
including the variables step, which is exactly the kind of "and don't forget this" that belongs
in an installer rather than in a person's memory.
