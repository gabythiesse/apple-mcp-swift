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

private let dateHelp = "AAAA-MM-JJ (journée) ou AAAA-MM-JJTHH:MM (heure locale)"

private let alerte = obj([
    "minutes_avant": n("Alerte N minutes avant le début (journée entière : depuis minuit, 900 = la veille à 9 h)"),
    "date": s("Alerte à une date : \(dateHelp)"),
    "lieu": s("Alerte de lieu : nom du lieu (avec latitude et longitude)"),
    "latitude": n("Latitude"), "longitude": n("Longitude"),
    "rayon": n("Rayon en mètres (100 par défaut)"),
    "quand": e(["arrivee", "depart"], "À l'arrivée ou au départ (arrivee par défaut)"),
])

private let recurrence = obj([
    "frequence": e(["jour", "semaine", "mois", "annee"], "Fréquence"),
    "intervalle": n("Tous les N (1 par défaut)"),
    "jours": arr(s("lundi…dimanche ; préfixe de rang : 2mardi = 2e mardi, -1vendredi = dernier vendredi"), "Jours de la semaine"),
    "jours_du_mois": arr(n("1 à 31, -1 = dernier jour"), "Jours du mois"),
    "mois": arr(n("1 à 12"), "Mois de l'année"),
    "positions": arr(n("1 = premier, -1 = dernier"), "Rang parmi les jours retenus de la période (ex. jours lundi…vendredi + positions [-1] = dernier jour ouvré du mois)"),
    "fin_le": s("Dernier jour inclus : \(dateHelp)"),
    "occurrences": n("Nombre d'occurrences"),
], ["frequence"])

/// Champs communs à la création et à la modification
private let champs: JSON = [
    "titre": s("Titre"),
    "debut": s("Début : \(dateHelp). Une date sans heure crée une journée entière"),
    "fin": s("Fin : \(dateHelp). Journée entière : dernier jour inclus"),
    "duree_min": n("Durée en minutes, à la place de fin (60 par défaut)"),
    "journee_entiere": b("Journée entière"),
    "fuseau": s("Fuseau IANA de l'événement (ex. America/New_York) ; debut et fin sont lus dans ce fuseau"),
    "lieu": s("Lieu affiché (\"\" pour effacer)"),
    "latitude": n("Latitude du lieu (avec longitude : lieu géolocalisé)"),
    "longitude": n("Longitude du lieu"),
    "notes": s("Notes (\"\" pour effacer)"),
    "url": s("URL (\"\" pour retirer)"),
    "disponibilite": e(["occupe", "libre", "provisoire", "absent"], "Disponibilité affichée"),
    "trajet_min": n("Temps de trajet en minutes (0 pour retirer)"),
    "alertes": arr(alerte, "Alertes : remplace toutes les alertes, [] pour toutes les retirer. Absent à la création : alerte par défaut du compte"),
    "recurrence": ["description": "Récurrence (null pour la retirer). Le début est recalé sur la 1re date conforme", "anyOf": [recurrence, ["type": "null"]]],
]

private let cible: JSON = [
    "id": s("Identifiant de l'événement"),
    "occurrence": s("Date de l'occurrence (champ occurrence renvoyé par evenements), pour un événement récurrent"),
    "portee": e(["cette_occurrence", "suivantes", "serie"], "Portée sur un récurrent : cette_occurrence par défaut si occurrence est fourni, sinon serie"),
]

private var champsCreation: JSON {
    var c = champs
    c["calendrier_id"] = s("Calendrier (calendrier par défaut si absent)")
    c["pieces_jointes"] = arr(s("Chemin absolu d'un fichier"), "Fichiers à joindre")
    return c
}

private var champsModification: JSON {
    var c = champs.merging(cible) { a, _ in a }
    c["calendrier_id"] = s("Déplacer vers ce calendrier (toute la série pour un récurrent)")
    c["ajouter_pieces_jointes"] = arr(s("Chemin absolu d'un fichier"), "Fichiers à joindre")
    return c
}

/// Annotations MCP : lectures en readOnly, suppressions en destructive, envois aux participants en openWorld
private let lectures: Set<String> = ["calendriers", "evenements", "creneaux_libres"]
private let externes: Set<String> = ["inviter", "repondre_invitations"]
private func annotations(_ nom: String) -> JSON {
    var a: JSON = ["readOnlyHint": lectures.contains(nom), "destructiveHint": nom.hasPrefix("supprimer_"), "openWorldHint": externes.contains(nom)]
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
        ["name": "calendriers",
         "description": "Liste les calendriers (identifiant, compte, couleur, lecture seule, par défaut) et les comptes où en créer. À appeler pour connaître les calendrier_id.",
         "inputSchema": obj(["nom_contient": s("Ne garder que les calendriers dont le nom contient ce texte")])],
        ["name": "creer_calendrier",
         "description": "Crée un calendrier dans un compte (celui du calendrier par défaut si absent). Renvoie son identifiant.",
         "inputSchema": obj(["nom": s("Nom"), "couleur": s("#RRGGBB ou rouge, orange, jaune, vert, bleu, violet, marron, gris, rose"),
                             "compte": s("Compte : nom ou type (icloud, exchange, sur_mon_mac, caldav) tel que renvoyé par calendriers")], ["nom"])],
        ["name": "modifier_calendrier",
         "description": "Renomme ou recolore un calendrier.",
         "inputSchema": obj(["id": s("Identifiant du calendrier"), "nom": s("Nouveau nom"), "couleur": s("#RRGGBB ou nom de couleur")], ["id"])],
        ["name": "supprimer_calendrier",
         "description": "Supprime définitivement un calendrier par identifiant. Refuse un calendrier non vide sans force: true.",
         "inputSchema": obj(["id": s("Identifiant du calendrier"), "force": b("Supprimer aussi ses événements")], ["id"])],
        ["name": "evenements",
         "description": "Lit les événements (occurrences des récurrents dépliées) : vues aujourdhui, demain, semaine (7 jours), a_venir (30 jours), conflits (chevauchements) ; ou fenêtre debut/fin, calendriers, texte (titre, notes, lieu), invitations en attente, ou un id précis. 20 résultats par défaut triés par début ; detail: true ajoute notes, alertes, récurrence, invités, pièces jointes.",
         "inputSchema": obj([
            "vue": e(["aujourdhui", "demain", "semaine", "a_venir", "conflits"], "Vue toute faite (semaine par défaut)"),
            "debut": s("Début de la fenêtre : \(dateHelp)"),
            "fin": s("Fin de la fenêtre (exclue) : \(dateHelp)"),
            "calendrier_ids": arr(s("Identifiant de calendrier"), "Limiter à ces calendriers"),
            "texte": s("Recherche dans titre, notes et lieu (sans casse ni accents ; fenêtre ±1 an si aucune n'est donnée)"),
            "invitations": b("Seulement les invitations auxquelles je n'ai pas répondu"),
            "id": s("Un seul événement (avec occurrence pour un récurrent) ; renvoie le détail"),
            "occurrence": s("Date de l'occurrence, avec id"),
            "detail": b("Ajouter notes, URL, alertes, récurrence, invités, pièces jointes, fuseau"),
            "limite": n("Nombre maximum de résultats (20 par défaut)"),
         ])],
        ["name": "creer_evenements",
         "description": "Crée un ou plusieurs événements en un appel (par ex. tout un planning) : lieu géolocalisé, alertes, récurrence (2e mardi, dernier jour ouvré…), fuseau, disponibilité, trajet, pièces jointes. Renvoie le succès ou l'échec élément par élément, avec les identifiants. N'invite personne (voir inviter).",
         "inputSchema": obj(["evenements": arr(obj(champsCreation, ["titre", "debut"]), "Événements à créer")], ["evenements"])],
        ["name": "modifier_evenements",
         "description": "Modifie un ou plusieurs événements par identifiant : champs, dates, déplacement de calendrier, pièces jointes. Pour un récurrent, portee choisit cette occurrence, les suivantes ou toute la série. Seuls les champs fournis changent.",
         "inputSchema": obj(["modifications": arr(obj(champsModification, ["id"]), "Une entrée par événement")], ["modifications"])],
        ["name": "supprimer_evenements",
         "description": "Supprime définitivement des événements par identifiant (pas de corbeille). Pour un récurrent : occurrence + portee (cette_occurrence, suivantes) ou toute la série.",
         "inputSchema": obj(["evenements": arr(obj(cible, ["id"]), "Événements à supprimer")], ["evenements"])],
        ["name": "creneaux_libres",
         "description": "Cherche les créneaux libres dans mes calendriers (événements « libre », journées entières et invitations refusées ignorés ; trajet compté). Pour trouver où placer une réunion ou un bloc de travail.",
         "inputSchema": obj([
            "debut": s("Début de la recherche : \(dateHelp) (maintenant par défaut)"),
            "fin": s("Fin de la recherche : \(dateHelp) (7 jours par défaut)"),
            "duree_min": n("Durée minimale en minutes (30 par défaut)"),
            "heure_debut": s("Début de journée HH:MM (09:00 par défaut)"),
            "heure_fin": s("Fin de journée HH:MM (18:00 par défaut)"),
            "weekend": b("Inclure samedi et dimanche (false par défaut)"),
            "calendrier_ids": arr(s("Identifiant de calendrier"), "Calendriers à prendre en compte (tous sauf Anniversaires par défaut)"),
            "limite": n("Nombre maximum de créneaux (20 par défaut)"),
         ])],
        ["name": "inviter",
         "description": "Ajoute des invités à des événements : les invitations partent aussitôt par e-mail ou iCloud. À utiliser seulement à la demande explicite de l'utilisateur.",
         "inputSchema": obj(["invitations": arr(obj(cible.merging([
            "invites": arr(obj(["email": s("Adresse e-mail"), "nom": s("Nom affiché")], ["email"]), "Personnes à inviter"),
         ]) { a, _ in a }, ["id", "invites"]), "Une entrée par événement")], ["invitations"])],
        ["name": "repondre_invitations",
         "description": "Accepte, refuse ou accepte provisoirement des invitations reçues : la réponse part à l'organisateur. À utiliser seulement à la demande explicite de l'utilisateur.",
         "inputSchema": obj(["reponses": arr(obj(cible.merging([
            "reponse": e(["accepter", "refuser", "peut_etre"], "Réponse"),
         ]) { a, _ in a }, ["id", "reponse"]), "Une entrée par invitation")], ["reponses"])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        try EK.ready()
        switch name {
        case "calendriers": return try Handlers.calendriers(a)
        case "creer_calendrier": return try Handlers.creerCalendrier(a)
        case "modifier_calendrier": return try Handlers.modifierCalendrier(a)
        case "supprimer_calendrier": return try Handlers.supprimerCalendrier(a)
        case "evenements": return try Handlers.evenements(a)
        case "creer_evenements": return try Handlers.creerEvenements(a)
        case "modifier_evenements": return try Handlers.modifierEvenements(a)
        case "supprimer_evenements": return try Handlers.supprimerEvenements(a)
        case "creneaux_libres": return try Handlers.creneauxLibres(a)
        case "inviter": return try Handlers.inviter(a)
        case "repondre_invitations": return try Handlers.repondreInvitations(a)
        default: throw MCPError("outil inconnu : \(name)")
        }
    }
}
