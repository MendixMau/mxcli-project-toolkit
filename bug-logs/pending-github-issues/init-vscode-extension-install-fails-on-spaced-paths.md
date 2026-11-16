**Repo:** `mendixlabs/mxcli`
**Source:** field run 2026-11-16 — Windows 11, mxcli **v0.32.0** `init`, VS Code in its default per-user location, project folder under OneDrive (path with spaces). Code read on `main` at 121c9b5.
**Status:** NOT YET FILED
**Severity:** Low — cosmetic; the extension can be installed by hand. Hits the default Windows install.

---

# `mxcli init`: VS Code extension install fails when `code.cmd` and the project path both contain spaces

## Observed (verbatim)

```
Warning: VS Code extension install failed: exit status 1
'C:\Users\<user>\AppData\Local\Programs\Microsoft' is not recognized as an internal or external command,
operable program or batch file.
```

## Cause (hypothesis, consistent with the message)

`findCodeCLI` returns `%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd`, and
`installVSCodeExtension` runs `exec.Command(codeCLI, "--install-extension", vsixPath, "--force")`.
A `.cmd` runs under `cmd.exe /c`. When the command line holds more than two quote characters —
here both the `code.cmd` path and `vsixPath` (`<project>\.claude\vscode-mdl.vsix`, under OneDrive)
need quotes — `cmd.exe` strips the first and last quote, and the program path breaks at the
first space: `...\Programs\Microsoft`.

## Suggested fix

Run through `cmd.exe /s /c ""<code.cmd>" --install-extension "<vsix>" --force"` with
`SysProcAttr.CmdLine` set explicitly, or call `Code.exe` with `resources\app\out\cli.js` directly
(what `code.cmd` does), avoiding the batch layer. Repro: a project path with a space, VS Code
installed per-user, `code` not on PATH.
