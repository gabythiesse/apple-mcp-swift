// Sonde 05 : NoteStore.sqlite en LECTURE SEULE (SQLITE_OPEN_READONLY) : schéma uniquement (tables, colonnes utiles)
import Foundation
import SQLite3
let path = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
var db: OpaquePointer?
let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
print("open rc=\(rc)", rc == SQLITE_OK ? "" : String(cString: sqlite3_errmsg(db)))
func q(_ sql: String) -> [[String]] {
  var st: OpaquePointer?; var rows: [[String]] = []
  guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { print("ERR", String(cString: sqlite3_errmsg(db))); return [] }
  while sqlite3_step(st) == SQLITE_ROW {
    rows.append((0..<sqlite3_column_count(st)).map { i in sqlite3_column_text(st, i).map { String(cString: $0) } ?? "NULL" })
  }
  sqlite3_finalize(st); return rows
}
let tables = q("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").map { $0[0] }
print("tables:", tables.joined(separator: " "))
let keys = CommandLine.arguments.dropFirst().map { $0.uppercased() }
for t in ["ZICCLOUDSYNCINGOBJECT", "ZICNOTEDATA"] where tables.contains(t) {
  let cols = q("PRAGMA table_info(\(t))").map { $0[1] }
  print("\(t) (\(cols.count) colonnes):", cols.filter { c in keys.isEmpty || keys.contains { c.contains($0) } }.joined(separator: " "))
}
print("entités:", q("SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY ORDER BY Z_ENT").map { "\($0[0])=\($0[1])" }.joined(separator: " "))
