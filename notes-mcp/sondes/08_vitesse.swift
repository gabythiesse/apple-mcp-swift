// Sonde 08 : vitesse. Création de 50 notes en UN script, lecture par lot (propriétés en une requête),
// recherche globale « whose » avec une chaîne introuvable (aucun contenu ne sort), tableau HTML.
let ids = try! String(contentsOfFile: "ids.txt", encoding: .utf8).split(separator: "\n").map(String.init)
let f = ids[0]
show("creation x50", runAS("""
tell application "Notes"
  set f to folder id "\(f)"
  set out to {}
  repeat with i from 1 to 50
    set end of out to id of (make new note at f with properties {body:"<div><h1>[mcp-test] lot " & i & "</h1></div><div>corps " & i & " zqmcpneedle</div>"})
  end repeat
  return (count of out) as string
end tell
""", timeout: 240))
show("lecture lot (id,nom,modif) dossier test", runAS("""
tell application "Notes"
  set f to folder id "\(f)"
  set {a, b, c} to {id, name, modification date} of notes of f
  return (count of a) as string
end tell
"""))
show("lecture lot plaintext dossier test", runAS("""
tell application "Notes"
  set t to plaintext of notes of folder id "\(f)"
  return (count of t) as string
end tell
"""))
show("count global", runAS("tell application \"Notes\" to return (count of notes) as string"))
show("whose name contains (global, introuvable)", runAS("tell application \"Notes\" to return (count of (notes whose name contains \"zz-introuvable-mcp-4242\")) as string"))
show("whose plaintext contains (global, introuvable)", runAS("tell application \"Notes\" to return (count of (notes whose plaintext contains \"zz-introuvable-mcp-4242\")) as string", timeout: 180))
show("whose body contains needle (global → 50 de test)", runAS("tell application \"Notes\" to return (count of (notes whose body contains \"zqmcpneedle\")) as string", timeout: 180))
show("tableau HTML", runAS("""
tell application "Notes"
  set n to make new note at folder id "\(f)" with properties {body:"<div><h1>[mcp-test] tableau</h1></div><table><tr><td>a</td><td>b</td></tr><tr><td>1</td><td>2</td></tr></table><ol><li>un</li><li>deux</li></ol><div><i>ital</i> https://example.com</div>"}
  return (id of n) & linefeed & (body of n)
end tell
"""))
