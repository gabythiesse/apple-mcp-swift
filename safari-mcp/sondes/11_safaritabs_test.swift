// Sonde 11 : SafariTabs.db en lecture seule, filtré sur les éléments [mcp-test] uniquement.
// Où sont stockés la liste de lecture et les groupes d'onglets ? (type/subtype/parent des lignes de test)
import Foundation
import SQLite3
let home = FileManager.default.homeDirectoryForCurrentUser.path
var db: OpaquePointer?
guard sqlite3_open_v2("file:\(home)/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { print("ouverture KO"); exit(1) }
func q(_ sql: String) {
    var st: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { print("KO : \(String(cString: sqlite3_errmsg(db)))"); return }
    let n = sqlite3_column_count(st)
    while sqlite3_step(st) == SQLITE_ROW {
        print("  " + (0..<n).map { i in "\(String(cString: sqlite3_column_name(st, i)))=\(sqlite3_column_text(st, i).map { String(cString: $0) } ?? "∅")" }.joined(separator: " "))
    }
    sqlite3_finalize(st)
}
print("lignes [mcp-test] :")
q("SELECT b.id, b.type, b.subtype, b.parent, p.special_id AS parent_special, p.type AS parent_type, b.title, b.url, b.read, b.deleted, b.external_uuid FROM bookmarks b LEFT JOIN bookmarks p ON p.id = b.parent WHERE b.title LIKE '[mcp-test]%'")
print("dossiers spéciaux (special_id non nul : structure, sans titre ni URL) :")
q("SELECT id, special_id, type, subtype, parent, num_children FROM bookmarks WHERE special_id IS NOT NULL AND special_id != 0 ORDER BY id")
