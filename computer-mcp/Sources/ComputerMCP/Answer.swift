// answer_dialog : répond à une fenêtre par le nom d'un bouton, dans n'importe quelle app ;
// watch_dialogs : politique persistante (app, texte, boutons) appliquée seule à toute nouvelle fenêtre tant que le serveur tourne.
import Foundation
import AppKit
import ApplicationServices
import MacUI

enum Answer {
    /// Fenêtres candidates : filtre app, texte, ref (fenêtre ou un de ses boutons), et qui ont le bouton demandé
    static func candidats(_ a: JSON, bouton: String) throws -> (avec: [Dialog], tous: [Dialog]) {
        let pids = try a.nonEmpty("app").map { [try Apps.require($0).processIdentifier] }
        var ds = Dialogs.scan(pids: pids)
        if let t = a.nonEmpty("contains").map(normalise) { ds = ds.filter { normalise($0.title + " " + $0.text).contains(t) } }
        if let r = a.nonEmpty("ref") {
            let el = try Refs.get(r)
            ds = ds.filter { d in CFEqual(d.element, el) || d.buttons.contains { CFEqual($0.el, el) } }
        }
        return (ds.filter { Dialogs.bouton($0, bouton) != nil }, ds)
    }

    static func answer(_ a: JSON) throws -> Any {
        try AX.trusted()
        let bouton = try a.req("button")
        let attente = min(max(a.double("wait") ?? 0, 0), 30)
        let fin = Date().addingTimeInterval(attente)
        var (avec, tous) = try candidats(a, bouton: bouton)
        while avec.isEmpty && Date() < fin {
            Thread.sleep(forTimeInterval: 0.2)
            (avec, tous) = try candidats(a, bouton: bouton)
        }
        guard !avec.isEmpty else {
            if tous.isEmpty { throw MCPError("no dialog open\(a.nonEmpty("app").map { " in \($0)" } ?? "")\(attente > 0 ? " after \(Int(attente)) s" : "")") }
            throw MCPError("no open dialog has a button \"\(bouton)\":\n" + tous.map(Tree.ligne).joined(separator: "\n"))
        }
        var d = avec[0]
        if avec.count > 1 {
            // Plusieurs : celle de l'app au premier plan, sinon on demande de préciser
            let devant = avec.filter { $0.pid == Front.frontPid }
            guard devant.count == 1 else {
                throw MCPError("\(avec.count) dialogs have \"\(bouton)\": give app, contains or ref\n" + avec.map(Tree.ligne).joined(separator: "\n"))
            }
            d = devant[0]
        }
        return try enAction {
            try Act.avecDialogues(d.pid) {
                let r = try Dialogs.answer(d, button: bouton, fill: a.string("fill"))
                return "\(d.app): pressed [\(r.button)] in \(d.kind) \"\(Tree.court(d.title, 80))\" (\(r.method))" + (r.closed ? ", closed" : ", still open")
            }
        }
    }

    // MARK: - surveillance

    struct Regle {
        let app: String?
        let contains: String?
        let boutons: [String]
        var json: JSON { ["app": app ?? "any", "contains": contains ?? "", "buttons": boutons] }
        func app(_ d: Dialog) -> Bool {
            guard let app else { return true }
            let n = normalise(app)
            return normalise(d.app) == n || normalise(d.bundle) == n
        }
        func texte(_ d: Dialog) -> Bool { contains.map { normalise(d.title + " " + d.text).contains(normalise($0)) } ?? true }
    }

    static let verrou = NSLock()
    nonisolated(unsafe) static var regles: [Regle] = []
    nonisolated(unsafe) static var journal: [(n: Int, ligne: String)] = []
    nonisolated(unsafe) static var lu = 0, compteur = 0
    nonisolated(unsafe) static var essais: [AXKey: Int] = [:]
    nonisolated(unsafe) static var demarre = false

    static func noter(_ s: String) {
        verrou.lock(); defer { verrou.unlock() }
        compteur += 1
        let h = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        journal.append((compteur, "\(h) \(s)"))
        if journal.count > 200 { journal.removeFirst(journal.count - 200) }
    }

    static func demarrer() {
        guard !demarre else { return }
        demarre = true
        let t = Thread {
            var sig = Set<Int>(), dernier = Date.distantPast
            while true {
                verrou.lock(); let rs = regles; verrou.unlock()
                if rs.isEmpty { Thread.sleep(forTimeInterval: 0.5); sig = []; continue }
                // Balayage complet seulement quand une fenêtre apparaît ou disparaît (ou toutes les 2 s) : quasi gratuit au repos
                let s = Dialogs.windowSignature()
                if s != sig || Date().timeIntervalSince(dernier) > 2 {
                    sig = s; dernier = Date()
                    if appliquer(rs) { sig = [] }   // une réponse peut en faire apparaître une autre (« Remplacer ? »)
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        t.qualityOfService = .utility
        t.start()
    }

    /// Applique les règles aux fenêtres ouvertes ; true si au moins une a été répondue
    static func appliquer(_ rs: [Regle]) -> Bool {
        var agi = false
        for d in Dialogs.scan() {
            verrou.lock(); let n = essais[d.key] ?? 0; verrou.unlock()
            guard n < 2 else { continue }
            guard let regle = rs.first(where: { $0.app(d) && $0.texte(d) && $0.boutons.contains { Dialogs.bouton(d, $0) != nil } }),
                  let nom = regle.boutons.first(where: { Dialogs.bouton(d, $0) != nil }) else { continue }
            verrou.lock(); essais[d.key] = n + 1; if essais.count > 500 { essais.removeAll() }; verrou.unlock()
            do {
                let r = try enAction { try Dialogs.answer(d, button: nom) }
                noter("✓ \(d.app) \(d.kind) \"\(Tree.court(d.title, 80))\" → [\(r.button)] (\(r.method)\(r.closed ? "" : ", still open"))")
                agi = true
            } catch {
                noter("✗ \(d.app) \(d.kind) \"\(Tree.court(d.title, 80))\" → [\(nom)]: \(error)")
            }
        }
        return agi
    }

    static func watch(_ a: JSON) throws -> Any {
        try AX.trusted()
        let nouvelles = try (a.objects("rules") ?? []).map { r -> Regle in
            var bs = (r["buttons"] as? [Any])?.compactMap { $0 as? String } ?? []
            if let b = r["button"] as? String { bs.insert(b, at: 0) }
            guard !bs.isEmpty else { throw MCPError("each rule needs button or buttons") }
            let app = (r["app"] as? String).flatMap { $0.isEmpty || $0 == "any" ? nil : $0 }
            return Regle(app: app, contains: (r["contains"] as? String).flatMap { $0.isEmpty ? nil : $0 }, boutons: bs)
        }
        let mode = a.nonEmpty("mode") ?? (nouvelles.isEmpty ? "status" : "add")
        verrou.lock()
        switch mode {
        case "add": regles += nouvelles
        case "replace": regles = nouvelles
        case "clear": regles = []
        case "status": break
        default: verrou.unlock(); throw MCPError("mode: add, replace, clear or status")
        }
        if mode != "status" { essais = [:] }
        let actives = regles
        verrou.unlock()
        if !actives.isEmpty {
            demarrer()
            if mode != "status" { _ = appliquer(actives) }   // les fenêtres déjà ouvertes sont traitées tout de suite
        }
        // Attente optionnelle : jusqu'à `count` nouvelles entrées du journal
        let attente = min(max(a.double("wait") ?? 0, 0), 120)
        if attente > 0 {
            verrou.lock(); let depart = lu; verrou.unlock()
            let voulu = max(1, a.int("count") ?? 1)
            _ = AX.attendre(attente, every: 0.2) { verrou.lock(); defer { verrou.unlock() }; return journal.filter { $0.n > depart }.count >= voulu }
        }
        verrou.lock(); defer { verrou.unlock() }
        let neuves = journal.filter { $0.n > lu }.map(\.ligne)
        lu = compteur
        var out = actives.isEmpty ? "not watching (no rule)" : "watching \(actives.count) rule\(actives.count > 1 ? "s" : ""):\n" + actives.map { r in
            "  \(r.app ?? "any app")\(r.contains.map { " containing \"\($0)\"" } ?? "") → \(r.boutons.map { "[\($0)]" }.joined(separator: " or "))"
        }.joined(separator: "\n")
        out += neuves.isEmpty ? "\nlog: nothing new" : "\nlog (new):\n" + neuves.map { "  " + $0 }.joined(separator: "\n")
        return out
    }
}
