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

private let dateHelp = "AAAA-MM-JJ ou AAAA-MM-JJTHH:MM (heure locale)"
private let texteHelp = "Contenu en texte simple : # titre, ## sous-titre, - puce, 1. liste numérotée, **gras**, *italique*"

/// Annotations MCP : seules les lectures sont readOnly, seules les suppressions sont destructive, rien ne sort du Mac
private let lectures: Set<String> = ["dossiers", "notes", "lire_notes", "tags", "ouvrir_note"]
private func annotations(_ nom: String) -> JSON {
    // Pas d'idempotentHint : supprimer deux fois une note la purge de la corbeille
    ["readOnlyHint": lectures.contains(nom), "destructiveHint": nom.hasPrefix("supprimer_"), "openWorldHint": false]
}

enum Tools {
    static let definitions: [JSON] = outils.map { o in
        var o = o
        o["annotations"] = annotations(o["name"] as! String)
        return o
    }

    private static let outils: [JSON] = [
        ["name": "dossiers",
         "description": "Liste les comptes et tous leurs dossiers (imbriqués : parent_id) avec identifiant et nombre de notes. À appeler pour connaître les dossier_id. La corbeille est marquée corbeille: true.",
         "inputSchema": obj(["nom_contient": s("Ne garder que les dossiers dont le nom contient ce texte")])],
        ["name": "notes",
         "description": "Liste ou cherche des notes (titre, dossier, date de modification ; épinglage, checklist et tags si la base est lisible), triées de la plus récente à la plus ancienne. Filtres : dossier (sous-dossiers compris), texte (titre et contenu), dates, tag, épinglées. Hors « Supprimées récemment » sauf supprimees: true ou dossier_id. 20 résultats par défaut.",
         "inputSchema": obj([
            "dossier_id": s("Limiter à ce dossier"),
            "sous_dossiers": b("Inclure les sous-dossiers du dossier_id (true par défaut)"),
            "texte": s("Recherche dans le titre et le contenu"),
            "modifiees_depuis": s("Modifiées à partir de : \(dateHelp)"),
            "modifiees_avant": s("Modifiées avant : \(dateHelp)"),
            "tag": s("Ne garder que les notes avec ce tag (sans #)"),
            "epinglees": b("Ne garder que les notes épinglées"),
            "supprimees": b("Inclure « Supprimées récemment »"),
            "limite": n("Nombre maximum de résultats (20 par défaut)"),
         ])],
        ["name": "lire_notes",
         "description": "Lit le contenu complet de notes par identifiant : texte (par défaut) ou HTML, dates, pièces jointes (id, nom), verrou, tags.",
         "inputSchema": obj(["ids": arr(s("Identifiant de note"), "Notes à lire"),
                             "format": e(["texte", "html"], "texte par défaut ; html garde la mise en forme (images remplacées par un repère)"),
                             "max_caracteres": n("Tronquer le contenu au-delà (20000 par défaut)")], ["ids"])],
        ["name": "creer_notes",
         "description": "Crée une ou plusieurs notes en un appel (par ex. depuis un compte-rendu). Le titre devient la première ligne. Renvoie le succès ou l'échec note par note, avec les identifiants. Notes ne crée ni case à cocher, ni tag, ni lien cliquable.",
         "inputSchema": obj(["notes": arr(obj([
            "titre": s("Titre (première ligne)"),
            "texte": s(texteHelp),
            "html": s("Contenu en HTML (à la place de texte) : div, h1-h3, b, i, u, ul/ol/li, table"),
            "dossier_id": s("Dossier (dossier par défaut si absent)"),
         ], ["titre"]), "Notes à créer")], ["notes"])],
        ["name": "modifier_notes",
         "description": "Modifie une ou plusieurs notes par identifiant : titre, contenu (remplacé), ajout en fin, déplacement de dossier. Déplacer une note de « Supprimées récemment » vers un dossier la restaure. Seuls les champs fournis changent.",
         "inputSchema": obj(["modifications": arr(obj([
            "id": s("Identifiant de la note"),
            "titre": s("Nouveau titre"),
            "texte": s("Remplace le contenu sous le titre. " + texteHelp),
            "html": s("Remplace le contenu sous le titre, en HTML"),
            "ajouter_texte": s("Ajoute à la fin de la note. " + texteHelp),
            "ajouter_html": s("Ajoute à la fin de la note, en HTML"),
            "dossier_id": s("Déplacer dans ce dossier (ou restaurer)"),
         ], ["id"]), "Une entrée par note")], ["modifications"])],
        ["name": "supprimer_notes",
         "description": "Supprime des notes par identifiant : elles vont dans « Supprimées récemment » (restaurables avec modifier_notes dossier_id). definitif: true les purge aussi de la corbeille.",
         "inputSchema": obj(["ids": arr(s("Identifiant de note"), "Notes à supprimer"),
                             "definitif": b("Purger aussi de « Supprimées récemment » (sans retour)")], ["ids"])],
        ["name": "creer_dossier",
         "description": "Crée un dossier (à la racine du compte ou dans un dossier parent), avec ses sous-dossiers éventuels. Renvoie les identifiants.",
         "inputSchema": obj(["nom": s("Nom"), "parent_id": s("Créer dans ce dossier"),
                             "compte_id": s("Compte (compte par défaut si absent ; ignoré avec parent_id)"),
                             "sous_dossiers": arr(s("Nom"), "Sous-dossiers à créer dedans")], ["nom"])],
        ["name": "renommer_dossier",
         "description": "Renomme un dossier. (Notes ne permet pas de déplacer un dossier par script.)",
         "inputSchema": obj(["id": s("Identifiant du dossier"), "nom": s("Nouveau nom")], ["id", "nom"])],
        ["name": "supprimer_dossier",
         "description": "Supprime un dossier et ses sous-dossiers, par identifiant. Leurs notes vont dans « Supprimées récemment ».",
         "inputSchema": obj(["id": s("Identifiant du dossier")], ["id"])],
        ["name": "ajouter_pieces_jointes",
         "description": "Ajoute des fichiers locaux (image, PDF, tout fichier) en pièces jointes de notes, en un appel.",
         "inputSchema": obj(["pieces": arr(obj(["note_id": s("Identifiant de la note"), "chemin": s("Chemin absolu du fichier")], ["note_id", "chemin"]),
                                           "Pièces à ajouter")], ["pieces"])],
        ["name": "exporter_pieces_jointes",
         "description": "Enregistre des pièces jointes dans un dossier local (par identifiant, ou toutes celles de notes). N'écrase jamais un fichier existant.",
         "inputSchema": obj(["dossier": s("Chemin absolu du dossier de destination (créé si besoin)"),
                             "ids": arr(s("Identifiant de pièce jointe"), "Pièces jointes"),
                             "note_ids": arr(s("Identifiant de note"), "Exporter toutes les pièces jointes de ces notes")], ["dossier"])],
        ["name": "tags",
         "description": "Liste les tags (#) avec leur nombre de notes, éventuellement dans un dossier. Lu dans la base de Notes (Accès complet au disque requis).",
         "inputSchema": obj(["dossier_id": s("Limiter à ce dossier et ses sous-dossiers")])],
        ["name": "ouvrir_note",
         "description": "Affiche une note dans l'app Notes, au premier plan.",
         "inputSchema": obj(["id": s("Identifiant de la note")], ["id"])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        switch name {
        case "dossiers": return try Handlers.dossiers(a)
        case "notes": return try Handlers.notes(a)
        case "lire_notes": return try Handlers.lireNotes(a)
        case "creer_notes": return try Handlers.creerNotes(a)
        case "modifier_notes": return try Handlers.modifierNotes(a)
        case "supprimer_notes": return try Handlers.supprimerNotes(a)
        case "creer_dossier": return try Handlers.creerDossier(a)
        case "renommer_dossier": return try Handlers.renommerDossier(a)
        case "supprimer_dossier": return try Handlers.supprimerDossier(a)
        case "ajouter_pieces_jointes": return try Handlers.ajouterPiecesJointes(a)
        case "exporter_pieces_jointes": return try Handlers.exporterPiecesJointes(a)
        case "tags": return try Handlers.tags(a)
        case "ouvrir_note": return try Handlers.ouvrirNote(a)
        default: throw MCPError("outil inconnu : \(name)")
        }
    }
}
