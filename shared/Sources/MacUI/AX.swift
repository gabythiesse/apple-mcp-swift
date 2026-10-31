// Accès à l'arbre d'Accessibilité (AXUIElement) de n'importe quelle app : lecture, recherche, actions.
// Tout passe par l'autorisation Accessibilité du lanceur AppleMCP.
import Foundation
import AppKit
import ApplicationServices

/// Erreur courte, lisible telle quelle par le modèle
public struct UIError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public enum AX {
    public static let denied = "Accessibility denied: System Settings > Privacy & Security > Accessibility > turn on AppleMCP (./installer.command)"

    /// Délai par message AX : une app bloquée ne gèle pas l'appel (défaut macOS : 6 s)
    public static func setTimeout(_ s: Float = 1.0) { AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), s) }

    public static func trusted() throws { guard AXIsProcessTrusted() else { throw UIError(denied) } }

    public static func app(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }

    public static func attr(_ el: AXUIElement, _ a: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success ? v : nil
    }
    /// Plusieurs attributs en un seul aller-retour (beaucoup plus rapide sur un grand arbre)
    public static func attrs(_ el: AXUIElement, _ noms: [String]) -> [AnyObject?] {
        var v: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(el, noms as CFArray, [], &v) == .success, let arr = v as? [AnyObject] else {
            return noms.map { attr(el, $0) }
        }
        return arr.map { o in
            if CFGetTypeID(o) == AXValueGetTypeID(), AXValueGetType(o as! AXValue) == .axError { return nil }
            if o is NSNull { return nil }
            return o
        }
    }
    public static func str(_ el: AXUIElement, _ a: String) -> String { attr(el, a) as? String ?? "" }
    public static func children(_ el: AXUIElement) -> [AXUIElement] { attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    public static func role(_ el: AXUIElement) -> String { str(el, kAXRoleAttribute) }
    public static func subrole(_ el: AXUIElement) -> String { str(el, kAXSubroleAttribute) }
    public static func ident(_ el: AXUIElement) -> String { str(el, kAXIdentifierAttribute) }
    public static func element(_ el: AXUIElement, _ a: String) -> AXUIElement? {
        guard let v = attr(el, a), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    public static func parent(_ el: AXUIElement) -> AXUIElement? { element(el, kAXParentAttribute) }
    @discardableResult
    public static func set(_ el: AXUIElement, _ a: String, _ v: CFTypeRef) -> Bool { AXUIElementSetAttributeValue(el, a as CFString, v) == .success }
    @discardableResult
    public static func press(_ el: AXUIElement) -> Bool { AXUIElementPerformAction(el, kAXPressAction as CFString) == .success }
    public static func pid(_ el: AXUIElement) -> pid_t { var p: pid_t = 0; AXUIElementGetPid(el, &p); return p }
    public static func enabled(_ el: AXUIElement) -> Bool { attr(el, kAXEnabledAttribute) as? Bool != false }
    /// L'élément existe encore (fenêtre fermée, bouton disparu : erreur « invalid UI element »)
    public static func alive(_ el: AXUIElement) -> Bool {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &v) != .invalidUIElement
    }
    public static func actions(_ el: AXUIElement) -> [String] {
        var n: CFArray?
        AXUIElementCopyActionNames(el, &n)
        return n as? [String] ?? []
    }

    /// Libellé lisible : titre, sinon description, sinon aide, sinon titre de l'élément-titre
    public static func label(_ el: AXUIElement) -> String {
        for a in [kAXTitleAttribute, kAXDescriptionAttribute] { let s = str(el, a); if !s.isEmpty { return s } }
        if let t = element(el, kAXTitleUIElementAttribute) { let s = str(t, kAXValueAttribute); if !s.isEmpty { return s } }
        return str(el, kAXHelpAttribute)
    }

    /// Action nommée exposée par l'élément (« Name:Supprimer\nTarget:… ») ; false si absente ou refusée
    public static func action(_ el: AXUIElement, _ nom: String) -> Bool {
        guard let a = actions(el).first(where: { $0 == nom || $0.hasPrefix("Name:\(nom)\n") }) else { return false }
        return AXUIElementPerformAction(el, a as CFString) == .success
    }

    public static func point(_ el: AXUIElement, _ a: String = kAXPositionAttribute) -> CGPoint? {
        guard let v = attr(el, a), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }
    public static func size(_ el: AXUIElement, _ a: String = kAXSizeAttribute) -> CGSize? {
        guard let v = attr(el, a), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }
    /// Rectangle en points écran (origine en haut à gauche de l'écran principal, comme CGEvent)
    public static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = point(el), let s = size(el) else { return nil }
        return CGRect(origin: p, size: s)
    }
    public static func frame(_ v: AnyObject?, _ w: AnyObject?) -> CGRect? {
        guard let v, let w, CFGetTypeID(v) == AXValueGetTypeID(), CFGetTypeID(w) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(v as! AXValue, .cgPoint, &p), AXValueGetValue(w as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    /// Recherche en profondeur ; par défaut jamais dans le contenu web (web: true pour y descendre)
    public static func find(_ el: AXUIElement, depth: Int = 0, maxDepth: Int = 18, web: Bool = false, _ pred: (AXUIElement) -> Bool) -> [AXUIElement] {
        if depth > maxDepth { return [] }
        var out: [AXUIElement] = []
        for c in children(el) {
            if pred(c) { out.append(c) }
            if web || role(c) != "AXWebArea" { out += find(c, depth: depth + 1, maxDepth: maxDepth, web: web, pred) }
        }
        return out
    }
    public static func first(_ el: AXUIElement, ident i: String) -> AXUIElement? { find(el) { ident($0) == i }.first }

    /// Valeur du premier texte d'identifiant donné sous l'élément
    public static func valeur(_ el: AXUIElement, ident i: String) -> String {
        find(el) { ident($0) == i }.first.map { str($0, kAXValueAttribute) } ?? ""
    }

    public static func attendre(_ timeout: TimeInterval = 3, every: TimeInterval = 0.1, _ cond: () -> Bool) -> Bool {
        let fin = Date().addingTimeInterval(timeout)
        while Date() < fin {
            if cond() { return true }
            Thread.sleep(forTimeInterval: every)
        }
        return cond()
    }

    /// Fenêtres d'une app (AXWindows), fenêtre focalisée en premier
    public static func windows(_ pid: pid_t) -> [AXUIElement] {
        let a = app(pid)
        var w = attr(a, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if let f = element(a, kAXFocusedWindowAttribute), let i = w.firstIndex(where: { CFEqual($0, f) }), i > 0 { w.insert(w.remove(at: i), at: 0) }
        return w
    }

    /// Fenêtre (élément de rôle AXWindow) qui contient cet élément
    public static func window(of el: AXUIElement) -> AXUIElement? {
        if role(el) == "AXWindow" { return el }
        if let w = element(el, kAXWindowAttribute) { return w }
        var e = el
        for _ in 0..<40 {
            guard let p = parent(e) else { return nil }
            if role(p) == "AXWindow" { return p }
            e = p
        }
        return nil
    }

    /// Identifiant WindowServer (CGWindowID) d'une fenêtre AX : fonction non publique, stable depuis 10.5
    public static func windowID(_ el: AXUIElement) -> CGWindowID? {
        guard let f = getWindowFn else { return nil }
        var id: CGWindowID = 0
        return f(el, &id) == .success && id != 0 ? id : nil
    }
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindowFn: GetWindow? = {
        guard let h = dlopen(nil, RTLD_NOW), let s = dlsym(h, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(s, to: GetWindow.self)
    }()

    /// Élément accessible au point écran (système entier)
    public static func element(at p: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        return AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &el) == .success ? el : nil
    }
}

/// Comparaison et hachage CoreFoundation : deux lectures du même élément donnent la même clé
public struct AXKey: Hashable {
    public let el: AXUIElement
    public init(_ el: AXUIElement) { self.el = el }
    public static func == (a: AXKey, b: AXKey) -> Bool { CFEqual(a.el, b.el) }
    public func hash(into h: inout Hasher) { h.combine(CFHash(el)) }
}

/// Comparaison de textes tolérante : casse, accents, points de suspension, espaces
public func normalise(_ s: String) -> String {
    var t = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    t = t.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
    t = t.replacingOccurrences(of: "\u{00a0}", with: " ").replacingOccurrences(of: "’", with: "'")
    return t.trimmingCharacters(in: .whitespacesAndNewlines)
}
