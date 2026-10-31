// Sonde 28b : double suppression d une PJ (delete attachment) : listing AppleScript brut et base, tout de suite puis 5 s après
import SQLite3
let here = FileManager.default.currentDirectoryPath
let ts = Int(Date().timeIntervalSince1970)
func dbq(_ pk: String) -> String {
  var db: OpaquePointer?; sqlite3_open_v2(NSHomeDirectory() + "/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite", &db, SQLITE_OPEN_READONLY, nil)
  defer { sqlite3_close(db) }
  var st: OpaquePointer?; sqlite3_prepare_v2(db, "SELECT ZMARKEDFORDELETION, ZNOTE FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK=\(pk)", -1, &st, nil)
  return sqlite3_step(st) == SQLITE_ROW ? "marquée=\(sqlite3_column_int(st, 0)) note=\(sqlite3_column_int(st, 1))" : "absente"
}
let r = runAS("""
tell application "Notes"
  set f to make new folder at default account with properties {name:"MCP-TEST-\(ts)"}
  make new note at f with properties {body:"<div><h1>[mcp-test] pj</h1></div>"}
  set n to item 1 of (notes of f)
  set a1 to make new attachment at n with data (POSIX file "\(here)/pixel.png")
  set a2 to make new attachment at n with data (POSIX file "\(here)/pj.txt")
  set AppleScript's text item delimiters to ","
  set avant to (id of attachments of n) as text
  set aid to id of a2
  delete attachment id aid of n
  try
    delete attachment id aid of n
  end try
  set apres to (id of attachments of n) as text
  return (id of f) & linefeed & (id of n) & linefeed & aid & linefeed & avant & linefeed & apres
end tell
""")
show("création + suppression", r)
let l = r.0!.components(separatedBy: "\n")
print("base tout de suite:", dbq(l[2].components(separatedBy: "/p").last!))
Thread.sleep(forTimeInterval: 5)
show("listing 5 s après", runAS("tell application \"Notes\"\nset AppleScript's text item delimiters to \",\"\nreturn (id of attachments of note id \"\(l[1])\") as text\nend tell"))
print("base 5 s après:", dbq(l[2].components(separatedBy: "/p").last!))
show("nettoyage", runAS("""
tell application "Notes"
  delete note id "\(l[1])"
  delete note id "\(l[1])"
  delete folder id "\(l[0])"
  return ((count of (notes whose name starts with "[mcp-test]")) as string) & "/" & (count of (folders whose name starts with "MCP-TEST-"))
end tell
"""))
