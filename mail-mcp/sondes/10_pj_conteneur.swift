// Sonde 10 : pièce jointe — copie du fichier dans le dossier temporaire du conteneur de Mail (bac à sable), brouillon via NSAppleScript, relu dans l'index
import Foundation
let ts = CommandLine.arguments[1], src = CommandLine.arguments[2]
let dir = NSHomeDirectory() + "/Library/Containers/com.apple.mail/Data/tmp/mcp-test-\(ts)"
do {
  try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
  let dst = dir + "/mcp-test.txt"
  try? FileManager.default.removeItem(atPath: dst)
  try FileManager.default.copyItem(atPath: src, toPath: dst)
  print("copie OK:", dst)
  let s = """
  tell application "Mail"
    set om to make new outgoing message with properties {subject:"[mcp-test] pj conteneur \(ts)", content:"Corps de test pj conteneur." & linefeed & linefeed, visible:false}
    tell om to make new to recipient at end of to recipients with properties {address:"dest-test@example.com"}
    tell content of om to make new attachment with properties {file name:(POSIX file "\(dst)")} at after last paragraph
    delay 1
    set n to count of attachments of content of om
    save om
    delay 2
    close om saving no
    set x to first message of drafts mailbox whose subject is "[mcp-test] pj conteneur \(ts)"
    return "pj outgoing " & n & " | brouillon " & (id of x) & " pj " & (count of mail attachments of x)
  end tell
  """
  var err: NSDictionary?
  let t0 = Date()
  let r = NSAppleScript(source: s)!.executeAndReturnError(&err)
  print(err.map { "ERREUR \($0)" } ?? r.stringValue ?? "?", "|", Int(Date().timeIntervalSince(t0)*1000), "ms")
} catch { print("échec:", error) }
