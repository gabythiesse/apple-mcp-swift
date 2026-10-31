// Voie AppleScript : ce que le framework Contacts ne fait pas ici (sondes 04-07) :
// note (entitlement Apple requis côté framework), retrait d'un groupe (sans effet sur iCloud via le framework),
// sélection de l'app, vCard avec la note, recherche dans les notes. Un seul script par appel d'outil, pour tout le lot.
import Foundation
import Darwin

enum AS {
    private static let bundle = "com.apple.AddressBook"

    /// Contacts doit tourner pour répondre : on le lance caché, en arrière-plan, puis on attend qu'il réponde.
    /// (NSRunningApplication n'est pas fiable ici : sans boucle d'événements, sa liste n'est pas rafraîchie.)
    private static func lancer() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-g", "-j", "-b", bundle]
        try? p.run()
        p.waitUntilExit()
        log("Contacts launched (open \(p.terminationStatus))")
    }

    private static func execute(_ src: String) -> (NSAppleEventDescriptor?, Int, String) {
        var res: NSAppleEventDescriptor?
        var err: NSDictionary?
        let t0 = Date()
        DispatchQueue.main.sync { res = NSAppleScript(source: src)?.executeAndReturnError(&err) }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if ms > 300 { log("AppleScript \(ms) ms : \(src.split(separator: "\n").dropFirst(2).prefix(2).joined(separator: " ⏎ ").prefix(80))") }
        let num = (err?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        return (res, num, "\(err?[NSAppleScript.errorMessage] ?? "unknown error") (\(num))")
    }

    /// Contacts tourne-t-il ? (libproc, sans lancer de processus : un Apple Event vers une app fermée attend ~5 s avant -600)
    private static func enCours() -> Bool {
        var pids = [pid_t](repeating: 0, count: 4096)
        let n = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var buf = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(max(0, n)) where pid > 0 {
            if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0, String(cString: buf).hasSuffix("/Contacts.app/Contents/MacOS/Contacts") { return true }
        }
        return false
    }

    @discardableResult
    static func run(_ body: String) throws -> NSAppleEventDescriptor {
        let src = "with timeout of 30 seconds\ntell application id \"\(bundle)\"\n\(body)\nend tell\nend timeout"
        if !enCours() { lancer() }
        var (res, num, msg) = execute(src)
        if res == nil && (num == -600 || num == -609) {
            // App fermée : on la lance, puis on réessaie le temps qu'elle accepte les Apple Events
            lancer()
            for _ in 0..<40 {
                (res, num, msg) = execute(src)
                if res != nil || !(num == -600 || num == -609) { break }
                usleep(250_000)
            }
        }
        if let res { return res }
        if num == -1743 {
            throw MCPError("Automation denied: System Settings > Privacy & Security > Automation, allow ContactsMCP to control Contacts.")
        }
        throw MCPError("AppleScript: \(msg)")
    }

    static func q(_ s: String) -> String {
        let e = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(e)\""
    }
    static func liste(_ items: [String]) -> String { "{" + items.map(q).joined(separator: ", ") + "}" }

    static func strings(_ d: NSAppleEventDescriptor) -> [String] {
        guard d.descriptorType == DescType(typeAEList) else { return d.stringValue.map { [$0] } ?? [] }
        guard d.numberOfItems > 0 else { return [] }
        return (1...d.numberOfItems).map { d.atIndex($0)?.stringValue ?? "" }
    }

    // MARK: - Notes

    static func notes(_ ids: [String]) throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        let d = try run("""
        set out to {}
        repeat with i in \(liste(ids))
        set n to ""
        try
        set n to note of person id (contents of i)
        if n is missing value then set n to ""
        end try
        set end of out to n
        end repeat
        return out
        """)
        let vals = strings(d)
        var res: [String: String] = [:]
        for (i, id) in ids.enumerated() where i < vals.count && !vals[i].isEmpty { res[id] = vals[i] }
        return res
    }

    /// Écrit les notes ("" efface) ; renvoie les identifiants en échec
    static func setNotes(_ notes: [(id: String, note: String)], attendre: Bool = false) throws -> Set<String> {
        guard !notes.isEmpty else { return [] }
        // Un contact tout juste créé par le framework apparaît dans l'app au bout de 0,3 à 1 s (sonde 08) : on l'attend (3 s au plus)
        let att = attendre ? "repeat 30 times\nif exists person id \(q(notes.last!.id)) then exit repeat\ndelay 0.1\nend repeat\n" : ""
        let lignes = notes.map { n -> String in
            let v = n.note.isEmpty ? "missing value" : q(n.note)  // "" bloquerait ensuite les écritures du framework (sonde 09)
            return "try\nset note of person id \(q(n.id)) to \(v)\non error\nset end of ko to \(q(n.id))\nend try"
        }
        let d = try run(att + "set ko to {}\n" + lignes.joined(separator: "\n") + "\nsave\nreturn ko")
        return Set(strings(d))
    }

    /// Lit puis retire les notes (missing value) de ces contacts, en un script ; renvoie les notes retirées
    static func mettreNotesDeCote(_ ids: [String]) throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        let d = try run("""
        set out to {}
        repeat with i in \(liste(ids))
        set n to ""
        try
        set p to person id (contents of i)
        set n to note of p
        if n is missing value then set n to ""
        set note of p to missing value
        end try
        set end of out to n
        end repeat
        save
        return out
        """)
        let vals = strings(d)
        var res: [String: String] = [:]
        for (i, id) in ids.enumerated() where i < vals.count && !vals[i].isEmpty { res[id] = vals[i] }
        return res
    }

    // MARK: - Groupes

    /// Retire des contacts de groupes ; renvoie les couples « id|groupe » en échec
    static func retirer(_ items: [(id: String, groupe: String)]) throws -> Set<String> {
        guard !items.isEmpty else { return [] }
        let lignes = items.map { "try\nremove person id \(q($0.id)) from group id \(q($0.groupe))\non error\nset end of ko to \(q($0.id + "|" + $0.groupe))\nend try" }
        let d = try run("set ko to {}\n" + lignes.joined(separator: "\n") + "\nsave\nreturn ko")
        return Set(strings(d))
    }

    // MARK: - Sélection, recherche dans les notes, vCard

    static func selection() throws -> [String] {
        strings(try run("""
        set out to {}
        repeat with p in (selection as list)
        try
        if class of p is person then set end of out to id of p
        end try
        end repeat
        return out
        """))
    }

    static func rechercheNotes(_ texte: String, groupe: String?) throws -> [String] {
        let portee = groupe.map { "every person of group id \(q($0))" } ?? "every person"
        return strings(try run("return id of (\(portee) whose note contains \(q(texte)))"))
    }

    static func vcards(_ ids: [String]) throws -> [String] {
        guard !ids.isEmpty else { return [] }
        return strings(try run("""
        set out to {}
        repeat with i in \(liste(ids))
        set end of out to vcard of person id (contents of i)
        end repeat
        return out
        """))
    }
}
