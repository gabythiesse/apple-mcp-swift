// Sonde 08 : History.db en lecture seule, filtré sur les pages de test de ce dossier uniquement
import Foundation
import SQLite3
let home = FileManager.default.homeDirectoryForCurrentUser.path
let prefixe = "file://\(home)/mcp/safari-mcp/%"
var db: OpaquePointer?
guard sqlite3_open_v2("file:\(home)/Library/Safari/History.db?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { print("ouverture KO"); exit(1) }
let t0 = Date()
let sql = """
SELECT i.id, i.url, i.visit_count, v.title, v.visit_time FROM history_items i
JOIN history_visits v ON v.history_item = i.id
WHERE i.url LIKE ?1 ORDER BY v.visit_time DESC LIMIT 20
"""
var st: OpaquePointer?
guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { print("prepare KO : \(String(cString: sqlite3_errmsg(db)))"); exit(1) }
sqlite3_bind_text(st, 1, prefixe, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
var n = 0
while sqlite3_step(st) == SQLITE_ROW {
    n += 1
    let url = String(cString: sqlite3_column_text(st, 1))
    let titre = sqlite3_column_text(st, 3).map { String(cString: $0) } ?? "∅"
    let date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(st, 4))
    print("  item \(sqlite3_column_int64(st, 0)) \(url.replacingOccurrences(of: home, with: "~")) visites=\(sqlite3_column_int(st, 2)) titre=\(titre) \(date)")
}
print("\(n) visite(s) de pages de test, \(Int(Date().timeIntervalSince(t0) * 1000)) ms (WAL lu : \(FileManager.default.fileExists(atPath: "\(home)/Library/Safari/History.db-wal")))")
