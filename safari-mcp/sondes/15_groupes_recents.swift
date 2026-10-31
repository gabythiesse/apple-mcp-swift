// Sonde 15 : lignes de SafariTabs.db ajoutées pendant la sonde 14, en lecture seule.
// Colonnes de structure uniquement (aucun titre, aucune URL).
import Foundation
import SQLite3
let minutes = Double(CommandLine.arguments.dropFirst().first ?? "15") ?? 15
let depuis = Date().addingTimeInterval(-minutes * 60).timeIntervalSinceReferenceDate
var db: OpaquePointer?
let p = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db"
guard sqlite3_open_v2("file:\(p)?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { print("KO"); exit(1) }
var st: OpaquePointer?
let sql = "SELECT id, type, subtype, parent, deleted, num_children, added FROM bookmarks WHERE added > ?1 ORDER BY id"
guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { print("KO \(String(cString: sqlite3_errmsg(db)))"); exit(1) }
sqlite3_bind_double(st, 1, depuis)
var n = 0
while sqlite3_step(st) == SQLITE_ROW {
    n += 1
    print((Int32(0)..<Int32(7)).map { "\(String(cString: sqlite3_column_name(st, $0)))=\(sqlite3_column_text(st, $0).map { String(cString: $0) } ?? "∅")" }.joined(separator: " "))
}
print("\(n) ligne(s) ajoutée(s) depuis \(Int(minutes)) min")
