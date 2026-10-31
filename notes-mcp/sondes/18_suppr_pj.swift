// Sonde 18 : supprimer une pièce jointe par id (delete attachment), puis nettoyage complet de la sonde
let here = FileManager.default.currentDirectoryPath
let ts = Int(Date().timeIntervalSince1970)
let r = runAS("""
tell application "Notes"
  set f to make new folder at default account with properties {name:"MCP-TEST-\(ts)"}
  set n to make new note at f with properties {body:"[mcp-test] pj"}
  set a to make new attachment at n with data (POSIX file "\(here)/pixel.png")
  set aid to id of a
  set avant to count of attachments of n
  try
    delete attachment id aid of n
    set res to "delete ok"
  on error e number k
    set res to "delete KO " & k & " " & e
  end try
  set apres to count of attachments of n
  set nid to id of n
  set fid to id of f
  delete n
  delete note id nid
  delete f
  return res & " | avant=" & avant & " apres=" & apres & " | " & aid & linefeed & nid & linefeed & fid & " | restes=" & (count of (folders whose name starts with "MCP-TEST-")) & "/" & (count of (notes whose name starts with "[mcp-test]"))
end tell
""", timeout: 120)
show("suppr pj", r)
