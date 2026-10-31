// Sonde 17 : structure des tags / épingles / checklists dans NoteStore.sqlite : COMPTES uniquement, aucun contenu
import Foundation
import SQLite3
var db: OpaquePointer?
sqlite3_open_v2(NSHomeDirectory() + "/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite", &db, SQLITE_OPEN_READONLY, nil)
func one(_ sql: String) -> String {
  var st: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return "ERR " + String(cString: sqlite3_errmsg(db)) }
  defer { sqlite3_finalize(st) }
  return sqlite3_step(st) == SQLITE_ROW ? (sqlite3_column_text(st, 0).map { String(cString: $0) } ?? "-") : "-"
}
let cols = { () -> [String] in var st: OpaquePointer?; var r: [String] = []; sqlite3_prepare_v2(db, "PRAGMA table_info(ZICCLOUDSYNCINGOBJECT)", -1, &st, nil); while sqlite3_step(st) == SQLITE_ROW { r.append(String(cString: sqlite3_column_text(st, 1))) }; return r }()
print("colonnes tag/texte:", cols.filter { ["ALTTEXT", "DISPLAYTEXT", "STANDARDIZED", "TOKEN"].contains(where: $0.contains) })
print("ICHashtag (ent 8):", one("SELECT count(*) FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT=8"))
print("types d'inline attachments:", one("SELECT group_concat(t || '=' || c, ' ') FROM (SELECT ZTYPEUTI1 t, count(*) c FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT=9 GROUP BY ZTYPEUTI1)"))
print("hashtags inline reliés à une note (ZNOTE1):", one("SELECT count(DISTINCT ZNOTE1) FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT=9 AND ZTYPEUTI1 LIKE '%hashtag%'"))
print("notes épinglées:", one("SELECT count(*) FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT=12 AND ZISPINNED=1"), " avec checklist:", one("SELECT count(*) FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT=12 AND ZHASCHECKLIST=1"))
print("ZDATA gzip ? (octets de tête de 1 note de test 1442):", one("SELECT hex(substr(ZDATA,1,2)) FROM ZICNOTEDATA WHERE ZNOTE=1442"))
