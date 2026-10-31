// Suppressions (liste de lecture, historique, groupes d'onglets) par l'interface de Safari (Accessibilité).
// Safari n'a pas d'API pour ça, et ses fichiers ne s'écrivent pas sans risque : History.db est tenu ouvert par
// le service com.apple.Safari.History même Safari fermé, et SafariTabs.db / Bookmarks.plist sont synchronisés par
// iCloud (une ligne retirée à la main revient). Safari fait donc lui-même la suppression (et sa synchro) ;
// le serveur ne fait que désigner l'élément, vérifié avant d'agir, dans une fenêtre dédiée ouverte sans URL
// (aucune visite ajoutée), refermée à la fin. Les fichiers ne servent qu'à vérifier (lecture seule).
import Foundation
import AppKit
import ApplicationServices

enum AX {
    static func attr(_ el: AXUIElement, _ a: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success ? v : nil
    }
    static func str(_ el: AXUIElement, _ a: String) -> String { attr(el, a) as? String ?? "" }
    static func children(_ el: AXUIElement) -> [AXUIElement] { attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    static func role(_ el: AXUIElement) -> String { str(el, kAXRoleAttribute) }
    static func ident(_ el: AXUIElement) -> String { str(el, kAXIdentifierAttribute) }
    static func set(_ el: AXUIElement, _ a: String, _ v: CFTypeRef) { AXUIElementSetAttributeValue(el, a as CFString, v) }
    static func press(_ el: AXUIElement) { AXUIElementPerformAction(el, kAXPressAction as CFString) }

    /// Action nommée exposée par l'élément (« Name:Supprimer\nTarget:… ») ; false si absente ou refusée
    static func action(_ el: AXUIElement, _ nom: String) -> Bool {
        var n: CFArray?
        AXUIElementCopyActionNames(el, &n)
        guard let a = (n as? [String] ?? []).first(where: { $0 == nom || $0.hasPrefix("Name:\(nom)\n") }) else { return false }
        return AXUIElementPerformAction(el, a as CFString) == .success
    }

    /// Recherche en profondeur, jamais dans le contenu web
    static func find(_ el: AXUIElement, depth: Int = 0, _ pred: (AXUIElement) -> Bool) -> [AXUIElement] {
        if depth > 18 { return [] }
        var out: [AXUIElement] = []
        for c in children(el) {
            if pred(c) { out.append(c) }
            if role(c) != "AXWebArea" { out += find(c, depth: depth + 1, pred) }
        }
        return out
    }
    static func first(_ el: AXUIElement, ident i: String) -> AXUIElement? { find(el) { ident($0) == i }.first }

    /// Valeur du premier texte d'identifiant donné sous l'élément
    static func valeur(_ el: AXUIElement, ident i: String) -> String {
        find(el) { ident($0) == i }.first.map { str($0, kAXValueAttribute) } ?? ""
    }

    static func attendre(_ timeout: TimeInterval = 3, _ cond: () -> Bool) -> Bool {
        let fin = Date().addingTimeInterval(timeout)
        while Date() < fin {
            if cond() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return cond()
    }
}

/// Fenêtre Safari dédiée aux suppressions : ouverte sans URL (page de démarrage, pas d'historique), au premier plan
final class FenetreTravail {
    let id: Int
    let app: AXUIElement
    private(set) var ax: AXUIElement
    var uuid: String { AX.ident(ax).components(separatedBy: "UUID=").last.map { String($0.prefix(36)) } ?? "" }

    static let accessibilite = "macOS refuse le pilotage de l'interface : autoriser SafariMCP dans Réglages Système > Confidentialité et sécurité > Accessibilité, puis réessayer"

    init() throws {
        guard AXIsProcessTrusted() else { throw MCPError(FenetreTravail.accessibilite) }
        let avant = Set(try AS.visibleWindowIDs())
        _ = try AS.run(#"tell application "Safari" to make new document"#)
        var nouv: Int?
        _ = AX.attendre(3) { nouv = (try? Set(AS.visibleWindowIDs()).subtracting(avant)).flatMap { $0.count == 1 ? $0.first : nil }; return nouv != nil }
        guard let w = nouv else { throw MCPError("fenêtre de travail non repérée : rien supprimé") }
        id = w
        _ = try? AS.run("tell application \"Safari\" to set index of window id \(w) to 1")
        AS.activerSafari()
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first?.processIdentifier else {
            throw MCPError("Safari n'est pas lancé")
        }
        let appAX = AXUIElementCreateApplication(pid)
        app = appAX
        let nom = (try? AS.run("tell application \"Safari\" to return name of window id \(w)").string) ?? ""
        var f: AXUIElement?
        let ok = AX.attendre(3) {
            f = AX.attr(appAX, kAXFocusedWindowAttribute) as! AXUIElement?
            return f.map { AX.str($0, kAXTitleAttribute) == nom && AX.ident($0).hasPrefix("SafariWindow") } ?? false
        }
        guard ok, let f else {
            _ = try? AS.run("tell application \"Safari\" to close window id \(w)")
            throw MCPError(AXIsProcessTrusted() ? "la fenêtre de travail n'est pas passée au premier plan : rien supprimé" : FenetreTravail.accessibilite)
        }
        ax = f
    }

    /// Fenêtre de premier plan encore la nôtre ?
    func devant() -> Bool {
        guard let f = AX.attr(app, kAXFocusedWindowAttribute) as! AXUIElement? else { return false }
        return AX.ident(f) == AX.ident(ax)
    }

    /// Clique un article de la barre des menus (titre exact, ou préfixe si prefixe: true)
    func menu(_ barre: String, _ article: String, prefixe: Bool = false) throws {
        guard devant() else { throw MCPError("la fenêtre de travail n'est plus au premier plan : arrêt") }
        guard let mb = AX.attr(app, kAXMenuBarAttribute) as! AXUIElement?,
              let m = AX.children(mb).first(where: { AX.str($0, kAXTitleAttribute) == barre }),
              let menu = AX.children(m).first,
              let it = AX.children(menu).first(where: { let t = AX.str($0, kAXTitleAttribute); return prefixe ? t.hasPrefix(article) : t == article })
        else { throw MCPError("menu « \(barre) > \(article) » introuvable") }
        guard AX.attr(it, kAXEnabledAttribute) as? Bool != false else { throw MCPError("menu « \(barre) > \(article) » indisponible") }
        AX.press(it)
    }

    /// Affiche une barre latérale si elle est masquée ; renvoie true si on l'a affichée (pour la remasquer ensuite)
    func afficher(_ barre: String, _ afficher: String, _ masquer: String) throws -> Bool {
        do { try menu(barre, afficher); return true } catch {
            if (try? existe(barre, masquer)) == true { return false }
            throw error
        }
    }
    private func existe(_ barre: String, _ article: String) throws -> Bool {
        guard let mb = AX.attr(app, kAXMenuBarAttribute) as! AXUIElement?,
              let m = AX.children(mb).first(where: { AX.str($0, kAXTitleAttribute) == barre }), let menu = AX.children(m).first else { return false }
        return AX.children(menu).contains { AX.str($0, kAXTitleAttribute) == article }
    }

    func fermer() { _ = try? AS.run("tell application \"Safari\" to close window id \(id)") }
}

enum Suppressions {
    // MARK: - Liste de lecture

    static func listeDeLecture(_ a: JSON) throws -> Any {
        guard let urls = a.strings("urls"), !urls.isEmpty else { throw MCPError("paramètre manquant : urls") }
        let elements = try lireListe()
        var res: [JSON] = []
        var cibles: [(url: String, titre: String, domaine: String)] = []
        for u in urls {
            guard let e = elements.first(where: { $0.url == u }) else { res.append(["url": u, "ok": false, "erreur": "absent de la liste de lecture"]); continue }
            // La ligne affiche « titre, domaine » : refuser si un autre élément non visé s'affiche pareil
            if elements.contains(where: { $0.titre == e.titre && $0.domaine == e.domaine && !urls.contains($0.url) }) {
                res.append(["url": u, "ok": false, "erreur": "ambigu : un autre élément a le même titre et le même domaine ; rien supprimé"]); continue
            }
            cibles.append(e)
        }
        if cibles.isEmpty { return ["resultats": res] }
        let f = try FenetreTravail()
        defer { f.fermer() }
        let affichee = try f.afficher("Présentation", "Afficher la barre latérale de la liste de lecture", "Masquer la barre latérale de la liste de lecture")
        var champ: AXUIElement?, table: AXUIElement?
        _ = AX.attendre(3) {
            champ = AX.first(f.ax, ident: "ReadingListSearchField")
            table = AX.first(f.ax, ident: "ReadingListSidebarScrollView").flatMap { AX.find($0) { AX.role($0) == "AXTable" }.first }
            return champ != nil && table != nil
        }
        guard let champ, let table else { throw MCPError("barre latérale de la liste de lecture introuvable : rien supprimé") }
        if let tout = AX.find(f.ax, { AX.role($0) == "AXRadioButton" && AX.str($0, kAXTitleAttribute) == "Tout" }).first { AX.press(tout) }
        defer {
            AX.set(champ, kAXValueAttribute, "" as CFString)
            if affichee { try? f.menu("Présentation", "Masquer la barre latérale de la liste de lecture") }
        }
        for c in cibles {
            do {
                AX.set(champ, kAXFocusedAttribute, kCFBooleanTrue)
                AX.set(champ, kAXValueAttribute, c.titre as CFString)
                AXUIElementPerformAction(champ, "AXConfirm" as CFString)
                var lignes: [AXUIElement] = []
                _ = AX.attendre(2) {
                    lignes = (AX.attr(table, kAXRowsAttribute) as? [AXUIElement] ?? []).filter { r in
                        AX.find(r) { AX.ident($0) == "ReadingListTableCellView" }.contains { AX.str($0, kAXDescriptionAttribute) == "\(c.titre), \(c.domaine)" }
                    }
                    return lignes.count == 1
                }
                guard lignes.count == 1 else { throw MCPError("\(lignes.count) ligne(s) correspondante(s) dans Safari au lieu d'une : rien supprimé") }
                // Action « Supprimer » de la ligne vérifiée (celle du menu contextuel)
                guard AX.action(lignes[0], "Supprimer") else { throw MCPError("action Supprimer indisponible sur la ligne : rien supprimé") }
                // Vérification : la ligne disparaît tout de suite ; Bookmarks.plist n'est réécrit qu'après ~15 s
                let encore = { (AX.attr(table, kAXRowsAttribute) as? [AXUIElement] ?? []).contains { r in
                    AX.find(r) { AX.ident($0) == "ReadingListTableCellView" }.contains { AX.str($0, kAXDescriptionAttribute) == "\(c.titre), \(c.domaine)" } } }
                guard AX.attendre(3, { !encore() }) else { throw MCPError("suppression demandée mais la ligne est encore affichée") }
                res.append(["url": c.url, "ok": true])
            } catch { res.append(["url": c.url, "ok": false, "erreur": "\(error)"]) }
        }
        return ["supprimes": res.filter { $0["ok"] as? Bool == true }.count, "resultats": res]
    }

    private static func lireListe() throws -> [(url: String, titre: String, domaine: String)] {
        guard let d = FileManager.default.contents(atPath: Fichiers.bookmarks),
              let r = try PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { throw MCPError(Fichiers.accesRefuse) }
        let rl = (r["Children"] as? [[String: Any]] ?? []).first { $0["Title"] as? String == "com.apple.ReadingList" }
        return (rl?["Children"] as? [[String: Any]] ?? []).map { n in
            let url = n["URLString"] as? String ?? ""
            let titre = (n["URIDictionary"] as? [String: Any])?["title"] as? String ?? ""
            var dom = URL(string: url)?.host ?? ""
            if dom.hasPrefix("www.") { dom.removeFirst(4) }
            return (url, titre, dom)
        }
    }

    // MARK: - Groupes d'onglets

    static func groupesOnglets(_ a: JSON) throws -> Any {
        let ids = (a["groupe_ids"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue ?? ($0 as? String).flatMap { Int($0) } }
        guard !ids.isEmpty else { throw MCPError("paramètre manquant : groupe_ids") }
        var res: [JSON] = []
        var f: FenetreTravail?, affichee = false
        defer {
            if let f { if affichee { try? f.menu("Présentation", "Masquer la barre latérale") }; f.fermer() }
        }
        for gid in ids {
            do {
                let db = try Fichiers.DB(Fichiers.tabs)
                guard let g = try db.rows("SELECT title, deleted FROM bookmarks WHERE id = ?1 AND type = 1 AND subtype = 0 AND (special_id IS NULL OR special_id = 0) AND id NOT IN (SELECT private_tab_group_id FROM windows WHERE private_tab_group_id IS NOT NULL) AND id NOT IN (SELECT local_tab_group_id FROM windows WHERE local_tab_group_id IS NOT NULL)", [gid]).first,
                      (g[1] as? Int) == 0 else { throw MCPError("groupe introuvable (voir groupes_onglets)") }
                let titre = g[0] as? String ?? ""
                if try !db.rows("SELECT 1 FROM windows WHERE date_closed IS NULL AND active_tab_group_id = ?1", [gid]).isEmpty {
                    throw MCPError("groupe ouvert dans une fenêtre Safari : basculer cette fenêtre sur un autre groupe ou la fermer, puis réessayer")
                }
                if f == nil {
                    f = try FenetreTravail()
                    affichee = try f!.afficher("Présentation", "Afficher la barre latérale", "Masquer la barre latérale")
                    Thread.sleep(forTimeInterval: 0.5)
                    if let retour = AX.first(f!.ax, ident: "SidebarBackButton") { AX.press(retour); Thread.sleep(forTimeInterval: 0.5) }
                }
                let fw = f!
                var lignes: [AXUIElement] = []
                _ = AX.attendre(3) {
                    lignes = AX.find(fw.ax) { AX.role($0) == "AXRow" && AX.find($0) { AX.ident($0).hasPrefix("SidebarLibraryItemTabGroup") }.count > 0 }
                        .filter { AX.valeur($0, ident: "LibraryItemCellTextField") == titre }
                    return !lignes.isEmpty
                }
                guard !lignes.isEmpty else { throw MCPError("groupe « \(titre) » absent de la barre latérale : rien supprimé") }
                // Homonymes possibles : on sélectionne chaque ligne jusqu'à ce que SafariTabs.db confirme que la fenêtre affiche ce groupe
                // (sinon, pour un titre unique, le nom de la fenêtre « titre — onglet » suffit)
                let unique = try db.rows("SELECT COUNT(*) FROM bookmarks WHERE type = 1 AND subtype = 0 AND deleted = 0 AND title = ?1", [titre]).first?.first as? Int == 1
                var confirme = false
                for l in lignes {
                    if let o = AX.find(fw.ax, { AX.role($0) == "AXOutline" }).first { AX.set(o, kAXSelectedRowsAttribute, [l] as CFArray) }
                    AX.set(l, kAXSelectedAttribute, kCFBooleanTrue)
                    confirme = AX.attendre(3) {
                        if (try? db.rows("SELECT active_tab_group_id FROM windows WHERE uuid = ?1", [fw.uuid]).first?.first as? Int) == gid { return true }
                        return unique && lignes.count == 1 && ((try? AS.run("tell application \"Safari\" to return name of window id \(fw.id)").string) ?? "").hasPrefix(titre + " — ")
                    }
                    if confirme { break }
                }
                guard confirme else { throw MCPError("impossible de confirmer que la fenêtre affiche le groupe \(gid) : rien supprimé") }
                try fw.menu("Fichier", "Supprimer le groupe d’onglets", prefixe: true)
                if AX.attendre(2, { AX.children(fw.ax).contains { AX.role($0) == "AXSheet" } }),
                   let feuille = AX.children(fw.ax).first(where: { AX.role($0) == "AXSheet" }) {
                    guard let b = AX.find(feuille, { AX.role($0) == "AXButton" && AX.str($0, kAXTitleAttribute).hasPrefix("Supprimer") }).first else {
                        throw MCPError("confirmation inattendue : rien supprimé")
                    }
                    AX.press(b)
                }
                guard AX.attendre(5, { (try? db.rows("SELECT 1 FROM bookmarks WHERE id = ?1 AND deleted = 0", [gid]).isEmpty) == true }) else {
                    throw MCPError("suppression demandée mais le groupe est encore présent")
                }
                res.append(["groupe_id": gid, "titre": titre, "ok": true])
            } catch { res.append(["groupe_id": gid, "ok": false, "erreur": "\(error)"]) }
        }
        return ["supprimes": res.filter { $0["ok"] as? Bool == true }.count, "resultats": res]
    }

    // MARK: - Historique

    static func historique(_ a: JSON) throws -> Any {
        let urls = a.strings("urls") ?? []
        let texte = a.nonEmpty("texte")
        let depuis = try a.nonEmpty("depuis").map { Calendar.current.startOfDay(for: try Dates.parse($0)) }
        let jusqua = try a.nonEmpty("jusqu_a").map { Calendar.current.startOfDay(for: try Dates.parse($0)) }
        // Plage seule = journées entières : non prise en charge (comportement de Safari non vérifiable sans toucher de vraies données)
        guard !urls.isEmpty || texte != nil else { throw MCPError("fournir urls ou texte (la plage de jours ne fait que restreindre les pages visées)") }
        let parJour = depuis != nil || jusqua != nil
        func correspond(_ titre: String, _ url: String) -> Bool {
            if !urls.isEmpty { return urls.contains(url) }
            return fold(titre).contains(fold(texte!)) || fold(url).contains(fold(texte!))
        }
        func dansPlage(_ jour: Date) -> Bool { (depuis.map { jour >= $0 } ?? true) && (jusqua.map { jour < $0 } ?? true) }

        let f = try FenetreTravail()
        defer { f.fermer() }
        try f.menu("Historique", "Afficher tout l’historique")
        var champ: AXUIElement?, outline: AXUIElement?
        _ = AX.attendre(3) {
            champ = AX.first(f.ax, ident: "BookmarksSearchField")
            outline = AX.find(f.ax) { AX.role($0) == "AXOutline" && AX.ident($0) == "History" }.first
            return champ != nil && outline != nil
        }
        guard let champ, let outline else { throw MCPError("vue Historique introuvable : rien supprimé") }
        func lignes() -> [AXUIElement] { AX.attr(outline, kAXRowsAttribute) as? [AXUIElement] ?? [] }
        func chercher(_ s: String) {
            AX.set(champ, kAXFocusedAttribute, kCFBooleanTrue)
            AX.set(champ, kAXValueAttribute, s as CFString)
            AXUIElementPerformAction(champ, "AXConfirm" as CFString)
            Thread.sleep(forTimeInterval: 0.8)
        }

        // Comptage par History.db (lecture seule) : Safari retire la page entière, donc toutes ses visites
        func compter(_ pages: [String]) -> Int {
            guard !pages.isEmpty, let db = try? Fichiers.DB(Fichiers.history) else { return pages.isEmpty ? 0 : -1 }
            let sql = "SELECT COUNT(*) FROM history_visits v JOIN history_items i ON i.id = v.history_item WHERE i.url IN (" + pages.indices.map { "?\($0 + 1)" }.joined(separator: ",") + ")"
            return (try? db.rows(sql, pages).first?.first as? Int) ?? -1
        }
        var total = (lignes: 0, visites: 0), pagesSupprimees: [String] = []
        // Lignes à supprimer : (ligne, URL affichée)
        func passe(_ cibles: [(AXUIElement, String)]) throws {
            guard !cibles.isEmpty else { return }
            let pages = Array(Set(cibles.map(\.1)))
            let avant = compter(pages)
            try supprimer(f, outline, cibles.map(\.0))
            var apres = avant
            _ = AX.attendre(5) { apres = compter(pages); return apres < avant }
            total.lignes += pages.count; total.visites += max(0, avant - apres); pagesSupprimees += pages
        }
        defer { chercher("") }
        if !parJour {
            // Recherche : une ligne par page, toutes visites confondues ; une passe par terme
            for terme in urls.isEmpty ? [texte!] : urls {
                chercher(terme)
                var cibles: [(AXUIElement, String)] = []
                for l in lignes() {
                    let t = AX.valeur(l, ident: "HistoryItemTitle"), u = AX.valeur(l, ident: "HistoryItemURL")
                    if !u.isEmpty, correspond(t, u), !cibles.contains(where: { $0.1 == u }) { cibles.append((l, u)) }
                }
                try passe(cibles)
            }
        } else {
            // Vue par jour : pages visitées pendant la plage (une page vue plusieurs jours n'est prise qu'une fois)
            chercher("")
            var cibles: [(AXUIElement, String)] = []
            for j in lignes().filter({ AX.attr($0, "AXDisclosureLevel") as? Int == 0 }) {
                guard let jour = jourDe(j), dansPlage(jour) else { continue }
                AX.set(j, "AXDisclosing", kCFBooleanTrue)
                _ = AX.attendre(2) { !(AX.attr(j, "AXDisclosedRows") as? [AXUIElement] ?? []).isEmpty }
                for l in AX.attr(j, "AXDisclosedRows") as? [AXUIElement] ?? [] {
                    let t = AX.valeur(l, ident: "HistoryItemTitle"), u = AX.valeur(l, ident: "HistoryItemURL")
                    if !u.isEmpty, correspond(t, u), !cibles.contains(where: { $0.1 == u }) { cibles.append((l, u)) }
                }
            }
            try passe(cibles)
        }
        var out: JSON = ["pages_supprimees": total.lignes, "visites_retirees": total.visites]
        if !pagesSupprimees.isEmpty { out["pages"] = Array(Set(pagesSupprimees)).sorted().prefix(20).map { $0 } }
        return out
    }

    /// Sélectionne les lignes, vérifie la sélection, puis Édition > Supprimer
    private static func supprimer(_ f: FenetreTravail, _ outline: AXUIElement, _ lignes: [AXUIElement]) throws {
        AX.set(outline, kAXSelectedRowsAttribute, lignes as CFArray)
        AX.set(outline, kAXFocusedAttribute, kCFBooleanTrue)
        guard AX.attendre(1, { (AX.attr(outline, kAXSelectedRowsAttribute) as? [AXUIElement])?.count == lignes.count }) else {
            throw MCPError("sélection non confirmée : rien supprimé")
        }
        try f.menu("Édition", "Supprimer")
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Date d'une section de jour de la vue Historique (« Dernières visites aujourd’hui », « vendredi 30 octobre 2026 »)
    private static func jourDe(_ ligne: AXUIElement) -> Date? {
        let textes = AX.find(ligne) { AX.role($0) == "AXStaticText" || AX.role($0) == "AXTextField" }.map { AX.str($0, kAXValueAttribute) }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: Locale.preferredLanguages.first ?? "fr_FR")
        fmt.dateFormat = "EEEE d MMMM yyyy"
        for t in textes {
            if t.localizedCaseInsensitiveContains("aujourd") || t.localizedCaseInsensitiveContains("today") { return Calendar.current.startOfDay(for: Date()) }
            if t.localizedCaseInsensitiveContains("hier") || t.localizedCaseInsensitiveContains("yesterday") {
                return Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))
            }
            if let d = fmt.date(from: t) { return Calendar.current.startOfDay(for: d) }
        }
        return nil
    }
}

/// Déclenche la demande d'accès Accessibilité (dialogue macOS) et écrit l'état sur stdout. Appelé par `SafariMCP --accessibilite`.
func import_ApplicationServices_trusted() {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    let ok = AXIsProcessTrustedWithOptions(opts)
    print(ok ? "accessibilite: accordee" : "accessibilite: a activer dans Réglages Système > Confidentialité et sécurité > Accessibilité (SafariMCP)")
}
