// Sonde 05 : (a) recherche par téléphone sur un numéro réservé à la fiction (ARCEP 01 99 00 xx xx) sous plusieurs formats,
// (b) retrait d'un groupe avec objets relus, (c) note par AppleScript (NSAppleScript dans le binaire) sur un contact créé par le framework,
// relecture croisée, (d) lecture de l'identifiant de « Ma carte » par AppleScript (identifiant seul). Nettoyage par identifiant.
import Foundation
import Contacts
import AppKit

let store = acces()
let ts = Int(Date().timeIntervalSince1970)
let tok = "mcptest\(ts)"
let defC = store.defaultContainerIdentifier()
let journal = FileManager.default.currentDirectoryPath + "/.crees.txt"
var crees: [String] = []
func noter(_ id: String) { crees.append(id); try? (crees.joined(separator: "\n") + "\n").write(toFile: journal, atomically: true, encoding: .utf8) }
func save(_ f: (CNSaveRequest) -> Void) throws { let r = CNSaveRequest(); f(r); try store.execute(r) }
let k = [CNContactIdentifierKey, CNContactGivenNameKey] as [CNKeyDescriptor]
func osa(_ src: String) -> (String?, String?) {
  var err: NSDictionary?
  let t0 = Date()
  let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
  print(String(format: "    (AppleScript %.0f ms)", Date().timeIntervalSince(t0) * 1000))
  return (r?.stringValue, err.map { "\($0[NSAppleScript.errorNumber] ?? "?") \($0[NSAppleScript.errorMessage] ?? "")" })
}

do {
  let g = CNMutableGroup(); g.name = "MCP-TEST-\(ts)"
  try save { $0.add(g, toContainerWithIdentifier: defC) }; noter(g.identifier)
  let c = CNMutableContact(); c.givenName = "[mcp-test] Carla"; c.familyName = tok
  let num = String(format: "%04d", ts % 10000)
  c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+33 1 99 00 \(num.prefix(2)) \(num.suffix(2))"))]
  try save { $0.add(c, toContainerWithIdentifier: defC); $0.addMember(c, to: g) }; noter(c.identifier)

  print("== Recherche par téléphone (autres résultats comptés, jamais lus)")
  for attente in [0, 2, 5] {
    Thread.sleep(forTimeInterval: Double(attente))
    let st2 = CNContactStore()
    let res = try st2.unifiedContacts(matching: CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: "01 99 00 \(num.prefix(2)) \(num.suffix(2))")), keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]).map(\.identifier)
    print("    après \(attente) s, nouveau store : trouvé \(res.contains(c.identifier))")
  }
  for q in ["01 99 00 \(num.prefix(2)) \(num.suffix(2))", "+3319900\(num)", "0199 00\(num)", "199 00 \(num)"] {
    let res = try store.unifiedContacts(matching: CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: q)), keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]).map(\.identifier)
    check(res.contains(c.identifier), "« \(q) » (autres : \(res.filter { $0 != c.identifier }.count))")
  }

  print("== Retrait d'un groupe (objets relus)")
  let gf = try store.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [g.identifier])).first!
  let cf = try store.unifiedContact(withIdentifier: c.identifier, keysToFetch: k)
  try save { $0.removeMember(cf, from: gf) }
  let mem = try store.unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: g.identifier), keysToFetch: k)
  check(mem.isEmpty, "retiré du groupe (membres restants : \(mem.count))")
  Thread.sleep(forTimeInterval: 2)
  let mem2 = try CNContactStore().unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: g.identifier), keysToFetch: k)
  check(mem2.isEmpty, "retiré du groupe, relu par un nouveau store après 2 s (restants : \(mem2.count))")
  if !mem2.isEmpty {
    try save { $0.removeMember(cf.mutableCopy() as! CNMutableContact, from: gf.mutableCopy() as! CNMutableGroup) }
    Thread.sleep(forTimeInterval: 1)
    check(try CNContactStore().unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: g.identifier), keysToFetch: k).isEmpty, "retrait avec copies mutables")
  }
  try save { $0.addMember(cf, to: gf) }
  check(try store.unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: g.identifier), keysToFetch: k).count == 1, "remis dans le groupe")

  print("== AppleScript : note et relecture croisée")
  let pid = c.identifier
  // NSAppleScript ne lance pas l'app depuis ce binaire (-600) : on la lance cachée, en arrière-plan
  let t0 = Date()
  let op = Process(); op.executableURL = URL(fileURLWithPath: "/usr/bin/open"); op.arguments = ["-g", "-j", "-a", "Contacts"]; try op.run(); op.waitUntilExit()
  var pret = false
  for _ in 0..<50 { if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.AddressBook").isEmpty { pret = true; break }; Thread.sleep(forTimeInterval: 0.1) }
  print(String(format: "    Contacts lancé : %@ (%.0f ms)", pret ? "oui" : "non", Date().timeIntervalSince(t0) * 1000))
  let (nom, e1) = osa("tell application \"Contacts\" to get name of person id \"\(pid)\"")
  check(nom?.contains("[mcp-test] Carla") == true, "contact créé par le framework vu par AppleScript : \(nom ?? e1 ?? "nil")")
  let note = "note [mcp-test] \(tok)\nligne 2 é"
  let (_, e2) = osa("tell application \"Contacts\"\nset note of person id \"\(pid)\" to \"\(note.replacingOccurrences(of: "\n", with: "\\n"))\"\nsave\nend tell")
  check(e2 == nil, "note écrite par AppleScript \(e2 ?? "")")
  let (lue, e3) = osa("tell application \"Contacts\" to get note of person id \"\(pid)\"")
  check(lue == note, "note relue par AppleScript : \(lue ?? e3 ?? "nil")")
  let (grp, e4) = osa("tell application \"Contacts\" to get name of groups of person id \"\(pid)\"")
  check(grp?.contains("MCP-TEST-") == true || (grp == nil && e4 == nil), "groupes du contact par AppleScript : \(grp ?? e4 ?? "liste")")
  let (vc, _) = osa("tell application \"Contacts\" to get vcard of person id \"\(pid)\"")
  check(vc?.contains("NOTE:") == true, "vCard AppleScript inclut la note : \(vc?.contains("NOTE:") ?? false)")
  // lot : lire les notes de N contacts en un seul script
  let (lot, e5) = osa("tell application \"Contacts\"\nset out to {}\nrepeat with i in {\"\(pid)\", \"\(pid)\"}\nset end of out to note of person id i\nend repeat\nreturn out as text\nend tell")
  check(lot != nil, "lot de notes en un script \(e5 ?? "")")
  let still = try store.unifiedContact(withIdentifier: pid, keysToFetch: [CNContactGivenNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor])
  check(still.phoneNumbers.count == 1, "framework relit le contact après écriture AppleScript (téléphones intacts)")

  print("== Ma carte (identifiant seulement)")
  let (meAS, e6) = osa("tell application \"Contacts\" to get id of my card")
  let meCN = try? store.unifiedMeContactWithKeys(toFetch: [])
  check(meAS != nil && meAS == meCN?.identifier, "« Ma carte » : même identifiant par AppleScript et framework \(e6 ?? "")")
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
let resteG = try store.groups(matching: nil).filter { $0.name.hasPrefix("MCP-TEST-") }.count
let resteC = crees.filter { (try? store.unifiedContact(withIdentifier: $0, keysToFetch: k)) != nil }.count
check(resteG == 0 && resteC == 0, "rien ne reste (groupes : \(resteG), contacts : \(resteC))")
if resteG == 0 && resteC == 0 { try? FileManager.default.removeItem(atPath: journal) }
