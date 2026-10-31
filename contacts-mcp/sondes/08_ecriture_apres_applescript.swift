// Sonde 08 : avec la boucle d'événements principale active (RunLoop.main.run) et AppleScript sur le thread principal :
// (a) délai avant que l'app Contacts voie un contact créé par le framework ;
// (b) écriture framework sur un contact dont la note vient d'être écrite par AppleScript
//     (erreur Core Data 134092 au smoke quand la boucle ne tournait pas). Nettoyage par identifiant.
import Foundation
import Contacts

relancerResponsable()
func osa(_ src: String) -> (String?, Int) {
  var r: NSAppleEventDescriptor?; var err: NSDictionary?
  DispatchQueue.main.sync { r = NSAppleScript(source: "with timeout of 20 seconds\ntell application id \"com.apple.AddressBook\"\n\(src)\nend tell\nend timeout")?.executeAndReturnError(&err) }
  return (r?.stringValue, (err?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0)
}
// Mode « maj <id> » : un processus neuf tente la même écriture
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "maj" {
  DispatchQueue.global().async {
    let st = acces()
    do {
      let m = try st.unifiedContact(withIdentifier: CommandLine.arguments[2], keysToFetch: [CNContactJobTitleKey as CNKeyDescriptor]).mutableCopy() as! CNMutableContact
      m.jobTitle = "processus neuf"; let r = CNSaveRequest(); r.update(m); try st.execute(r); print("    [processus neuf] maj : OK")
    } catch { print("    [processus neuf] maj :", (error as NSError).code) }
    exit(0)
  }
  RunLoop.main.run()
}
DispatchQueue.global().async {
  let store0 = acces()
  let k = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactJobTitleKey] as [CNKeyDescriptor]
  let c = CNMutableContact(); c.givenName = "[mcp-test] Gus"
  let r = CNSaveRequest(); r.add(c, toContainerWithIdentifier: nil); try! store0.execute(r)
  try? (c.identifier + "\n").write(toFile: ".crees.txt", atomically: true, encoding: .utf8)
  print("créé", c.identifier)
  var t0 = Date()
  let (n, e0) = osa("get name")
  print(String(format: "    app répond : %@ (%d) %.1f s", n ?? "nil", e0, Date().timeIntervalSince(t0)))
  t0 = Date()
  var vu = false
  for _ in 0..<50 {
    if osa("return exists person id \"\(c.identifier)\"").0 == "true" { vu = true; break }
    usleep(200_000)
  }
  print(String(format: "(a) vu par l'app : %@ après %.1f s", vu ? "oui" : "non", Date().timeIntervalSince(t0)))
  t0 = Date()
  let (_, e1) = osa("set note of person id \"\(c.identifier)\" to \"note [mcp-test]\"\nsave")
  print(String(format: "    note AppleScript : erreur %d, %.1f s", e1, Date().timeIntervalSince(t0)))
  func maj(_ st: CNContactStore, _ titre: String) -> String {
    do {
      let m = try st.unifiedContact(withIdentifier: c.identifier, keysToFetch: k).mutableCopy() as! CNMutableContact
      m.jobTitle = titre
      let r = CNSaveRequest(); r.update(m); try st.execute(r)
      return "OK"
    } catch { return "\((error as NSError).code)" }
  }
  print("(b) maj immédiate, nouveau store :", maj(CNContactStore(), "a"))
  for attente in [0.1, 0.5, 1.0, 2.0] {
    usleep(UInt32(attente * 1_000_000))
    let x = maj(CNContactStore(), "b\(attente)")
    print("    après \(attente) s de plus :", x)
    if x == "OK" { break }
  }
  let p = Process(); p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); p.arguments = ["maj", c.identifier]
  try! p.run(); p.waitUntilExit()
  print("    maj par le processus d'origine ensuite :", maj(CNContactStore(), "c"))
  print("    poste vu par l'app :", osa("get job title of person id \"\(c.identifier)\"").0 ?? "nil")
  print("    note toujours là :", osa("get note of person id \"\(c.identifier)\"").0 ?? "nil")
  let d = CNSaveRequest()
  d.delete(try! CNContactStore().unifiedContact(withIdentifier: c.identifier, keysToFetch: k).mutableCopy() as! CNMutableContact)
  do { try CNContactStore().execute(d) } catch { print("suppression framework :", (error as NSError).code) }
  let reste = (try? CNContactStore().unifiedContact(withIdentifier: c.identifier, keysToFetch: k)) != nil
  print("reste :", reste)
  if !reste { try? FileManager.default.removeItem(atPath: ".crees.txt") }
  exit(0)
}
RunLoop.main.run()
