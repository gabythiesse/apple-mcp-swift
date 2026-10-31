// Voie index : base « Envelope Index » de Mail, ouverte en LECTURE SEULE (jamais d'écriture)
import Foundation
import SQLite3

/// Boîte telle que la voit l'index. id = "<compte_id>/<chemin>" ou "local/<chemin>"
struct Boite {
    let rowid: Int64
    let id: String
    let compte: String
    let chemin: String
    let total: Int
    let nonLus: Int
    var nom: String { chemin.split(separator: "/").last.map(String.init) ?? chemin }
}

enum Index {
    private static var db: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func path() -> String? {
        let base = NSHomeDirectory() + "/Library/Mail"
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: base)) ?? [])
            .filter { $0.hasPrefix("V") }.compactMap { Int($0.dropFirst()) }.sorted()
        guard let v = versions.last else { return nil }
        return "\(base)/V\(v)/MailData/Envelope Index"
    }

    static func open() throws -> OpaquePointer {
        if let db { return db }
        guard let p = path() else { throw accesErr }
        var h: OpaquePointer?
        guard sqlite3_open_v2("file:" + p + "?mode=ro", &h, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              sqlite3_exec(h, "SELECT 1 FROM messages LIMIT 1", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(h)
            throw accesErr
        }
        sqlite3_busy_timeout(h, 2000)
        db = h
        return h!
    }

    private static let accesErr = MCPError("Mail's index is not readable: give the Claude app Full Disk Access (System Settings > Privacy & Security > Full Disk Access), then relaunch it.")

    /// Requête paramétrée : valeurs Int64, Double, String ou nil
    static func rows(_ sql: String, _ binds: [Any] = []) throws -> [[Any?]] {
        let h = try open()
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &st, nil) == SQLITE_OK else {
            throw MCPError("index: \(String(cString: sqlite3_errmsg(h)))")
        }
        defer { sqlite3_finalize(st) }
        for (i, v) in binds.enumerated() {
            let k = Int32(i + 1)
            switch v {
            case let x as Int: sqlite3_bind_int64(st, k, Int64(x))
            case let x as Int64: sqlite3_bind_int64(st, k, x)
            case let x as Double: sqlite3_bind_double(st, k, x)
            case let x as String: sqlite3_bind_text(st, k, x, -1, transient)
            default: sqlite3_bind_null(st, k)
            }
        }
        var out: [[Any?]] = []
        while sqlite3_step(st) == SQLITE_ROW {
            out.append((0..<sqlite3_column_count(st)).map { c -> Any? in
                switch sqlite3_column_type(st, c) {
                case SQLITE_INTEGER: return sqlite3_column_int64(st, c)
                case SQLITE_FLOAT: return sqlite3_column_double(st, c)
                case SQLITE_TEXT: return String(cString: sqlite3_column_text(st, c))
                default: return nil
                }
            })
        }
        return out
    }

    static func maxRowid() throws -> Int64 { try rows("SELECT ifnull(max(ROWID),0) FROM messages").first?[0] as? Int64 ?? 0 }

    // MARK: - Boîtes

    static func boites() throws -> [Boite] {
        try rows("SELECT ROWID, url, total_count, unread_count FROM mailboxes").compactMap { r in
            guard let url = r[1] as? String, let (compte, chemin) = parse(url) else { return nil }
            return Boite(rowid: r[0] as! Int64, id: "\(compte)/\(chemin)", compte: compte, chemin: chemin,
                         total: Int(r[2] as? Int64 ?? 0), nonLus: Int(r[3] as? Int64 ?? 0))
        }
    }

    /// "imap://UUID/A/B%20C" → ("UUID", "A/B C") ; "local://UUID/X" → ("local", "X")
    static func parse(_ url: String) -> (String, String)? {
        guard let r = url.range(of: "://") else { return nil }
        let scheme = url[..<r.lowerBound]
        let rest = url[r.upperBound...]
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let uuid = String(rest[..<slash])
        let chemin = (String(rest[rest.index(after: slash)...]).removingPercentEncoding ?? "").precomposedStringWithCanonicalMapping
        guard !chemin.isEmpty else { return nil }
        return (scheme == "local" ? "local" : uuid, chemin)
    }

    private static let speciaux: [String: Set<String>] = [
        "envoyes": ["Sent Messages", "Sent", "Sent Mail", "Sent Items", "Envoyés", "Messages envoyés", "Éléments envoyés"],
        "brouillons": ["Drafts", "Brouillons"],
        "corbeille": ["Deleted Messages", "Trash", "Deleted Items", "Bin", "Corbeille", "Éléments supprimés"],
        "indesirables": ["Junk", "Spam", "Junk E-mail", "Courrier indésirable", "Indésirables"],
        "sortie": ["Outbox", "Boîte d'envoi"],
    ]
    static func est(_ b: Boite, _ type: String) -> Bool { speciaux[type]?.contains(b.nom) ?? false }
    static func estSpeciale(_ b: Boite) -> Bool { speciaux.keys.contains { est(b, $0) } }
}

/// Référence AppleScript d'une boîte à partir de son identifiant
func refBoite(_ id: String) throws -> String {
    guard let slash = id.firstIndex(of: "/") else { throw MCPError("invalid mailbox id: \(id) (expected \"<account_id>/<path>\", see list_mailboxes)") }
    let compte = String(id[..<slash]), chemin = String(id[id.index(after: slash)...])
    return compte == "local" ? "mailbox \(AS.q(chemin))" : "mailbox \(AS.q(chemin)) of account id \(AS.q(compte))"
}

/// Message id → référence AppleScript (via la boîte connue de l'index)
func refsMessages(_ ids: [Int]) throws -> [Int: String] {
    guard !ids.isEmpty else { return [:] }
    let parBoite = Dictionary(uniqueKeysWithValues: try Index.boites().map { ($0.rowid, $0.id) })
    let rows = try Index.rows("SELECT ROWID, mailbox FROM messages WHERE ROWID IN (\(ids.map(String.init).joined(separator: ",")))")
    var out: [Int: String] = [:]
    for r in rows {
        guard let id = r[0] as? Int64, let mb = r[1] as? Int64, let b = parBoite[mb] else { continue }
        out[Int(id)] = "(first message of \(try refBoite(b)) whose id is \(id))"
    }
    return out
}
