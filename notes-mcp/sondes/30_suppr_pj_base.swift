// Sonde 30 : la double suppression d'une PJ finit-elle marquée en base ? Relevé toutes les 30 s pendant 3 min, puis nettoyage
import SQLite3
let here = FileManager.default.currentDirectoryPath
let ts = Int(Date().timeIntervalSince1970)
func dbq(_ pk: String) -> String {
  var db: OpaquePointer?; sqlite3_open_v2(NSHomeDirectory() + "/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite", &db, SQLITE_OPEN_READONLY, nil)
  defer { sqlite3_close(db) }
  var st: OpaquePointer?; sqlite3_prepare_v2(db, "SELECT ZMARKEDFORDELETION FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK=\(pk)", -1, &st, nil)
  return sqlite3_step(st) == SQLITE_ROW ? "marquée=\(sqlite3_column_int(st, 0))" : "absente"
}
let r = runAS("""
tell application "Notes"
  set f to make new folder at default account with properties {name:"MCP-TEST-\(ts)"}
  make new note at f with properties {body:"<div><h1>[mcp-test] pj base</h1></div>"}
  set n to item 1 of (notes of f)
  make new attachment at n with data (POSIX file "\(here)/pixel.png")
  set a2 to make new attachment at n with data (POSIX file "\(here)/pj.txt")
  set aid to id of a2
  delete attachment id aid of n
  delete attachment id aid of n
  return (id of f) & linefeed & (id of n) & linefeed & aid
end tell
""", timeout: 60)
let l = r.0!.components(separatedBy: "\n")
let pk = l[2].components(separatedBy: "/p").last!
for k in 0..<7 { print("t+\(k * 30)s :", dbq(pk)); fflush(stdout); if k < 6 { Thread.sleep(forTimeInterval: 30) } }
show("body sans PJ txt ?", runAS("tell application \"Notes\" to return (count of attachments of note id \"\(l[1])\") as string"))
show("nettoyage", runAS("""
tell application "Notes"
  delete note id "\(l[1])"
  delete note id "\(l[1])"
  delete folder id "\(l[0])"
  return ((count of (notes whose name starts with "[mcp-test]")) as string) & "/" & (count of (folders whose name starts with "MCP-TEST-"))
end tell
""", timeout: 60))
