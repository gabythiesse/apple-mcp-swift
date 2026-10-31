// Sonde 04 : framework Contacts sur données de test. Groupe MCP-TEST-<ts> + sous-groupe, contact [mcp-test] avec tous les champs
// (téléphones, emails, adresse, URL, anniversaire, dates, relations, réseaux, messagerie, photo, libellé personnalisé),
// note à part (entitlement ?), appartenance au groupe, relecture, modification, recherche nom/téléphone/email
// (résultats filtrés sur nos identifiants), vCard aller-retour, fusion par API publique, suppression par identifiant.
import Foundation
import Contacts

let store = acces()
let ts = Int(Date().timeIntervalSince1970)
let tok = "mcptest\(ts)"
let defC = store.defaultContainerIdentifier()
var mesContacts: [String] = []
var mesGroupes: [String] = []
let journal = FileManager.default.currentDirectoryPath + "/.crees.txt"
func noter(_ id: String) { if let h = FileHandle(forWritingAtPath: journal) { h.seekToEndOfFile(); h.write(Data((id + "\n").utf8)) } else { try? (id + "\n").write(toFile: journal, atomically: true, encoding: .utf8) } }

func save(_ f: (CNSaveRequest) -> Void) throws { let r = CNSaveRequest(); f(r); try store.execute(r) }
let base: [CNKeyDescriptor] = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactMiddleNameKey,
  CNContactNamePrefixKey, CNContactNameSuffixKey, CNContactNicknameKey, CNContactPhoneticGivenNameKey, CNContactOrganizationNameKey,
  CNContactDepartmentNameKey, CNContactJobTitleKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactPostalAddressesKey,
  CNContactUrlAddressesKey, CNContactBirthdayKey, CNContactNonGregorianBirthdayKey, CNContactDatesKey, CNContactRelationsKey,
  CNContactSocialProfilesKey, CNContactInstantMessageAddressesKey, CNContactImageDataAvailableKey, CNContactImageDataKey, CNContactThumbnailImageDataKey,
  CNContactTypeKey, CNContactPreviousFamilyNameKey] as [CNKeyDescriptor]
func lire(_ id: String, _ keys: [CNKeyDescriptor] = base) throws -> CNContact { try store.unifiedContact(withIdentifier: id, keysToFetch: keys) }

do {
  print("== Groupe et sous-groupe (conteneur par défaut)")
  let g = CNMutableGroup(); g.name = "MCP-TEST-\(ts)"
  try save { $0.add(g, toContainerWithIdentifier: defC) }
  mesGroupes.append(g.identifier); noter(g.identifier); check(true, "groupe créé \(g.identifier)")
  let sg = CNMutableGroup(); sg.name = "MCP-TEST-\(ts)-sous"
  do {
    try save { $0.add(sg, toContainerWithIdentifier: defC) }
    mesGroupes.append(sg.identifier); noter(sg.identifier)
    try save { $0.addSubgroup(sg, to: g) }
    let subs = try store.groups(matching: CNGroup.predicateForSubgroupsInGroup(withIdentifier: g.identifier))
    check(subs.map(\.identifier) == [sg.identifier], "sous-groupe imbriqué relu (\(subs.count))")
  } catch { check(false, "sous-groupe : \(error)") }
  let g2 = g.mutableCopy() as! CNMutableGroup; g2.name = "MCP-TEST-\(ts)-renomme"
  try save { $0.update(g2) }
  check(try store.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [g.identifier])).first?.name == g2.name, "groupe renommé")

  print("== Contact complet")
  let c = CNMutableContact()
  c.givenName = "[mcp-test] Alice"; c.familyName = tok; c.middleName = "M"; c.namePrefix = "Dr"; c.nameSuffix = "Jr"
  c.nickname = "Ali"; c.phoneticGivenName = "a-lis"; c.previousFamilyName = "Ancien"
  c.organizationName = "[mcp-test] Org"; c.departmentName = "R&D"; c.jobTitle = "Testeuse"
  c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+999 \(ts % 100000000)")),
                    CNLabeledValue(label: "ligne perso mcp", value: CNPhoneNumber(stringValue: "+999 111"))]
  c.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "\(tok)@example.invalid" as NSString)]
  let adr = CNMutablePostalAddress(); adr.street = "1 rue du Test"; adr.city = "Testville"; adr.postalCode = "99999"; adr.country = "France"; adr.isoCountryCode = "fr"
  c.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: adr)]
  c.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: "https://example.invalid" as NSString)]
  c.birthday = DateComponents(month: 2, day: 29)  // sans année
  var nonG = DateComponents(); nonG.calendar = Calendar(identifier: .chinese); nonG.month = 1; nonG.day = 1; nonG.isLeapMonth = false
  c.nonGregorianBirthday = nonG
  c.dates = [CNLabeledValue(label: CNLabelDateAnniversary, value: DateComponents(year: 2020, month: 6, day: 15) as NSDateComponents),
             CNLabeledValue(label: "date perso mcp", value: DateComponents(year: 2021, month: 1, day: 2) as NSDateComponents)]
  c.contactRelations = [CNLabeledValue(label: CNLabelContactRelationSister, value: CNContactRelation(name: "[mcp-test] Sœur")),
                        CNLabeledValue(label: "parrain mcp", value: CNContactRelation(name: "[mcp-test] Parrain"))]
  c.socialProfiles = [CNLabeledValue(label: nil, value: CNSocialProfile(urlString: nil, username: tok, userIdentifier: nil, service: CNSocialProfileServiceLinkedIn))]
  c.instantMessageAddresses = [CNLabeledValue(label: nil, value: CNInstantMessageAddress(username: tok, service: CNInstantMessageServiceSkype))]
  c.imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  try save { $0.add(c, toContainerWithIdentifier: defC); $0.addMember(c, to: g) }
  mesContacts.append(c.identifier); noter(c.identifier); check(true, "contact créé \(c.identifier)")

  let r = try lire(c.identifier)
  check(r.givenName == "[mcp-test] Alice" && r.middleName == "M" && r.namePrefix == "Dr" && r.nameSuffix == "Jr" && r.nickname == "Ali", "noms")
  check(r.organizationName == "[mcp-test] Org" && r.departmentName == "R&D" && r.jobTitle == "Testeuse", "organisation, service, poste")
  check(r.phoneNumbers.count == 2 && r.phoneNumbers.contains { $0.label == "ligne perso mcp" }, "téléphones + libellé personnalisé : \(r.phoneNumbers.map { "\($0.label ?? "-")=\($0.value.stringValue)" })")
  check(r.emailAddresses.first?.value as String? == "\(tok)@example.invalid", "email")
  let a2 = r.postalAddresses.first?.value
  check(a2?.street == "1 rue du Test" && a2?.city == "Testville" && a2?.postalCode == "99999", "adresse postale : \(a2.map { CNPostalAddressFormatter.string(from: $0, style: .mailingAddress).replacingOccurrences(of: "\n", with: " / ") } ?? "nil")")
  check(r.urlAddresses.count == 1, "URL")
  check(r.birthday?.month == 2 && r.birthday?.day == 29 && r.birthday?.year == nil, "anniversaire sans année : \(String(describing: r.birthday))")
  check(r.nonGregorianBirthday?.calendar?.identifier == .chinese, "anniversaire calendrier chinois : \(r.nonGregorianBirthday?.calendar?.identifier as Any)")
  check(r.dates.count == 2 && r.dates.contains { $0.label == "date perso mcp" }, "dates (anniversaire de mariage + date à libellé perso) : \(r.dates.map { $0.label ?? "-" })")
  check(r.contactRelations.count == 2 && r.contactRelations.contains { $0.label == "parrain mcp" }, "relations : \(r.contactRelations.map { "\($0.label ?? "-")=\($0.value.name)" })")
  check(r.socialProfiles.first?.value.username == tok, "réseau social : \(r.socialProfiles.map { $0.value.service })")
  check(r.instantMessageAddresses.first?.value.username == tok, "messagerie instantanée")
  check(r.imageDataAvailable && (r.imageData?.count ?? 0) > 0, "photo (imageData \(r.imageData?.count ?? 0) o, vignette \(r.thumbnailImageData?.count ?? 0) o)")
  check(r.previousFamilyName == "Ancien" && r.phoneticGivenName == "a-lis", "nom de naissance, phonétique")
  let membres = try store.unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: g.identifier), keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
  check(membres.map(\.identifier) == [c.identifier], "membre du groupe (\(membres.count))")
  let grpsDuContact = try store.groups(matching: nil).filter { mesGroupes.contains($0.identifier) }.filter { gr in
    ((try? store.unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: gr.identifier), keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])) ?? []).contains { $0.identifier == c.identifier } }
  check(grpsDuContact.count == 1, "groupes d'un contact : pas d'API directe, balayage des groupes (\(grpsDuContact.count))")

  print("== Note (sans entitlement, la clé est ignorée en silence et l'accès lèverait une exception ObjC)")
  let rn = try lire(c.identifier, [CNContactNoteKey as CNKeyDescriptor])
  check(rn.isKeyAvailable(CNContactNoteKey), "clé note disponible après fetch : \(rn.isKeyAvailable(CNContactNoteKey))")

  print("== Modification")
  let m = try lire(c.identifier).mutableCopy() as! CNMutableContact
  m.jobTitle = "Cheffe"; m.emailAddresses = []
  m.phoneNumbers.append(CNLabeledValue(label: CNLabelPhoneNumberiPhone, value: CNPhoneNumber(stringValue: "+999 222")))
  m.birthday = DateComponents(year: 1990, month: 3, day: 4)
  m.imageData = nil
  try save { $0.update(m) }
  let r2 = try lire(c.identifier)
  check(r2.jobTitle == "Cheffe" && r2.emailAddresses.isEmpty && r2.phoneNumbers.count == 3 && r2.birthday?.year == 1990 && !r2.imageDataAvailable, "poste, email retiré, tél ajouté, anniversaire avec année, photo retirée")

  print("== Recherche (résultats filtrés : seul le nombre d'intrus est affiché)")
  let k = [CNContactIdentifierKey as CNKeyDescriptor]
  func bilan(_ label: String, _ p: NSPredicate) {
    do {
      let res = try store.unifiedContacts(matching: p, keysToFetch: k).map(\.identifier)
      check(res.contains(c.identifier), "\(label) (autres résultats : \(res.filter { !mesContacts.contains($0) }.count))")
    } catch { check(false, "\(label) : \(error)") }
  }
  bilan("par nom", CNContact.predicateForContacts(matchingName: tok))
  bilan("par téléphone (format différent)", CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: "+999222")))
  let m3 = try lire(c.identifier).mutableCopy() as! CNMutableContact
  m3.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: "\(tok)@example.invalid" as NSString)]; try save { $0.update(m3) }
  bilan("par email", CNContact.predicateForContacts(matchingEmailAddress: "\(tok)@example.invalid"))
  let fr = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey, CNContactOrganizationNameKey] as [CNKeyDescriptor])
  fr.predicate = CNContact.predicateForContactsInGroup(withIdentifier: g.identifier); fr.sortOrder = .familyName
  var n = 0; try store.enumerateContacts(with: fr) { x, _ in if x.organizationName.contains("[mcp-test]") { n += 1 } }
  check(n == 1, "recherche texte libre (organisation) : pas de prédicat public, énumération + filtre côté serveur")

  print("== vCard")
  let vk = [CNContactVCardSerialization.descriptorForRequiredKeys()]
  let vc = try CNContactVCardSerialization.data(with: [try lire(c.identifier, vk)])
  let vs = String(decoding: vc, as: UTF8.self)
  check(vs.contains("BEGIN:VCARD"), "export vCard (\(vc.count) o, NOTE incluse : \(vs.contains("NOTE:")), PHOTO : \(vs.contains("PHOTO")))")
  let imp = try CNContactVCardSerialization.contacts(with: vs.replacingOccurrences(of: "[mcp-test] Alice", with: "[mcp-test] Bob").data(using: .utf8)!)
  let bob = imp.first!.mutableCopy() as! CNMutableContact
  try save { $0.add(bob, toContainerWithIdentifier: defC); $0.addMember(bob, to: g) }
  mesContacts.append(bob.identifier); noter(bob.identifier)
  check(try lire(bob.identifier).givenName == "[mcp-test] Bob", "import vCard → nouveau contact")

  print("== Fusion (API publique : on recopie les valeurs dans la cible puis on supprime la source)")
  let dup = CNMutableContact(); dup.givenName = "[mcp-test] Alice"; dup.familyName = tok
  dup.emailAddresses = [CNLabeledValue(label: CNLabelOther, value: "autre-\(tok)@example.invalid" as NSString)]
  dup.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+999 222"))]
  try save { $0.add(dup, toContainerWithIdentifier: defC); $0.addMember(dup, to: g) }
  mesContacts.append(dup.identifier); noter(dup.identifier)
  let doublons = try store.unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: g.identifier), keysToFetch: base)
    .filter { $0.familyName == tok }
  check(doublons.count == 2, "détection doublons (même nom) dans le groupe : \(doublons.count)")
  let cible = try lire(c.identifier).mutableCopy() as! CNMutableContact
  let src = try lire(dup.identifier)
  let telsCible = Set(cible.phoneNumbers.map { $0.value.stringValue.filter(\.isNumber) })
  cible.phoneNumbers += src.phoneNumbers.filter { !telsCible.contains($0.value.stringValue.filter(\.isNumber)) }
  let mailsCible = Set(cible.emailAddresses.map { ($0.value as String).lowercased() })
  cible.emailAddresses += src.emailAddresses.filter { !mailsCible.contains(($0.value as String).lowercased()) }.map { CNLabeledValue(label: $0.label, value: $0.value) }
  try save { $0.update(cible); $0.delete(src.mutableCopy() as! CNMutableContact) }
  let f = try lire(c.identifier)
  check(f.emailAddresses.count == 2 && f.phoneNumbers.count == 3, "fusion : 2 emails, 3 tél (doublon de tél ignoré) : \(f.emailAddresses.count)/\(f.phoneNumbers.count)")
  check((try? lire(dup.identifier)) == nil, "source supprimée")
  mesContacts.removeAll { $0 == dup.identifier }

  print("== Retrait du groupe")
  try save { $0.removeMember(bob, from: g) }
  let mem2 = try store.unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: g.identifier), keysToFetch: k).map(\.identifier)
  check(!mem2.contains(bob.identifier) && (try? lire(bob.identifier)) != nil, "retiré du groupe, contact conservé")
} catch { check(false, "ERREUR : \(error)") }

print("== Nettoyage par identifiant")
for id in mesContacts {
  do { let x = try lire(id, [CNContactGivenNameKey as CNKeyDescriptor])
    guard x.givenName.hasPrefix("[mcp-test]") else { print("  REFUS", id); continue }
    try save { $0.delete(x.mutableCopy() as! CNMutableContact) } } catch { print("  contact", id, error) }
}
for id in mesGroupes.reversed() {
  do { guard let x = try store.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [id])).first, x.name.hasPrefix("MCP-TEST-") else { continue }
    try save { $0.delete(x.mutableCopy() as! CNMutableGroup) } } catch { print("  groupe", id, error) }
}
let resteG = try store.groups(matching: nil).filter { $0.name.hasPrefix("MCP-TEST-") }.count
let resteC = mesContacts.filter { (try? lire($0, [CNContactIdentifierKey as CNKeyDescriptor])) != nil }.count
let resteTok = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: tok), keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]).count
check(resteG == 0 && resteC == 0 && resteTok == 0, "rien ne reste (groupes MCP-TEST : \(resteG), contacts : \(resteC), jeton : \(resteTok))")

if resteG == 0 && resteC == 0 { try? FileManager.default.removeItem(atPath: journal) }
