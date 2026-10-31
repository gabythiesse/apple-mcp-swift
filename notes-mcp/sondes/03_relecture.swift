// Sonde 03 : relit les notes de test (ids.txt) : nom, conteneur, body HTML, plaintext, dates, verrou, partage
let ids = try! String(contentsOfFile: "ids.txt", encoding: .utf8).split(separator: "\n").map(String.init)
for nid in ids.dropFirst(2) {
  show(nid.components(separatedBy: "/").last!, runAS("""
  tell application "Notes"
    set n to note id "\(nid)"
    set c to container of n
    return "nom=" & name of n & linefeed & "conteneur=" & (name of c) & linefeed & "body=" & body of n & linefeed & "plaintext=" & plaintext of n & linefeed & "verrou=" & (password protected of n) & " partage=" & (shared of n) & " modif=" & (modification date of n as «class isot» as string) & " pj=" & (count of attachments of n)
  end tell
  """))
}
show("sous-dossier.container", runAS("tell application \"Notes\"\nset c to container of folder id \"\(ids[1])\"\nset c0 to container of folder id \"\(ids[0])\"\nreturn (name of c) & \" / \" & (class of c0 as string)\nend tell"))
