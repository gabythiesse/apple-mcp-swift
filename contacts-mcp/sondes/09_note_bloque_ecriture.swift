// Sonde 09 : un contact qui a une note devient-il non modifiable par le framework (sans entitlement notes) ?
// Témoin sans note ; contact avec note ; puis note vidée par AppleScript ("") → écriture → note remise. Nettoyage par identifiant.
import Foundation
import Contacts

relancerResponsable()
func osa(_ src: String) -> (String?, Int) {
  var r: NSAppleEventDescriptor?; var err: NSDictionary?
  DispatchQueue.main.sync { r = NSAppleScript(source: "with timeout of 20 seconds\ntell application id \"com.apple.AddressBook\"\n\(src)\nend tell\nend timeout")?.executeAndReturnError(&err) }
  return (r?.stringValue, (err?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0)
}
DispatchQueue.global().async {
  let st = acces()
  let k = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactJobTitleKey] as [CNKeyDescriptor]
  func maj(_ id: String, _ t: String) -> String {
    do { let m = try CNContactStore().unifiedContact(withIdentifier: id, keysToFetch: k).mutableCopy() as! CNMutableContact
      m.jobTitle = t; let r = CNSaveRequest(); r.update(m); try CNContactStore().execute(r); return "OK" } catch { return "\((error as NSError).code)" }
  }
  let a = CNMutableContact(); a.givenName = "[mcp-test] Témoin"
  let b = CNMutableContact(); b.givenName = "[mcp-test] Avec note"
  let r = CNSaveRequest(); r.add(a, toContainerWithIdentifier: nil); r.add(b, toContainerWithIdentifier: nil); try! st.execute(r)
  try? "\(a.identifier)\n\(b.identifier)\n".write(toFile: ".crees.txt", atomically: true, encoding: .utf8)
  _ = osa("get name")
  for _ in 0..<50 where osa("return exists person id \"\(b.identifier)\"").0 != "true" { usleep(200_000) }
  // Témoin : AppleScript modifie un autre champ que la note
  _ = osa("set nickname of person id \"\(a.identifier)\" to \"x\"\nsave")
  check(maj(a.identifier, "1") == "OK", "témoin modifié par AppleScript (surnom), puis framework : \(maj(a.identifier, "1b"))")
  // Matrice : quelle note bloque l'écriture framework ?
  for n in ["note", "note [mcp-test]", "", "abc def", "é", "note de test", String(repeating: "x", count: 60), "a\\nb", "[x]", "mcp-test"] {
    let (_, e) = osa("set note of person id \"\(b.identifier)\" to \"\(n)\"\nsave")
    let r1 = maj(b.identifier, "m")
    usleep(300_000)
    print("    note «\(n.prefix(20))» (AS \(e)) → framework \(r1), après 0,3 s \(maj(b.identifier, "m2"))")
  }
  _ = osa("set note of person id \"\(b.identifier)\" to missing value\nsave")
  print("    missing value → framework", maj(b.identifier, "z"))
  for id in [a.identifier, b.identifier] {
    let d = CNSaveRequest(); d.delete(try! CNContactStore().unifiedContact(withIdentifier: id, keysToFetch: k).mutableCopy() as! CNMutableContact); try? CNContactStore().execute(d)
  }
  let reste = [a.identifier, b.identifier].filter { (try? CNContactStore().unifiedContact(withIdentifier: $0, keysToFetch: k)) != nil }.count
  check(reste == 0, "nettoyage (\(reste))")
  if reste == 0 { try? FileManager.default.removeItem(atPath: ".crees.txt") }
  exit(0)
}
RunLoop.main.run()
