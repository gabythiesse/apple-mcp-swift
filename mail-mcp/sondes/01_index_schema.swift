// Sonde 01 : index local de Mail (Envelope Index) ouvert en LECTURE SEULE — schéma uniquement, aucun contenu
import Foundation
import SQLite3

let path = NSHomeDirectory() + "/Library/Mail/V10/MailData/Envelope Index"
var db: OpaquePointer?
let rc = sqlite3_open_v2("file:" + path + "?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
print("ouverture ro:", rc == SQLITE_OK ? "OK" : String(cString: sqlite3_errmsg(db)))
guard rc == SQLITE_OK else { exit(1) }
func rows(_ sql: String) -> [[String]] {
  var st: OpaquePointer?; var out: [[String]] = []
  guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { print("ERR", String(cString: sqlite3_errmsg(db))); return [] }
  while sqlite3_step(st) == SQLITE_ROW {
    out.append((0..<sqlite3_column_count(st)).map { sqlite3_column_text(st, $0).map { String(cString: $0) } ?? "" })
  }
  sqlite3_finalize(st); return out
}
let tables = rows("SELECT name FROM sqlite_master WHERE type IN ('table','view') ORDER BY name").map { $0[0] }
print("tables:", tables.count)
let wanted = CommandLine.arguments.count > 1 ? Set(CommandLine.arguments.dropFirst()) : Set(tables)
for t in tables where wanted.contains(t) {
  let cols = rows("PRAGMA table_info('\(t)')").map { $0[1] }
  print("\(t): \(cols.joined(separator: ","))")
}
print("user_version:", rows("PRAGMA user_version").first?.first ?? "?")
sqlite3_close(db)
