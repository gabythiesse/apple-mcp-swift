// Sonde 10 : récupérer les ids des notes créées sans payer ~1,4 s/note.
// A : garder les références puis lire les ids après la boucle. B : relire le dossier en lot et faire correspondre les titres.
let f = try! String(contentsOfFile: "ids.txt", encoding: .utf8).split(separator: "\n").map(String.init)[0]
show("A refs puis ids", runAS("""
tell application "Notes"
  set f to folder id "\(f)"
  set refs to {}
  repeat with i from 1 to 10
    set end of refs to (make new note at f with properties {body:"<div><h1>[mcp-test] refA " & i & "</h1></div>"})
  end repeat
  set out to {}
  repeat with r in refs
    set end of out to id of r
  end repeat
  return (item 1 of out) & " … " & (count of out)
end tell
"""))
show("B lot puis correspondance", runAS("""
tell application "Notes"
  set f to folder id "\(f)"
  set t0 to current date
  repeat with i from 1 to 10
    make new note at f with properties {body:"<div><h1>[mcp-test] refB " & i & "</h1></div>"}
  end repeat
  set {ids, noms} to {id, name} of (notes of f whose name starts with "[mcp-test] refB")
  return (count of ids) as string
end tell
"""))
