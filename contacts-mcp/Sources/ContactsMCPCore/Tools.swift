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
private func ids(_ d: String) -> JSON { arr(s("Identifiant"), d) }

private let libelle = "Libellé : mobile, iphone, principal, domicile, travail, autre, ecole, fax_travail… ou texte libre"
private let valeurLibellee: JSON = ["anyOf": [s("Valeur seule (libellé par défaut)"), obj(["libelle": s(libelle), "valeur": s("Valeur")], ["valeur"])]]
private let adresse = obj(["libelle": s(libelle), "rue": s("Rue (plusieurs lignes possibles)"), "ville": s("Ville"), "code_postal": s("Code postal"),
                           "region": s("Région ou État"), "pays": s("Pays"), "code_pays": s("Code ISO du pays (fr, be…)")])

/// Champs communs à la création et à la modification. Clé absente = inchangé ; "" ou null = effacé ; une liste remplace l'existante.
private let champs: JSON = [
    "prenom": s("Prénom"), "nom_famille": s("Nom de famille"), "deuxieme_prenom": s("Deuxième prénom"),
    "prefixe": s("Préfixe (Dr, Me…)"), "suffixe": s("Suffixe"), "surnom": s("Surnom"), "nom_naissance": s("Nom de naissance"),
    "prenom_phonetique": s("Prénom phonétique"), "nom_phonetique": s("Nom phonétique"),
    "societe": s("Société"), "service": s("Service"), "poste": s("Poste"), "est_societe": b("Fiche de société (affichée sous le nom de la société)"),
    "telephones": arr(valeurLibellee, "Téléphones (mobile par défaut)"), "emails": arr(valeurLibellee, "Emails"),
    "urls": arr(valeurLibellee, "Sites web (libellé page_accueil possible)"), "adresses": arr(adresse, "Adresses postales"),
    "anniversaire": s("AAAA-MM-JJ, ou --MM-JJ sans année"),
    "anniversaire_autre_calendrier": obj(["calendrier": e(["chinois", "hebreu", "islamique", "persan"], "Calendrier"),
                                          "mois": n("Mois"), "jour": n("Jour"), "annee": n("Année (facultatif)")], ["calendrier", "mois", "jour"]),
    "dates": arr(obj(["libelle": s("anniversaire (de mariage), autre ou texte libre"), "date": s("AAAA-MM-JJ ou --MM-JJ")], ["date"]), "Autres dates"),
    "relations": arr(obj(["libelle": s("mere, pere, parent, frere, soeur, enfant, fils, fille, conjoint, partenaire, ami, assistant, manager ou texte libre"),
                          "nom": s("Nom de la personne liée")], ["nom"]), "Personnes liées"),
    "reseaux": arr(obj(["service": s("LinkedIn, Twitter, Facebook…"), "utilisateur": s("Nom d'utilisateur"), "url": s("URL du profil")]), "Profils de réseaux sociaux"),
    "messageries": arr(obj(["service": s("Skype, Jabber…"), "utilisateur": s("Identifiant")], ["utilisateur"]), "Messageries instantanées"),
    "photo": s("Chemin absolu d'une image (\"\" pour retirer la photo)"),
    "note": s("Note de la fiche (\"\" pour effacer)"),
]

private var champsCreation: JSON {
    var c = champs
    c["groupe_ids"] = ids("Groupes où ranger le contact")
    c["compte_id"] = s("Compte (compte par défaut si absent ; voir l'outil groupes)")
    return c
}

private var champsModification: JSON {
    var c = champs
    c["id"] = s("Identifiant du contact")
    c["ajouter_telephones"] = arr(valeurLibellee, "Téléphones à ajouter")
    c["retirer_telephones"] = arr(s("Numéro (comparé sur les 9 derniers chiffres)"), "Téléphones à retirer")
    c["ajouter_emails"] = arr(valeurLibellee, "Emails à ajouter")
    c["retirer_emails"] = arr(s("Email"), "Emails à retirer")
    return c
}

/// Annotations MCP : seules les lectures sont readOnly, seules les suppressions (fusion comprise) sont destructive
private let lectures: Set<String> = ["groupes", "contacts", "doublons"]
private let destructifs: Set<String> = ["supprimer_groupe", "supprimer_contacts", "fusionner_contacts"]
private func annotations(_ nom: String) -> JSON {
    var a: JSON = ["readOnlyHint": lectures.contains(nom), "destructiveHint": destructifs.contains(nom), "openWorldHint": false]
    if nom.hasPrefix("supprimer_") { a["idempotentHint"] = true }
    return a
}

enum Tools {
    static let definitions: [JSON] = outils.map { o in
        var o = o
        o["annotations"] = annotations(o["name"] as! String)
        return o
    }

    private static let outils: [JSON] = [
        ["name": "groupes",
         "description": "Liste les comptes (iCloud, Exchange, Sur mon Mac) avec leur nombre de contacts, et les groupes avec identifiant, compte, nombre de membres et groupe parent. À appeler pour connaître les groupe_id et compte_id.",
         "inputSchema": obj(["nom_contient": s("Ne garder que les groupes dont le nom contient ce texte")])],
        ["name": "creer_groupe",
         "description": "Crée un groupe, éventuellement dans un groupe parent (sous-groupe). Renvoie son identifiant.",
         "inputSchema": obj(["nom": s("Nom"), "parent_id": s("Créer comme sous-groupe de ce groupe"), "compte_id": s("Compte (par défaut si absent)")], ["nom"])],
        ["name": "modifier_groupe",
         "description": "Renomme un groupe, le range dans un groupe parent ou l'en sort.",
         "inputSchema": obj(["id": s("Identifiant du groupe"), "nom": s("Nouveau nom"), "parent_id": s("Groupe parent (\"\" pour le sortir de son parent)")], ["id"])],
        ["name": "supprimer_groupe",
         "description": "Supprime définitivement des groupes par identifiant. Leurs contacts sont conservés.",
         "inputSchema": obj(["ids": ids("Groupes à supprimer")], ["ids"])],
        ["name": "contacts",
         "description": "Cherche et lit des contacts. Filtres combinables : ids, texte (nom, société, poste, email, téléphone, ville…), téléphone (tout format), email exact, groupe, compte, Ma carte, sélection de l'app, anniversaires à venir, modifiés depuis, fiches sans téléphone ou sans email. Vue compacte (id, nom, société, 1er tél, 1er email) ; detail: true pour tous les champs, la note et les groupes. 20 résultats par défaut, triés par nom.",
         "inputSchema": obj([
            "ids": ids("Limiter à ces contacts"),
            "texte": s("Recherche sans tenir compte des accents ni de la casse"),
            "dans_notes": b("Chercher le texte dans les notes au lieu des champs"),
            "telephone": s("Numéro, tout format (comparé sur les 9 derniers chiffres)"),
            "email": s("Adresse email exacte"),
            "groupe_id": s("Membres de ce groupe"),
            "compte_id": s("Contacts de ce compte"),
            "ma_carte": b("Seulement « Ma carte »"),
            "selection": b("Seulement les contacts sélectionnés dans l'app Contacts"),
            "anniversaires_jours": n("Anniversaires dans les N prochains jours (0 = aujourd'hui), triés par date"),
            "modifies_depuis": s("Modifiés depuis AAAA-MM-JJ, du plus récent au plus ancien"),
            "sans": e(["telephone", "email"], "Fiches sans téléphone ou sans email"),
            "detail": b("Tous les champs, la note et les groupes"),
            "limite": n("Nombre maximum de résultats (20 par défaut)"),
         ])],
        ["name": "creer_contacts",
         "description": "Crée un ou plusieurs contacts en un appel (par ex. depuis une signature ou une carte de visite), avec tous les champs, note, photo et groupes. Renvoie le succès ou l'échec élément par élément, avec les identifiants.",
         "inputSchema": obj(["contacts": arr(obj(champsCreation), "Contacts à créer")], ["contacts"])],
        ["name": "modifier_contacts",
         "description": "Modifie un ou plusieurs contacts par identifiant. Seuls les champs fournis changent ; une liste fournie remplace l'existante (ajouter_/retirer_ pour les téléphones et emails).",
         "inputSchema": obj(["modifications": arr(obj(champsModification, ["id"]), "Une entrée par contact")], ["modifications"])],
        ["name": "supprimer_contacts",
         "description": "Supprime définitivement des contacts par identifiant.",
         "inputSchema": obj(["ids": ids("Contacts à supprimer")], ["ids"])],
        ["name": "ranger_contacts",
         "description": "Ajoute des contacts à des groupes ou les en retire (les contacts sont conservés), en un appel.",
         "inputSchema": obj(["operations": arr(obj(["groupe_id": s("Groupe"), "ajouter": ids("Contacts à ajouter"), "retirer": ids("Contacts à retirer")], ["groupe_id"]), "Une entrée par groupe")], ["operations"])],
        ["name": "doublons",
         "description": "Repère les doublons probables (même nom, même téléphone ou même email) et les renvoie par paquets avec la raison. À utiliser avant fusionner_contacts.",
         "inputSchema": obj(["groupe_id": s("Limiter à ce groupe"), "compte_id": s("Limiter à ce compte"), "limite": n("Paquets maximum (20 par défaut)")])],
        ["name": "fusionner_contacts",
         "description": "Fusionne des fiches dans une fiche cible : champs vides complétés, téléphones, emails, adresses, dates… ajoutés sans doublon, notes réunies, groupes repris. Les fiches sources sont ensuite supprimées définitivement.",
         "inputSchema": obj(["cible_id": s("Contact conservé"), "source_ids": ids("Contacts fusionnés puis supprimés")], ["cible_id", "source_ids"])],
        ["name": "exporter_vcard",
         "description": "Écrit des contacts (ou tout un groupe) dans un fichier .vcf, note comprise. Pour partager une fiche, l'exporter puis la joindre à un mail.",
         "inputSchema": obj(["ids": ids("Contacts à exporter"), "groupe_id": s("Exporter tous les membres de ce groupe"), "chemin": s("Chemin absolu du fichier .vcf à écrire")], ["chemin"])],
        ["name": "importer_vcard",
         "description": "Crée des contacts depuis un fichier .vcf (une ou plusieurs fiches), note comprise, éventuellement dans un groupe.",
         "inputSchema": obj(["chemin": s("Chemin absolu du fichier .vcf"), "groupe_id": s("Ranger les contacts importés dans ce groupe"), "compte_id": s("Compte (par défaut si absent)")], ["chemin"])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        try CN.ready()
        switch name {
        case "groupes": return try Handlers.groupes(a)
        case "creer_groupe": return try Handlers.creerGroupe(a)
        case "modifier_groupe": return try Handlers.modifierGroupe(a)
        case "supprimer_groupe": return try Handlers.supprimerGroupe(a)
        case "contacts": return try Handlers.contacts(a)
        case "creer_contacts": return try Handlers.creerContacts(a)
        case "modifier_contacts": return try Handlers.modifierContacts(a)
        case "supprimer_contacts": return try Handlers.supprimerContacts(a)
        case "ranger_contacts": return try Handlers.rangerContacts(a)
        case "doublons": return try Handlers.doublons(a)
        case "fusionner_contacts": return try Handlers.fusionnerContacts(a)
        case "exporter_vcard": return try Handlers.exporterVcard(a)
        case "importer_vcard": return try Handlers.importerVcard(a)
        default: throw MCPError("outil inconnu : \(name)")
        }
    }
}
