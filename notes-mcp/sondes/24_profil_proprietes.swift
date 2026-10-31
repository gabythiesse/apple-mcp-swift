// Sonde 24 : coût de chaque propriété d'une note (avec PJ) et des formes en lot pour les dossiers ; nettoyage par id
let ts = Int(Date().timeIntervalSince1970)
let here = FileManager.default.currentDirectoryPath
// Reprise : dossier et note de test laissés par le 1er essai (ids passés en argument), sinon création
let args = CommandLine.arguments.dropFirst()
var F = "", N = ""
if args.count == 2 { F = args.first!; N = args.last! } else {
  let r = runAS("""
  tell application "Notes"
    set f to make new folder at default account with properties {name:"MCP-TEST-\(ts)"}
    make new note at f with properties {body:"<div><h1>[mcp-test] profil</h1></div><div>x</div>"}
    return (id of f) & linefeed & (item 1 of (id of notes of f))
  end tell
  """)
  show("création", r)
  let l = r.0!.components(separatedBy: "\n"); F = l[0]; N = l[1]
}
let ref = "note id \"\(N)\" of folder id \"\(F)\""
for p in ["id", "name", "container", "creation date", "modification date", "password protected", "shared", "plaintext", "body", "id of attachments", "name of attachments"] {
  show(p, runAS("tell application \"Notes\"\nset n to \(ref)\nget \(p) of n\nreturn \"ok\"\nend tell"))
}
show("make attachment sans id", runAS("tell application \"Notes\"\nset n to \(ref)\nmake new attachment at n with data (POSIX file \"\(here)/pixel.png\")\nreturn \"ok\"\nend tell"))
show("make attachment avec id+name", runAS("tell application \"Notes\"\nset n to \(ref)\nset a to make new attachment at n with data (POSIX file \"\(here)/pj.txt\")\nreturn (id of a) & name of a\nend tell"))
for p in ["id of attachments", "name of attachments", "plaintext", "body", "creation date", "shared", "password protected"] {
  show("après PJ : " + p, runAS("tell application \"Notes\"\nset n to \(ref)\nget \(p) of n\nreturn \"ok\"\nend tell"))
}
show("lot dossiers : id/name/container", runAS("tell application \"Notes\"\nset a to id of folders of default account\nset b to name of folders of default account\nset c to id of container of folders of default account\nreturn ((count of a) as string) & \"/\" & (count of c)\nend tell"))
show("nettoyage", runAS("""
tell application "Notes"
  set n to \(ref)
  delete n
  delete note id "\(N)"
  delete folder id "\(F)"
  return ((count of (notes whose name starts with "[mcp-test]")) as string) & "/" & (count of (folders whose name starts with "MCP-TEST-"))
end tell
"""))
