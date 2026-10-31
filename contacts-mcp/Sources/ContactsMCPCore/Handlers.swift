// Logique des outils : framework Contacts pour le cœur, AppleScript pour la note, le retrait de groupe, la sélection et la vCard
import Foundation
import Contacts

extension Dictionary where Key == String, Value == Any {
    /// Liste d'éléments (chaînes ou objets) ; null = liste vide ; clé absente = nil
    func items(_ k: String) -> [Any]? {
        if self[k] is NSNull { return [] }
        if let s = self[k] as? String {
            if s.hasPrefix("["), let arr = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [Any] { return arr }
            return s.isEmpty ? [] : [s]
        }
        return self[k] as? [Any]
    }
}

enum Handlers {
    private static var store: CNContactStore { CN.store }

    // MARK: - Comptes et groupes

    static func groupes(_ a: JSON) throws -> Any {
        let filtre = a.nonEmpty("nom_contient")
        let defID = store.defaultContainerIdentifier()
        var comptes: [JSON] = []
        var groupes: [JSON] = []
        var parents: [String: String] = [:]
        let tous = try store.groups(matching: nil)
        for g in tous {
            for s in try store.groups(matching: CNGroup.predicateForSubgroupsInGroup(withIdentifier: g.identifier)) { parents[s.identifier] = g.identifier }
        }
        for c in try store.containers(matching: nil) {
            var d: JSON = ["id": c.identifier, "nom": c.name, "type": CN.typeCompte(c.type),
                           "nb_contacts": try CN.contacts(CNContact.predicateForContactsInContainer(withIdentifier: c.identifier), CN.idKey).count]
            if c.identifier == defID { d["par_defaut"] = true }
            comptes.append(d)
            for g in try store.groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: c.identifier))
            where filtre == nil || g.name.localizedStandardContains(filtre!) {
                var x: JSON = ["id": g.identifier, "nom": g.name, "compte_id": c.identifier, "nb": try CN.memberIDs(g.identifier).count]
                if let p = parents[g.identifier] { x["parent_id"] = p }
                groupes.append(x)
            }
        }
        return ["comptes": comptes, "groupes": groupes]
    }

    static func creerGroupe(_ a: JSON) throws -> Any {
        let nom = try a.req("nom")
        let parent = try a.nonEmpty("parent_id").map(CN.group)
        let compte: String
        if let p = parent {
            compte = try store.containers(matching: CNContainer.predicateForContainerOfGroup(withIdentifier: p.identifier)).first?.identifier ?? CN.container(nil)
        } else { compte = try CN.container(a.nonEmpty("compte_id")) }
        let g = CNMutableGroup()
        g.name = nom
        do { try CN.execute { $0.add(g, toContainerWithIdentifier: compte) } }
        catch { throw MCPError("création refusée par le compte (\(error.localizedDescription)) : certains comptes, comme Exchange, n'acceptent pas les groupes") }
        var out: JSON = ["ok": true, "id": g.identifier, "nom": nom]
        if let p = parent {
            do { try CN.execute { $0.addSubgroup(g, to: p) }; out["parent_id"] = p.identifier }
            catch { out["avertissement"] = "groupe créé hors du parent : \(error.localizedDescription)" }
        }
        return out
    }

    static func modifierGroupe(_ a: JSON) throws -> Any {
        let id = try a.req("id")
        let g = try CN.group(id)
        var out: JSON = ["ok": true, "id": id]
        if let nom = a.nonEmpty("nom") {
            let m = g.mutableCopy() as! CNMutableGroup
            m.name = nom
            try CN.execute { $0.update(m) }
            out["nom"] = nom
        }
        if a.has("parent_id") {
            let actuel = try store.groups(matching: nil).first { p in
                ((try? store.groups(matching: CNGroup.predicateForSubgroupsInGroup(withIdentifier: p.identifier))) ?? []).contains { $0.identifier == id }
            }
            let cible = a.nonEmpty("parent_id")
            if let p = actuel, p.identifier != cible {
                // Ni le framework (removeSubgroup sans effet) ni AppleScript (remove ne s'applique pas aux groupes) ne le font (smoke)
                throw MCPError("impossible de sortir un sous-groupe de son parent « \(p.name) » : Contacts ne l'expose ni au framework ni à AppleScript. Le faire dans l'app (glisser le groupe).")
            }
            if let pid = cible, pid != actuel?.identifier {
                let p = try CN.group(pid)
                try CN.execute { $0.addSubgroup(g, to: p) }
            }
            out["parent_id"] = cible ?? NSNull()
        }
        return out
    }

    static func supprimerGroupe(_ a: JSON) throws -> Any {
        guard let ids = a.strings("ids"), !ids.isEmpty else { throw MCPError("paramètre manquant : ids") }
        var res: [JSON] = []
        for id in ids {
            do {
                let g = try CN.group(id)
                try CN.execute { $0.delete(g.mutableCopy() as! CNMutableGroup) }
                res.append(["ok": true, "id": id, "nom": g.name])
            } catch { res.append(["ok": false, "id": id, "erreur": "\(error)"]) }
        }
        return ["resultats": res]
    }

    // MARK: - Lecture des contacts

    static func contacts(_ a: JSON) throws -> Any {
        let detail = a.bool("detail") == true
        let modifDepuis = try a.nonEmpty("modifies_depuis").map(Dates.jour)
        let annivJours = a.int("anniversaires_jours")
        var keys = detail ? CN.complet : CN.recherche
        if modifDepuis != nil || detail { keys.append(Prive.modificationKey) }

        // Restrictions par identifiants (intersection)
        var restrict: Set<String>?
        func inter(_ s: Set<String>) { restrict = restrict.map { $0.intersection(s) } ?? s }
        if let ids = a.strings("ids") { inter(Set(ids)) }
        if a.bool("ma_carte") == true { inter(Set([try? store.unifiedMeContactWithKeys(toFetch: CN.idKey).identifier].compactMap { $0 })) }
        if let g = a.nonEmpty("groupe_id") { _ = try CN.group(g); inter(try CN.memberIDs(g)) }
        if a.bool("selection") == true { inter(Set(try AS.selection())) }
        let texte = a.nonEmpty("texte")
        let dansNotes = a.bool("dans_notes") == true
        if let t = texte, dansNotes { inter(Set(try AS.rechercheNotes(t, groupe: a.nonEmpty("groupe_id")))) }
        let compte = try a.nonEmpty("compte_id").map { try CN.container($0) }
        if let c = compte, restrict != nil {
            inter(Set(try CN.contacts(CNContact.predicateForContactsInContainer(withIdentifier: c), CN.idKey).map(\.identifier)))
        }

        var items: [CNContact]
        if let r = restrict {
            items = r.isEmpty ? [] : try CN.contacts(CNContact.predicateForContacts(withIdentifiers: Array(r)), keys)
        } else if let c = compte {
            items = try CN.contacts(CNContact.predicateForContactsInContainer(withIdentifier: c), keys)
        } else if let e = a.nonEmpty("email") {
            items = try CN.contacts(CNContact.predicateForContacts(matchingEmailAddress: e), keys)
        } else {
            items = try CN.contacts(nil, keys)
        }

        // Filtres en mémoire
        if let t = texte.map(fold), !dansNotes {
            items = items.filter { c in
                var parts = [CN.nom(c), c.nickname, c.organizationName, c.departmentName, c.jobTitle]
                parts += c.emailAddresses.map { $0.value as String } + c.phoneNumbers.map { $0.value.stringValue } + c.urlAddresses.map { $0.value as String }
                parts += c.postalAddresses.flatMap { [$0.value.street, $0.value.city, $0.value.postalCode, $0.value.country] }
                return fold(parts.joined(separator: "\n")).contains(t)
            }
        }
        if let e = a.nonEmpty("email")?.lowercased() {
            items = items.filter { $0.emailAddresses.contains { ($0.value as String).lowercased() == e } }
        }
        if let q = a.nonEmpty("telephone") {
            let d = chiffres(q)
            guard d.count >= 4 else { throw MCPError("téléphone : au moins 4 chiffres") }
            items = items.filter { $0.phoneNumbers.contains { p in
                let n = chiffres(p.value.stringValue)
                return d.count >= 9 ? n == d : n.hasSuffix(d)
            } }
        }
        switch a.nonEmpty("sans") {
        case "telephone": items = items.filter { $0.phoneNumbers.isEmpty }
        case "email": items = items.filter { $0.emailAddresses.isEmpty }
        case nil: break
        case let s?: throw MCPError("sans : telephone ou email (reçu \(s))")
        }
        let today = Calendar.current.startOfDay(for: Date())
        var jours: [String: Int] = [:]
        if let n = annivJours {
            items = items.filter { c in
                guard let b = c.birthday, let j = Dates.joursAvant(b, depuis: today), j <= n else { return false }
                jours[c.identifier] = j
                return true
            }
            items.sort { jours[$0.identifier]! < jours[$1.identifier]! }
        }
        if let d = modifDepuis {
            items = items.filter { (Prive.modification($0) ?? .distantPast) >= d }
            items.sort { (Prive.modification($0) ?? .distantPast) > (Prive.modification($1) ?? .distantPast) }
        }
        if annivJours == nil && modifDepuis == nil {
            items.sort { CN.nom($0).localizedStandardCompare(CN.nom($1)) == .orderedAscending }
        }

        let total = items.count
        let page = Array(items.prefix(max(1, a.int("limite") ?? 20)))
        var notes: [String: String] = [:]
        var groupesDe: [String: [JSON]] = [:]
        if detail && !page.isEmpty {
            notes = try AS.notes(page.map(\.identifier))
            let ids = Set(page.map(\.identifier))
            for g in try store.groups(matching: nil) {
                for m in try CN.memberIDs(g.identifier) where ids.contains(m) { groupesDe[m, default: []].append(["id": g.identifier, "nom": g.name]) }
            }
        }
        var out: JSON = ["total": total, "contacts": page.map { c -> JSON in
            var d = describe(c, detail: detail, note: notes[c.identifier], groupes: groupesDe[c.identifier])
            if let j = jours[c.identifier] { d["anniversaire"] = c.birthday.map(Dates.text); d["dans_jours"] = j }
            if modifDepuis != nil || detail, let m = Prive.modification(c) { d["modifie_le"] = Dates.iso(m) }
            return d
        }]
        if total > page.count { out["tronque"] = "\(page.count) affichés sur \(total) : augmenter limite ou filtrer" }
        return out
    }

    private static func lv<T>(_ vals: [CNLabeledValue<T>], _ f: (T) -> Any) -> [JSON] {
        vals.map { v in
            var d: JSON = ["valeur": f(v.value)]
            if let l = Labels.fr(v.label) { d["libelle"] = l }
            return d
        }
    }

    static func describe(_ c: CNContact, detail: Bool, note: String? = nil, groupes: [JSON]? = nil) -> JSON {
        var d: JSON = ["id": c.identifier, "nom": CN.nom(c)]
        if c.contactType == .organization { d["est_societe"] = true }
        if !detail {
            if !c.organizationName.isEmpty && c.contactType != .organization { d["societe"] = c.organizationName }
            if let t = c.phoneNumbers.first { d["tel"] = t.value.stringValue }
            if let e = c.emailAddresses.first { d["email"] = e.value as String }
            return d
        }
        let champs: [(String, String)] = [("prenom", c.givenName), ("nom_famille", c.familyName), ("deuxieme_prenom", c.middleName),
            ("prefixe", c.namePrefix), ("suffixe", c.nameSuffix), ("surnom", c.nickname), ("nom_naissance", c.previousFamilyName),
            ("prenom_phonetique", c.phoneticGivenName), ("nom_phonetique", c.phoneticFamilyName), ("societe", c.organizationName),
            ("service", c.departmentName), ("poste", c.jobTitle)]
        for (k, v) in champs where !v.isEmpty { d[k] = v }
        if !c.phoneNumbers.isEmpty { d["telephones"] = lv(c.phoneNumbers) { $0.stringValue } }
        if !c.emailAddresses.isEmpty { d["emails"] = lv(c.emailAddresses) { $0 as String } }
        if !c.urlAddresses.isEmpty { d["urls"] = lv(c.urlAddresses) { $0 as String } }
        if !c.postalAddresses.isEmpty {
            d["adresses"] = c.postalAddresses.map { v -> JSON in
                let p = v.value
                var x: JSON = [:]
                for (k, s) in [("rue", p.street), ("ville", p.city), ("code_postal", p.postalCode), ("region", p.state), ("pays", p.country), ("code_pays", p.isoCountryCode)] where !s.isEmpty { x[k] = s }
                if let l = Labels.fr(v.label) { x["libelle"] = l }
                return x
            }
        }
        if let b = c.birthday { d["anniversaire"] = Dates.text(b) }
        if let n = c.nonGregorianBirthday, let cal = n.calendar {
            var x: JSON = ["calendrier": "\(cal.identifier)", "mois": n.month ?? 0, "jour": n.day ?? 0]
            if let y = n.year { x["annee"] = y }
            d["anniversaire_autre_calendrier"] = x
        }
        if !c.dates.isEmpty { d["dates"] = lv(c.dates) { Dates.text($0 as DateComponents) } }
        if !c.contactRelations.isEmpty { d["relations"] = lv(c.contactRelations) { $0.name } }
        if !c.socialProfiles.isEmpty {
            d["reseaux"] = c.socialProfiles.map { v -> JSON in
                var x: JSON = ["service": v.value.service]
                if !v.value.username.isEmpty { x["utilisateur"] = v.value.username }
                if !v.value.urlString.isEmpty { x["url"] = v.value.urlString }
                return x
            }
        }
        if !c.instantMessageAddresses.isEmpty {
            d["messageries"] = c.instantMessageAddresses.map { ["service": $0.value.service, "utilisateur": $0.value.username] }
        }
        if c.imageDataAvailable { d["photo"] = true }
        if let n = note, !n.isEmpty { d["note"] = n }
        if let g = groupes, !g.isEmpty { d["groupes"] = g }
        return d
    }

    // MARK: - Écriture des champs (clé absente = inchangé ; "" ou null = effacé ; listes remplacées)

    private static let scalaires: [(String, ReferenceWritableKeyPath<CNMutableContact, String>)] = [
        ("prenom", \.givenName), ("nom_famille", \.familyName), ("deuxieme_prenom", \.middleName), ("prefixe", \.namePrefix),
        ("suffixe", \.nameSuffix), ("surnom", \.nickname), ("nom_naissance", \.previousFamilyName),
        ("prenom_phonetique", \.phoneticGivenName), ("nom_phonetique", \.phoneticFamilyName), ("societe", \.organizationName),
        ("service", \.departmentName), ("poste", \.jobTitle),
    ]

    private static func split(_ x: Any, _ kind: Labels.Kind, _ defaut: String?, valeur: String = "valeur") -> (String?, Any?) {
        if let o = x as? JSON { return (o.has("libelle") ? Labels.cn(o.string("libelle"), kind) : defaut, o[valeur] ?? o) }
        return (defaut, x)
    }

    private static func texte(_ v: Any?, _ quoi: String) throws -> String {
        guard let s = (v as? String) ?? (v as? NSNumber)?.stringValue, !s.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MCPError("\(quoi) : valeur manquante")
        }
        return s
    }

    private static func phones(_ xs: [Any]) throws -> [CNLabeledValue<CNPhoneNumber>] {
        try xs.map { x in
            let (l, v) = split(x, .phone, CNLabelPhoneNumberMobile)
            return CNLabeledValue(label: l, value: CNPhoneNumber(stringValue: try texte(v, "téléphone")))
        }
    }

    private static func strs(_ xs: [Any], _ quoi: String, _ defaut: String?) throws -> [CNLabeledValue<NSString>] {
        try xs.map { x in
            let (l, v) = split(x, .generic, defaut)
            return CNLabeledValue(label: l, value: try texte(v, quoi) as NSString)
        }
    }

    private static func adresses(_ xs: [Any]) throws -> [CNLabeledValue<CNPostalAddress>] {
        xs.map { x in
            let p = CNMutablePostalAddress()
            var label: String? = CNLabelHome
            if let o = x as? JSON {
                p.street = o.string("rue") ?? ""; p.city = o.string("ville") ?? ""; p.postalCode = o.string("code_postal") ?? ""
                p.state = o.string("region") ?? ""; p.country = o.string("pays") ?? ""; p.isoCountryCode = o.string("code_pays")?.lowercased() ?? ""
                if o.has("libelle") { label = Labels.cn(o.string("libelle"), .generic) }
            } else { p.street = "\(x)" }
            return CNLabeledValue(label: label, value: p)
        }
    }

    private static func dates(_ xs: [Any]) throws -> [CNLabeledValue<NSDateComponents>] {
        try xs.map { x in
            let o = x as? JSON
            let l: String? = o.flatMap { $0.has("libelle") ? Labels.cn($0.string("libelle"), .date) : CNLabelDateAnniversary } ?? CNLabelDateAnniversary
            let s = try texte(o?["date"] ?? o?["valeur"] ?? x, "date")
            return CNLabeledValue(label: l, value: try Dates.components(s) as NSDateComponents)
        }
    }

    private static func relations(_ xs: [Any]) throws -> [CNLabeledValue<CNContactRelation>] {
        try xs.map { x in
            let o = x as? JSON
            let l = o.flatMap { Labels.cn($0.string("libelle"), .relation) }
            return CNLabeledValue(label: l, value: CNContactRelation(name: try texte(o?["nom"] ?? o?["valeur"] ?? x, "relation")))
        }
    }

    private static func reseaux(_ xs: [Any]) throws -> [CNLabeledValue<CNSocialProfile>] {
        try xs.map { x in
            guard let o = x as? JSON else { throw MCPError("réseau : objet {service, utilisateur, url} attendu") }
            return CNLabeledValue(label: nil, value: CNSocialProfile(urlString: o.nonEmpty("url"), username: o.nonEmpty("utilisateur"),
                                                                   userIdentifier: nil, service: o.nonEmpty("service")))
        }
    }

    private static func messageries(_ xs: [Any]) throws -> [CNLabeledValue<CNInstantMessageAddress>] {
        try xs.map { x in
            guard let o = x as? JSON else { throw MCPError("messagerie : objet {service, utilisateur} attendu") }
            return CNLabeledValue(label: nil, value: CNInstantMessageAddress(username: try o.req("utilisateur"), service: o.string("service") ?? ""))
        }
    }

    static func apply(_ c: CNMutableContact, _ a: JSON) throws {
        for (k, kp) in scalaires where a.has(k) { c[keyPath: kp] = a.string(k) ?? "" }
        if let b = a.bool("est_societe") { c.contactType = b ? .organization : .person }
        if let x = a.items("telephones") { c.phoneNumbers = try phones(x) }
        if let x = a.items("ajouter_telephones") { c.phoneNumbers += try phones(x) }
        if let x = a.items("retirer_telephones") {
            let set = Set(x.map { chiffres("\(($0 as? JSON)?["valeur"] ?? $0)") })
            c.phoneNumbers.removeAll { set.contains(chiffres($0.value.stringValue)) }
        }
        if let x = a.items("emails") { c.emailAddresses = try strs(x, "email", CNLabelOther) }
        if let x = a.items("ajouter_emails") { c.emailAddresses += try strs(x, "email", CNLabelOther) }
        if let x = a.items("retirer_emails") {
            let set = Set(x.map { "\(($0 as? JSON)?["valeur"] ?? $0)".lowercased() })
            c.emailAddresses.removeAll { set.contains(($0.value as String).lowercased()) }
        }
        if let x = a.items("urls") { c.urlAddresses = try strs(x, "URL", CNLabelOther) }
        if let x = a.items("adresses") { c.postalAddresses = try adresses(x) }
        if let x = a.items("dates") { c.dates = try dates(x) }
        if let x = a.items("relations") { c.contactRelations = try relations(x) }
        if let x = a.items("reseaux") { c.socialProfiles = try reseaux(x) }
        if let x = a.items("messageries") { c.instantMessageAddresses = try messageries(x) }
        if a.has("anniversaire") { c.birthday = try a.nonEmpty("anniversaire").map(Dates.components) }
        if a.has("anniversaire_autre_calendrier") {
            if let o = a.object("anniversaire_autre_calendrier") {
                let ids: [String: Calendar.Identifier] = ["chinese": .chinese, "chinois": .chinese, "hebrew": .hebrew, "hebreu": .hebrew,
                                                          "islamic": .islamic, "islamique": .islamic, "persian": .persian, "persan": .persian]
                guard let id = ids[fold(o.string("calendrier") ?? "")], let m = o.int("mois"), let j = o.int("jour") else {
                    throw MCPError("anniversaire_autre_calendrier : {calendrier: chinois|hebreu|islamique|persan, mois, jour, annee?}")
                }
                var dc = DateComponents(year: o.int("annee"), month: m, day: j)
                dc.calendar = Calendar(identifier: id)
                c.nonGregorianBirthday = dc
            } else { c.nonGregorianBirthday = nil }
        }
        if a.has("photo") {
            if let p = a.nonEmpty("photo") {
                let path = (p as NSString).expandingTildeInPath
                guard let data = FileManager.default.contents(atPath: path), !data.isEmpty else { throw MCPError("photo illisible : \(path)") }
                c.imageData = data
            } else { c.imageData = nil }
        }
    }

    /// Enregistre tout le lot en une requête ; si elle échoue, élément par élément pour isoler l'erreur.
    /// Un contact qui a une note n'est plus modifiable par le framework sans l'entitlement Apple des notes
    /// (erreur Core Data 134092, sonde 09) : sa note est alors mise de côté le temps de l'écriture, puis remise.
    /// `notes` : nouvelles notes demandées ; si la note d'un contact a dû être mise de côté, la nouvelle est posée
    /// à la remise (un script de moins) et son identifiant est ajouté à `notesFaites`.
    private static func enregistrer<T>(_ items: [T], ids: (T) -> [String] = { _ in [] }, notes: [String: String] = [:],
                                       notesFaites: inout Set<String>, _ add: (CNSaveRequest, T) -> Void) -> [Error?] {
        if (try? CN.execute({ r in items.forEach { add(r, $0) } })) != nil { return items.map { _ in nil } }
        var errs = items.map { x in Result { try CN.execute { add($0, x) } }.failure }
        let bloques = items.indices.filter { errs[$0].map(NotesDeCote.estBlocage) ?? false }
        let cids = Array(Set(bloques.flatMap { ids(items[$0]) }))
        guard !cids.isEmpty else { return errs }
        let nouvelles = notes.filter { cids.contains($0.key) }
        do {
            try NotesDeCote.pendant(cids, nouvelles: nouvelles) {
                for i in bloques { errs[i] = Result { try CN.execute { add($0, items[i]) } }.failure }
            }
            notesFaites.formUnion(nouvelles.keys)
        } catch { for i in bloques { errs[i] = error } }
        return errs
    }

    private static func enregistrer<T>(_ items: [T], _ add: (CNSaveRequest, T) -> Void) -> [Error?] {
        var x = Set<String>()
        return enregistrer(items, notesFaites: &x, add)
    }

    // MARK: - Création, modification, suppression

    static func creerContacts(_ a: JSON) throws -> Any {
        guard let items = a.objects("contacts"), !items.isEmpty else { throw MCPError("paramètre manquant : contacts (tableau)") }
        var res = [JSON](repeating: [:], count: items.count)
        var prets: [(i: Int, c: CNMutableContact, compte: String, groupes: [CNGroup])] = []
        for (i, x) in items.enumerated() {
            do {
                let c = CNMutableContact()
                try apply(c, x)
                guard !(c.givenName + c.familyName + c.organizationName + c.nickname).trimmingCharacters(in: .whitespaces).isEmpty
                        || !c.emailAddresses.isEmpty || !c.phoneNumbers.isEmpty else {
                    throw MCPError("contact vide : fournir au moins un nom, une société, un email ou un téléphone")
                }
                prets.append((i, c, try CN.container(x.nonEmpty("compte_id")), try (x.strings("groupe_ids") ?? []).map(CN.group)))
            } catch { res[i] = ["ok": false, "erreur": "\(error)"] }
        }
        let errs = enregistrer(prets) { r, p in
            r.add(p.c, toContainerWithIdentifier: p.compte)
            p.groupes.forEach { r.addMember(p.c, to: $0) }
        }
        var notes: [(id: String, note: String)] = []
        for (p, e) in zip(prets, errs) {
            if let e { res[p.i] = ["ok": false, "nom": CN.nom(p.c), "erreur": e.localizedDescription]; continue }
            res[p.i] = ["ok": true, "id": p.c.identifier, "nom": CN.nom(p.c)]
            if let n = items[p.i].nonEmpty("note") { notes.append((p.c.identifier, n)) }
        }
        try ecrireNotes(notes, &res, index: Dictionary(uniqueKeysWithValues: prets.map { ($0.c.identifier, $0.i) }), nouveaux: true)
        return bilan(res, "crees")
    }

    private static func ecrireNotes(_ notes: [(id: String, note: String)], _ res: inout [JSON], index: [String: Int], nouveaux: Bool = false) throws {
        guard !notes.isEmpty else { return }
        do {
            let ko = try AS.setNotes(notes, attendre: nouveaux)
            for id in ko { if let i = index[id] { res[i]["avertissement"] = "note non écrite" } }
        } catch {
            for n in notes { if let i = index[n.id] { res[i]["avertissement"] = "note non écrite : \(error)" } }
        }
    }

    private static func bilan(_ res: [JSON], _ quoi: String) -> JSON {
        let ok = res.filter { $0["ok"] as? Bool == true }.count
        return [quoi: ok, "echecs": res.count - ok, "resultats": res]
    }

    static func modifierContacts(_ a: JSON) throws -> Any {
        guard let items = a.objects("modifications"), !items.isEmpty else { throw MCPError("paramètre manquant : modifications (tableau)") }
        var res = [JSON](repeating: [:], count: items.count)
        var prets: [(i: Int, c: CNMutableContact)] = []
        for (i, x) in items.enumerated() {
            let id = x.string("id") ?? ""
            do {
                let c = try CN.contact(try x.req("id"), CN.ecriture).mutableCopy() as! CNMutableContact
                try apply(c, x)
                prets.append((i, c))
            } catch { res[i] = ["ok": false, "id": id, "erreur": "\(error)"] }
        }
        var demandees: [String: String] = [:]
        for p in prets where items[p.i].has("note") { demandees[p.c.identifier] = items[p.i].string("note") ?? "" }
        var faites = Set<String>()
        let errs = enregistrer(prets, ids: { [$0.c.identifier] }, notes: demandees, notesFaites: &faites) { $0.update($1.c) }
        var notes: [(id: String, note: String)] = []
        for (p, e) in zip(prets, errs) {
            if let e { res[p.i] = ["ok": false, "id": p.c.identifier, "erreur": e.localizedDescription]; continue }
            res[p.i] = ["ok": true, "id": p.c.identifier, "nom": CN.nom(p.c)]
            if let n = demandees[p.c.identifier], !faites.contains(p.c.identifier) { notes.append((p.c.identifier, n)) }
        }
        try ecrireNotes(notes, &res, index: Dictionary(uniqueKeysWithValues: prets.map { ($0.c.identifier, $0.i) }))
        return bilan(res, "modifies")
    }

    static func supprimerContacts(_ a: JSON) throws -> Any {
        guard let ids = a.strings("ids"), !ids.isEmpty else { throw MCPError("paramètre manquant : ids") }
        var res = [JSON](repeating: [:], count: ids.count)
        var prets: [(i: Int, c: CNContact)] = []
        for (i, id) in ids.enumerated() {
            do { prets.append((i, try CN.contact(id, CN.compact))) } catch { res[i] = ["ok": false, "id": id, "erreur": "\(error)"] }
        }
        let errs = enregistrer(prets) { $0.delete($1.c.mutableCopy() as! CNMutableContact) }
        for (p, e) in zip(prets, errs) {
            res[p.i] = e.map { ["ok": false, "id": p.c.identifier, "erreur": $0.localizedDescription] } ?? ["ok": true, "id": p.c.identifier, "nom": CN.nom(p.c)]
        }
        return bilan(res, "supprimes")
    }

    // MARK: - Groupes : ranger

    static func rangerContacts(_ a: JSON) throws -> Any {
        guard let ops = a.objects("operations"), !ops.isEmpty else { throw MCPError("paramètre manquant : operations (tableau)") }
        var res: [JSON] = []
        var retraits: [(id: String, groupe: String)] = []
        for o in ops {
            let gid = o.string("groupe_id") ?? ""
            do {
                let g = try CN.group(try o.req("groupe_id"))
                let ajouts = try (o.strings("ajouter") ?? []).map { try CN.contact($0, CN.idKey) }
                var x = Set<String>()
                let errs = enregistrer(ajouts, ids: { [$0.identifier] }, notesFaites: &x) { $0.addMember($1, to: g) }
                for (c, e) in zip(ajouts, errs) {
                    res.append(e.map { ["ok": false, "groupe_id": gid, "id": c.identifier, "ajout": true, "erreur": $0.localizedDescription] }
                               ?? ["ok": true, "groupe_id": gid, "id": c.identifier, "ajout": true])
                }
                retraits += (o.strings("retirer") ?? []).map { ($0, gid) }
            } catch { res.append(["ok": false, "groupe_id": gid, "erreur": "\(error)"]) }
        }
        if !retraits.isEmpty {
            // Le framework ne retire rien sur iCloud (sondes 04-06) : AppleScript, un script pour tout le lot
            let ko = try AS.retirer(retraits)
            for r in retraits {
                res.append(ko.contains("\(r.id)|\(r.groupe)") ? ["ok": false, "groupe_id": r.groupe, "id": r.id, "retrait": true, "erreur": "retrait refusé"]
                                                              : ["ok": true, "groupe_id": r.groupe, "id": r.id, "retrait": true])
            }
        }
        return bilan(res, "faits")
    }

    // MARK: - Doublons et fusion

    static func doublons(_ a: JSON) throws -> Any {
        let items: [CNContact]
        if let g = a.nonEmpty("groupe_id") {
            _ = try CN.group(g)
            let ids = try CN.memberIDs(g)
            items = ids.isEmpty ? [] : try CN.contacts(CNContact.predicateForContacts(withIdentifiers: Array(ids)), CN.compact)
        } else if let c = a.nonEmpty("compte_id") {
            items = try CN.contacts(CNContact.predicateForContactsInContainer(withIdentifier: try CN.container(c)), CN.compact)
        } else { items = try CN.contacts(nil, CN.compact) }

        var parent = Array(items.indices)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        var vu: [String: Int] = [:]
        var raisons: [Int: Set<String>] = [:]
        for (i, c) in items.enumerated() {
            var cles: [(String, String)] = []
            let n = fold((c.givenName + " " + c.familyName).trimmingCharacters(in: .whitespaces))
            if c.contactType == .person, !n.isEmpty { cles.append(("nom", "n:" + n)) }
            cles += c.phoneNumbers.map { chiffres($0.value.stringValue) }.filter { $0.count >= 8 }.map { ("telephone", "t:" + $0) }
            cles += c.emailAddresses.map { ("email", "e:" + ($0.value as String).lowercased()) }
            for (raison, k) in cles {
                if let j = vu[k] {
                    let (ri, rj) = (find(i), find(j))
                    if ri != rj { parent[ri] = rj }
                    raisons[i, default: []].insert(raison); raisons[j, default: []].insert(raison)
                } else { vu[k] = i }
            }
        }
        var paquets: [Int: [Int]] = [:]
        for i in items.indices { paquets[find(i), default: []].append(i) }
        let groupes = paquets.values.filter { $0.count > 1 }.map { idx -> JSON in
            ["ids": idx.map { items[$0].identifier }, "noms": idx.map { CN.nom(items[$0]) },
             "raisons": Array(idx.reduce(into: Set<String>()) { $0.formUnion(raisons[$1] ?? []) }).sorted()]
        }.sorted { ($0["noms"] as! [String])[0].localizedStandardCompare(($1["noms"] as! [String])[0]) == .orderedAscending }
        let lim = max(1, a.int("limite") ?? 20)
        var out: JSON = ["total": groupes.count, "doublons": Array(groupes.prefix(lim))]
        if groupes.count > lim { out["tronque"] = "\(lim) affichés sur \(groupes.count)" }
        return out
    }

    static func fusionnerContacts(_ a: JSON) throws -> Any {
        let cibleID = try a.req("cible_id")
        guard let srcIDs = a.strings("source_ids")?.filter({ $0 != cibleID }), !srcIDs.isEmpty else { throw MCPError("paramètre manquant : source_ids") }
        let cible = try CN.contact(cibleID, CN.ecriture).mutableCopy() as! CNMutableContact
        let sources = try srcIDs.map { try CN.contact($0, CN.ecriture) }
        var ajouts: [String: Int] = [:]
        func union<T>(_ cur: inout [CNLabeledValue<T>], _ add: [CNLabeledValue<T>], _ quoi: String, _ key: (T) -> String) {
            var seen = Set(cur.map { key($0.value) })
            for v in add where seen.insert(key(v.value)).inserted { cur.append(CNLabeledValue(label: v.label, value: v.value)); ajouts[quoi, default: 0] += 1 }
        }
        for s in sources {
            let sm = s.mutableCopy() as! CNMutableContact
            for (k, kp) in scalaires where cible[keyPath: kp].isEmpty && !sm[keyPath: kp].isEmpty {
                cible[keyPath: kp] = sm[keyPath: kp]; ajouts[k, default: 0] += 1
            }
            union(&cible.phoneNumbers, s.phoneNumbers, "telephones") { chiffres($0.stringValue) }
            union(&cible.emailAddresses, s.emailAddresses, "emails") { ($0 as String).lowercased() }
            union(&cible.urlAddresses, s.urlAddresses, "urls") { ($0 as String).lowercased() }
            union(&cible.postalAddresses, s.postalAddresses, "adresses") { fold(CNPostalAddressFormatter.string(from: $0, style: .mailingAddress)) }
            union(&cible.dates, s.dates, "dates") { Dates.text($0 as DateComponents) }
            union(&cible.contactRelations, s.contactRelations, "relations") { fold($0.name) }
            union(&cible.socialProfiles, s.socialProfiles, "reseaux") { fold($0.service + "|" + $0.username) }
            union(&cible.instantMessageAddresses, s.instantMessageAddresses, "messageries") { fold($0.service + "|" + $0.username) }
            if cible.birthday == nil, let b = s.birthday { cible.birthday = b; ajouts["anniversaire"] = 1 }
            if cible.nonGregorianBirthday == nil, let b = s.nonGregorianBirthday { cible.nonGregorianBirthday = b }
            if cible.imageData == nil, let d = s.imageData { cible.imageData = d; ajouts["photo"] = 1 }
        }
        // Notes (AppleScript) et groupes des sources, lus avant la suppression
        let notes = try AS.notes([cibleID] + srcIDs)
        var vues = Set<String>()
        let toutes = ([cibleID] + srcIDs).compactMap { notes[$0] }.filter { vues.insert($0).inserted }
        let srcSet = Set(srcIDs)
        var groupes: [CNGroup] = []
        for g in try CN.store.groups(matching: nil) {
            let m = try CN.memberIDs(g.identifier)
            if !m.contains(cibleID) && !m.isDisjoint(with: srcSet) { groupes.append(g) }
        }
        let ecrire = {
            try CN.execute { r in
                r.update(cible)
                groupes.forEach { r.addMember(cible, to: $0) }
                sources.forEach { r.delete($0.mutableCopy() as! CNMutableContact) }
            }
        }
        let reunie = toutes.count > 1 ? toutes.joined(separator: "\n\n") : nil
        var noteFaite = false
        do { try ecrire() } catch where NotesDeCote.estBlocage(error) {
            try NotesDeCote.pendant([cibleID], nouvelles: reunie.map { [cibleID: $0] } ?? [:], ecrire)
            noteFaite = true
        }
        var out: JSON = ["ok": true, "id": cibleID, "nom": CN.nom(cible), "sources_supprimees": srcIDs]
        if let reunie {
            if !noteFaite && (try? AS.setNotes([(cibleID, reunie)]))?.isEmpty != true { out["avertissement"] = "notes non fusionnées" }
            else { ajouts["note"] = 1 }
        }
        if !groupes.isEmpty { ajouts["groupes"] = groupes.count }
        out["ajouts"] = ajouts
        return out
    }

    // MARK: - vCard

    static func exporterVcard(_ a: JSON) throws -> Any {
        var ids = a.strings("ids") ?? []
        if let g = a.nonEmpty("groupe_id") { _ = try CN.group(g); ids += try CN.memberIDs(g).sorted() }
        guard !ids.isEmpty else { throw MCPError("fournir ids ou groupe_id (non vide)") }
        let path = (try a.req("chemin") as NSString).expandingTildeInPath
        // AppleScript : la vCard du framework perd la note (sonde 04), celle de l'app la garde (sonde 05)
        let cards = try AS.vcards(ids).map { $0.hasSuffix("\n") ? $0 : $0 + "\r\n" }
        let data = Data(cards.joined().utf8)
        do { try data.write(to: URL(fileURLWithPath: path)) } catch { throw MCPError("écriture impossible : \(path)") }
        return ["ok": true, "chemin": path, "nb": cards.count, "octets": data.count]
    }

    static func importerVcard(_ a: JSON) throws -> Any {
        let path = (try a.req("chemin") as NSString).expandingTildeInPath
        guard let raw = FileManager.default.contents(atPath: path), let txt = String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1) else {
            throw MCPError("fichier illisible : \(path)")
        }
        let compte = try CN.container(a.nonEmpty("compte_id"))
        let groupe = try a.nonEmpty("groupe_id").map(CN.group)
        let cartes = Vcard.cartes(txt)
        guard !cartes.isEmpty else { throw MCPError("aucune fiche vCard dans \(path)") }
        var res = [JSON](repeating: [:], count: cartes.count)
        var prets: [(i: Int, c: CNMutableContact, note: String?)] = []
        for (i, carte) in cartes.enumerated() {
            do {
                // La note est retirée avant l'analyse (le framework ne peut pas l'écrire) puis posée par AppleScript
                guard let c = try CNContactVCardSerialization.contacts(with: Data(carte.texte.utf8)).first else { throw MCPError("fiche vide") }
                prets.append((i, c.mutableCopy() as! CNMutableContact, carte.note))
            } catch { res[i] = ["ok": false, "erreur": "vCard illisible : \(error.localizedDescription)"] }
        }
        let errs = enregistrer(prets) { r, p in
            r.add(p.c, toContainerWithIdentifier: compte)
            if let g = groupe { r.addMember(p.c, to: g) }
        }
        var notes: [(id: String, note: String)] = []
        for (p, e) in zip(prets, errs) {
            if let e { res[p.i] = ["ok": false, "nom": CN.nom(p.c), "erreur": e.localizedDescription]; continue }
            res[p.i] = ["ok": true, "id": p.c.identifier, "nom": CN.nom(p.c)]
            if let n = p.note, !n.isEmpty { notes.append((p.c.identifier, n)) }
        }
        try ecrireNotes(notes, &res, index: Dictionary(uniqueKeysWithValues: prets.map { ($0.c.identifier, $0.i) }), nouveaux: true)
        return bilan(res, "crees")
    }
}

extension Result where Failure == Error {
    var failure: Error? { if case .failure(let e) = self { return e }; return nil }
}

// MARK: - Découpage d'un fichier vCard (fiches, note extraite)

enum Vcard {
    static func cartes(_ txt: String) -> [(texte: String, note: String?)] {
        // Dépliage des lignes continuées (RFC 6350 : CRLF suivi d'un espace ou d'une tabulation)
        let lignes = txt.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "").components(separatedBy: "\n")
        var out: [(String, String?)] = []
        var cur: [String] = []
        var note: String?
        var dedans = false
        for l in lignes {
            let u = l.uppercased()
            if u.hasPrefix("BEGIN:VCARD") { dedans = true; cur = [l]; note = nil; continue }
            guard dedans else { continue }
            if u.hasPrefix("END:VCARD") { cur.append(l); out.append((cur.joined(separator: "\r\n") + "\r\n", note)); dedans = false; continue }
            let nom = u.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
            let prop = nom.split(separator: ";").first.map(String.init) ?? ""
            if prop == "NOTE" || prop.hasSuffix(".NOTE"), let i = l.firstIndex(of: ":") {
                note = String(l[l.index(after: i)...]).replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
                    .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
                continue
            }
            cur.append(l)
        }
        return out
    }
}

// MARK: - Notes mises de côté (avec journal de secours, remis au démarrage suivant si le serveur s'arrête en cours)

enum NotesDeCote {
    private static let journal = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        .deletingLastPathComponent().appendingPathComponent(".notes-en-attente.json")

    static func estBlocage(_ e: Error) -> Bool { (e as NSError).code == 134092 || "\(e)".contains("134092") }

    /// Met de côté les notes de ces contacts, exécute f, puis remet les notes (ou les nouvelles, si fournies) en un script
    static func pendant(_ ids: [String], nouvelles: [String: String] = [:], _ f: () throws -> Void) throws {
        let notes = try AS.mettreNotesDeCote(ids)
        if !notes.isEmpty { try? JSONSerialization.data(withJSONObject: notes).write(to: journal) }
        var reussi = false
        defer {
            let aPoser = reussi ? notes.merging(nouvelles) { _, n in n } : notes
            if !aPoser.isEmpty { remettre(aPoser) }
        }
        try f()
        reussi = true
    }

    private static func remettre(_ notes: [String: String]) {
        do {
            _ = try AS.setNotes(notes.map { ($0.key, $0.value) })
            try? FileManager.default.removeItem(at: journal)
        } catch { log("notes non remises, gardées dans \(journal.path) : \(error)") }
    }

    /// Au démarrage : remet les notes d'une écriture interrompue
    static func reprendre() {
        guard let d = try? Data(contentsOf: journal), let n = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return }
        log("reprise de \(n.count) note(s) mises de côté")
        remettre(n)
    }
}
