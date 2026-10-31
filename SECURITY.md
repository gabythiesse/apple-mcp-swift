# Security policy

apple-mcp-swift can access personal data in Apple apps and can perform actions such as creating drafts, sending email, changing calendars, or deleting items. Please report suspected vulnerabilities responsibly.

## Reporting a vulnerability

Do **not** include exploit details, personal data, tokens, mail contents, contacts, calendar events, notes, Safari history, screenshots, or full logs in a public issue.

Use GitHub's **Report a vulnerability** workflow for this repository when it is available. If it is not available, open a public issue containing only a short request for a private reporting channel; do not disclose the vulnerability there.

Please include, privately:

- a clear description of the impact and affected server or tool;
- reproducible, minimal steps or a proof of concept;
- affected macOS and MCP-client versions; and
- any suggested mitigation, if you have one.

Please allow time for assessment and a fix before public disclosure.

## Scope

Reports are particularly helpful for unintended access to Apple-app data, permission or signing bypasses, accidental sending or deletion, command injection, unsafe handling of local databases, and disclosure of configuration or secrets.

The project uses some private macOS frameworks; compatibility failures alone are not necessarily security vulnerabilities, but reports showing a security impact are in scope.
