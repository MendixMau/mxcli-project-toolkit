# Local boot: app-specific login replacement means no local password works

**Source:** a field project's `docs/case-study/boot.md`. **Status:** unreviewed.

The app replaces XAS login with a custom Java listener that verifies against a remote identity
service, so no local/demo password logs in. The project keeps a local patch (skip-worktree) that
the cloud container lacks — UI e2e runs there were blocked, and a test agent misdiagnosed it as
an SSO module problem.

Proposed for the boot skill / boot script: detect a custom login listener in `javasource/`
(e.g. a class registering a login handler at startup) and report "local login needs a patch"
up front, instead of letting the journey fail at the login step. Project-specific details stay
in the project brain.
