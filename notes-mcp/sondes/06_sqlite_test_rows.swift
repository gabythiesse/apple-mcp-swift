// Sonde 06 : lecture seule des SEULES lignes de test (Z_PK issus de ids.txt et objets qui y pointent) :
// vrai tag ? checklist ? pièces jointes réelles ? épinglage ? corbeille ? Usage : swift 06... (lit ids.txt)
import Foundation
import SQLite3
let path = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
var db: OpaquePointer?
sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
func q(_ sql: String) -> [[String]] {
  var st: OpaquePointer?; var rows: [[String]] = []
  guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { print("ERR", String(cString: sqlite3_errmsg(db))); return [] }
  while sqlite3_step(st) == SQLITE_ROW {
    rows.append((0..<sqlite3_column_count(st)).map { i in sqlite3_column_text(st, i).map { String(cString: $0) } ?? "-" })
  }
  sqlite3_finalize(st); return rows
}
let ids = (try? String(contentsOfFile: "ids.txt", encoding: .utf8)) ?? ""
let pks = ids.split(separator: "\n").compactMap { $0.components(separatedBy: "/p").last }.joined(separator: ",")
let extra = CommandLine.arguments.dropFirst().joined(separator: ",")
let set = [pks, extra].filter { !$0.isEmpty }.joined(separator: ",")
print("objets de test:")
for r in q("SELECT Z_PK, Z_ENT, COALESCE(ZTITLE1, ZTITLE2, ZTITLE, ''), ZFOLDER, ZPARENT, ZISPINNED, ZHASCHECKLIST, ZMARKEDFORDELETION, ZFOLDERTYPE, ZIDENTIFIER FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK IN (\(set))") { print(" ", r.joined(separator: " | ")) }
print("pointant vers les notes de test (pj, tags inline, médias):")
for r in q("SELECT Z_PK, Z_ENT, ZTYPEUTI, ZTYPEUTI1, ZNOTE, ZNOTE1, ZPARENTATTACHMENT, ZMARKEDFORDELETION, COALESCE(ZTITLE,'') FROM ZICCLOUDSYNCINGOBJECT WHERE ZNOTE IN (\(set)) OR ZNOTE1 IN (\(set))") { print(" ", r.joined(separator: " | ")) }
print("hashtags nommés mcptest:", q("SELECT Z_PK, ZMARKEDFORDELETION FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT=8 AND lower(COALESCE(ZTITLE,'')) LIKE '%mcptest%'"))
print("dossier « Supprimées récemment » (type, nb notes, pas de titres):", q("SELECT f.Z_PK, f.ZFOLDERTYPE, (SELECT count(*) FROM ZICCLOUDSYNCINGOBJECT n WHERE n.ZFOLDER=f.Z_PK) FROM ZICCLOUDSYNCINGOBJECT f WHERE f.Z_ENT=15 AND f.ZFOLDERTYPE=1"))
