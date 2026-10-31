// Désignation des cibles : apps (nom, bundle, pid), refs stables d'éléments AX, verrou des actions.
import Foundation
import AppKit
import ApplicationServices
import MacUI

/// Une seule action réelle à la fois (outils et surveillance des dialogues ne s'entremêlent jamais)
let actionLock = NSRecursiveLock()
func enAction<T>(_ body: () throws -> T) rethrows -> T { actionLock.lock(); defer { actionLock.unlock() }; return try body() }

/// Refs stables : le même élément AX (CFEqual) garde le même « a12 » tant que le serveur tourne
enum Refs {
    private static let lock = NSLock()
    private static var parCle: [AXKey: Int] = [:]
    private static var parId: [Int: AXUIElement] = [:]
    private static var suivant = 1

    static func ref(_ el: AXUIElement) -> String {
        lock.lock(); defer { lock.unlock() }
        let k = AXKey(el)
        if let i = parCle[k] { return "a\(i)" }
        if parId.count > 30000 { parCle.removeAll(); parId.removeAll() }   // borne mémoire : les anciennes refs se perdent
        let i = suivant; suivant += 1
        parCle[k] = i; parId[i] = el
        return "a\(i)"
    }

    static func get(_ s: String) throws -> AXUIElement {
        let n = Int(s.trimmingCharacters(in: .whitespaces).drop(while: { !$0.isNumber })) ?? -1
        lock.lock(); let el = parId[n]; lock.unlock()
        guard let el else { throw MCPError("unknown ref \(s): call find or dialogs first") }
        guard AX.alive(el) else { throw MCPError("ref \(s) is gone (its window closed or changed): call find again") }
        return el
    }
}

enum Apps {
    static var running: [NSRunningApplication] {
        Running.apps()
    }

    /// App en cours d'exécution : pid, bundle id, ou nom (exact, puis début du nom), insensible à la casse et aux accents
    static func find(_ q: String) -> NSRunningApplication? {
        if let p = Int32(q), let a = Running.app(p) { return a }
        let n = normalise(q.hasSuffix(".app") ? String(q.dropLast(4)) : q)
        let apps = running
        if let a = apps.first(where: { normalise($0.bundleIdentifier ?? "") == n }) { return a }
        let nommees = apps.filter { normalise($0.localizedName ?? "") == n || normalise($0.bundleURL?.deletingPathExtension().lastPathComponent ?? "") == n }
        if let a = nommees.first(where: { $0.activationPolicy == .regular }) ?? nommees.first { return a }
        return apps.first { $0.activationPolicy == .regular && normalise($0.localizedName ?? "").hasPrefix(n) }
    }

    static func require(_ q: String) throws -> NSRunningApplication {
        guard let a = find(q) else { throw MCPError("\(q) is not running (app tool, action launch, starts it)") }
        return a
    }

    /// App désignée par `app` dans les arguments, sinon l'app au premier plan
    static func target(_ a: JSON) throws -> NSRunningApplication {
        if let q = a.nonEmpty("app") { return try require(q) }
        guard let f = Front.frontmost else { throw MCPError("no app in front") }
        return f
    }

    static func name(_ pid: pid_t) -> String { Running.app(pid)?.localizedName ?? "pid \(pid)" }

    /// App installée (pour la lancer) : bundle id, chemin .app, ou nom affiché (localisé ou non) dans les dossiers d'apps
    static func installed(_ q: String) -> URL? {
        if q.hasPrefix("/"), FileManager.default.fileExists(atPath: q) { return URL(fileURLWithPath: q) }
        if q.contains("."), !q.hasSuffix(".app"), let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: q) { return u }
        let n = normalise(q.hasSuffix(".app") ? String(q.dropLast(4)) : q)
        let fm = FileManager.default
        let dossiers = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                        NSHomeDirectory() + "/Applications", "/System/Library/CoreServices", "/System/Library/CoreServices/Applications",
                        "/System/Volumes/Preboot/Cryptexes/App/System/Applications"]
        var prefixe: URL?
        for d in dossiers {
            for f in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where f.hasSuffix(".app") {
                let chemin = d + "/" + f
                let noms = [String(f.dropLast(4)), fm.displayName(atPath: chemin)].map { normalise($0.hasSuffix(".app") ? String($0.dropLast(4)) : $0) }
                if noms.contains(n) { return URL(fileURLWithPath: chemin) }
                if prefixe == nil, noms.contains(where: { $0.hasPrefix(n) }) { prefixe = URL(fileURLWithPath: chemin) }
            }
        }
        return prefixe
    }
}

/// Description courte d'un élément : rôle "titre"
func decrire(_ el: AXUIElement) -> String {
    let r = AX.role(el).replacingOccurrences(of: "AX", with: "")
    let l = AX.label(el)
    return (r.isEmpty ? "element" : r.prefix(1).lowercased() + r.dropFirst()) + (l.isEmpty ? "" : " \"\(l.prefix(60))\"")
}

func entier(_ v: CGFloat) -> Int { Int(v.rounded()) }
func rect(_ r: CGRect) -> String { "\(entier(r.minX)),\(entier(r.minY)) \(entier(r.width))x\(entier(r.height))" }
