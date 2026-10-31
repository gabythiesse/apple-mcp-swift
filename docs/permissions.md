# macOS permissions

**Rule: every permission is given once, by `./installer.command`, while you are at the Mac. After that, no window, ever.**
The servers are often used remotely (from a phone): a macOS prompt on the Mac blocks the tool and nobody is there to click.
Any permission prompt after installation is a bug.

All six servers run behind the signed `bin/AppleMCP` launcher, which is the "responsible process" for macOS
(`launcher/Sources/AppleMCP/main.swift`). So every permission below is one `AppleMCP` line in System Settings,
tied to "identifier `dev.applemcp.launcher` + the local `Apple MCP` certificate": it survives rebuilds and restarts,
and is lost only if the certificate changes (the installer never replaces it without asking).

## Inventory

Found in the code, not the docs: `tell application`, `NSAppleScript`, `AXUIElement`, `EventKit`, `CNContactStore`,
SQLite and file access under `~/Library` or user-given paths.

| # | Service (TCC) | Needed by | Evidence in the code |
|---|---|---|---|
| 1 | Reminders (full access) | reminders: all 14 tools | `reminders-mcp/Sources/RemindersMCP/EventKit.swift:13-16` (`requestFullAccessToReminders`); ReminderKit (`Private.swift:100`) rides on the same grant |
| 2 | Calendars (full access) | calendar: all 11 tools | `calendar-mcp/Sources/CalendarMCP/EventKit.swift:13-16` (`requestFullAccessToEvents`) |
| 3 | Contacts | contacts: all 13 tools | `contacts-mcp/Sources/ContactsMCPCore/Contacts.swift:13-16` (`CNContactStore.requestAccess`) |
| 4 | Automation → Mail | mail: every tool that reads or changes messages and mailboxes through Mail | `mail-mcp/Sources/MailMCP/AppleScript.swift:14` (`tell application "Mail"`), `Handlers.swift:61,149,182` |
| 5 | Automation → Notes | notes: all 13 tools | `notes-mcp/Sources/NotesMCP/AppleScript.swift:90` (`tell application "Notes"`) |
| 6 | Automation → Safari | safari: tabs, pages, JavaScript, reading list, deletions | `safari-mcp/Sources/SafariMCP/Handlers.swift:34,78,92,158,225,275,409`, `AppleScript.swift:58,64,120`, `Suppressions.swift:70-89` |
| 7 | Automation → Contacts | contacts: notes, removal from a group, selection in the app, vCard with notes, search in notes | `contacts-mcp/Sources/ContactsMCPCore/AppleScript.swift:45` (`tell application id "com.apple.AddressBook"`) |
| 8 | Automation → System Events | mail: `delete_mailboxes` (clicks the Mailbox menu) | `mail-mcp/Sources/MailMCP/Handlers.swift:166` (`tell application "System Events" to tell process "Mail"`) |
| 9 | Accessibility | safari: `open` with a private window, `delete_history`, `delete_tab_groups`, `delete_from_reading_list`; mail: `delete_mailboxes` (UI scripting through System Events) | `safari-mcp/Sources/SafariMCP/AppleScript.swift:81-88` (`AXIsProcessTrusted`, `AXUIElementCreateApplication`), `Suppressions.swift:61-126`; `mail-mcp/Sources/MailMCP/Handlers.swift:166-180` |
| 10 | Full Disk Access | mail: `list_mailboxes`, `list_messages`, `move_messages` (Mail index `~/Library/Mail`), `create_drafts` with attachments (`~/Library/Containers/com.apple.mail`); notes: tags, pinned, folders, trash (`~/Library/Group Containers/group.com.apple.notes`); safari: `list_history`, `list_bookmarks`, `list_reading_list`, `list_tab_groups` (`~/Library/Safari`, Safari's container); every tool taking a file path (Downloads, Desktop, Documents…) | `mail-mcp/Sources/MailMCP/Index.swift:21-32`, `Handlers.swift:35`, `Compose.swift:105-109`; `notes-mcp/Sources/NotesMCP/SQLite.swift:8-19`; `safari-mcp/Sources/SafariMCP/Fichiers.swift:8-37`; paths: `reminders-mcp/.../Handlers.swift:384` (`add_image`), `calendar-mcp/.../Private.swift:55` (attachments), `contacts-mcp/.../Handlers.swift:640-649` (vCard), `notes-mcp/.../Handlers.swift:488,531`, `mail-mcp/.../Handlers.swift:362` (`save_attachments`, default `~/Downloads`) |

Why Full Disk Access covers so much: without it, `~/Library/Mail` and `~/Library/Safari` are simply refused, while
other apps' containers (Mail, Notes, Safari) and Downloads/Desktop/Documents open a *prompt* on first access,
which is exactly what must never happen remotely. Full Disk Access grants all of them silently, so it is one switch
instead of a series of prompts.

Not a macOS permission (no prompt, the tool just returns an error): Safari's *Develop > Allow JavaScript from Apple Events*,
needed by `read_page`, `run_js` and back/forward in `navigate`.

## Onboarding and check

```bash
./installer.command           # step 5 asks for everything above, then prints the ✓/✗ table; "Done" only when all is ✓
./installer.command --check   # same table plus the signature state, changes nothing, shows no window
```

Both run `bin/AppleMCP permissions [--request]` (`launcher/Sources/AppleMCP/Permissions.swift`), so every request
is attributed to `AppleMCP`, exactly like the servers. It never reads or changes any data:

| Service | Request (`--request`) | Check (no window possible) |
|---|---|---|
| Reminders, Calendars | `requestFullAccessToReminders` / `ToEvents` | `EKEventStore.authorizationStatus` |
| Contacts | `CNContactStore.requestAccess` | `CNContactStore.authorizationStatus` |
| Automation → app | `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: true)`: the consent prompt, no event sent | same call with `askUserIfNeeded: false`. The target app is launched hidden first (`open -g -j`), as the servers do |
| Accessibility | `AXIsProcessTrustedWithOptions(prompt)`, then waits for the switch | `AXIsProcessTrusted()` |
| Full Disk Access | opens the pane, shows `bin/AppleMCP` in Finder (drag it into the list if missing), waits for the switch | opens `TCC.db` read-only; once that works, lists the folders above (never touched before) |

A permission already granted is skipped, so running the installer again only redoes what is missing.
A permission that was denied cannot be asked again by macOS: the installer opens the right pane and says which switch to turn on.

## Rule for developers

A tool that reaches a new service (another app via Apple Events, a new protected folder, a new framework with its
own permission) **must** be added in the same change to:

1. the table above, with the file and line that need it;
2. `Permissions.services` in `launcher/Sources/AppleMCP/Permissions.swift` (request + check);
3. the usage strings in `launcher/Info.plist` if macOS needs one.

Then run `./installer.command --check`: a tool that would prompt after installation is a bug.
