// Supprime des données de test par identifiant (refuse tout contact sans préfixe [mcp-test] et tout groupe sans préfixe MCP-TEST-).
// Usage : nettoyage <id>… ; sans argument, liste seulement le nombre de groupes MCP-TEST- restants.
import Foundation
import Contacts

let store = acces()
for id in CommandLine.arguments.dropFirst() {
  let r = CNSaveRequest()
  if id.hasSuffix(":ABGroup") {
    guard let g = try store.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [id])).first else { print("absent:", id); continue }
    guard g.name.hasPrefix("MCP-TEST-") else { print("REFUS:", id); continue }
    r.delete(g.mutableCopy() as! CNMutableGroup)
  } else {
    guard let c = try? store.unifiedContact(withIdentifier: id, keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor]) else { print("absent:", id); continue }
    guard c.givenName.hasPrefix("[mcp-test]") else { print("REFUS:", id); continue }
    r.delete(c.mutableCopy() as! CNMutableContact)
  }
  try store.execute(r); print("supprimé:", id)
}
print("contacts [mcp-test] restants:", try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: "mcp-test"), keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor]).filter { $0.givenName.hasPrefix("[mcp-test]") }.map(\.identifier))
print("groupes MCP-TEST- restants:", try store.groups(matching: nil).filter { $0.name.hasPrefix("MCP-TEST-") }.map(\.identifier))
