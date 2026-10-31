// Sonde 07 : (a) dates de création/modification : AppleScript (public) et clé privée du framework, filtrées sur le groupe de test ;
// (b) « selection » de l'app : sélectionner un contact de test par AppleScript et relire la sélection (identifiant seul) ;
// (c) groupe supprimé avec un membre : le contact reste. Nettoyage par identifiant.
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

do {
  let g = CNMutableGroup(); g.name = "MCP-TEST-\(ts)"
  try save { $0.add(g, toContainerWithIdentifier: defC) }; noter(g.identifier)
  let a = CNMutableContact(); a.givenName = "[mcp-test] Fay"
  try save { $0.add(a, toContainerWithIdentifier: defC); $0.addMember(a, to: g) }; noter(a.identifier)

  print("== Dates de modification")
  let x = try store.unifiedContact(withIdentifier: a.identifier, keysToFetch: k + ["modificationDate" as NSString, "creationDate" as NSString])
  let md = (x as NSObject).value(forKey: "modificationDate") as? Date
  check(md != nil && abs(md!.timeIntervalSinceNow) < 120, "clé privée modificationDate du framework : \(md.map { "\($0)" } ?? "nil")")
  let op = Process(); op.executableURL = URL(fileURLWithPath: "/usr/bin/open"); op.arguments = ["-g", "-j", "-a", "Contacts"]; try op.run(); op.waitUntilExit()
  for _ in 0..<50 { if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.AddressBook").isEmpty { break }; Thread.sleep(forTimeInterval: 0.1) }
  let (ids, e) = osa("tell application \"Contacts\" to get id of every person of group id \"\(g.identifier)\" whose modification date > ((current date) - 600)")
  check(ids?.contains(a.identifier) == true || ids == a.identifier, "AppleScript : modifiés < 10 min dans le groupe \(e ?? "")")

  print("== Sélection dans l'app")
  let (_, e1) = osa("tell application \"Contacts\" to set selection to person id \"\(a.identifier)\"")
  let (sel, e2) = osa("tell application \"Contacts\" to get id of item 1 of (selection as list)")
  check(sel == a.identifier, "sélection posée puis relue (\(e1 ?? e2 ?? "ok"))")

  print("== Suppression d'un groupe non vide")
  let gf = try store.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [g.identifier])).first!
  try save { $0.delete(gf.mutableCopy() as! CNMutableGroup) }
  check(try store.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [g.identifier])).isEmpty && (try? store.unifiedContact(withIdentifier: a.identifier, keysToFetch: k)) != nil, "groupe supprimé, contact conservé")
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
