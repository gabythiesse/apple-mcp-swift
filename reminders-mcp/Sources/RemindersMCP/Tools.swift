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

private let dateHelp = "AAAA-MM-JJ (journée entière) ou AAAA-MM-JJTHH:MM (heure locale)"

private let alarme = obj([
    "date": s("Alerte à une date : \(dateHelp)"),
    "minutes_avant": n("Alerte N minutes avant l'échéance"),
    "lieu": s("Alerte de lieu : nom du lieu (avec latitude et longitude)"),
    "latitude": n("Latitude du lieu"),
    "longitude": n("Longitude du lieu"),
    "rayon": n("Rayon en mètres (100 par défaut)"),
    "quand": e(["arrivee", "depart"], "Déclencher à l'arrivée ou au départ (arrivee par défaut)"),
])

private let recurrence = obj([
    "frequence": e(["jour", "semaine", "mois", "annee"], "Fréquence"),
    "intervalle": n("Tous les N (1 par défaut)"),
    "jours": arr(e(["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"], "Jour"), "Jours de la semaine (fréquence semaine)"),
    "fin_le": s("Date de fin : \(dateHelp)"),
    "occurrences": n("Nombre d'occurrences"),
], ["frequence"])

/// Champs communs à la création et à la modification
private let champs: JSON = [
    "titre": s("Titre"),
    "notes": s("Notes (\"\" pour effacer)"),
    "echeance": s("Échéance : \(dateHelp). Avec une heure, une alerte est posée à l'heure d'échéance comme dans l'app. \"\" pour effacer"),
    "debut": s("Date de début : \(dateHelp). \"\" pour effacer"),
    "priorite": e(["haute", "moyenne", "basse", "aucune"], "Priorité"),
    "drapeau": b("Drapeau"),
    "url": s("URL affichée dans le rappel (\"\" pour retirer)"),
    "section_id": s("Section de la liste (voir l'outil sections ; \"\" pour sortir de la section)"),
    "alarmes": arr(alarme, "Alertes (remplace toutes les alertes existantes ; [] pour toutes les retirer)"),
    "recurrence": ["description": "Récurrence (null pour la retirer). Nécessite une échéance.", "anyOf": [recurrence, ["type": "null"]]],
]

private var champsCreation: JSON {
    var c = champs
    c["liste_id"] = s("Liste (liste par défaut si absent ; ignoré pour une sous-tâche)")
    c["tags"] = arr(s("Tag sans #"), "Tags")
    c["parent_id"] = s("Créer comme sous-tâche de ce rappel")
    c["sous_taches"] = arr(obj(champs, ["titre"]), "Sous-tâches à créer sous ce rappel (un seul niveau)")
    return c
}

private var champsModification: JSON {
    var c = champs
    c["id"] = s("Identifiant du rappel")
    c["liste_id"] = s("Déplacer vers cette liste (les sous-tâches suivent)")
    c["parent_id"] = s("Faire de ce rappel une sous-tâche de ce parent (\"\" pour le détacher)")
    c["ajouter_tags"] = arr(s("Tag sans #"), "Tags à ajouter")
    c["retirer_tags"] = arr(s("Tag sans #"), "Tags à retirer")
    return c
}

/// Annotations MCP : seules les lectures sont readOnly, seules les suppressions sont destructive
private let lectures: Set<String> = ["listes", "rappels", "sections", "tags"]
private func annotations(_ nom: String) -> JSON {
    var a: JSON = ["readOnlyHint": lectures.contains(nom), "destructiveHint": nom.hasPrefix("supprimer_"), "openWorldHint": false]
    if nom == "terminer_rappels" { a["idempotentHint"] = true }
    return a
}

enum Tools {
    static let definitions: [JSON] = outils.map { o in
        var o = o
        o["annotations"] = annotations(o["name"] as! String)
        return o
    }

    private static let outils: [JSON] = [
        ["name": "listes",
         "description": "Liste les listes de Rappels avec leur identifiant, compte, couleur, groupe et nombre de rappels à faire. À appeler d'abord pour connaître les liste_id. Les groupes (dossiers de listes) ont groupe: true.",
         "inputSchema": obj(["nom_contient": s("Ne garder que les listes dont le nom contient ce texte")])],
        ["name": "creer_liste",
         "description": "Crée une liste, ou un groupe de listes (groupe: true). Renvoie son identifiant.",
         "inputSchema": obj(["nom": s("Nom"), "couleur": s("#RRGGBB ou rouge, orange, jaune, vert, bleu, violet, marron, gris, rose"),
                             "groupe": b("Créer un groupe (dossier de listes) au lieu d'une liste"),
                             "groupe_id": s("Créer la liste dans ce groupe")], ["nom"])],
        ["name": "modifier_liste",
         "description": "Renomme une liste ou un groupe, change sa couleur, la range dans un groupe ou l'en sort.",
         "inputSchema": obj(["id": s("Identifiant de la liste ou du groupe"), "nom": s("Nouveau nom"), "couleur": s("#RRGGBB ou nom de couleur"),
                             "groupe_id": s("Ranger la liste dans ce groupe (\"\" pour la sortir de son groupe)")], ["id"])],
        ["name": "supprimer_liste",
         "description": "Supprime définitivement une liste (et ses rappels) ou un groupe vide, par identifiant. Refuse une liste non vide sans force: true.",
         "inputSchema": obj(["id": s("Identifiant de la liste ou du groupe"), "force": b("Supprimer aussi les rappels qu'elle contient")], ["id"])],
        ["name": "sections",
         "description": "Liste les sections d'une liste (identifiant et nom), pour ranger des rappels avec section_id.",
         "inputSchema": obj(["liste_id": s("Identifiant de la liste")], ["liste_id"])],
        ["name": "creer_section",
         "description": "Crée une section dans une liste. Renvoie son identifiant.",
         "inputSchema": obj(["liste_id": s("Identifiant de la liste"), "nom": s("Nom de la section")], ["liste_id", "nom"])],
        ["name": "supprimer_section",
         "description": "Supprime une section par identifiant. Ses rappels restent dans la liste, hors section.",
         "inputSchema": obj(["id": s("Identifiant de la section")], ["id"])],
        ["name": "rappels",
         "description": "Lit des rappels avec filtres : vues toutes faites (aujourdhui inclut les retards, en_retard, semaine, programmes, drapeau, termines_recents), listes, texte, tag, dates, statut, sous-tâches d'un parent. Renvoie identifiants, échéances, tags, drapeau, sous-tâches, section, etc. 100 résultats par défaut, triés par échéance.",
         "inputSchema": obj([
            "vue": e(["aujourdhui", "en_retard", "semaine", "programmes", "drapeau", "termines_recents"], "Vue toute faite"),
            "liste_ids": arr(s("Identifiant de liste"), "Limiter à ces listes"),
            "statut": e(["a_faire", "termines", "tous"], "a_faire par défaut"),
            "texte": s("Recherche dans le titre et les notes (sans tenir compte des accents ni de la casse)"),
            "tag": s("Ne garder que ce tag (sans #)"),
            "drapeau": b("Ne garder que les rappels avec (true) ou sans (false) drapeau"),
            "echeance_avant": s("Échéance strictement avant : \(dateHelp)"),
            "echeance_apres": s("Échéance à partir de : \(dateHelp)"),
            "sans_echeance": b("Ne garder que les rappels sans échéance"),
            "parent_id": s("Ne renvoyer que les sous-tâches de ce rappel"),
            "limite": n("Nombre maximum de résultats (100 par défaut)"),
         ])],
        ["name": "creer_rappels",
         "description": "Crée un ou plusieurs rappels en un appel (par ex. toutes les tâches d'un compte-rendu), avec sous-tâches, tags, drapeau, alertes, récurrence, URL, section. Renvoie le succès ou l'échec élément par élément, avec les identifiants.",
         "inputSchema": obj(["rappels": arr(obj(champsCreation, ["titre"]), "Rappels à créer")], ["rappels"])],
        ["name": "modifier_rappels",
         "description": "Modifie un ou plusieurs rappels par identifiant : champs, tags, drapeau, déplacement de liste (sous-tâches comprises), section, rattachement à un parent. Seuls les champs fournis changent. Pour terminer, utiliser terminer_rappels.",
         "inputSchema": obj(["modifications": arr(obj(champsModification, ["id"]), "Une entrée par rappel")], ["modifications"])],
        ["name": "terminer_rappels",
         "description": "Marque des rappels comme terminés (ou les rouvre avec termine: false). Un rappel récurrent terminé crée l'occurrence suivante.",
         "inputSchema": obj(["ids": arr(s("Identifiant"), "Rappels"), "termine": b("true par défaut ; false pour rouvrir")], ["ids"])],
        ["name": "supprimer_rappels",
         "description": "Supprime définitivement des rappels par identifiant (pas de corbeille). Supprimer un parent supprime aussi ses sous-tâches.",
         "inputSchema": obj(["ids": arr(s("Identifiant"), "Rappels à supprimer")], ["ids"])],
        ["name": "ajouter_image",
         "description": "Ajoute une image (fichier local PNG, JPEG, HEIC…) en pièce jointe d'un rappel.",
         "inputSchema": obj(["id": s("Identifiant du rappel"), "chemin": s("Chemin absolu du fichier image")], ["id", "chemin"])],
        ["name": "tags",
         "description": "Liste les tags utilisés avec le nombre de rappels concernés (à faire par défaut).",
         "inputSchema": obj(["liste_ids": arr(s("Identifiant de liste"), "Limiter à ces listes"),
                             "statut": e(["a_faire", "termines", "tous"], "a_faire par défaut")])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        try EK.ready()
        switch name {
        case "listes": return try Handlers.listes(a)
        case "creer_liste": return try Handlers.creerListe(a)
        case "modifier_liste": return try Handlers.modifierListe(a)
        case "supprimer_liste": return try Handlers.supprimerListe(a)
        case "sections": return try Handlers.sections(a)
        case "creer_section": return try Handlers.creerSection(a)
        case "supprimer_section": return try Handlers.supprimerSection(a)
        case "rappels": return try Handlers.rappels(a)
        case "creer_rappels": return try Handlers.creerRappels(a)
        case "modifier_rappels": return try Handlers.modifierRappels(a)
        case "terminer_rappels": return try Handlers.terminerRappels(a)
        case "supprimer_rappels": return try Handlers.supprimerRappels(a)
        case "ajouter_image": return try Handlers.ajouterImage(a)
        case "tags": return try Handlers.tags(a)
        default: throw MCPError("outil inconnu : \(name)")
        }
    }
}
