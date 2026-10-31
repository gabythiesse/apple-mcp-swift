// Voie fichiers : données de Safari en LECTURE SEULE (Bookmarks.plist, History.db, SafariTabs.db).
// Jamais d'écriture : ce sont les vraies données de l’utilisateur, synchronisées par iCloud. Exige l'Accès complet au disque.
import Foundation
import SQLite3

enum Fichiers {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static let bookmarks = "\(home)/Library/Safari/Bookmarks.plist"
    static let history = "\(home)/Library/Safari/History.db"
    static let tabs = "\(home)/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db"

    static let accesRefuse = "lecture refusée : donner l'Accès complet au disque à Claude (Réglages Système > Confidentialité et sécurité)"

    // MARK: - Bookmarks.plist (cache selon la date de modification)

    private static var cache: (date: Date, racine: [String: Any])?

    static func racineFavoris() throws -> [String: Any] {
        let attrs = try? FileManager.default.attributesOfItem(atPath: bookmarks)
        let mtime = attrs?[.modificationDate] as? Date ?? Date()
        if let c = cache, c.date == mtime { return c.racine }
        guard let d = FileManager.default.contents(atPath: bookmarks) else { throw MCPError(accesRefuse) }
        guard let r = try PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else {
            throw MCPError("Bookmarks.plist illisible")
        }
        cache = (mtime, r)
        return r
    }

    // MARK: - SQLite en lecture seule

    final class DB {
        let db: OpaquePointer
        init(_ path: String) throws {
            var p: OpaquePointer?
            guard FileManager.default.isReadableFile(atPath: path) || FileManager.default.fileExists(atPath: path) else { throw MCPError("fichier absent : \(path)") }
            guard sqlite3_open_v2("file:\(path)?mode=ro", &p, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let p else {
                throw MCPError(Fichiers.accesRefuse)
            }
            db = p
            sqlite3_busy_timeout(db, 2000)
        }
        deinit { sqlite3_close(db) }

        /// Exécute une requête ; les paramètres sont des String, Double ou Int
        func rows(_ sql: String, _ params: [Any] = []) throws -> [[Any?]] {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
                let m = String(cString: sqlite3_errmsg(db))
                throw MCPError(m.contains("authoriz") || m.contains("unable to open") ? Fichiers.accesRefuse : "requête : \(m)")
            }
            defer { sqlite3_finalize(st) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (i, v) in params.enumerated() {
                let k = Int32(i + 1)
                switch v {
                case let s as String: sqlite3_bind_text(st, k, s, -1, transient)
                case let d as Double: sqlite3_bind_double(st, k, d)
                case let n as Int: sqlite3_bind_int64(st, k, Int64(n))
                default: sqlite3_bind_null(st, k)
                }
            }
            var out: [[Any?]] = []
            let n = sqlite3_column_count(st)
            while true {
                let rc = sqlite3_step(st)
                if rc == SQLITE_DONE { break }
                guard rc == SQLITE_ROW else { throw MCPError("lecture : \(String(cString: sqlite3_errmsg(db)))") }
                out.append((0..<n).map { i -> Any? in
                    switch sqlite3_column_type(st, i) {
                    case SQLITE_INTEGER: return Int(sqlite3_column_int64(st, i))
                    case SQLITE_FLOAT: return sqlite3_column_double(st, i)
                    case SQLITE_TEXT: return String(cString: sqlite3_column_text(st, i))
                    default: return nil
                    }
                })
            }
            return out
        }
    }
}

/// Dates locales : AAAA-MM-JJ ou AAAA-MM-JJTHH:MM
enum Dates {
    static func parse(_ s: String) throws -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for fmt in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        throw MCPError("date invalide : \(s) (AAAA-MM-JJ ou AAAA-MM-JJTHH:MM)")
    }
    static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.string(from: d)
    }
}

func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
