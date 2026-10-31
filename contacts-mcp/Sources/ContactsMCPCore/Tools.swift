// Outils exposés : noms, descriptions (quand les utiliser) et schémas d'entrée
import Foundation

private func obj(_ props: JSON, _ required: [String] = []) -> JSON {
    ["type": "object", "properties": props, "required": required]
}
private func s(_ d: String) -> JSON { ["type": "string", "description": d] }
private func b(_ d: String) -> JSON { ["type": "boolean", "description": d] }
private func n(_ d: String) -> JSON { ["type": "number", "description": d] }
private func e(_ values: [String], _ d: String) -> JSON { ["type": "string", "enum": values, "description": d] }
private func arr(_ items: JSON, _ d: String) -> JSON { ["type": "array", "items": items, "description": d] }
private func ids(_ d: String) -> JSON { arr(s("Identifier"), d) }

private let libelle = "Label: mobile, iphone, main, home, work, other, school, work_fax… or free text"
private let valeurLibellee: JSON = ["anyOf": [s("Value only (default label)"), obj(["label": s(libelle), "value": s("Value")], ["value"])]]
private let adresse = obj(["label": s(libelle), "street": s("Street (may span several lines)"), "city": s("City"), "postal_code": s("Postal code"),
                           "state": s("State or region"), "country": s("Country"), "country_code": s("ISO country code (us, fr…)")])

/// Champs communs à la création et à la modification. Clé absente = inchangé ; "" ou null = effacé ; une liste remplace l'existante.
private let champs: JSON = [
    "first_name": s("First name"), "last_name": s("Last name"), "middle_name": s("Middle name"),
    "prefix": s("Prefix (Dr, Mr…)"), "suffix": s("Suffix"), "nickname": s("Nickname"), "maiden_name": s("Maiden name"),
    "phonetic_first_name": s("Phonetic first name"), "phonetic_last_name": s("Phonetic last name"),
    "organization": s("Company"), "department": s("Department"), "job_title": s("Job title"), "is_company": b("Company card (shown under the company name)"),
    "phones": arr(valeurLibellee, "Phone numbers (mobile by default)"), "emails": arr(valeurLibellee, "Emails"),
    "urls": arr(valeurLibellee, "Websites (homepage label available)"), "addresses": arr(adresse, "Postal addresses"),
    "birthday": s("YYYY-MM-DD, or --MM-DD for a birthday without a year"),
    "alternate_birthday": obj(["calendar": e(["chinese", "hebrew", "islamic", "persian"], "Calendar"),
                               "month": n("Month"), "day": n("Day"), "year": n("Year (optional)")], ["calendar", "month", "day"]),
    "dates": arr(obj(["label": s("anniversary, other or free text"), "date": s("YYYY-MM-DD or --MM-DD")], ["date"]), "Other dates"),
    "related_names": arr(obj(["label": s("mother, father, parent, brother, sister, child, son, daughter, spouse, partner, friend, assistant, manager or free text"),
                              "name": s("Name of the related person")], ["name"]), "Related names"),
    "social_profiles": arr(obj(["service": s("LinkedIn, Twitter, Facebook…"), "username": s("Username"), "url": s("Profile URL")]), "Social profiles"),
    "instant_messages": arr(obj(["service": s("Skype, Jabber…"), "username": s("Username")], ["username"]), "Instant message addresses"),
    "photo": s("Absolute path to an image (\"\" to remove the photo)"),
    "note": s("Card note (\"\" to clear)"),
]

private var champsCreation: JSON {
    var c = champs
    c["group_ids"] = ids("Groups to add the contact to")
    c["account_id"] = s("Account (default account if omitted; see the list_groups tool)")
    return c
}

private var champsModification: JSON {
    var c = champs
    c["id"] = s("Contact identifier")
    c["add_phones"] = arr(valeurLibellee, "Phone numbers to add")
    c["remove_phones"] = arr(s("Number (matched on the last 9 digits)"), "Phone numbers to remove")
    c["add_emails"] = arr(valeurLibellee, "Emails to add")
    c["remove_emails"] = arr(s("Email"), "Emails to remove")
    return c
}

/// Annotations MCP : seules les lectures sont readOnly, seules les suppressions (fusion comprise) sont destructive
private let lectures: Set<String> = ["list_groups", "list_contacts", "find_duplicates"]
private let destructifs: Set<String> = ["delete_group", "delete_contacts", "merge_contacts"]
private func annotations(_ nom: String) -> JSON {
    var a: JSON = ["readOnlyHint": lectures.contains(nom), "destructiveHint": destructifs.contains(nom), "openWorldHint": false]
    if nom.hasPrefix("delete_") { a["idempotentHint"] = true }
    return a
}

enum Tools {
    static let definitions: [JSON] = outils.map { o in
        var o = o
        o["annotations"] = annotations(o["name"] as! String)
        return o
    }

    private static let outils: [JSON] = [
        ["name": "list_groups",
         "description": "Lists accounts (iCloud, Exchange, On My Mac) with their contact count, and groups with identifier, account, member count and parent group. Call it to get group_id and account_id values.",
         "inputSchema": obj(["name_contains": s("Only keep groups whose name contains this text")])],
        ["name": "create_group",
         "description": "Creates a group, optionally inside a parent group (subgroup). Returns its identifier.",
         "inputSchema": obj(["name": s("Name"), "parent_id": s("Create as a subgroup of this group"), "account_id": s("Account (default if omitted)")], ["name"])],
        ["name": "update_group",
         "description": "Renames a group, or moves it into a parent group.",
         "inputSchema": obj(["id": s("Group identifier"), "name": s("New name"), "parent_id": s("Parent group (\"\" to take it out of its parent)")], ["id"])],
        ["name": "delete_group",
         "description": "Permanently deletes groups by identifier. Their contacts are kept.",
         "inputSchema": obj(["ids": ids("Groups to delete")], ["ids"])],
        ["name": "list_contacts",
         "description": "Searches and reads contacts. Combinable filters: ids, text (name, company, job title, email, phone, city…), phone (any format), exact email, group, account, My Card, app selection, upcoming birthdays, modified since, cards without a phone or without an email. Compact view (id, name, company, first phone, first email); detail: true for every field, the note and the groups. 20 results by default, sorted by name.",
         "inputSchema": obj([
            "ids": ids("Restrict to these contacts"),
            "text": s("Search, ignoring accents and case"),
            "in_notes": b("Search the text in notes instead of fields"),
            "phone": s("Number, any format (matched on the last 9 digits)"),
            "email": s("Exact email address"),
            "group_id": s("Members of this group"),
            "account_id": s("Contacts in this account"),
            "my_card": b("Only “My Card”"),
            "selection": b("Only the contacts selected in the Contacts app"),
            "birthdays_within_days": n("Birthdays in the next N days (0 = today), sorted by date"),
            "modified_since": s("Modified since YYYY-MM-DD, newest first"),
            "missing": e(["phone", "email"], "Cards without a phone or without an email"),
            "detail": b("Every field, the note and the groups"),
            "limit": n("Maximum number of results (20 by default)"),
         ])],
        ["name": "create_contacts",
         "description": "Creates one or more contacts in a single call (e.g. from an email signature or a business card), with every field, note, photo and groups. Returns success or failure per item, with identifiers.",
         "inputSchema": obj(["contacts": arr(obj(champsCreation), "Contacts to create")], ["contacts"])],
        ["name": "update_contacts",
         "description": "Updates one or more contacts by identifier. Only the fields provided change; a list provided replaces the existing one (add_/remove_ for phones and emails).",
         "inputSchema": obj(["updates": arr(obj(champsModification, ["id"]), "One entry per contact")], ["updates"])],
        ["name": "delete_contacts",
         "description": "Permanently deletes contacts by identifier.",
         "inputSchema": obj(["ids": ids("Contacts to delete")], ["ids"])],
        ["name": "organize_contacts",
         "description": "Adds contacts to groups or removes them from groups (the contacts are kept), in a single call.",
         "inputSchema": obj(["operations": arr(obj(["group_id": s("Group"), "add": ids("Contacts to add"), "remove": ids("Contacts to remove")], ["group_id"]), "One entry per group")], ["operations"])],
        ["name": "find_duplicates",
         "description": "Finds likely duplicates (same name, same phone or same email) and returns them in clusters with the reason. Use before merge_contacts.",
         "inputSchema": obj(["group_id": s("Restrict to this group"), "account_id": s("Restrict to this account"), "limit": n("Maximum clusters (20 by default)")])],
        ["name": "merge_contacts",
         "description": "Merges cards into a target card: empty fields filled in, phones, emails, addresses, dates… added without duplicates, notes combined, groups carried over. The source cards are then permanently deleted.",
         "inputSchema": obj(["target_id": s("Contact to keep"), "source_ids": ids("Contacts merged then deleted")], ["target_id", "source_ids"])],
        ["name": "export_vcard",
         "description": "Writes contacts (or a whole group) to a .vcf file, note included. To share a card, export it then attach it to an email.",
         "inputSchema": obj(["ids": ids("Contacts to export"), "group_id": s("Export every member of this group"), "path": s("Absolute path of the .vcf file to write")], ["path"])],
        ["name": "import_vcard",
         "description": "Creates contacts from a .vcf file (one or more cards), note included, optionally in a group.",
         "inputSchema": obj(["path": s("Absolute path of the .vcf file"), "group_id": s("Add the imported contacts to this group"), "account_id": s("Account (default if omitted)")], ["path"])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        try CN.ready()
        switch name {
        case "list_groups": return try Handlers.groupes(a)
        case "create_group": return try Handlers.creerGroupe(a)
        case "update_group": return try Handlers.modifierGroupe(a)
        case "delete_group": return try Handlers.supprimerGroupe(a)
        case "list_contacts": return try Handlers.contacts(a)
        case "create_contacts": return try Handlers.creerContacts(a)
        case "update_contacts": return try Handlers.modifierContacts(a)
        case "delete_contacts": return try Handlers.supprimerContacts(a)
        case "organize_contacts": return try Handlers.rangerContacts(a)
        case "find_duplicates": return try Handlers.doublons(a)
        case "merge_contacts": return try Handlers.fusionnerContacts(a)
        case "export_vcard": return try Handlers.exporterVcard(a)
        case "import_vcard": return try Handlers.importerVcard(a)
        default: throw MCPError("unknown tool: \(name)")
        }
    }
}
