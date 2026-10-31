# Contributing to apple-mcp-swift

Contributions are welcome: bug reports, documentation corrections, tests, and small focused changes are especially useful.

## Before opening an issue

Please check the [README](README.md), the [known limits](README.md#limits), and existing issues first. Do not include private data from Mail, Notes, Contacts, Calendar, Reminders, Safari, or macOS permission dialogs in a public issue. Redact names, email addresses, URLs, event details, paths, and logs.

For a bug report, include:

- macOS version, Mac architecture, and MCP client;
- the server and tool involved;
- expected and actual behavior;
- minimal redacted steps to reproduce; and
- the relevant error output, with private data removed.

Use the feature-request template to explain the problem before proposing an implementation. A new feature may require a new macOS permission, private framework, or destructive operation; that is a design and safety decision, not a mechanical addition.

## Development rules

- Keep the project dependency-free: production servers use Swift and the macOS frameworks already available on the machine.
- Keep a tool's MCP annotations accurate: read-only, destructive, and open-world behavior must be declared honestly.
- Deletions must remain explicit and ID-based. Sending email, invitations, or replies must remain an intentional operation.
- If a change touches a new service, app, protected folder, or framework permission, update both [docs/permissions.md](docs/permissions.md) and `Permissions.services` in `launcher/Sources/AppleMCP/Permissions.swift`. A permission prompt after installation is a bug.
- Preserve the stable `AppleMCP` signing and launcher model. Replacing the local identity or using an ad-hoc signature makes macOS ask for permissions again.

## Build and test

The supported target is macOS 14+ on Apple Silicon. The build expects the local signing identity created by `installer.command`:

```bash
./build.sh --all
```

Smoke tests interact with the real Apple apps and create then remove `MCP-TEST-<timestamp>` items. They never send email or invitations, but they still require care and Full Disk Access for the terminal:

```bash
scripts/smoke-all.sh
```

Run the narrowest relevant check. Do not run a smoke test against a personal account unless you understand the data it will touch. See the README for the full test and platform limitations.

## Pull requests

Keep each pull request focused. Explain the user-facing behavior, the permissions it needs, the checks you ran, and any macOS-version or language limitation. Update the README and permissions documentation whenever a user-visible capability changes.

For a vulnerability, follow the private reporting guidance in [SECURITY.md](SECURITY.md) instead of opening a public issue.
