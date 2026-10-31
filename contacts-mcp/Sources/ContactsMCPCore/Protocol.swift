// Protocole MCP écrit à la main : initialize, ping, tools/list, tools/call
import Foundation

typealias JSON = [String: Any]

struct MCPError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum Stdio {
    private static let lock = NSLock()

    /// stdout est réservé au protocole : une ligne JSON par message, rien d'autre
    static func send(_ obj: Any) {
        guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else {
            log("réponse non sérialisable")
            return
        }
        data.append(0x0A)
        lock.lock(); defer { lock.unlock() }
        FileHandle.standardOutput.write(data)
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data(("[contacts-mcp] " + message + "\n").utf8))
}

func jsonText(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes, .sortedKeys]) else {
        return "\(value)"
    }
    return String(decoding: data, as: UTF8.self)
}

enum Server {
    static let name = "contacts"
    static let version = "1.0.0"
    static let instructions = """
    Pilote l'app Contacts du Mac : comptes, groupes et sous-groupes, contacts (tous les champs, note, photo), recherche, doublons, fusion, vCard. \
    Chaque lecture et création renvoie des identifiants stables à réutiliser. Les écritures prennent des listes (lot). \
    Dates : AAAA-MM-JJ, ou --MM-JJ pour un anniversaire sans année. Libellés : mobile, iphone, principal, domicile, travail, autre… ou texte libre. \
    Les suppressions se font uniquement par identifiant et sont définitives.
    """

    static func handle(_ msg: JSON) -> JSON? {
        // Notification (pas d'id) : aucune réponse
        guard let id = msg["id"], !(id is NSNull) else { return nil }
        let method = msg["method"] as? String ?? ""
        let params = msg["params"] as? JSON ?? [:]

        switch method {
        case "initialize":
            return result(id, [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": name, "version": version],
                "instructions": instructions,
            ])
        case "ping":
            return result(id, [String: Any]())
        case "tools/list":
            return result(id, ["tools": Tools.definitions])
        case "tools/call":
            let tool = params["name"] as? String ?? ""
            let args = params["arguments"] as? JSON ?? [:]
            do {
                let value = try Tools.call(tool, args)
                return result(id, ["content": [["type": "text", "text": jsonText(value)]]])
            } catch {
                return result(id, ["content": [["type": "text", "text": "Erreur : \(error)"]], "isError": true])
            }
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Méthode inconnue : \(method)"]]
        }
    }

    private static func result(_ id: Any, _ value: Any) -> JSON {
        ["jsonrpc": "2.0", "id": id, "result": value]
    }
}

// Lecture tolérante des arguments : null ou "" = effacer, clé absente = ne pas toucher
extension Dictionary where Key == String, Value == Any {
    func has(_ k: String) -> Bool { self[k] != nil }
    func string(_ k: String) -> String? { self[k] as? String }
    func nonEmpty(_ k: String) -> String? {
        guard let s = self[k] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
    func req(_ k: String) throws -> String {
        guard let s = nonEmpty(k) else { throw MCPError("paramètre manquant : \(k)") }
        return s
    }
    func bool(_ k: String) -> Bool? {
        if let b = self[k] as? Bool { return b }
        if let s = self[k] as? String { return ["true", "oui", "1"].contains(s.lowercased()) }
        return nil
    }
    func int(_ k: String) -> Int? { (self[k] as? NSNumber)?.intValue ?? (self[k] as? String).flatMap { Int($0) } }
    func double(_ k: String) -> Double? { (self[k] as? NSNumber)?.doubleValue ?? (self[k] as? String).flatMap { Double($0) } }
    func strings(_ k: String) -> [String]? {
        if let s = self[k] as? String {
            if s.hasPrefix("["), let arr = decoded(s) as? [Any] { return arr.compactMap { $0 as? String } }
            return s.isEmpty ? [] : [s]
        }
        return (self[k] as? [Any])?.compactMap { $0 as? String }
    }
    func objects(_ k: String) -> [JSON]? {
        if let s = self[k] as? String, let arr = decoded(s) as? [Any] { return arr.compactMap { $0 as? JSON } }
        return (self[k] as? [Any])?.compactMap { $0 as? JSON }
    }
    func object(_ k: String) -> JSON? {
        if let s = self[k] as? String { return decoded(s) as? JSON }
        return self[k] as? JSON
    }
    private func decoded(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8)) }
}
