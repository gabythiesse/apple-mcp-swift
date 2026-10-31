// Voie AppleScript : NSAppleScript dans le processus (un script par appel d'outil, tout le lot d'un coup)
import Foundation
import AppKit

/// Référence d'onglet : identifiant de fenêtre AppleScript + index (de gauche à droite, à partir de 1)
struct TabRef: Hashable {
    let fenetre: Int
    let index: Int
    var json: JSON { ["window_id": fenetre, "index": index] }
    var spec: String { "tab \(index) of window id \(fenetre)" }
}

enum AS {
    /// Exécute un script sur la file principale (NSAppleScript n'est pas fait pour plusieurs threads)
    static func run(_ source: String) throws -> NSAppleEventDescriptor {
        var result: Result<NSAppleEventDescriptor, MCPError>!
        let work = {
            var err: NSDictionary?
            let t0 = Date()
            defer {
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                if ms > 1000 { log("slow AppleScript (\(ms) ms) : " + source.split(separator: "\n").prefix(3).joined(separator: " ⏎ ")) }
            }
            // Délai court : un Safari bloqué (dialogue, autorisation) renvoie une erreur au lieu de geler l'appel 2 min
            guard let script = NSAppleScript(source: "with timeout of 20 seconds\n" + source + "\nend timeout") else { result = .failure(MCPError("invalid script")); return }
            let d = script.executeAndReturnError(&err)
            if let err { result = .failure(MCPError(message(err))) } else { result = .success(d) }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        return try result.get()
    }

    private static func message(_ err: NSDictionary) -> String {
        let n = err[NSAppleScript.errorNumber] as? Int ?? 0
        let m = err[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
        if n == -25211 || m.localizedCaseInsensitiveContains("assist") || m.contains("accès d’aide") {
            return "Accessibility denied: System Settings > Privacy & Security > Accessibility > turn on AppleMCP"
        }
        switch n {
        case -1743: return "Automation denied: System Settings > Privacy & Security > Automation > AppleMCP > turn on Safari"
        case -1719, -1728: return "window or tab not found (\(m))"
        default: return m + " (\(n))"
        }
    }

    /// Littéral de chaîne AppleScript
    static func lit(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Liste AppleScript de références {fenetre_id, index}
    static func refsList(_ refs: [TabRef]) -> String {
        "{" + refs.map { "{\($0.fenetre), \($0.index)}" }.joined(separator: ", ") + "}"
    }

    /// Identifiants des fenêtres visibles (Apple Events bruts, voir AppleEvents.swift)
    static func visibleWindowIDs() throws -> [Int] { try AE.visibleWindowIDs() }

    /// Onglet actif de la fenêtre de premier plan
    static func currentTab() throws -> TabRef { try AE.currentTab() }

    /// Safari au premier plan, sans passer par la commande AppleScript activate (qui attend une réponse d'activation)
    static func activerSafari() {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first?.activate()
    }

    /// Nouvelle fenêtre privée par le menu Fichier de Safari, pressé directement par l'Accessibilité (AXUIElement) :
    /// aucune Automatisation « System Events » n'est nécessaire, seule l'autorisation Accessibilité. Renvoie son identifiant.
    static func newPrivateWindow() throws -> Int {
        let avant = Set(try visibleWindowIDs())
        activerSafari()
        guard AXIsProcessTrusted() else { throw MCPError(FenetreTravail.accessibilite) }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first?.processIdentifier,
              let barre = AX.attr(AXUIElementCreateApplication(pid), kAXMenuBarAttribute) else { throw MCPError("Safari menu bar not accessible") }
        // Menu Fichier (2e menu après le menu Safari), puis l'élément dont le titre parle de fenêtre privée (fr / en)
        let menus = AX.children(barre as! AXUIElement)
        let fichier = menus.first { ["Fichier", "File"].contains(AX.str($0, kAXTitleAttribute)) } ?? (menus.count > 2 ? menus[2] : nil)
        guard let f = fichier, let sous = AX.children(f).first,
              let item = AX.children(sous).first(where: { let t = AX.str($0, kAXTitleAttribute).lowercased(); return t.contains("privée") || t.contains("private") })
        else { throw MCPError("\"New Private Window\" menu item not found") }
        AX.press(item)
        for _ in 0..<40 {
            let nouv = Set(try visibleWindowIDs()).subtracting(avant)
            if nouv.count == 1 { return nouv.first! }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw MCPError("the private window could not be located")
    }

    /// Script JavaScript qui renvoie toujours une chaîne : « § » + résultat, ou « §ERR » + message
    static func jsWrapper(_ code: String) -> String {
        let t = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = ["throw ", "var ", "let ", "const ", "if ", "if(", "for ", "for(", "while", "try", "function ", "class ", "switch", "do "]
        let simple = !t.contains("return") && !t.contains(";") && !t.contains("\n") && !instructions.contains(where: t.hasPrefix)
        let body = simple ? "return (\(t));" : t
        return "(function(){try{var r=(function(){\n\(body)\n})();return '§'+(r===undefined||r===null?'':(typeof r==='string'?r:JSON.stringify(r)));}catch(e){return '§ERR'+((e&&e.message)||String(e));}})()"
    }

    /// Attend la fin du chargement : readyState complete et adresse différente de l'adresse avant navigation.
    /// Une sonde par onglet toutes les 30 ms (Apple Event brut, < 1 ms). Renvoie titre, adresse et pret (false si le délai est dépassé).
    static func waitLoaded(_ refs: [TabRef], before: [TabRef: String] = [:], timeout: TimeInterval = 15) -> [TabRef: (titre: String, url: String, pret: Bool)] {
        var restant = refs
        var out: [TabRef: (titre: String, url: String, pret: Bool)] = [:]
        let fin = Date().addingTimeInterval(timeout)
        while !restant.isEmpty {
            var encore: [TabRef] = []
            for ref in restant {
                // État, adresse et titre lus dans le document lui-même : l'URL de l'onglet change avant que la page ne remplace l'ancienne
                let p = ((try? AE.js("document.readyState+'\\u001f'+location.href+'\\u001f'+document.title", in: ref, timeout: 2)) ?? nil)?
                    .components(separatedBy: "\u{1f}") ?? []
                let etat = p.first ?? "", href = p.count > 1 ? p[1] : "", titre = p.count > 2 ? p[2] : ""
                let pret = etat == "complete" && href != before[ref] && (href != "about:blank" || before[ref] == nil)
                out[ref] = (titre, href, pret)
                if !pret { encore.append(ref) }
            }
            restant = encore
            if restant.isEmpty || Date() >= fin { break }
            Thread.sleep(forTimeInterval: 0.03)
        }
        return out
    }
}

/// Lecture des descripteurs Apple Event
extension NSAppleEventDescriptor {
    var items: [NSAppleEventDescriptor] {
        guard descriptorType == typeAEList else { return [] }
        return numberOfItems > 0 ? (1...numberOfItems).compactMap { atIndex($0) } : []
    }
    var isMissing: Bool { descriptorType == typeType && typeCodeValue == 0x6D736E67 /* msng */ || descriptorType == typeNull }
    var string: String? { isMissing ? nil : stringValue }
    var int: Int? { isMissing ? nil : Int(int32Value) }
    var bool: Bool { descriptorType == typeTrue || (descriptorType == typeBoolean && booleanValue) }
    var ints: [Int] { descriptorType == typeAEList ? items.compactMap(\.int) : (int.map { [$0] } ?? []) }
}
