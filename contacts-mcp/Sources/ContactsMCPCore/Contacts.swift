// Voie publique : framework Contacts (comptes, groupes, contacts et tous leurs champs sauf la note, photo, vCard)
import Foundation
import Contacts

enum CN {
    private(set) static var store = CNContactStore()
    private static var granted = false

    /// Vérifie l'accès à Contacts (le demande au premier appel), puis repart d'un store frais
    /// (AppleScript a pu écrire entre deux appels).
    static func ready() throws {
        if !granted {
            if CNContactStore.authorizationStatus(for: .contacts) != .authorized {
                let sem = DispatchSemaphore(value: 0)
                var ok = false
                CNContactStore().requestAccess(for: .contacts) { g, _ in ok = g; sem.signal() }
                sem.wait()
                guard ok else {
                    throw MCPError("access to Contacts denied. System Settings > Privacy & Security > Contacts: allow ContactsMCP, then restart the Claude app.")
                }
            }
            granted = true
            NotesDeCote.reprendre()
        }
        store = CNContactStore()
    }

    // MARK: - Clés

    private static func k(_ s: String...) -> [CNKeyDescriptor] { s.map { $0 as NSString } }
    static let compact: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
        + k(CNContactIdentifierKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactTypeKey)
    static let recherche: [CNKeyDescriptor] = compact + k(CNContactNicknameKey, CNContactDepartmentNameKey, CNContactJobTitleKey,
        CNContactPostalAddressesKey, CNContactBirthdayKey, CNContactUrlAddressesKey)
    static let complet: [CNKeyDescriptor] = recherche + k(CNContactGivenNameKey, CNContactFamilyNameKey, CNContactMiddleNameKey,
        CNContactNamePrefixKey, CNContactNameSuffixKey, CNContactPreviousFamilyNameKey, CNContactPhoneticGivenNameKey,
        CNContactPhoneticFamilyNameKey, CNContactNonGregorianBirthdayKey, CNContactDatesKey, CNContactRelationsKey,
        CNContactSocialProfilesKey, CNContactInstantMessageAddressesKey, CNContactImageDataAvailableKey)
    static let ecriture: [CNKeyDescriptor] = complet + k(CNContactImageDataKey)
    static let idKey: [CNKeyDescriptor] = k(CNContactIdentifierKey)

    // MARK: - Accès

    static func contacts(_ predicate: NSPredicate?, _ keys: [CNKeyDescriptor]) throws -> [CNContact] {
        let fr = CNContactFetchRequest(keysToFetch: keys)
        fr.predicate = predicate
        fr.unifyResults = true
        var out: [CNContact] = []
        try store.enumerateContacts(with: fr) { c, _ in out.append(c) }
        return out
    }

    static func contact(_ id: String, _ keys: [CNKeyDescriptor]) throws -> CNContact {
        do { return try store.unifiedContact(withIdentifier: id, keysToFetch: keys) }
        catch { throw MCPError("contact not found: \(id)") }
    }

    static func group(_ id: String) throws -> CNGroup {
        guard let g = try store.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [id])).first else {
            throw MCPError("group not found: \(id)")
        }
        return g
    }

    static func memberIDs(_ groupID: String) throws -> Set<String> {
        Set(try contacts(CNContact.predicateForContactsInGroup(withIdentifier: groupID), idKey).map(\.identifier))
    }

    static func container(_ id: String?) throws -> String {
        guard let id else { return store.defaultContainerIdentifier() }
        guard try !store.containers(matching: CNContainer.predicateForContainers(withIdentifiers: [id])).isEmpty else {
            throw MCPError("account not found: \(id) (see the list_groups tool)")
        }
        return id
    }

    static func execute(_ build: (CNSaveRequest) throws -> Void) throws {
        let r = CNSaveRequest()
        try build(r)
        let t0 = Date()
        defer { let ms = Int(Date().timeIntervalSince(t0) * 1000); if ms > 300 { log("framework write \(ms) ms") } }
        try store.execute(r)
    }

    static func nom(_ c: CNContact) -> String {
        if let n = CNContactFormatter.string(from: c, style: .fullName), !n.isEmpty { return n }
        if !c.organizationName.isEmpty { return c.organizationName }
        return (c.emailAddresses.first?.value as String?) ?? ""
    }

    static func typeCompte(_ t: CNContainerType) -> String {
        switch t {
        case .local: return "on_my_mac"
        case .exchange: return "exchange"
        case .cardDAV: return "carddav"
        default: return "unknown"
        }
    }
}

// MARK: - Libellés (clé courte ↔ libellé Contacts ; tout autre texte devient un libellé personnalisé)

enum Labels {
    enum Kind { case phone, generic, date, relation }
    private static let commun: [(String, String)] = [("home", CNLabelHome), ("work", CNLabelWork), ("other", CNLabelOther), ("school", CNLabelSchool)]
    private static let specifiques: [Kind: [(String, String)]] = [
        .phone: [("mobile", CNLabelPhoneNumberMobile), ("iphone", CNLabelPhoneNumberiPhone), ("main", CNLabelPhoneNumberMain),
                 ("home_fax", CNLabelPhoneNumberHomeFax), ("work_fax", CNLabelPhoneNumberWorkFax), ("pager", CNLabelPhoneNumberPager)],
        .generic: [("icloud", CNLabelEmailiCloud), ("homepage", CNLabelURLAddressHomePage)],
        .date: [("anniversary", CNLabelDateAnniversary)],
        .relation: [("father", CNLabelContactRelationFather), ("mother", CNLabelContactRelationMother), ("parent", CNLabelContactRelationParent),
                    ("brother", CNLabelContactRelationBrother), ("sister", CNLabelContactRelationSister), ("child", CNLabelContactRelationChild),
                    ("son", CNLabelContactRelationSon), ("daughter", CNLabelContactRelationDaughter), ("friend", CNLabelContactRelationFriend),
                    ("spouse", CNLabelContactRelationSpouse), ("partner", CNLabelContactRelationPartner),
                    ("assistant", CNLabelContactRelationAssistant), ("manager", CNLabelContactRelationManager)],
    ]
    private static let alias: [String: String] = ["home_page": "homepage", "fax_home": "home_fax", "fax_work": "work_fax"]
    private static let inverse: [String: String] = {
        var d: [String: String] = [:]
        for (fr, cn) in commun + specifiques.values.flatMap({ $0 }) where d[cn] == nil { d[cn] = fr }
        return d
    }()

    static func cn(_ s: String?, _ kind: Kind) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var key = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).replacingOccurrences(of: " ", with: "_")
        key = alias[key] ?? key
        return (commun + (specifiques[kind] ?? [])).first { $0.0 == key }?.1 ?? s
    }

    static func fr(_ label: String?) -> String? {
        guard let l = label, !l.isEmpty else { return nil }
        if let f = inverse[l] { return f }
        if l.hasPrefix("_$!<") { return CNLabeledValue<NSString>.localizedString(forLabel: l) }
        return l
    }
}

// MARK: - Dates (AAAA-MM-JJ ; --MM-JJ ou MM-JJ sans année)

enum Dates {
    static var cal: Calendar { Calendar(identifier: .gregorian) }
    private static let pattern = try! NSRegularExpression(pattern: #"^(?:(\d{4})-|-{0,2})(\d{1,2})-(\d{1,2})$"#)

    static func components(_ s: String) throws -> DateComponents {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let m = pattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else {
            throw MCPError("invalid date “\(s)”: expected YYYY-MM-DD, or --MM-DD for a birthday without a year")
        }
        func g(_ i: Int) -> Int? { Range(m.range(at: i), in: t).flatMap { Int(t[$0]) } }
        guard let mo = g(2), let d = g(3), (1...12).contains(mo), (1...31).contains(d) else { throw MCPError("invalid date: \(s)") }
        return DateComponents(year: g(1), month: mo, day: d)
    }

    static func text(_ dc: DateComponents) -> String {
        if let y = dc.year { return String(format: "%04d-%02d-%02d", y, dc.month ?? 0, dc.day ?? 0) }
        return String(format: "--%02d-%02d", dc.month ?? 0, dc.day ?? 0)
    }

    static func jour(_ s: String) throws -> Date {
        let dc = try components(s)
        guard dc.year != nil, let d = cal.date(from: dc) else { throw MCPError("full date expected (YYYY-MM-DD): \(s)") }
        return d
    }

    /// Jours avant le prochain anniversaire (0 = aujourd'hui)
    static func joursAvant(_ dc: DateComponents, depuis today: Date) -> Int? {
        guard let m = dc.month, let d = dc.day else { return nil }
        let c = cal
        let y = c.component(.year, from: today)
        for year in [y, y + 1] {
            if let date = c.date(from: DateComponents(year: year, month: m, day: d)), date >= today {
                return c.dateComponents([.day], from: today, to: date).day
            }
        }
        return nil
    }

    static func iso(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return String(format: "%04d-%02d-%02dT%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!)
    }
}

func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
func chiffres(_ s: String) -> String { String(s.filter(\.isNumber).suffix(9)) }
