// Sonde 12 : déplacer un dossier (vers la racine du compte puis de retour), restaurer une note depuis
// « Recently Deleted » par move, compter (sans lire) les notes verrouillées et partagées.
let ids = try! String(contentsOfFile: "ids.txt", encoding: .utf8).split(separator: "\n").map(String.init)
let (f, sf, n1) = (ids[0], ids[1], ids[2])
show("move dossier → racine", runAS("""
tell application "Notes"
  set sfo to folder id "\(sf)"
  move sfo to default account
  set c to container of sfo
  return class of c as string
end tell
"""))
show("état dossier après move", runAS("""
tell application "Notes"
  set out to ""
  repeat with fo in (folders whose name starts with "[mcp-test]")
    set c to container of fo
    set out to out & (id of fo) & " parent=" & (name of c) & linefeed
  end repeat
  return out
end tell
"""))
show("move dossier → dans test", runAS("""
tell application "Notes"
  set sfo to first folder of default account whose name starts with "[mcp-test]"
  move sfo to folder id "\(f)"
  set c to container of sfo
  return (id of sfo) & " parent=" & (name of c)
end tell
"""))
show("restauration", runAS("""
tell application "Notes"
  set n to note id "\(n1)"
  set c to container of n
  set c1 to name of c
  move n to folder id "\(f)"
  set n to note id "\(n1)"
  set c to container of n
  return c1 & " → " & (name of c) & " pj=" & (count of attachments of n)
end tell
"""))
