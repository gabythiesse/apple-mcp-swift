// click, type, press, scroll, drag, move : AXPress quand il suffit, vrais événements CGEvent sinon,
// l'app ciblée amenée au premier plan pour la durée de l'action puis le premier plan rendu.
import Foundation
import AppKit
import ApplicationServices
import MacUI

struct Cible {
    var el: AXUIElement?
    var point: CGPoint?
    var pid: pid_t
    var nom: String
}

enum Act {
    static let pressables: Set<String> = ["AXButton", "AXCheckBox", "AXRadioButton", "AXMenuItem", "AXMenuBarItem", "AXMenuButton",
                                          "AXPopUpButton", "AXLink", "AXDisclosureTriangle", "AXIncrementor", "AXTab"]

    /// Élément par titre dans une app : feuilles et dialogues d'abord, puis la fenêtre focalisée, puis les autres
    static func parTitre(_ app: NSRunningApplication, _ titre: String, role: String?) throws -> AXUIElement {
        let n = normalise(titre)
        let r = role.map { "AX" + normalise($0).replacingOccurrences(of: "ax", with: "", options: .anchored) }
        var racines: [AXUIElement] = []
        for w in AX.windows(app.processIdentifier) {
            racines += AX.children(w).filter { AX.role($0) == "AXSheet" }
            racines.append(w)
        }
        var contient: AXUIElement?
        for racine in racines {
            let tous = AX.find(racine, maxDepth: 30, web: true) { e in
                guard r == nil || normalise(AX.role(e)) == normalise(r!) else { return false }
                return !normalise(AX.label(e)).isEmpty
            }
            let tries = tous.sorted { a, b in (pressables.contains(AX.role(a)) ? 0 : 1) < (pressables.contains(AX.role(b)) ? 0 : 1) }
            if let e = tries.first(where: { normalise(AX.label($0)) == n }) { return e }
            if contient == nil { contient = tries.first { normalise(AX.label($0)).contains(n) } }
        }
        if let contient { return contient }
        throw MCPError("nothing titled \"\(titre)\" in \(app.localizedName ?? "the app")'s windows (find lists what is there; menus: use menu)")
    }

    static func centre(_ el: AXUIElement) -> CGPoint? {
        guard let f = AX.frame(el), f.width > 0 || f.height > 0 else { return nil }
        return CGPoint(x: f.midX, y: f.midY)
    }

    /// Fenêtre la plus haute sous un point (WindowServer) : son app reçoit le clic
    static func pidAuPoint(_ p: CGPoint) -> pid_t? {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for i in infos {
            guard let b = i[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b), r.contains(p),
                  (i[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 else { continue }
            return (i[kCGWindowOwnerPID as String] as? Int).map(pid_t.init)
        }
        return nil
    }

    /// Cible commune : ref, ou app + title (+ role), ou x/y écran (préfixe : « », « to_ » pour drag)
    static func cible(_ a: JSON, _ p: String = "") throws -> Cible {
        if let r = a.nonEmpty(p + "ref") {
            let el = try Refs.get(r)
            return Cible(el: el, point: centre(el), pid: AX.pid(el), nom: decrire(el))
        }
        if let x = a.double(p + "x"), let y = a.double(p + "y") {
            let pt = CGPoint(x: x, y: y)
            let pid = pidAuPoint(pt) ?? AX.element(at: pt).map(AX.pid) ?? 0
            return Cible(el: nil, point: pt, pid: pid, nom: "point \(Int(x)),\(Int(y))")
        }
        if let t = a.nonEmpty(p + "title") {
            let app = try Apps.target(a)
            let el = try parTitre(app, t, role: a.nonEmpty("role"))
            return Cible(el: el, point: centre(el), pid: app.processIdentifier, nom: decrire(el))
        }
        throw MCPError(p.isEmpty ? "give ref, or app + title, or x and y" : "give \(p)ref or \(p)x and \(p)y")
    }

    /// Exécute l'action et rapporte les fenêtres de dialogue qu'elle a fait apparaître
    static func avecDialogues(_ pid: pid_t, _ body: () throws -> String) throws -> String {
        let avantSig = Dialogs.windowSignature()
        let avant = Set(Dialogs.scan(pids: pid > 0 ? [pid] : []).map(\.key))
        var out = try body()
        // Une feuille ou une alerte apparaît en général dans les 100-400 ms : on guette 0,5 s, sortie dès qu'une fenêtre naît
        var nouvelles = Set<Int>()
        _ = AX.attendre(0.5, every: 0.05) { nouvelles = Dialogs.windowSignature().subtracting(avantSig); return !nouvelles.isEmpty }
        guard !nouvelles.isEmpty else { return out }
        Thread.sleep(forTimeInterval: 0.08)   // le temps que son contenu AX se remplisse
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        var pids = Set(infos.filter { nouvelles.contains($0[kCGWindowNumber as String] as? Int ?? -1) }.compactMap { ($0[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) })
        if pid > 0 { pids.insert(pid) }
        let ds = Dialogs.scan(pids: Array(pids)).filter { !avant.contains($0.key) }
        if !ds.isEmpty { out += "\nnew dialog:\n" + ds.map(Tree.ligne).joined(separator: "\n") }
        return out
    }

    static func front(_ restored: Bool, _ pid: pid_t) -> String {
        restored ? "" : (Front.frontPid == pid ? " (\(Apps.name(pid)) left in front\(Front.menuOpen(pid) ? ": a menu is open" : ""))" : "")
    }

    // MARK: - click

    static func click(_ a: JSON) throws -> Any {
        try AX.trusted()
        let c = try cible(a)
        let bouton = a.nonEmpty("button") ?? "left"
        let n = max(1, min(a.int("count") ?? 1, 3))
        let mods = a.strings("modifiers") ?? []
        let simple = bouton == "left" && n == 1 && mods.isEmpty && a.bool("real") != true
        return try enAction {
            try avecDialogues(c.pid) {
                // 1. AXPress : l'élément est pressé où qu'il soit, sans toucher à la souris ni au premier plan
                if simple {
                    var el = c.el
                    if el == nil, let p = c.point, let e = AX.element(at: p) { el = pressables.contains(AX.role(e)) ? e : nil }
                    if let e = el, AX.actions(e).contains(kAXPressAction) {
                        guard AX.enabled(e) else { throw MCPError("\(decrire(e)) is disabled") }
                        if AX.press(e) { return "pressed \(decrire(e)) in \(Apps.name(AX.pid(e))) (AXPress)" }
                    }
                }
                // 2. Vrai clic au point, l'app passe devant le temps du clic
                guard let p = c.point else { throw MCPError("\(c.nom) has no position on screen: nothing to click") }
                if c.pid == 0 { Input.click(at: p, button: bouton, count: n, modifiers: mods); return "clicked \(c.nom) (CGEvent)" }
                let w = c.el.flatMap(AX.window(of:)) ?? AX.element(at: p).flatMap(AX.window(of:))
                let (_, rendu) = try Front.with(c.pid, window: w, keep: a.bool("keep_front") == true) {
                    Input.click(at: p, button: bouton, count: n, modifiers: mods)
                }
                let quoi = n == 2 ? "double-clicked" : n == 3 ? "triple-clicked" : bouton == "right" ? "right-clicked" : "clicked"
                return "\(quoi) \(c.nom) at \(Int(p.x)),\(Int(p.y)) in \(Apps.name(c.pid)) (CGEvent)" + front(rendu, c.pid)
            }
        }
    }

    // MARK: - type, press

    /// Cible clavier : ref (focalisée d'abord) ou app ; jamais « l'app de devant » par défaut (ce serait souvent le client MCP lui-même)
    static func clavier(_ a: JSON) throws -> (pid: pid_t, el: AXUIElement?) {
        if let r = a.nonEmpty("ref") { let el = try Refs.get(r); return (AX.pid(el), el) }
        guard a.nonEmpty("app") != nil else {
            throw MCPError("give app (or ref): keys go to the front app, which is \(Front.frontmost?.localizedName ?? "unknown")")
        }
        return (try Apps.target(a).processIdentifier, nil)
    }

    static func focaliser(_ el: AXUIElement) {
        if !AX.set(el, kAXFocusedAttribute, kCFBooleanTrue), let p = centre(el) { Input.click(at: p) }
        Thread.sleep(forTimeInterval: 0.05)
    }

    static func type(_ a: JSON) throws -> Any {
        try AX.trusted()
        guard let texte = a.string("text") else { throw MCPError("missing parameter: text") }
        let (pid, el) = try clavier(a)
        return try enAction {
            try avecDialogues(pid) {
                let w = el.flatMap(AX.window(of:))
                let (_, rendu) = try Front.with(pid, window: w, keep: a.bool("keep_front") == true) {
                    if let el { focaliser(el) }
                    if a.bool("clear") == true { try Input.key("cmd+a"); try Input.key("backspace") }
                    // garde-fou : jamais de frappe dans une autre app que la cible
                    guard Front.frontPid == pid else { throw MCPError("\(Apps.name(pid)) lost the front: typing stopped") }
                    Input.type(texte)
                    if a.bool("submit") == true { try Input.key("return") }
                }
                var out = "typed \(texte.count) characters in \(Apps.name(pid))"
                if let f = AX.element(AX.app(pid), kAXFocusedUIElementAttribute) {
                    out += " → " + decrire(f)
                    if let v = AX.attr(f, kAXValueAttribute) as? String { out += " =\"\(Tree.court(v, 120))\"" }
                }
                return out + front(rendu, pid)
            }
        }
    }

    static func press(_ a: JSON) throws -> Any {
        try AX.trusted()
        guard let touches = a.strings("keys"), !touches.isEmpty else { throw MCPError("missing parameter: keys (\"cmd+s\", \"enter\", [\"tab\", \"tab\"])") }
        let (pid, el) = try clavier(a)
        let fois = max(1, min(a.int("repeat") ?? 1, 50))
        for k in touches { _ = try Input.keyCodeOrThrow(k) }
        return try enAction {
            try avecDialogues(pid) {
                let w = el.flatMap(AX.window(of:))
                let (_, rendu) = try Front.with(pid, window: w, keep: a.bool("keep_front") == true) {
                    if let el { focaliser(el) }
                    for _ in 0..<fois {
                        for k in touches {
                            guard Front.frontPid == pid else { throw MCPError("\(Apps.name(pid)) lost the front: keys stopped") }
                            try Input.key(k)
                            Thread.sleep(forTimeInterval: 0.03)
                        }
                    }
                }
                return "pressed \(touches.joined(separator: ", "))\(fois > 1 ? " ×\(fois)" : "") in \(Apps.name(pid))" + front(rendu, pid)
            }
        }
    }

    // MARK: - scroll, drag, move

    static func scroll(_ a: JSON) throws -> Any {
        try AX.trusted()
        var c: Cible
        if a.nonEmpty("ref") != nil || a.has("x") { c = try cible(a) }
        else {
            let app = try Apps.target(a)
            guard let w = AX.windows(app.processIdentifier).first, let p = centre(w) else { throw MCPError("\(app.localizedName ?? "the app") has no window to scroll") }
            c = Cible(el: w, point: p, pid: app.processIdentifier, nom: "window \"\(AX.str(w, kAXTitleAttribute))\"")
        }
        guard let p = c.point else { throw MCPError("\(c.nom) has no position") }
        let dy = a.int("dy") ?? (a.has("dx") ? 0 : 5), dx = a.int("dx") ?? 0
        return try enAction {
            let w = c.el.flatMap(AX.window(of:))
            let (_, rendu) = try Front.with(c.pid > 0 ? c.pid : (Front.frontPid ?? 0), window: w, keep: a.bool("keep_front") == true) {
                Input.scroll(at: p, dx: dx, dy: dy)
            }
            return "scrolled \(dy != 0 ? "\(abs(dy)) lines \(dy > 0 ? "down" : "up")" : "")\(dx != 0 ? " \(abs(dx)) columns \(dx > 0 ? "right" : "left")" : "") over \(c.nom)" + front(rendu, c.pid)
        }
    }

    static func drag(_ a: JSON) throws -> Any {
        try AX.trusted()
        let de = try cible(a, "from_"), vers = try cible(a, "to_")
        guard let p1 = de.point, let p2 = vers.point else { throw MCPError("drag needs two positions") }
        let pid = de.pid > 0 ? de.pid : (Front.frontPid ?? 0)
        return try enAction {
            try avecDialogues(pid) {
                let w = de.el.flatMap(AX.window(of:)) ?? AX.element(at: p1).flatMap(AX.window(of:))
                let (_, rendu) = try Front.with(pid, window: w, keep: a.bool("keep_front") == true) {
                    Input.drag(from: p1, to: p2, button: a.nonEmpty("button") ?? "left", modifiers: a.strings("modifiers") ?? [],
                               duration: min(max(a.double("duration") ?? 0.4, 0.05), 5))
                }
                return "dragged from \(de.nom) to \(vers.nom) (CGEvent)" + front(rendu, pid)
            }
        }
    }

    static func move(_ a: JSON) throws -> Any {
        try Session.check()
        let c = try cible(a)
        guard let p = c.point else { throw MCPError("\(c.nom) has no position") }
        var devant = ""
        // Survoler un élément caché par une autre fenêtre n'a pas de sens : son app passe devant et y reste (le survol doit rester visible)
        if c.el != nil, c.pid > 0, pidAuPoint(p) != c.pid {
            if let w = c.el.flatMap(AX.window(of:)) { Front.raise(w) }
            if Front.activate(c.pid) { devant = " (\(Apps.name(c.pid)) brought to the front to hover it)" }
        }
        enAction { Input.move(to: p) }
        Thread.sleep(forTimeInterval: 0.3)
        var out = "pointer at \(Int(p.x)),\(Int(p.y))" + devant
        if let e = AX.element(at: p) { out += " over \(decrire(e)) in \(Apps.name(AX.pid(e)))" }
        return out
    }
}

extension Input {
    @discardableResult
    static func keyCodeOrThrow(_ combo: String) throws -> Int {
        var parts = combo.split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 2, parts.last == "", parts[parts.count - 2] == "" { return keyCode("+") ?? 0 }
        let k = parts.popLast() ?? ""
        guard let c = keyCode(k) else { throw MCPError("unknown key: \(k) (a character, or enter, tab, escape, backspace, delete, space, arrows, home, end, pageup, pagedown, f1-f15)") }
        return c
    }
}
