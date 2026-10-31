// AppleMCP: single launcher for the six Apple MCP servers. Usage: AppleMCP <reminders|calendar|mail|notes|contacts|safari>
// Why: macOS ties every permission to the "responsible process". By disclaiming responsibility for itself
// (responsibility_spawnattrs_setdisclaim) and then spawning the requested server as an ordinary child, THE LAUNCHER is
// what macOS sees for everything: a single "AppleMCP" row in Full Disk Access, Accessibility, Reminders, Calendar,
// Contacts, Automation, whatever the client (Claude, Codex, Terminal). Signed with the "Apple MCP" certificate,
// the permission is tied to "identifier + certificate" and survives rebuilds (of the launcher and of the servers).
import Foundation

let serveurs: [String: String] = [
    "reminders": "reminders-mcp/bin/RemindersMCP", "calendar": "calendar-mcp/bin/CalendarMCP",
    "mail": "mail-mcp/bin/MailMCP", "notes": "notes-mcp/bin/NotesMCP",
    "contacts": "contacts-mcp/bin/ContactsMCP", "safari": "safari-mcp/bin/SafariMCP",
]
let commande = CommandLine.arguments.count >= 2 ? CommandLine.arguments[1] : ""
guard commande == "permissions" || serveurs[commande] != nil else {
    fputs("usage: AppleMCP <\(serveurs.keys.sorted().joined(separator: "|"))> [server options]\n", stderr)
    fputs("       AppleMCP permissions [--request]   (check, or request, every macOS permission: docs/permissions.md)\n", stderr)
    exit(64)
}
let relatif = serveurs[commande] ?? ""
let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
let racine = URL(fileURLWithPath: exe).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
let cible = racine.appendingPathComponent(relatif).path

// 1. Relaunch as our own responsible process (once; the marker prevents a loop)
typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
nonisolated(unsafe) var enfant: pid_t = 0
func transmettre(_ sig: Int32) { if enfant > 0 { kill(enfant, sig) } }
func lancer(_ chemin: String, _ args: [String], disclaim: Bool) -> pid_t? {
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    if disclaim, let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "responsibility_spawnattrs_setdisclaim") {
        guard unsafeBitCast(sym, to: Disclaim.self)(&attr, 1) == 0 else { return nil }
    }
    var argv: [UnsafeMutablePointer<CChar>?] = ([chemin] + args).map { strdup($0) } + [nil]
    var pid: pid_t = 0
    return posix_spawn(&pid, chemin, nil, &attr, &argv, environ) == 0 ? pid : nil
}
func attendre(_ pid: pid_t) -> Never {
    enfant = pid
    for s in [SIGTERM, SIGINT, SIGHUP] { signal(s) { transmettre($0) } }
    var st: Int32 = 0
    while waitpid(pid, &st, 0) == -1 && errno == EINTR {}
    exit((st & 0x7f) == 0 ? (st >> 8) & 0xff : 1)
}
if ProcessInfo.processInfo.environment["APPLE_MCP_RESPONSABLE"] == nil {
    setenv("APPLE_MCP_RESPONSABLE", "1", 1)
    if let pid = lancer(exe, Array(CommandLine.arguments.dropFirst()), disclaim: true) { attendre(pid) }
    // relaunch failed: keep going in this process (responsibility inherited from the client)
}

if commande == "permissions" { exit(Permissions.run(request: CommandLine.arguments.contains("--request"))) }

// 2. Launch the server as an ordinary child: it inherits the launcher's responsibility and does NOT relaunch itself
for m in ["RAPPELS", "CALENDRIER", "MAIL", "NOTES", "CONTACTS", "SAFARI"] { setenv("\(m)_MCP_RESPONSABLE", "1", 1) }
guard FileManager.default.isExecutableFile(atPath: cible) else { fputs("[AppleMCP] server not found: \(cible)\n", stderr); exit(66) }
guard let pid = lancer(cible, Array(CommandLine.arguments.dropFirst(2)), disclaim: false) else { fputs("[AppleMCP] could not launch: \(cible)\n", stderr); exit(71) }
attendre(pid)
