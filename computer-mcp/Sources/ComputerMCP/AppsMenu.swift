// app : lancer, activer, masquer, quitter ; menu : lister ou cliquer un chemin de la barre des menus (« Fichier > Exporter… »).
import Foundation
import AppKit
import ApplicationServices
import MacUI

enum AppTool {
    static func run(_ a: JSON) throws -> Any {
        let action = a.nonEmpty("action") ?? "launch"
        let q = try a.req("app")
        switch action {
        case "launch": return try lancer(q, a)
        case "activate":
            let app = try Apps.require(q)
            try Session.check()
            guard Front.activate(app.processIdentifier) else { throw MCPError("\(app.localizedName ?? q) could not be brought to the front") }
            return "\(app.localizedName ?? q) is in front"
        case "hide":
            let app = try Apps.require(q)
            app.hide()
            return "\(app.localizedName ?? q) hidden"
        case "quit": return try quitter(try Apps.require(q), force: a.bool("force") == true)
        default: throw MCPError("action: launch, activate, hide or quit")
        }
    }

    static func lancer(_ q: String, _ a: JSON) throws -> Any {
        let devant = a.bool("activate") ?? false
        let deja = Apps.find(q)
        let docs = (a.strings("open") ?? []).map { s -> URL in
            s.contains("://") ? URL(string: s)! : URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
        }
        if let deja, docs.isEmpty {
            if devant { Front.activate(deja.processIdentifier) }
            return "\(deja.localizedName ?? q) already running, pid=\(deja.processIdentifier)" + etat(deja.processIdentifier)
        }
        guard let url = deja?.bundleURL ?? Apps.installed(q) else { throw MCPError("no app named \"\(q)\" in Applications (give its name, bundle id or path)") }
        let conf = NSWorkspace.OpenConfiguration()
        conf.activates = devant
        conf.addsToRecentItems = false
        let sem = DispatchSemaphore(value: 0)
        var lancee: NSRunningApplication?, err: Error?
        if docs.isEmpty {
            NSWorkspace.shared.openApplication(at: url, configuration: conf) { app, e in lancee = app; err = e; sem.signal() }
        } else {
            NSWorkspace.shared.open(docs, withApplicationAt: url, configuration: conf) { app, e in lancee = app; err = e; sem.signal() }
        }
        guard sem.wait(timeout: .now() + 15) == .success else { throw MCPError("\(url.lastPathComponent) did not start within 15 s") }
        if let err { throw MCPError("could not launch \(url.lastPathComponent): \(err.localizedDescription)") }
        guard let app = lancee else { throw MCPError("could not launch \(url.lastPathComponent)") }
        let pid = app.processIdentifier
        // Prête quand son arbre AX répond et qu'une fenêtre (ou une feuille) est là, 5 s au plus
        _ = AX.attendre(5, every: 0.1) { !AX.windows(pid).isEmpty }
        return "\(app.localizedName ?? q) \(deja == nil ? "launched" : "opened \(docs.count) item\(docs.count > 1 ? "s" : "")"), pid=\(pid)" + etat(pid)
    }

    /// Fenêtres et dialogues de l'app, en bref
    static func etat(_ pid: pid_t) -> String {
        let ws = AX.windows(pid).prefix(6).map { "\(Refs.ref($0)) \"\(Tree.court(AX.str($0, kAXTitleAttribute), 60))\"" }
        var s = ws.isEmpty ? "; no window" : "; windows: " + ws.joined(separator: ", ")
        let ds = Dialogs.scan(pids: [pid])
        if !ds.isEmpty { s += "\ndialog:\n" + ds.map(Tree.ligne).joined(separator: "\n") }
        return s
    }

    static func quitter(_ app: NSRunningApplication, force: Bool) throws -> Any {
        let nom = app.localizedName ?? "the app", pid = app.processIdentifier
        if force { app.forceTerminate() } else { app.terminate() }
        // Elle demande quelque chose (enregistrer les modifications…) : la question est rendue dès qu'elle apparaît
        var ds: [Dialog] = [], n = 0
        let fini = AX.attendre(force ? 3 : 4, every: 0.1) {
            n += 1
            if !Running.alive(pid) { return true }
            if n % 3 == 0 { ds = Dialogs.scan(pids: [pid]) }
            return !ds.isEmpty
        }
        if fini && !Running.alive(pid) { return "\(nom) quit" }
        if !ds.isEmpty { return "\(nom) is still open and asks (answer with answer_dialog):\n" + ds.map(Tree.ligne).joined(separator: "\n") }
        throw MCPError("\(nom) did not quit within 4 s and shows no dialog (force: true quits it without saving)")
    }
}

enum Menu {
    struct Article { let el: AXUIElement; let titre: String }

    static func articles(_ menu: AXUIElement) -> [Article] {
        AX.children(menu).compactMap { e in
            let t = AX.str(e, kAXTitleAttribute)
            return t.isEmpty ? nil : Article(el: e, titre: t)
        }
    }

    /// Sous-menu d'un article (AXMenu enfant) ; un menu dynamique vide est ouvert un instant pour se remplir
    static func sousMenu(_ el: AXUIElement) -> AXUIElement? { AX.children(el).first { AX.role($0) == "AXMenu" } }

    static func trouver(_ items: [Article], _ nom: String) -> Article? {
        let n = normalise(nom)
        return items.first { normalise($0.titre) == n } ?? items.first { normalise($0.titre).hasPrefix(n) }
    }

    static func raccourci(_ el: AXUIElement) -> String {
        guard let c = AX.attr(el, kAXMenuItemCmdCharAttribute) as? String, !c.isEmpty else { return "" }
        let m = (AX.attr(el, kAXMenuItemCmdModifiersAttribute) as? Int) ?? 0
        var s = ""
        if m & 4 != 0 { s += "⌃" }; if m & 2 != 0 { s += "⌥" }; if m & 1 != 0 { s += "⇧" }; if m & 8 == 0 { s += "⌘" }
        return s + c
    }

    static func liste(_ menu: AXUIElement, _ chemin: [String]) -> String {
        let items = AX.children(menu).compactMap { e -> String? in
            let t = AX.str(e, kAXTitleAttribute)
            if t.isEmpty { return nil }
            var l = "  \(t)"
            if sousMenu(e) != nil { l += " >" }
            let k = raccourci(e); if !k.isEmpty { l += "  \(k)" }
            if let m = AX.attr(e, kAXMenuItemMarkCharAttribute) as? String, !m.isEmpty { l += "  ✓" }
            if !AX.enabled(e) { l += "  (disabled)" }
            return l
        }
        return (chemin.isEmpty ? "menus" : chemin.joined(separator: " > ")) + ":\n" + items.joined(separator: "\n")
    }

    static func run(_ a: JSON) throws -> Any {
        try AX.trusted()
        let app = try Apps.target(a)
        let pid = app.processIdentifier
        guard let barre = AX.element(AX.app(pid), kAXMenuBarAttribute) else { throw MCPError("\(app.localizedName ?? "the app") has no menu bar (it is not a regular app)") }
        let chemin: [String] = (a.strings("path") ?? []).count > 1 ? a.strings("path")! :
            (a.string("path") ?? "").split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if chemin.isEmpty { return "\(app.localizedName ?? "?") " + liste(barre, []) }
        var courant = barre
        var parcouru: [String] = []
        var ouvert: AXUIElement?   // menu de la barre ouvert pour se remplir, à refermer
        defer { if let ouvert { AXUIElementPerformAction(ouvert, kAXCancelAction as CFString) } }
        for (i, nom) in chemin.enumerated() {
            var items = articles(courant)
            if items.isEmpty, i > 0, let parent = AX.parent(courant) {
                AX.press(parent); ouvert = parent; Thread.sleep(forTimeInterval: 0.2); items = articles(courant)
            }
            guard let it = trouver(items, nom) else {
                throw MCPError("no \"\(nom)\" in \(parcouru.isEmpty ? "the menu bar" : parcouru.joined(separator: " > ")); items: \(items.map(\.titre).joined(separator: ", "))")
            }
            parcouru.append(it.titre)
            if let sous = sousMenu(it.el) {
                if i == chemin.count - 1 {
                    var r = articles(sous)
                    if r.isEmpty { AX.press(it.el); ouvert = it.el; Thread.sleep(forTimeInterval: 0.2); r = articles(sous) }
                    return "\(app.localizedName ?? "?") " + liste(sous, parcouru)
                }
                courant = sous
                continue
            }
            guard i == chemin.count - 1 else { throw MCPError("\"\(it.titre)\" is not a submenu") }
            if let o = ouvert { AXUIElementPerformAction(o, kAXCancelAction as CFString); ouvert = nil }
            // L'app passe devant (le menu agit sur sa fenêtre clé), l'article est pressé par l'Accessibilité, le premier plan est rendu.
            // Un article grisé tant que l'app était derrière se revalide quand son menu s'ouvre : on l'ouvre avant de conclure.
            let haut = AX.children(barre).first { CFEqual($0, AX.parent(AX.parent(it.el) ?? it.el) ?? it.el) }
            return try enAction {
                try Act.avecDialogues(pid) {
                    let avant = Front.frontmost
                    let devant = Session.locked ? false : Front.activate(pid)
                    var menuOuvert = false
                    if !AX.enabled(it.el), let haut {
                        AX.press(haut); menuOuvert = true
                        _ = AX.attendre(0.5, every: 0.05) { AX.enabled(it.el) }
                    }
                    guard AX.enabled(it.el) else {
                        if menuOuvert, let haut { AXUIElementPerformAction(haut, kAXCancelAction as CFString) }
                        throw MCPError("\(parcouru.joined(separator: " > ")) is disabled right now")
                    }
                    guard AX.press(it.el) else { throw MCPError("\(parcouru.joined(separator: " > ")) refused the press") }
                    var rendu = ""
                    if devant, a.bool("keep_front") != true, let avant, avant.processIdentifier != pid {
                        Thread.sleep(forTimeInterval: 0.2)
                        if Front.menuOpen(pid, settle: 0.4) { rendu = " (\(app.localizedName ?? "app") left in front: a menu is open)" }
                        else if !Front.activate(avant.processIdentifier, timeout: 0.6) { rendu = " (\(avant.localizedName ?? "previous app") did not take the front back)" }
                    } else if !devant { rendu = " (app not brought to the front)" }
                    return "\(app.localizedName ?? "?"): \(parcouru.joined(separator: " > "))" + rendu
                }
            }
        }
        return ""
    }
}
