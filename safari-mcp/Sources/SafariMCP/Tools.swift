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
private let ref: JSON = obj(["fenetre_id": n("Identifiant de fenêtre (voir onglets)"), "index": n("Index de l'onglet dans la fenêtre, à partir de 1")], ["fenetre_id", "index"])
private let refs = arr(ref, "Onglets visés (onglet actif de la fenêtre de premier plan si absent)")

/// Annotations MCP : seules les lectures sont readOnly, seule la fermeture est destructive,
/// seul executer_js est openWorld (un script peut soumettre un formulaire ou envoyer des données)
private let lectures: Set<String> = ["onglets", "lire_page", "liste_de_lecture", "favoris", "historique", "groupes_onglets"]
private func annotations(_ nom: String) -> JSON {
    ["readOnlyHint": lectures.contains(nom), "destructiveHint": nom == "fermer" || nom.hasPrefix("supprimer_"), "openWorldHint": nom == "executer_js"]
}

enum Tools {
    static let definitions: [JSON] = outils.map { o in
        var o = o
        o["annotations"] = annotations(o["name"] as! String)
        return o
    }

    private static let outils: [JSON] = [
        ["name": "onglets",
         "description": "Liste les fenêtres Safari ouvertes et leurs onglets (fenetre_id, index, titre, URL, actif). À appeler d'abord pour désigner des onglets. 50 onglets par défaut.",
         "inputSchema": obj(["fenetre_id": n("Seulement cette fenêtre"), "texte": s("Ne garder que les onglets dont le titre ou l'URL contient ce texte"),
                             "limite": n("Nombre maximum d'onglets (50 par défaut)")])],
        ["name": "ouvrir",
         "description": "Ouvre une ou plusieurs URL en nouveaux onglets : dans une fenêtre donnée, dans la fenêtre de premier plan (par défaut), dans une nouvelle fenêtre ou une fenêtre privée. Renvoie fenetre_id et index de chaque onglet.",
         "inputSchema": obj(["urls": arr(s("URL (https:// ajouté si absent ; chemin local accepté)"), "URL à ouvrir"),
                             "fenetre_id": n("Ouvrir dans cette fenêtre"), "nouvelle_fenetre": b("Ouvrir dans une nouvelle fenêtre"),
                             "prive": b("Ouvrir dans une nouvelle fenêtre privée (sans historique ; Safari passe au premier plan)"),
                             "attendre": b("Attendre la fin du chargement et renvoyer les titres")], ["urls"])],
        ["name": "naviguer",
         "description": "Agit sur des onglets existants : aller à une URL, recharger, précédent, suivant, ou activer (afficher l'onglet et sa fenêtre au premier plan).",
         "inputSchema": obj(["actions": arr(obj(["fenetre_id": n("Fenêtre"), "index": n("Onglet"), "url": s("Aller à cette URL"),
                                                 "action": e(["url", "recharger", "precedent", "suivant", "activer"], "url par défaut si url est fourni")],
                                                ["fenetre_id", "index"]), "Une entrée par onglet"),
                             "attendre": b("Attendre la fin du chargement et renvoyer les titres")], ["actions"])],
        ["name": "fermer",
         "description": "Ferme des onglets (par fenetre_id et index) et/ou des fenêtres entières. url_attendue évite de fermer un onglet qui aurait changé depuis la lecture.",
         "inputSchema": obj(["onglets": arr(obj(["fenetre_id": n("Fenêtre"), "index": n("Onglet"), "url_attendue": s("Ne fermer que si l'URL commence par ceci")], ["fenetre_id", "index"]), "Onglets à fermer"),
                             "fenetres": arr(n("Identifiant"), "Fenêtres à fermer avec tous leurs onglets")])],
        ["name": "lire_page",
         "description": "Lit le contenu d'un ou plusieurs onglets : texte visible (par défaut), liens, ou HTML courant. Pour résumer, comparer ou extraire.",
         "inputSchema": obj(["onglets": refs, "format": e(["texte", "liens", "html"], "texte par défaut"),
                             "max_caracteres": n("Tronquer chaque page à ce nombre de caractères (8000 par défaut)")])],
        ["name": "executer_js",
         "description": "Exécute du JavaScript synchrone dans un ou plusieurs onglets et renvoie le résultat (objet converti en JSON). Une expression simple suffit ; sinon un corps de fonction avec return. Pour cliquer, remplir, extraire.",
         "inputSchema": obj(["script": s("Code JavaScript"), "onglets": refs], ["script"])],
        ["name": "liste_de_lecture",
         "description": "Lit la liste de lecture (titre, URL, date d'ajout, lu), du plus récent au plus ancien. 20 éléments par défaut.",
         "inputSchema": obj(["texte": s("Filtrer sur le titre, l'URL ou l'aperçu"), "non_lus": b("Seulement les éléments non lus"),
                             "apercu": b("Inclure le texte d'aperçu"), "limite": n("Nombre maximum (20 par défaut)")])],
        ["name": "ajouter_liste_de_lecture",
         "description": "Ajoute une ou plusieurs URL à la liste de lecture. Safari remplace le titre par celui de la page.",
         "inputSchema": obj(["elements": arr(obj(["url": s("URL"), "titre": s("Titre (facultatif)"), "apercu": s("Texte d'aperçu (facultatif)")], ["url"]), "Éléments à ajouter")], ["elements"])],
        ["name": "favoris",
         "description": "Cherche dans les favoris (signets) : titre, URL, dossier. Avec dossiers: true, liste les dossiers. 50 résultats par défaut.",
         "inputSchema": obj(["texte": s("Filtrer sur le titre ou l'URL"), "dossier": s("Seulement dans les dossiers dont le chemin contient ce texte"),
                             "dossiers": b("Lister les dossiers au lieu des favoris"), "limite": n("Nombre maximum (50 par défaut)")])],
        ["name": "historique",
         "description": "Cherche dans l'historique de navigation : pages visitées (titre, URL, dernière visite, nombre de visites), de la plus récente à la plus ancienne. 20 par défaut.",
         "inputSchema": obj(["texte": s("Filtrer sur le titre ou l'URL"), "domaine": s("Seulement ce domaine (ex. lemonde.fr)"),
                             "depuis": s("Visites à partir de : \(dateHelp)"), "jusqu_a": s("Visites avant : \(dateHelp)"),
                             "limite": n("Nombre maximum (20 par défaut)")])],
        ["name": "groupes_onglets",
         "description": "Liste les groupes d'onglets (nom, nombre d'onglets, ouvert ou non), ou les onglets d'un groupe avec groupe_id. Ouvrir un groupe se fait dans Safari ; supprimer : supprimer_groupe_onglets.",
         "inputSchema": obj(["texte": s("Filtrer sur le nom du groupe"), "groupe_id": n("Lister les onglets de ce groupe"),
                             "sans_nom": b("Inclure les groupes sans nom propres à chaque fenêtre")])],
        ["name": "supprimer_liste_de_lecture",
         "description": "Supprime définitivement des éléments de la liste de lecture, par URL exacte (voir liste_de_lecture). Passe par la barre latérale de Safari dans une fenêtre dédiée, refermée à la fin (exige l'accès Accessibilité).",
         "inputSchema": obj(["urls": arr(s("URL exacte de l'élément"), "Éléments à supprimer")], ["urls"])],
        ["name": "supprimer_historique",
         "description": "Supprime définitivement des pages de l'historique (chaque page avec toutes ses visites, comme Safari) : par URL exacte ou par texte (titre ou URL), en option restreint aux pages visitées pendant une plage de jours. Renvoie le nombre de pages et de visites retirées. Passe par la vue Historique de Safari dans une fenêtre dédiée (exige l'accès Accessibilité).",
         "inputSchema": obj(["urls": arr(s("URL exacte"), "Pages à supprimer"), "texte": s("Pages dont le titre ou l'URL contient ce texte"),
                             "depuis": s("Seulement les pages visitées à partir de ce jour : AAAA-MM-JJ"), "jusqu_a": s("… et avant ce jour (exclu) : AAAA-MM-JJ")])],
        ["name": "supprimer_groupe_onglets",
         "description": "Supprime définitivement des groupes d'onglets (et leurs onglets) par groupe_id (voir groupes_onglets). Refuse un groupe affiché dans une fenêtre ouverte. Passe par la barre latérale de Safari dans une fenêtre dédiée (exige l'accès Accessibilité).",
         "inputSchema": obj(["groupe_ids": arr(n("Identifiant du groupe"), "Groupes à supprimer")], ["groupe_ids"])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        switch name {
        case "onglets": return try Handlers.onglets(a)
        case "ouvrir": return try Handlers.ouvrir(a)
        case "naviguer": return try Handlers.naviguer(a)
        case "fermer": return try Handlers.fermer(a)
        case "lire_page": return try Handlers.lirePage(a)
        case "executer_js": return try Handlers.executerJS(a)
        case "liste_de_lecture": return try Handlers.listeDeLecture(a)
        case "ajouter_liste_de_lecture": return try Handlers.ajouterListeDeLecture(a)
        case "favoris": return try Handlers.favoris(a)
        case "historique": return try Handlers.historique(a)
        case "groupes_onglets": return try Handlers.groupesOnglets(a)
        case "supprimer_liste_de_lecture": return try Suppressions.listeDeLecture(a)
        case "supprimer_historique": return try Suppressions.historique(a)
        case "supprimer_groupe_onglets": return try Suppressions.groupesOnglets(a)
        default: throw MCPError("outil inconnu : \(name)")
        }
    }
}
