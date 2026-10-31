// Escalade des actions quand les événements synthétiques ne suffisent pas (draw.io, apps canvas, Google Docs) :
// niveau 2 = AXPress sur l'élément web à ce point (Accessibilité, Safari reste en arrière-plan) ;
// niveau 3 = vrais événements souris/clavier CGEvent (isTrusted: true), Safari passe au premier plan.
// Les deux relèvent de l'autorisation Accessibilité, déjà demandée à l'installation (CGPreflightPostEventAccess la suit).
// L'Accessibilité, les vrais événements et le premier plan viennent du module partagé MacUI (../shared), commun avec computer-mcp ;
// ici ne reste que ce qui est propre à Safari : fenêtre AppleScript ↔ fenêtre AX, zone web, conversion CSS → écran.
import Foundation
import AppKit
import ApplicationServices
import MacUI

enum Native {
    static let accessibilite = "Accessibility denied: System Settings > Privacy & Security > Accessibility > turn on AppleMCP"

    /// Session verrouillée (écran de connexion devant) : aucun événement réel n'atteint Safari, l'arbre AX des fenêtres est vide
    static var ecranVerrouille: Bool { Session.locked }
    static let verrouille = "the Mac's screen is locked: the Accessibility press and real mouse/keyboard events cannot reach Safari until the session is unlocked"

    static var pid: pid_t? { Running.byBundle(AE.bundle)?.processIdentifier }

    /// Bornes AppleScript d'une fenêtre (rectangle QuickDraw : haut, gauche, bas, droite), en points écran
    static func bornes(_ w: Int) throws -> CGRect {
        guard let d = try AE.get(AE.prop("pbnd", of: AE.window(w))) else { throw MCPError("window not found") }
        if d.descriptorType == typeQDRectangle, d.data.count >= 8 {
            let v = d.data.withUnsafeBytes { p in (0..<4).map { CGFloat(p.load(fromByteOffset: $0 * 2, as: Int16.self)) } }
            return CGRect(x: v[1], y: v[0], width: v[3] - v[1], height: v[2] - v[0])
        }
        let l = d.coerce(toDescriptorType: typeAEList)?.ints ?? []
        guard l.count == 4 else { throw MCPError("window bounds unreadable") }
        return CGRect(x: CGFloat(l[0]), y: CGFloat(l[1]), width: CGFloat(l[2] - l[0]), height: CGFloat(l[3] - l[1]))
    }

    static func frame(_ el: AXUIElement) -> CGRect? { AX.frame(el) }

    /// Fenêtre AX qui correspond à la fenêtre Safari `w` (mêmes bornes)
    static func axWindow(_ w: Int) throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw MCPError(accessibilite) }
        guard let pid else { throw MCPError("Safari is not running") }
        let b = try bornes(w)
        let fenetres = AX.attr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
        let f = fenetres.min { a, c in ecart(frame(a), b) < ecart(frame(c), b) }
        guard let f, ecart(frame(f), b) < 8 else { throw MCPError("Safari window not found in the Accessibility tree") }
        return f
    }
    private static func ecart(_ r: CGRect?, _ b: CGRect) -> CGFloat {
        guard let r else { return .infinity }
        return abs(r.minX - b.minX) + abs(r.minY - b.minY) + abs(r.width - b.width) + abs(r.height - b.height)
    }

    /// Zone web de la fenêtre (AXWebArea principale)
    static func webArea(_ fenetre: AXUIElement) -> AXUIElement? {
        var file = [fenetre], n = 0
        while !file.isEmpty && n < 400 {
            let e = file.removeFirst(); n += 1
            if AX.role(e) == "AXWebArea" { return e }
            file += AX.children(e)
        }
        return nil
    }

    /// Prépare l'onglet pour une action native : onglet actif de sa fenêtre, fenêtre devant les autres fenêtres de Safari.
    /// Renvoie la zone web (repère écran) et si l'onglet a dû être activé.
    static func preparer(_ t: TabRef) throws -> (web: CGRect, tabSwitched: Bool) {
        if ecranVerrouille { throw MCPError(verrouille) }
        var bascule = false
        if (try? AE.get(AE.prop("pidx", of: AE.prop("cTab", of: AE.window(t.fenetre))))?.int) != t.index {
            try AE.set(AE.prop("cTab", of: AE.window(t.fenetre)), AE.tab(t))
            bascule = true
            Thread.sleep(forTimeInterval: 0.15)
        }
        let f = try axWindow(t.fenetre)
        AXUIElementPerformAction(f, kAXRaiseAction as CFString)
        AX.set(f, kAXMainAttribute, kCFBooleanTrue)
        guard let wa = webArea(f), let r = frame(wa) else { throw MCPError("web area not found in the Accessibility tree") }
        return (r, bascule)
    }

    /// Point écran d'un point CSS de la page (vw = innerWidth : le rapport donne le zoom de la page)
    static func ecran(_ web: CGRect, x: Double, y: Double, vw: Double) -> CGPoint {
        let k = vw > 0 ? web.width / CGFloat(vw) : 1
        return CGPoint(x: web.minX + CGFloat(x) * k, y: web.minY + CGFloat(y) * k)
    }

    // MARK: - Niveau 2 : AXPress

    /// Presse l'élément accessible sous ce point (ou son plus proche ancêtre qui accepte AXPress)
    static func axPress(at p: CGPoint) -> String? {
        guard let pid else { return nil }
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(pid), Float(p.x), Float(p.y), &el) == .success, var e = el else { return nil }
        for _ in 0..<6 {
            var noms: CFArray?
            AXUIElementCopyActionNames(e, &noms)
            if (noms as? [String] ?? []).contains(kAXPressAction), AXUIElementPerformAction(e, kAXPressAction as CFString) == .success {
                let titre = AX.str(e, kAXTitleAttribute).isEmpty ? AX.str(e, kAXDescriptionAttribute) : AX.str(e, kAXTitleAttribute)
                return AX.role(e) + (titre.isEmpty ? "" : " \"\(titre.prefix(60))\"")
            }
            guard let parent = AX.attr(e, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            e = parent as! AXUIElement
            if AX.role(e) == "AXWebArea" { break }
        }
        return nil
    }

    // MARK: - Niveau 3 : CGEvent (module partagé)

    /// Safari au premier plan (nécessaire pour que les vrais événements arrivent dans la page) ;
    /// attend d'abord que l'humain ait cessé de taper, vérifie ensuite que Safari a bien le clavier
    static func activer() throws {
        guard Input.canPost() else { throw MCPError(accessibilite) }
        guard let pid else { throw MCPError("Safari is not running") }
        Front.humanPause()
        // garde-fou : de vrais événements envoyés ailleurs iraient dans une autre app
        guard Front.activate(pid) else { throw MCPError("Safari could not be brought to the front: real events not sent") }
    }

    static func click(at p: CGPoint, button: String = "left", count: Int = 1, modifiers: [String] = []) {
        Input.click(at: p, button: button, count: count, modifiers: modifiers)
    }
    static func move(to p: CGPoint) { Input.move(to: p) }
    static func key(_ combo: String) throws {
        do { try Input.key(combo) } catch { throw MCPError("unknown key for native mode: \(combo)") }
    }
    static func type(_ texte: String) { Input.type(texte) }

    /// Feuilles et alertes natives de Safari ouvertes (Autoriser les téléchargements, Enregistrer sous, Quitter la page…),
    /// lues par le même code que l'outil dialogs du serveur computer
    static func dialogues() -> [String] {
        guard AXIsProcessTrusted(), let pid else { return [] }
        return Dialogs.scan(pids: [pid]).map { d in
            "\(d.kind) \"\(d.title.prefix(120))\"" + (d.text.isEmpty ? "" : " — \(d.text.prefix(160))") + " buttons: " + d.buttons.map(\.title).joined(separator: ", ")
        }
    }
}
