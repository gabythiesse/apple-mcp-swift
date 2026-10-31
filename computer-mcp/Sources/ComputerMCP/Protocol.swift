// Protocole MCP écrit à la main (repris des autres serveurs) : initialize, ping, tools/list, tools/call.
// Un outil renvoie du texte (String), du JSON, ou un Contenu (image PNG + texte).
import Foundation

typealias JSON = [String: Any]

struct MCPError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Réponse riche : blocs MCP tels quels (image base64, texte)
struct Contenu {
    let blocs: [JSON]
    static func image(_ png: Data, _ legende: String) -> Contenu {
        Contenu(blocs: [["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"], ["type": "text", "text": legende]])
    }
}

enum Stdio {
    private static let lock = NSLock()

    /// stdout est réservé au protocole : une ligne JSON par message, rien d'autre
    static func send(_ obj: Any) {
        guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else {
            log("response not serializable")
            return
        }
        data.append(0x0A)
        lock.lock(); defer { lock.unlock() }
        FileHandle.standardOutput.write(data)
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data(("[computer-mcp] " + message + "\n").utf8))
}

func jsonText(_ value: Any) -> String {
    if let s = value as? String { return s }
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes, .sortedKeys]) else {
        return "\(value)"
    }
    return String(decoding: data, as: UTF8.self)
}

enum Server {
    static let name = "computer"
    static let version = "1.0.0"
    static let instructions = """
    Uses the Mac like a person, in any app: sees the screen, reads any window through Accessibility, clicks, types, answers dialogs.
    Never ask the human to click: dialogs (Save As, Allow downloads, Open in app, Leave page, Finder panels, Mail sheets…) are answered with answer_dialog, \
    or automatically with watch_dialogs before an action that will raise them.
    To look: windows (apps and windows), dialogs (every open alert, sheet or panel with its buttons), find (a window's Accessibility tree, one line per \
    element with a ref such as a12), screenshot (only when the tree is not enough: canvas, images, layout).
    To act: click (ref, button title in an app, or screen point), type, press (shortcuts), scroll, drag, move, menu ("File > Export…"), app (launch, activate, quit).
    The target app is brought to the front only for real mouse and keyboard events, then the previous app gets the front back. \
    Actions report any dialog they made appear: answer it in the next call. Coordinates are screen points (origin top left of the main display).
    Only macOS's own privacy and password windows refuse synthetic clicks: the tool then says so in one sentence, they are set once at install.
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
                if let c = value as? Contenu { return result(id, ["content": c.blocs]) }
                return result(id, ["content": [["type": "text", "text": jsonText(value)]]])
            } catch {
                return result(id, ["content": [["type": "text", "text": "Error: \(error)"]], "isError": true])
            }
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]]
        }
    }

    private static func result(_ id: Any, _ value: Any) -> JSON {
        ["jsonrpc": "2.0", "id": id, "result": value]
    }
}

// Lecture tolérante des arguments
extension Dictionary where Key == String, Value == Any {
    func has(_ k: String) -> Bool { self[k] != nil && !(self[k] is NSNull) }
    func string(_ k: String) -> String? { self[k] as? String }
    func nonEmpty(_ k: String) -> String? {
        guard let s = self[k] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
    func req(_ k: String) throws -> String {
        guard let s = nonEmpty(k) else { throw MCPError("missing parameter: \(k)") }
        return s
    }
    func bool(_ k: String) -> Bool? {
        if let b = self[k] as? Bool { return b }
        if let s = self[k] as? String { return ["true", "yes", "oui", "1"].contains(s.lowercased()) }
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
