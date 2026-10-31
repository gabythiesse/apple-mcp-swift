// Sonde 06 : (a) retrait d'un membre de groupe : framework (échoue sur iCloud en 05 ?) puis AppleScript « remove … from »,
// relu par le framework ; (b) recherche par téléphone : prédicat public sur un mobile fictif (ARCEP 06 39 98 xx xx)
// puis énumération restreinte au groupe de test + comparaison des chiffres (repli). Nettoyage par identifiant.
import Foundation
import Contacts
import AppKit

let store = acces()
let ts = Int(Date().timeIntervalSince1970)
let defC = store.defaultContainerIdentifier()
var crees: [String] = []
let journal = FileManager.default.currentDirectoryPath + "/.crees.txt"
func noter(_ id: String) { crees.append(id); try? (crees.joined(separator: "\n") + "\n").write(toFile: journal, atomically: true, encoding: .utf8) }
func save(_ f: (CNSaveRequest) -> Void) throws { let r = CNSaveRequest(); f(r); try store.execute(r) }
let k = [CNContactIdentifierKey, CNContactGivenNameKey] as [CNKeyDescriptor]
func osa(_ src: String) -> (String?, String?) {
  var err: NSDictionary?; let t0 = Date()
  let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
  print(String(format: "    (AppleScript %.0f ms)", Date().timeIntervalSince(t0) * 1000))
  return (r?.stringValue, err.map { "\($0[NSAppleScript.errorNumber] ?? "?") \($0[NSAppleScript.errorMessage] ?? "")" })
}
func membres(_ gid: String) throws -> [String] { try CNContactStore().unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: gid), keysToFetch: k).map(\.identifier) }

do {
  let g = CNMutableGroup(); g.name = "MCP-TEST-\(ts)"
  try save { $0.add(g, toContainerWithIdentifier: defC) }; noter(g.identifier)
  let a = CNMutableContact(); a.givenName = "[mcp-test] Dan"
  let n = String(format: "%04d", ts % 10000)
  a.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "06 39 98 \(n.prefix(2)) \(n.suffix(2))"))]
  let b = CNMutableContact(); b.givenName = "[mcp-test] Eve"
  try save { $0.add(a, toContainerWithIdentifier: defC); $0.add(b, toContainerWithIdentifier: defC); $0.addMember(a, to: g); $0.addMember(b, to: g) }
  noter(a.identifier); noter(b.identifier)
  check(Set(try membres(g.identifier)) == [a.identifier, b.identifier], "2 membres")

  print("== Retrait par le framework (requête seule)")
  let r = CNSaveRequest(); r.removeMember(a, from: g)
  do { try store.execute(r); check(true, "execute sans erreur") } catch { check(false, "execute : \(error)") }
  let m1 = try membres(g.identifier)
  check(!m1.contains(a.identifier), "Dan retiré par le framework (membres : \(m1.count))")

  print("== Retrait par AppleScript")
  let op = Process(); op.executableURL = URL(fileURLWithPath: "/usr/bin/open"); op.arguments = ["-g", "-j", "-a", "Contacts"]; try op.run(); op.waitUntilExit()
  for _ in 0..<50 { if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.AddressBook").isEmpty { break }; Thread.sleep(forTimeInterval: 0.1) }
  let (_, e) = osa("tell application \"Contacts\"\nremove person id \"\(a.identifier)\" from group id \"\(g.identifier)\"\nsave\nend tell")
  check(e == nil, "remove … from group \(e ?? "")")
  Thread.sleep(forTimeInterval: 1)
  let m2 = try membres(g.identifier)
  check(m2 == [b.identifier], "relu par le framework : seul Eve reste (\(m2.count))")
  let (_, e2) = osa("tell application \"Contacts\"\nadd person id \"\(a.identifier)\" to group id \"\(g.identifier)\"\nsave\nend tell")
  Thread.sleep(forTimeInterval: 1)
  check(try e2 == nil && Set(membres(g.identifier)) == [a.identifier, b.identifier], "add … to group par AppleScript, relu par le framework \(e2 ?? "")")

  print("== Téléphone")
  for q in ["06 39 98 \(n.prefix(2)) \(n.suffix(2))", "+33639 98\(n)", "0639 98 \(n)"] {
    let res = try CNContactStore().unifiedContacts(matching: CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: q)), keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]).map(\.identifier)
    check(res.contains(a.identifier), "prédicat public « \(q) » (autres : \(res.filter { !crees.contains($0) }.count))")
  }
  func chiffres(_ s: String) -> String { String(s.filter(\.isNumber).suffix(9)) }
  let fr = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor])
  fr.predicate = CNContact.predicateForContactsInGroup(withIdentifier: g.identifier)
  var trouves: [String] = []
  let cible = chiffres("+33 6 39 98 \(n)")
  let t0 = Date()
  try store.enumerateContacts(with: fr) { c, _ in if c.phoneNumbers.contains(where: { chiffres($0.value.stringValue) == cible }) { trouves.append(c.identifier) } }
  check(trouves == [a.identifier], String(format: "énumération + 9 derniers chiffres (+33… vs 06…) : %.0f ms", Date().timeIntervalSince(t0) * 1000))
} catch { check(false, "ERREUR : \(error)") }

print("== Nettoyage par identifiant")
for id in crees.reversed() {
  let r = CNSaveRequest()
  if id.hasSuffix(":ABGroup") {
    if let x = try? store.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [id])).first, x.name.hasPrefix("MCP-TEST-") { r.delete(x.mutableCopy() as! CNMutableGroup) } else { continue }
  } else {
    if let x = try? store.unifiedContact(withIdentifier: id, keysToFetch: k), x.givenName.hasPrefix("[mcp-test]") { r.delete(x.mutableCopy() as! CNMutableContact) } else { continue }
  }
  do { try store.execute(r) } catch { print("  ", id, error) }
}
let resteG = try CNContactStore().groups(matching: nil).filter { $0.name.hasPrefix("MCP-TEST-") }.count
let resteC = crees.filter { (try? CNContactStore().unifiedContact(withIdentifier: $0, keysToFetch: k)) != nil }.count
check(resteG == 0 && resteC == 0, "rien ne reste (groupes : \(resteG), contacts : \(resteC))")
if resteG == 0 && resteC == 0 { try? FileManager.default.removeItem(atPath: journal) }
