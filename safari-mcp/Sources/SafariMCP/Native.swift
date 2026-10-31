// Escalade des actions quand les événements synthétiques ne suffisent pas (draw.io, apps canvas, Google Docs) :
// niveau 2 = AXPress sur l'élément web à ce point (Accessibilité, Safari reste en arrière-plan) ;
// niveau 3 = vrais événements souris/clavier CGEvent (isTrusted: true), Safari passe au premier plan.
// Les deux relèvent de l'autorisation Accessibilité, déjà demandée à l'installation (CGPreflightPostEventAccess la suit).
import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum Native {
    static let accessibilite = "Accessibility denied: System Settings > Privacy & Security > Accessibility > turn on AppleMCP"

    /// Session verrouillée (écran de connexion devant) : aucun événement réel n'atteint Safari, l'arbre AX des fenêtres est vide
    static var ecranVerrouille: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
    }
    static let verrouille = "the Mac's screen is locked: the Accessibility press and real mouse/keyboard events cannot reach Safari until the session is unlocked"

    static var pid: pid_t? { NSRunningApplication.runningApplications(withBundleIdentifier: AE.bundle).first?.processIdentifier }

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

    private static func point(_ el: AXUIElement, _ a: String) -> CGPoint? {
        guard let v = AX.attr(el, a), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }
    private static func size(_ el: AXUIElement, _ a: String) -> CGSize? {
        guard let v = AX.attr(el, a), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }
    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = point(el, kAXPositionAttribute), let s = size(el, kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }

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

    // MARK: - Niveau 3 : CGEvent

    /// Safari au premier plan (nécessaire pour que les vrais événements arrivent dans la page)
    static func activer() throws {
        guard CGPreflightPostEventAccess() || AXIsProcessTrusted() else { throw MCPError(accessibilite) }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: AE.bundle).first else { throw MCPError("Safari is not running") }
        if !app.isActive {
            app.activate()
            for _ in 0..<40 where NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier { Thread.sleep(forTimeInterval: 0.025) }
            Thread.sleep(forTimeInterval: 0.08)
        }
    }

    static func flags(_ m: [String]) -> CGEventFlags {
        var f: CGEventFlags = []
        for x in m.map({ $0.lowercased() }) {
            if ["cmd", "command", "meta", "⌘"].contains(x) { f.insert(.maskCommand) }
            if ["ctrl", "control"].contains(x) { f.insert(.maskControl) }
            if ["alt", "option", "opt", "⌥"].contains(x) { f.insert(.maskAlternate) }
            if ["shift", "⇧"].contains(x) { f.insert(.maskShift) }
        }
        return f
    }

    static func click(at p: CGPoint, button: String = "left", count: Int = 1, modifiers: [String] = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        let (bt, down, up): (CGMouseButton, CGEventType, CGEventType) = button == "right" ? (.right, .rightMouseDown, .rightMouseUp)
            : button == "middle" ? (.center, .otherMouseDown, .otherMouseUp) : (.left, .leftMouseDown, .leftMouseUp)
        let f = flags(modifiers)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: bt)?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.03)
        for i in 1...max(1, count) {
            for type in [down, up] {
                let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: bt)
                e?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                e?.flags = f
                e?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    static func move(to p: CGPoint) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// Touches nommées : codes virtuels (indépendants de la disposition)
    private static let nommees: [String: Int] = [
        "enter": kVK_Return, "return": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape, "esc": kVK_Escape, "backspace": kVK_Delete,
        "delete": kVK_ForwardDelete, "space": kVK_Space, "arrowleft": kVK_LeftArrow, "left": kVK_LeftArrow, "arrowright": kVK_RightArrow,
        "right": kVK_RightArrow, "arrowup": kVK_UpArrow, "up": kVK_UpArrow, "arrowdown": kVK_DownArrow, "down": kVK_DownArrow,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
        "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12]

    /// Code virtuel qui produit ce caractère avec la disposition clavier active (AZERTY : « a » n'est pas kVK_ANSI_A)
    private static let parCaractere: [Character: Int] = Thread.isMainThread ? tableCaracteres() : DispatchQueue.main.sync(execute: tableCaracteres)
    /// Les fonctions TIS ne s'appellent que sur le fil principal
    private static func tableCaracteres() -> [Character: Int] {
        var m: [Character: Int] = [:]
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return m }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in 0..<128 {
                var etat: UInt32 = 0, n = 0
                var chars = [UniChar](repeating: 0, count: 4)
                if UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &etat, 4, &n, &chars) == noErr, n == 1, let c = String(utf16CodeUnits: chars, count: 1).first, m[c] == nil {
                    m[c] = code
                }
            }
        }
        return m
    }

    /// Une touche ou un raccourci (« Cmd+B », « Enter », « Shift+Tab »)
    static func key(_ combo: String) throws {
        var parts = combo.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        let k = parts.popLast() ?? ""
        let f = flags(parts)
        let code: Int
        if let c = nommees[k.lowercased()] { code = c }
        else if k.count == 1, let c = parCaractere[Character(k.lowercased())] { code = c }
        else { throw MCPError("unknown key for native mode: \(k)") }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: down)
            e?.flags = f
            e?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.015)
        }
    }

    /// Texte tapé comme au clavier, par paquets de caractères Unicode (indépendant de la disposition)
    static func type(_ texte: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        var reste = Array(texte.utf16)
        while !reste.isEmpty {
            let paquet = Array(reste.prefix(16)); reste.removeFirst(paquet.count)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                paquet.withUnsafeBufferPointer { e?.keyboardSetUnicodeString(stringLength: paquet.count, unicodeString: $0.baseAddress) }
                e?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }
}
