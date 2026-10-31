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
private let ids = arr(n("Identifiant de message"), "Identifiants de messages")
private let couleurs = ["rouge", "orange", "jaune", "vert", "bleu", "violet", "gris"]

/// Message à composer (brouillon ou envoi direct)
private let composition = obj([
    "a": arr(s("Adresse, ou « Nom <adresse> »"), "Destinataires"),
    "cc": arr(s("Adresse"), "Copie"),
    "cci": arr(s("Adresse"), "Copie cachée"),
    "sujet": s("Sujet (pour une réponse ou un transfert : laisser vide pour garder Re:/Fwd:)"),
    "corps": s("Texte du message (pour une réponse ou un transfert, placé au-dessus du message cité)"),
    "expediteur": s("Adresse d'envoi parmi celles des comptes (compte par défaut sinon)"),
    "signature": s("Nom d'une signature de Mail (voir boites)"),
    "pieces_jointes": arr(s("Chemin absolu"), "Fichiers à joindre"),
    "repondre_a": n("Répondre à ce message : destinataire, sujet Re: et citation remplis (nouveau message, pas rattaché au fil chez le destinataire)"),
    "tous": b("Avec repondre_a : répondre à tous"),
    "transferer": n("Transférer ce message : sujet Fwd:, message cité et pièces jointes repris"),
])

/// Annotations MCP : lectures pures readOnly, suppression destructive, envoi openWorld
private let lectures: Set<String> = ["boites", "messages", "lire_messages"]
private func annotations(_ nom: String) -> JSON {
    var a: JSON = ["readOnlyHint": lectures.contains(nom), "destructiveHint": nom.hasPrefix("supprimer_"), "openWorldHint": nom == "envoyer"]
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
        ["name": "boites",
         "description": "Liste les comptes (id, nom, adresses), les boîtes aux lettres (id, non lus, total) et les noms de signatures. À appeler pour connaître les identifiants de boîte.",
         "inputSchema": obj(["nom_contient": s("Ne garder que les boîtes dont le chemin contient ce texte")])],
        ["name": "messages",
         "description": "Cherche et liste des messages via l'index de Mail (rapide) : vues toutes faites, boîtes, compte, non lus, drapeau, dates, expéditeur, destinataire, texte (sujet, expéditeur, début du corps), pièces jointes, conversation. dans_corps cherche dans tout le corps (plus lent, une seule boîte). 20 résultats par défaut, du plus récent au plus ancien.",
         "inputSchema": obj([
            "vue": e(["aujourdhui", "non_lus", "drapeau", "recents", "sans_reponse", "selection"],
                     "aujourdhui = reçus aujourd'hui ; non_lus ; drapeau ; recents ; sans_reponse = envoyés depuis 30 j sans réponse dans le fil ; selection = messages sélectionnés dans Mail. Les vues hors drapeau/selection ignorent envoyés, brouillons, corbeille et indésirables."),
            "boites": arr(s("Identifiant de boîte"), "Limiter à ces boîtes"),
            "compte": s("Limiter à ce compte (id, ou local)"),
            "non_lu": b("true = non lus seulement, false = lus seulement"),
            "drapeau": b("true = avec drapeau, false = sans"),
            "depuis": s("Reçu à partir de : \(dateHelp)"),
            "avant": s("Reçu strictement avant : \(dateHelp)"),
            "de": s("Expéditeur (adresse ou nom, partiel)"),
            "a": s("Destinataire to/cc (adresse ou nom, partiel)"),
            "texte": s("Texte dans le sujet, l'expéditeur ou le début du corps"),
            "dans_corps": s("Texte à chercher dans tout le corps (exige une seule boîte dans boites)"),
            "avec_pj": b("Seulement les messages avec pièces jointes"),
            "conversation": n("Seulement ce fil (champ conv)"),
            "ids": ids,
            "apercu": b("Ajouter le début du corps (160 caractères)"),
            "limite": n("Nombre maximum (20 par défaut)"),
         ])],
        ["name": "lire_messages",
         "description": "Lit le contenu complet d'un ou plusieurs messages : expéditeur, destinataires, date, corps en texte, pièces jointes. En-têtes et source brute sur demande.",
         "inputSchema": obj(["ids": ids, "entetes": b("Ajouter tous les en-têtes"), "source": b("Ajouter la source brute (RFC 822)"),
                             "max_car": n("Longueur maximale du corps (5000 par défaut)")], ["ids"])],
        ["name": "enregistrer_pieces_jointes",
         "description": "Enregistre sur le disque les pièces jointes d'un ou plusieurs messages. Renvoie les chemins des fichiers.",
         "inputSchema": obj(["ids": ids, "dossier": s("Dossier de destination (Téléchargements par défaut)"),
                             "noms": arr(s("Nom de fichier"), "N'enregistrer que ces pièces jointes")], ["ids"])],
        ["name": "marquer_messages",
         "description": "Change l'état de messages en lot : lu, drapeau et sa couleur, couleur de fond, indésirable. Seuls les champs fournis changent.",
         "inputSchema": obj(["modifications": arr(obj([
            "id": n("Identifiant du message"),
            "lu": b("Lu (true) ou non lu (false)"),
            "drapeau": b("Poser (true) ou retirer (false) le drapeau"),
            "couleur_drapeau": e(couleurs, "Couleur du drapeau (pose le drapeau)"),
            "couleur_fond": e(couleurs + ["aucune"], "Couleur de fond dans la liste"),
            "indesirable": b("Marquer comme indésirable ou non"),
         ], ["id"]), "Une entrée par message")], ["modifications"])],
        ["name": "deplacer_messages",
         "description": "Déplace (ou copie) des messages vers une boîte, par exemple pour archiver. Renvoie le nouvel identifiant de chaque message (l'ancien ne sert plus).",
         "inputSchema": obj(["ids": ids, "boite": s("Identifiant de la boîte de destination"), "copier": b("Copier au lieu de déplacer")], ["ids", "boite"])],
        ["name": "supprimer_messages",
         "description": "Supprime des messages ou des brouillons par identifiant : ils vont à la corbeille de leur compte. Un brouillon créé depuis le dernier lancement de Mail garde une copie dans Brouillons jusqu'au prochain relancement de Mail.",
         "inputSchema": obj(["ids": ids], ["ids"])],
        ["name": "creer_brouillons",
         "description": "Crée un ou plusieurs brouillons (nouveau message, réponse, réponse à tous, transfert), avec pièces jointes et signature, sans rien envoyer. Renvoie l'identifiant de chaque brouillon.",
         "inputSchema": obj(["brouillons": arr(composition, "Brouillons à créer")], ["brouillons"])],
        ["name": "envoyer",
         "description": "ENVOIE réellement des mails : soit des brouillons existants (brouillon_ids : recomposés, envoyés puis supprimés), soit des messages composés directement (messages, mêmes champs que creer_brouillons). À n'utiliser qu'après accord explicite.",
         "inputSchema": obj(["brouillon_ids": ids, "messages": arr(composition, "Messages à composer et envoyer")])],
        ["name": "gerer_boites",
         "description": "Crée ou renomme des boîtes aux lettres (pour supprimer : supprimer_boites).",
         "inputSchema": obj([
            "creer": arr(obj(["chemin": s("Chemin, ex. « Clients/2026 »"), "compte": s("Compte (id) ; local par défaut (Sur mon Mac)")], ["chemin"]), "Boîtes à créer"),
            "renommer": arr(obj(["id": s("Identifiant de la boîte"), "nom": s("Nouveau nom (dernier élément du chemin)")], ["id", "nom"]), "Boîtes à renommer"),
         ])],
        ["name": "supprimer_boites",
         "description": "Supprime définitivement des boîtes aux lettres par identifiant (avec leur contenu). Refuse une boîte qui contient des messages ou des sous-boîtes, sauf forcer: true. Passe par le menu de Mail : Mail passe au premier plan quelques secondes (exige l'accès Accessibilité).",
         "inputSchema": obj(["ids": arr(s("Identifiant de boîte (voir boites)"), "Boîtes à supprimer"),
                             "forcer": b("Supprimer même si la boîte contient des messages ou des sous-boîtes")], ["ids"])],
        ["name": "relever",
         "description": "Relève le courrier (tous les comptes ou un seul), et synchronise la boîte IMAP si demandé.",
         "inputSchema": obj(["compte": s("Identifiant du compte"), "synchroniser": b("Synchroniser aussi le compte (exige compte)")])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        switch name {
        case "boites": return try Handlers.boites(a)
        case "messages": return try Handlers.messages(a)
        case "lire_messages": return try Handlers.lireMessages(a)
        case "enregistrer_pieces_jointes": return try Handlers.enregistrerPJ(a)
        case "marquer_messages": return try Handlers.marquer(a)
        case "deplacer_messages": return try Handlers.deplacer(a)
        case "supprimer_messages": return try Handlers.supprimer(a)
        case "creer_brouillons": return try Compose.creerBrouillons(a)
        case "envoyer": return try Compose.envoyer(a)
        case "gerer_boites": return try Handlers.gererBoites(a)
        case "supprimer_boites": return try Handlers.supprimerBoites(a)
        case "relever": return try Handlers.relever(a)
        default: throw MCPError("outil inconnu : \(name)")
        }
    }
}
