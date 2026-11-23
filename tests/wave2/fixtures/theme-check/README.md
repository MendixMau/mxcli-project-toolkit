# theme-check golden input (#837)

Captured on a real Mendix 11.8.0 app (`mxcli new`, Linux container, reproducing the 2026-11-17 field regression run,
mxcli v0.33.1) with a deliberately broken theme. Only the project root prefix in paths was rewritten
(to `/proj`); nothing else was edited.

- `sass-11.8.0-syntax-error.stderr`, `sass-11.8.0-missing-import.stderr` — stderr of the dart-sass 1.49.11 that
  ships in `<mxbuild dir>/tools/sass/linux-x64/sass`, run as `sass --no-source-map --no-color --no-unicode --quiet --load-path=<model dir> <entry> <out>` (exit 65).
- `deployment-sass-main-11.8.0.scss` — the entry file mxbuild generated (`deployment/sass/main.scss`); two of its
  13 entries name modules that no longer existed, as in the real file.
- `mx-check-11.8.0-CE6093.json` — `mx check -j` on the broken app after a model change: CE6093, no file, no line.
- `mxbuild-11.8.0-theme-errors-only.json` — `mxbuild --write-errors` of a warm deploy build: `errors[]` only, `problems[]` empty, exit 3.
