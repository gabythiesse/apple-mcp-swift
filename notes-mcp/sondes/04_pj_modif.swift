// Sonde 04 : pièce jointe (image + fichier) sur une note de test, export d'une pièce jointe,
// modification du body (sans name : le titre = 1re ligne), ajout en fin, renommage du sous-dossier
let ids = try! String(contentsOfFile: "ids.txt", encoding: .utf8).split(separator: "\n").map(String.init)
let here = FileManager.default.currentDirectoryPath
let out = NSTemporaryDirectory() + "pj-export"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
show("pj.ajout", runAS("""
tell application "Notes"
  set n to note id "\(ids[2])"
  set a1 to make new attachment at n with data (POSIX file "\(here)/pixel.png")
  set a2 to make new attachment at n with data (POSIX file "\(here)/pj.txt")
  return (id of a1) & " | " & (name of a1) & " | " & (count of attachments of n)
end tell
"""))
show("pj.lecture+export", runAS("""
tell application "Notes"
  set n to note id "\(ids[2])"
  set out to ""
  repeat with a in attachments of n
    set out to out & (name of a) & " cid=" & (content identifier of a) & linefeed
  end repeat
  save (first attachment of n) in POSIX file "\(out)/export.png"
  return out & (body of n)
end tell
"""))
print(try! FileManager.default.contentsOfDirectory(atPath: out))
show("modif.body", runAS("""
tell application "Notes"
  set n to note id "\(ids[3])"
  set body of n to "<div><h1>[mcp-test] checklist v2</h1></div><div>remplacé</div>"
  set b to body of n
  set body of n to b & "<div>ajout en fin</div>"
  set name of folder id "\(ids[1])" to "[mcp-test] sous-dossier renommé"
  return (name of n) & linefeed & (plaintext of n)
end tell
"""))
