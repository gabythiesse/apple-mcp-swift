// Voie Apple Events bruts : les opérations chaudes (do JavaScript, URL, titre, liste des onglets) sans AppleScript.
// Sonde 28 : compiler un script coûte ~20 ms à chaque appel, un Apple Event construit à la main ~0,4 ms.
// AESendMessage est sûr hors du fil principal : ces appels se font depuis la file stdio, sans attendre la RunLoop.
import Foundation
import AppKit

enum AE {
    static let bundle = "com.apple.Safari"

    static func code(_ s: String) -> FourCharCode { s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) } }

    // MARK: - Spécificateurs d'objets (équivalents de « tab 2 of window id 123 »)

    static func spec(_ want: String, _ from: NSAppleEventDescriptor, _ form: String, _ seld: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let r = NSAppleEventDescriptor.record().coerce(toDescriptorType: typeObjectSpecifier)!
        r.setDescriptor(NSAppleEventDescriptor(typeCode: code(want)), forKeyword: AEKeyword(keyAEDesiredClass))
        r.setDescriptor(from, forKeyword: AEKeyword(keyAEContainer))
        r.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: AEKeyword(keyAEKeyForm))
        r.setDescriptor(seld, forKeyword: AEKeyword(keyAEKeyData))
        return r
    }
    static var all: NSAppleEventDescriptor {
        var a = code("all ")
        return NSAppleEventDescriptor(descriptorType: DescType(typeAbsoluteOrdinal), bytes: &a, length: 4)!
    }
    static func window(_ id: Int) -> NSAppleEventDescriptor { spec("cwin", .null(), "ID  ", NSAppleEventDescriptor(int32: Int32(id))) }
    static var everyWindow: NSAppleEventDescriptor { spec("cwin", .null(), "indx", all) }
    static func tab(_ r: TabRef) -> NSAppleEventDescriptor { spec("bTab", window(r.fenetre), "indx", NSAppleEventDescriptor(int32: Int32(r.index))) }
    static func everyTab(of w: NSAppleEventDescriptor) -> NSAppleEventDescriptor { spec("bTab", w, "indx", all) }
    static func prop(_ p: String, of o: NSAppleEventDescriptor) -> NSAppleEventDescriptor { spec("prop", o, "prop", NSAppleEventDescriptor(typeCode: code(p))) }

    // MARK: - Envoi

    /// Envoie un événement à Safari et renvoie le paramètre direct de la réponse (nil = missing value).
    /// Délai court par défaut : un Safari bloqué (dialogue, autorisation) rend une erreur au lieu de geler l'appel.
    @discardableResult
    static func send(_ classe: String, _ id: String, direct: NSAppleEventDescriptor? = nil,
                     params: [String: NSAppleEventDescriptor] = [:], timeout: TimeInterval = 5) throws -> NSAppleEventDescriptor? {
        let ev = NSAppleEventDescriptor.appleEvent(withEventClass: code(classe), eventID: code(id),
                                                   targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundle),
                                                   returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let direct { ev.setParam(direct, forKeyword: keyDirectObject) }
        for (k, v) in params { ev.setParam(v, forKeyword: code(k)) }
        var essai = 0
        while true {
            do {
                let rep = try ev.sendEvent(options: [.waitForReply], timeout: timeout)
                if let n = rep.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, n != 0 {
                    throw MCPError(message(Int(n), rep.paramDescriptor(forKeyword: keyErrorString)?.stringValue))
                }
                return rep.paramDescriptor(forKeyword: keyDirectObject)
            } catch let e as NSError where e.domain == NSOSStatusErrorDomain {
                // Safari pas lancé : on le lance en arrière-plan, comme le ferait « tell application »
                if e.code == -600 && essai == 0 { essai += 1; try lancerSafari(); continue }
                throw MCPError(message(e.code, nil))
            }
        }
    }

    static func get(_ objet: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor? {
        try send("core", "getd", direct: objet)
    }
    static func set(_ objet: NSAppleEventDescriptor, _ valeur: NSAppleEventDescriptor) throws {
        try send("core", "setd", direct: objet, params: ["data": valeur])
    }

    /// do JavaScript dans un onglet : renvoie la valeur du script convertie en chaîne (nil pour undefined ou une erreur de syntaxe)
    static func js(_ code: String, in r: TabRef, timeout: TimeInterval = 5) throws -> String? {
        let d = try send("sfri", "dojs", direct: NSAppleEventDescriptor(string: code), params: ["dcnm": tab(r)], timeout: timeout)
        guard let d, !d.isMissing else { return nil }
        return d.stringValue
    }

    private static func lancerSafari() throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { throw MCPError("Safari not found") }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        let sem = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 10)
        for _ in 0..<50 where NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty { Thread.sleep(forTimeInterval: 0.1) }
    }

    static func message(_ n: Int, _ m: String?) -> String {
        switch n {
        case -1743: return "Automation denied: System Settings > Privacy & Security > Automation > AppleMCP > turn on Safari"
        case -1719, -1728: return "window or tab not found"
        case -1712: return "Safari did not answer in time (a dialog or a busy page?)"
        case -600: return "Safari is not running"
        default:
            if let m, m.contains("JavaScript") && (m.contains("Apple Events") || m.contains("Apple Event")) {
                return "JavaScript unavailable: enable Develop > Allow JavaScript from Apple Events in Safari"
            }
            return (m ?? "Apple Event error") + " (\(n))"
        }
    }

    // MARK: - Fenêtres et onglets

    /// Identifiants des fenêtres visibles, de l'avant vers l'arrière (une fenêtre fermée reste listée par Safari, invisible)
    static func visibleWindowIDs() throws -> [Int] {
        let ids = try get(prop("ID  ", of: everyWindow))?.ints ?? []
        let vis = try get(prop("pvis", of: everyWindow))?.items.map(\.bool) ?? []
        return zip(ids, vis).filter(\.1).map(\.0)
    }

    /// Onglet actif de la fenêtre de premier plan
    static func currentTab() throws -> TabRef {
        guard let w = try visibleWindowIDs().first else { throw MCPError("no Safari window open") }
        guard let i = try get(prop("pidx", of: prop("cTab", of: window(w))))?.int else { throw MCPError("no current tab") }
        return TabRef(fenetre: w, index: i)
    }

    /// Titre et URL d'un onglet
    static func titleURL(_ r: TabRef) throws -> (String, String) {
        let t = try get(prop("pnam", of: tab(r)))?.string ?? ""
        let u = try get(prop("pURL", of: tab(r)))?.string ?? "about:blank"
        return (t, u)
    }
}
