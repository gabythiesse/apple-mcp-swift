// AppleMCP : lanceur unique des six serveurs MCP Apple. Usage : AppleMCP <reminders|calendar|mail|notes|contacts|safari>
// Pourquoi : macOS lie chaque autorisation au « processus responsable ». En se déclarant responsable de lui-même
// (responsibility_spawnattrs_setdisclaim) puis en lançant le serveur demandé comme enfant ordinaire, c'est LE LANCEUR
// que macOS voit pour tout : une seule ligne « AppleMCP » dans Accès complet au disque, Accessibilité, Rappels, Calendrier,
// Contacts, Automatisation — quel que soit le client (Claude, Codex, Terminal). Signé avec le certificat « Apple MCP »,
// l'autorisation est liée à « identifiant + certificat » et survit aux recompilations (du lanceur comme des serveurs).
import Foundation

let serveurs: [String: String] = [
    "reminders": "reminders-mcp/bin/RemindersMCP", "calendar": "calendar-mcp/bin/CalendarMCP",
    "mail": "mail-mcp/bin/MailMCP", "notes": "notes-mcp/bin/NotesMCP",
    "contacts": "contacts-mcp/bin/ContactsMCP", "safari": "safari-mcp/bin/SafariMCP",
]
guard CommandLine.arguments.count >= 2, let relatif = serveurs[CommandLine.arguments[1]] else {
    fputs("usage : AppleMCP <\(serveurs.keys.sorted().joined(separator: "|"))> [options du serveur]\n", stderr)
    exit(64)
}
let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
let racine = URL(fileURLWithPath: exe).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
let cible = racine.appendingPathComponent(relatif).path

// 1. Se relancer en responsable de soi-même (une fois ; le marqueur évite la boucle)
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
    // relance impossible : on continue dans ce processus (responsabilité héritée du client)
}

// 2. Lancer le serveur comme enfant ordinaire : il hérite de la responsabilité du lanceur et NE se relance PAS lui-même
for m in ["RAPPELS", "CALENDRIER", "MAIL", "NOTES", "CONTACTS", "SAFARI"] { setenv("\(m)_MCP_RESPONSABLE", "1", 1) }
guard FileManager.default.isExecutableFile(atPath: cible) else { fputs("[AppleMCP] serveur introuvable : \(cible)\n", stderr); exit(66) }
guard let pid = lancer(cible, Array(CommandLine.arguments.dropFirst(2)), disclaim: false) else { fputs("[AppleMCP] lancement impossible : \(cible)\n", stderr); exit(71) }
attendre(pid)
