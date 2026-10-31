// Sonde 11 : supprimer une note de test par id → où va-t-elle ? Une 2e suppression par id la purge-t-elle ?
let ids = try! String(contentsOfFile: "ids.txt", encoding: .utf8).split(separator: "\n").map(String.init)
let nid = ids[4]  // [mcp-test] tag, dans le sous-dossier
let etat = """
  try
    set n to note id "\(nid)"
    set c to container of n
    set r to "existe, nom=" & (name of n) & ", dossier=" & (name of c) & " (" & (id of c) & ")"
  on error e
    set r to "absente : " & e
  end try
"""
show("avant", runAS("tell application \"Notes\"\n\(etat)\nreturn r\nend tell"))
show("delete 1", runAS("tell application \"Notes\"\nset n to note id \"\(nid)\"\nif name of n does not start with \"[mcp-test]\" then error \"refus\"\ndelete n\n\(etat)\nreturn r\nend tell"))
show("delete 2 (purge ?)", runAS("tell application \"Notes\"\nset n to note id \"\(nid)\"\nif name of n does not start with \"[mcp-test]\" then error \"refus\"\ndelete n\n\(etat)\nreturn r\nend tell"))
