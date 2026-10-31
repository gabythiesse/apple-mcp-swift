// Pont vers la bibliothèque mcp.js : injection une fois par page, appels minuscules, jobs asynchrones sondés toutes les 30 ms
import Foundation

/// La page a été remplacée pendant l'opération (navigation, rechargement) : le job en cours est perdu
struct PageNavigated: Error, CustomStringConvertible { var description: String { "the page navigated during the operation" } }

enum Page {
    /// Source de mcp.js, embarquée dans le binaire (Package.swift : resources .embedInCode)
    static let source = String(decoding: PackageResources.mcp_js, as: UTF8.self)
    /// Version = empreinte du fichier : une page qui a une ancienne bibliothèque reçoit la nouvelle, sans numéro à tenir à jour
    static let version: Int = source.utf8.reduce(5381) { ($0 &* 33 &+ Int($1)) & 0x7fffffff }
    /// Ce qui part dans la page : le fichier sans ses lignes de commentaire ni son indentation (lisible dans le dépôt, léger à l'injection)
    static let lib: String = source.split(separator: "\n", omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("//") }
        .joined(separator: "\n")
        .replacingOccurrences(of: "var V = 0;", with: "var V = \(version);")
    private static let absente = "\u{0}nolib"

    /// Littéral JavaScript d'une valeur JSON (chaîne, nombre, objet…)
    static func lit(_ v: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .withoutEscapingSlashes]) else { return "null" }
        return String(decoding: d, as: UTF8.self)
    }

    /// Évalue `expr` (qui s'appuie sur __mcp et renvoie une chaîne JSON) ; injecte la bibliothèque si la page ne l'a pas.
    /// La première ligne du script est l'en-tête : le code de l'appelant commence à la ligne 2 (numéros d'erreur de run_js).
    static func raw(_ expr: String, in tab: TabRef, timeout: TimeInterval = 5) throws -> JSON {
        let script = "window.__mcp&&__mcp.v===\(version)?\(expr):\(lit(absente))"
        var r = try AE.js(script, in: tab, timeout: timeout)
        if r == absente {
            _ = try AE.js(lib + "\n;'ok'", in: tab, timeout: 5)
            r = try AE.js(script, in: tab, timeout: timeout)
            if r == absente { throw MCPError("could not load the helper library in this page (no document, or a PDF/image viewer)") }
        }
        guard let r else { throw MCPError("no result: JavaScript syntax error, or the page has no document") }
        guard let o = (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? JSON else { throw MCPError("unexpected page answer: \(r.prefix(200))") }
        return o
    }

    /// Opération `op` de mcp.js. Les jobs asynchrones sont sondés jusqu'au résultat ou au délai ; les dialogues interceptés
    /// pendant l'opération sont cumulés sous "dialogs". Une erreur de la page devient une MCPError.
    static func call(_ op: String, _ args: JSON = [:], in tab: TabRef, timeout: TimeInterval = 10) throws -> JSON {
        try poll(raw("__mcp.run(\(lit(op)),\(lit(args)))", in: tab, timeout: min(timeout, 5)), in: tab, timeout: timeout)
    }

    /// Suit un éventuel job jusqu'au résultat
    static func poll(_ premier: JSON, in tab: TabRef, timeout: TimeInterval) throws -> JSON {
        var o = premier
        var dialogues = o["dialogs"] as? [Any] ?? []
        let fin = Date().addingTimeInterval(timeout)
        while let id = o["job"] as? Int {
            if Date() >= fin {
                _ = try? AE.js("window.__mcp&&__mcp.jobs.delete(\(id))", in: tab, timeout: 1)
                throw MCPError("timed out after \(Int(timeout * 1000)) ms")
            }
            Thread.sleep(forTimeInterval: 0.03)
            do { o = try raw("__mcp.run('poll',{id:\(id)})", in: tab, timeout: 2) }
            catch let e as MCPError where e.description.contains("did not answer") { continue }   // page occupée : on resonde
            if o["lost"] as? Bool == true { throw PageNavigated() }
            if o["pending"] as? Bool == true { o["job"] = id }
            dialogues += o["dialogs"] as? [Any] ?? []
        }
        if let e = o["error"] as? String {
            var m = e
            if let l = o["line"] as? Int { m += " (line \(l))" }
            throw MCPError(m)
        }
        o["dialogs"] = dialogues.isEmpty ? nil : dialogues
        return o
    }
}
