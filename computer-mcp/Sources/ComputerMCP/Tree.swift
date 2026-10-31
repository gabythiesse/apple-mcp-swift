// find : arbre d'Accessibilité compact, une ligne par élément utile (ref, rôle, titre, valeur, position) ;
// dialogs : toutes les fenêtres qui attendent une réponse, dans toutes les apps.
import Foundation
import AppKit
import ApplicationServices
import MacUI

enum Tree {
    /// Conteneurs sans intérêt quand ils n'ont ni titre ni valeur : on descend dedans sans les afficher
    static let muets: Set<String> = ["AXGroup", "AXScrollArea", "AXSplitGroup", "AXLayoutArea", "AXLayoutItem", "AXUnknown", "AXGenericElement",
                                     "AXList", "AXSection", "AXRow", "AXColumn", "AXLevelIndicator", "AXMatte", "AXGrowArea", "AXSplitter"]
    static let noms = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
                       kAXPositionAttribute, kAXSizeAttribute, kAXEnabledAttribute, kAXFocusedAttribute, kAXChildrenAttribute,
                       kAXIdentifierAttribute, kAXPlaceholderValueAttribute, kAXSelectedAttribute]

    static func valeur(_ v: AnyObject?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func court(_ s: String, _ n: Int = 80) -> String {
        let t = s.replacingOccurrences(of: "\n", with: "⏎ ").replacingOccurrences(of: "\"", with: "'")
        return t.count > n ? String(t.prefix(n)) + "…" : t
    }

    static func find(_ a: JSON) throws -> Any {
        try AX.trusted()
        let limite = min(max(a.int("limit") ?? 250, 1), 2000)
        let profMax = min(max(a.int("depth") ?? 40, 1), 80)
        let texte = a.nonEmpty("text").map(normalise)
        let roles = (a.strings("role") ?? []).flatMap { $0.split(separator: ",").map { normalise(String($0)).replacingOccurrences(of: "ax", with: "", options: .anchored) } }
        let filtre = texte != nil || !roles.isEmpty
        let web = a.bool("web") ?? true
        let fin = Date().addingTimeInterval(min(a.double("timeout") ?? 4, 15))

        var racines: [(AXUIElement, String)] = []
        var entete: String
        if let r = a.nonEmpty("ref") {
            let el = try Refs.get(r)
            racines = [(el, "")]
            entete = "\(Apps.name(AX.pid(el))) › \(decrire(el))"
        } else {
            let app = try Apps.target(a)
            let pid = app.processIdentifier
            entete = "\(app.localizedName ?? "?") pid=\(pid)"
            var ws = AX.windows(pid)
            if let w = a.nonEmpty("window") {
                let n = normalise(w)
                ws = ws.filter { win in
                    (Int(w).map { UInt32($0) == AX.windowID(win) } ?? false) || Refs.ref(win) == w || normalise(AX.str(win, kAXTitleAttribute)).contains(n)
                }
                if ws.isEmpty { throw MCPError("no window \"\(w)\" in \(app.localizedName ?? "the app")") }
            }
            racines = ws.map { ($0, "") }
            if a.bool("menu_bar") == true, let mb = AX.element(AX.app(pid), kAXMenuBarAttribute) { racines.append((mb, "")) }
            if racines.isEmpty { return entete + "\n(no window: use menu, or app with action activate)" }
        }

        var lignes: [String] = [], vus = 0, coupe = false
        func visiter(_ el: AXUIElement, _ prof: Int, _ indent: Int) {
            if lignes.count >= limite || Date() > fin { coupe = true; return }
            vus += 1
            let v = AX.attrs(el, noms)
            let role = v[0] as? String ?? ""
            let sub = v[1] as? String ?? ""
            var titre = v[2] as? String ?? ""
            let desc = v[3] as? String ?? ""
            var val = valeur(v[4]) ?? ""
            if sub == "AXSecureTextField" { val = val.isEmpty ? "" : "••••" }
            if titre.isEmpty, role != "AXStaticText", let p = v[11] as? String { titre = p }
            let enfants = v[9] as? [AXUIElement] ?? []
            let muet = muets.contains(role) && titre.isEmpty && desc.isEmpty && val.isEmpty
            var affiche = !muet
            if filtre {
                let r = normalise(role).replacingOccurrences(of: "ax", with: "", options: .anchored)
                let s = normalise(sub).replacingOccurrences(of: "ax", with: "", options: .anchored)
                let okRole = roles.isEmpty || roles.contains(r) || roles.contains(s)
                let okTexte = texte.map { t in [titre, desc, val, v[10] as? String ?? ""].contains { normalise($0).contains(t) } } ?? true
                affiche = okRole && okTexte && !(muet && texte == nil)
            }
            if affiche {
                var l = String(repeating: " ", count: filtre ? 0 : min(indent, 30))
                let r = role.replacingOccurrences(of: "AX", with: "")
                l += Refs.ref(el) + " " + (r.isEmpty ? "?" : r.prefix(1).lowercased() + r.dropFirst())
                if !sub.isEmpty, !["AXStandardWindow"].contains(sub) { l += ":" + sub.replacingOccurrences(of: "AX", with: "").lowercased() }
                if !titre.isEmpty { l += " \"\(court(titre))\"" }
                if !desc.isEmpty, desc != titre { l += " (\(court(desc, 60)))" }
                if !val.isEmpty, val != titre { l += " =\"\(court(val, role == "AXStaticText" ? 160 : 80))\"" }
                if let f = AX.frame(v[5], v[6]) { l += " @\(rect(f))" }
                if v[7] as? Bool == false { l += " disabled" }
                if v[8] as? Bool == true { l += " focused" }
                if v[12] as? Bool == true { l += " selected" }
                lignes.append(l)
            }
            guard prof < profMax, web || role != "AXWebArea" else { return }
            for c in enfants { visiter(c, prof + 1, affiche ? indent + 1 : indent); if coupe { return } }
        }
        for (r, _) in racines { visiter(r, 0, 0); if coupe { break } }
        var out = entete + "\n" + (lignes.isEmpty ? "(nothing matches)" : lignes.joined(separator: "\n"))
        if coupe { out += "\n… stopped at \(lignes.count) lines (\(vus) elements read): narrow with text, role, window or ref" }
        return out
    }

    // MARK: - dialogs

    static func ligne(_ d: Dialog) -> String {
        var l = "\(d.app) \(d.kind) \(Refs.ref(d.element)) \"\(court(d.title, 140))\""
        if !d.text.isEmpty { l += " — \(court(d.text, 220))" }
        let boutons = d.buttons.map { b -> String in
            var s = "[\(b.title)]"
            if b.title == d.defaultButton { s += "*" }
            return s + Refs.ref(b.el)
        }
        if !boutons.isEmpty { l += "\n    buttons: " + boutons.joined(separator: " ") + (d.defaultButton != nil ? "  (* default)" : "") }
        let champs = d.fields.prefix(4).map { "\"\(court($0.label, 40))\"=\"\(court($0.value, 60))\" \(Refs.ref($0.el))" }
        if !champs.isEmpty { l += "\n    fields: " + champs.joined(separator: "; ") }
        if d.password { l += "\n    asks for a password" }
        if d.secure { l += "\n    macOS privacy/password window: synthetic clicks are ignored here" }
        return l
    }

    static func dialogs(_ a: JSON) throws -> Any {
        try AX.trusted()
        let pids = try a.nonEmpty("app").map { [try Apps.require($0).processIdentifier] }
        let ds = Dialogs.scan(pids: pids)
        var out = ds.isEmpty ? "no dialog open" : ds.map(ligne).joined(separator: "\n")
        if Session.locked { out += "\n! screen locked" }
        return out
    }
}
