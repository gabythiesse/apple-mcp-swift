// Vrais événements souris et clavier (CGEvent, isTrusted côté pages web), postés au niveau HID comme une vraie souris.
// Relève de l'autorisation Accessibilité (CGPreflightPostEventAccess la suit, aucune fenêtre en plus).
// Les événements vont à ce qui est sous le pointeur ou à l'app au premier plan : l'appelant s'assure d'abord que c'est la bonne.
import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

public enum Input {
    public static func canPost() -> Bool { CGPreflightPostEventAccess() || AXIsProcessTrusted() }

    public static func flags(_ m: [String]) -> CGEventFlags {
        var f: CGEventFlags = []
        for x in m.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) {
            if ["cmd", "command", "meta", "⌘", "super"].contains(x) { f.insert(.maskCommand) }
            if ["ctrl", "control", "⌃"].contains(x) { f.insert(.maskControl) }
            if ["alt", "option", "opt", "⌥"].contains(x) { f.insert(.maskAlternate) }
            if ["shift", "⇧"].contains(x) { f.insert(.maskShift) }
            if ["fn", "function"].contains(x) { f.insert(.maskSecondaryFn) }
        }
        return f
    }

    private static func boutons(_ button: String) -> (CGMouseButton, CGEventType, CGEventType, CGEventType) {
        switch button {
        case "right": return (.right, .rightMouseDown, .rightMouseUp, .rightMouseDragged)
        case "middle": return (.center, .otherMouseDown, .otherMouseUp, .otherMouseDragged)
        default: return (.left, .leftMouseDown, .leftMouseUp, .leftMouseDragged)
        }
    }

    public static func click(at p: CGPoint, button: String = "left", count: Int = 1, modifiers: [String] = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        let (bt, down, up, _) = boutons(button)
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

    public static func move(to p: CGPoint) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// Glisser : appui, trajet en étapes régulières (événements « dragged »), relâchement
    public static func drag(from a: CGPoint, to b: CGPoint, button: String = "left", modifiers: [String] = [], duration: TimeInterval = 0.4) {
        let src = CGEventSource(stateID: .hidSystemState)
        let (bt, down, up, dragged) = boutons(button)
        let f = flags(modifiers)
        move(to: a); Thread.sleep(forTimeInterval: 0.05)
        let d = CGEvent(mouseEventSource: src, mouseType: down, mouseCursorPosition: a, mouseButton: bt); d?.flags = f; d?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
        let n = max(4, Int(duration / 0.016))
        for i in 1...n {
            let t = CGFloat(i) / CGFloat(n)
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            let e = CGEvent(mouseEventSource: src, mouseType: dragged, mouseCursorPosition: p, mouseButton: bt); e?.flags = f; e?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: duration / Double(n))
        }
        Thread.sleep(forTimeInterval: 0.05)
        let u = CGEvent(mouseEventSource: src, mouseType: up, mouseCursorPosition: b, mouseButton: bt); u?.flags = f; u?.post(tap: .cghidEventTap)
    }

    /// Molette au point donné (lignes ; dy > 0 = vers le bas, dx > 0 = vers la droite)
    public static func scroll(at p: CGPoint, dx: Int = 0, dy: Int = 0) {
        move(to: p); Thread.sleep(forTimeInterval: 0.03)
        let src = CGEventSource(stateID: .hidSystemState)
        // Par paquets de 5 lignes : certaines apps plafonnent un seul gros événement
        var rx = dx, ry = dy
        while rx != 0 || ry != 0 {
            let sy = max(-5, min(5, ry)), sx = max(-5, min(5, rx))
            CGEvent(scrollWheelEvent2Source: src, units: .line, wheelCount: 2, wheel1: Int32(-sy), wheel2: Int32(-sx), wheel3: 0)?.post(tap: .cghidEventTap)
            ry -= sy; rx -= sx
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    /// Touches nommées : codes virtuels (indépendants de la disposition)
    static let nommees: [String: Int] = [
        "enter": kVK_Return, "return": kVK_Return, "entrée": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape, "esc": kVK_Escape,
        "backspace": kVK_Delete, "delete": kVK_ForwardDelete, "forwarddelete": kVK_ForwardDelete, "space": kVK_Space, "espace": kVK_Space,
        "arrowleft": kVK_LeftArrow, "left": kVK_LeftArrow, "arrowright": kVK_RightArrow, "right": kVK_RightArrow,
        "arrowup": kVK_UpArrow, "up": kVK_UpArrow, "arrowdown": kVK_DownArrow, "down": kVK_DownArrow,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown, "help": kVK_Help,
        "keypadenter": kVK_ANSI_KeypadEnter,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
        "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15]

    /// Repli QWERTY quand la disposition active ne produit pas le caractère sans majuscule (chiffres en AZERTY)
    static let ansi: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G,
        "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N,
        "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
        "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6,
        "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "\\": kVK_ANSI_Backslash,
        "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "`": kVK_ANSI_Grave]

    /// Code virtuel qui produit ce caractère avec la disposition clavier active (AZERTY : « a » n'est pas kVK_ANSI_A)
    static let parCaractere: [Character: Int] = Thread.isMainThread ? tableCaracteres() : DispatchQueue.main.sync(execute: tableCaracteres)
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

    /// Code virtuel d'une touche nommée ou d'un caractère ; nil si inconnue
    public static func keyCode(_ k: String) -> Int? {
        if let c = nommees[k.lowercased()] { return c }
        guard k.count == 1, let ch = k.lowercased().first else { return nil }
        return parCaractere[ch] ?? ansi[ch]
    }

    /// Une touche ou un raccourci (« Cmd+B », « Enter », « Shift+Tab », « cmd+shift+s »)
    public static func key(_ combo: String) throws {
        var parts = combo.split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        // « cmd++ » : la touche est « + »
        if parts.count >= 2, parts.last == "", parts[parts.count - 2] == "" { parts.removeLast(2); parts.append("+") }
        let k = parts.popLast() ?? ""
        let f = flags(parts)
        guard let code = keyCode(k) else { throw UIError("unknown key: \(k) (use a character, or enter, tab, escape, backspace, delete, space, arrows, home, end, pageup, pagedown, f1-f15)") }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: down)
            e?.flags = f
            e?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.015)
        }
    }

    /// Texte tapé comme au clavier, par paquets de caractères Unicode (indépendant de la disposition) ;
    /// les sauts de ligne et tabulations passent par les vraies touches Entrée et Tab
    public static func type(_ texte: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        var morceau: [UniChar] = []
        func envoyer() {
            var reste = morceau
            while !reste.isEmpty {
                let paquet = Array(reste.prefix(16)); reste.removeFirst(paquet.count)
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                    paquet.withUnsafeBufferPointer { e?.keyboardSetUnicodeString(stringLength: paquet.count, unicodeString: $0.baseAddress) }
                    e?.flags = []   // jamais une touche de modification héritée : « s » ne doit pas devenir Cmd+S
                    e?.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
            morceau = []
        }
        for c in texte {
            if c == "\n" || c == "\r\n" || c == "\t" {
                envoyer()
                try? key(c == "\t" ? "tab" : "return")
            } else { morceau += Array(String(c).utf16) }
        }
        envoyer()
    }
}
