// Sonde 02 : dossier MCP-TEST-<ts>, sous-dossier imbriqué, 3 notes en un seul script (HTML : titre, liste,
// tentative de case à cocher, #tag, lien), déplacement vers le sous-dossier. Écrit les ids dans ids.txt.
let ts = Int(Date().timeIntervalSince1970)
let r = runAS("""
tell application "Notes"
  set acc to default account
  set f to make new folder at acc with properties {name:"MCP-TEST-\(ts)"}
  set sf to make new folder at f with properties {name:"[mcp-test] sous-dossier"}
  set n1 to make new note at f with properties {name:"[mcp-test] simple", body:"<div><h1>[mcp-test] simple</h1></div><div>ligne <b>gras</b> et <a href=\\"https://example.com\\">lien</a></div><ul><li>puce 1</li><li>puce 2</li></ul>"}
  set n2 to make new note at f with properties {name:"[mcp-test] checklist", body:"<div><h1>[mcp-test] checklist</h1></div><ul class=\\"checklist\\"><li class=\\"checked\\">fait</li><li>pas fait</li></ul>"}
  set n3 to make new note at f with properties {name:"[mcp-test] tag", body:"<div>[mcp-test] tag</div><div>texte #mcptest fin</div>"}
  move n3 to sf
  set out to (id of f) & linefeed & (id of sf) & linefeed & (id of n1) & linefeed & (id of n2) & linefeed & (id of n3)
  return out
end tell
""")
show("creation", r)
if let ids = r.0 { try! ids.write(toFile: "ids.txt", atomically: true, encoding: .utf8) }
