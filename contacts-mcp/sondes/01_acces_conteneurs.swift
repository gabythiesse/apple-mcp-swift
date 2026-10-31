// Sonde 01 : accès au framework Contacts, conteneurs (type + nombre, sans contenu), présence de « Ma carte »
import Foundation
import Contacts

print("statut (3 = autorisé):", CNContactStore.authorizationStatus(for: .contacts).rawValue)
let store = acces()

let types = [0: "inconnu", 1: "local (Sur mon Mac)", 2: "Exchange", 3: "CardDAV (iCloud…)"]
let defID = store.defaultContainerIdentifier()
let containers = try store.containers(matching: nil)
for c in containers {
  let n = try store.unifiedContacts(matching: CNContact.predicateForContactsInContainer(withIdentifier: c.identifier), keysToFetch: []).count
  let g = try store.groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: c.identifier)).count
  print("conteneur:", types[c.type.rawValue] ?? "?", "| par défaut:", c.identifier == defID, "| contacts:", n, "| groupes:", g)
}
// Ma carte : présence seulement, aucun champ lu
let me = try? store.unifiedMeContactWithKeys(toFetch: [])
print("Ma carte définie:", me != nil)
