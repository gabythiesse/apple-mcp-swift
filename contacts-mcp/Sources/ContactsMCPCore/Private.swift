// Voies non publiques. Peuvent casser à une mise à jour de macOS.
// 1. responsibility_spawnattrs_setdisclaim (libsystem) : le lanceur devient son propre responsable TCC,
//    pour que macOS lise SON Info.plist (NSContactsUsageDescription) au lieu de refuser sans invite (sondes 01-02).
// 2. Clé « modificationDate » du framework Contacts : date de modification d'une fiche (sonde 07).
import Foundation
import Contacts

enum Responsabilite {
    private typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    private static let marqueur = "CONTACTS_MCP_RESPONSABLE"

    static func relancerSiBesoin() {
        guard ProcessInfo.processInfo.environment[marqueur] == nil,
              let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "responsibility_spawnattrs_setdisclaim") else { return }
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        guard unsafeBitCast(sym, to: Disclaim.self)(&attr, 1) == 0 else { return }
        setenv(marqueur, "1", 1)
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        var argv: [UnsafeMutablePointer<CChar>?] = ([exe] + CommandLine.arguments.dropFirst()).map { strdup($0) } + [nil]
        var pid: pid_t = 0
        // stdin, stdout et stderr sont hérités : l'enfant parle directement au client MCP
        guard posix_spawn(&pid, exe, nil, &attr, &argv, environ) == 0 else {
            unsetenv(marqueur)
            log("relance impossible, poursuite dans ce processus")
            return
        }
        enfant = pid
        for s in [SIGTERM, SIGINT, SIGHUP] { signal(s) { sig in if Responsabilite.enfant > 0 { kill(Responsabilite.enfant, sig) } } }
        var st: Int32 = 0
        while waitpid(pid, &st, 0) == -1 && errno == EINTR {}
        exit((st & 0x7f) == 0 ? (st >> 8) & 0xff : 1)
    }
    nonisolated(unsafe) static var enfant: pid_t = 0
}

enum Prive {
    static let modificationKey = "modificationDate" as NSString

    static func modification(_ c: CNContact) -> Date? {
        guard c.isKeyAvailable("modificationDate") else { return nil }
        return (c as NSObject).value(forKey: "modificationDate") as? Date
    }
}
