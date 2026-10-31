// Sonde 14 : formes de résolution d'un sous-dossier par id (app, compte, parent), puis déplacement de dossier
let ids = try! String(contentsOfFile: "ids.txt", encoding: .utf8).split(separator: "\n").map(String.init)
let (f, sf) = (ids[0], ids[1])
for (label, ref) in [("app", "folder id \"\(sf)\""), ("compte", "folder id \"\(sf)\" of default account"),
                     ("parent", "folder id \"\(sf)\" of folder id \"\(f)\""), ("whose id", "first folder of folder id \"\(f)\" whose id is \"\(sf)\"")] {
  show("résolution \(label)", runAS("tell application \"Notes\"\nset x to \(ref)\nreturn name of x\nend tell"))
}
show("move dossier → racine (via parent)", runAS("""
tell application "Notes"
  set sfo to folder id "\(sf)" of folder id "\(f)"
  move sfo to default account
  return "ok, top-level [mcp-test] : " & (count of (folders of default account whose name starts with "[mcp-test]")) & ", sous f : " & (count of folders of folder id "\(f)")
end tell
"""))
