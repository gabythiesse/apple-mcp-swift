// Logique des outils : EventKit pour le cœur, ReminderKit pour ce qu'EventKit n'expose pas
import Foundation
import EventKit
import ImageIO
import UniformTypeIdentifiers

enum Handlers {
    private static var ek: EKEventStore { EK.store }

    // MARK: - Listes et groupes

    static func listes(_ a: JSON) throws -> Any {
        let filtre = a.nonEmpty("nom_contient")
        let cals = ek.calendars(for: .reminder).filter { filtre == nil || $0.title.localizedStandardContains(filtre!) }
        var counts: [String: Int] = [:]
        if !cals.isEmpty {
            for r in EK.fetch(ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)) {
                if let id = r.calendar?.calendarIdentifier { counts[id, default: 0] += 1 }
            }
        }
        let st = try? RK.store()
        let defaultID = ek.defaultCalendarForNewReminders()?.calendarIdentifier
        var out: [JSON] = cals.map { c in
            var d: JSON = ["id": c.calendarIdentifier, "nom": c.title, "compte": c.source?.title ?? ""]
            if let h = Colors.hex(c.cgColor) { d["couleur"] = h }
            let info = st.flatMap { RK.listInfo($0, c.calendarIdentifier) }
            if info?.isGroup == true { d["groupe"] = true } else { d["nb_a_faire"] = counts[c.calendarIdentifier] ?? 0 }
            if let g = info?.parentID { d["groupe_id"] = g }
            if c.calendarIdentifier == defaultID { d["par_defaut"] = true }
            return d
        }
        // EventKit n'énumère pas les groupes : ReminderKit les ajoute
        let seen = Set(cals.map(\.calendarIdentifier))
        for g in RK.groups() where !seen.contains(g.id) && (filtre == nil || g.name.localizedStandardContains(filtre!)) {
            out.append(["id": g.id, "nom": g.name, "compte": g.account, "groupe": true])
        }
        return ["listes": out]
    }

    static func creerListe(_ a: JSON) throws -> Any {
        let nom = try a.req("nom")
        let groupeID = a.nonEmpty("groupe_id")
        if a.bool("groupe") == true {
            let id = try RK.createGroup(nom, sameAccountAs: try groupeID.map(EK.calendar)?.calendarIdentifier ?? EK.defaultList().calendarIdentifier)
            return ["ok": true, "id": id, "nom": nom, "groupe": true]
        }
        let c = EKCalendar(for: .reminder, eventStore: ek)
        c.title = nom
        c.source = try groupeID.map { try EK.calendar($0).source } ?? EK.defaultList().source
        if let col = a.nonEmpty("couleur") { c.cgColor = try Colors.parse(col) }
        try ek.saveCalendar(c, commit: true)
        var out: JSON = ["ok": true, "id": c.calendarIdentifier, "nom": nom]
        if let g = groupeID {
            do { try RK.moveList(c.calendarIdentifier, toGroup: g); out["groupe_id"] = g }
            catch { out["avertissement"] = "liste créée hors du groupe : \(error)" }
        }
        return out
    }

    static func modifierListe(_ a: JSON) throws -> Any {
        let id = try a.req("id")
        let c = try EK.calendar(id)
        if let nom = a.nonEmpty("nom") { c.title = nom }
        if let col = a.nonEmpty("couleur") { c.cgColor = try Colors.parse(col) }
        if c.hasChanges { try ek.saveCalendar(c, commit: true) }
        if a.has("groupe_id") { try RK.moveList(id, toGroup: a.nonEmpty("groupe_id")) }
        return ["ok": true, "id": id, "nom": c.title]
    }

    static func supprimerListe(_ a: JSON) throws -> Any {
        let id = try a.req("id")
        let c = try EK.calendar(id)
        if let st = try? RK.store(), RK.listInfo(st, id)?.isGroup == true {
            let enfants = ek.calendars(for: .reminder).filter { RK.listInfo(st, $0.calendarIdentifier)?.parentID == id }
            guard enfants.isEmpty else {
                throw MCPError("le groupe « \(c.title) » contient \(enfants.count) liste(s) (\(enfants.map(\.title).joined(separator: ", "))). Sors-les avec modifier_liste groupe_id \"\" ou supprime-les d'abord.")
            }
            try RK.deleteGroup(id)
            return ["ok": true, "supprime": id, "nom": c.title, "groupe": true]
        }
        let n = EK.fetch(ek.predicateForReminders(in: [c])).count
        if n > 0 && a.bool("force") != true {
            throw MCPError("la liste « \(c.title) » contient \(n) rappel(s). Relance avec force: true pour la supprimer avec son contenu.")
        }
        try ek.removeCalendar(c, commit: true)
        return ["ok": true, "supprime": id, "nom": c.title, "rappels_supprimes": n]
    }

    // MARK: - Sections

    static func sections(_ a: JSON) throws -> Any {
        let id = try a.req("liste_id")
        _ = try EK.calendar(id)
        return ["liste_id": id, "sections": try RK.sections(id).map { ["id": $0.id, "nom": $0.name] }]
    }

    static func creerSection(_ a: JSON) throws -> Any {
        let id = try a.req("liste_id")
        _ = try EK.calendar(id)
        let nom = try a.req("nom")
        return ["ok": true, "id": try RK.createSection(id, name: nom), "nom": nom, "liste_id": id]
    }

    static func supprimerSection(_ a: JSON) throws -> Any {
        let id = try a.req("id")
        return ["ok": true, "supprime": id, "nom": try RK.deleteSection(id)]
    }

    // MARK: - Lecture des rappels

    private static func dueDate(_ r: EKReminder) -> Date? { r.dueDateComponents.flatMap(Dates.date) }
    private static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }

    static func rappels(_ a: JSON) throws -> Any {
        let vue = a.nonEmpty("vue")
        var statut = a.nonEmpty("statut") ?? "a_faire"
        if vue == "termines_recents" { statut = "termines" }
        else if vue != nil { statut = "a_faire" }

        let cals = try a.strings("liste_ids").map { try $0.map(EK.calendar) }
        let now = Date()
        let cal = Dates.cal
        let today = cal.startOfDay(for: now)

        let predicate: NSPredicate
        switch statut {
        case "a_faire": predicate = ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)
        case "termines":
            let depuis = vue == "termines_recents" ? cal.date(byAdding: .day, value: -7, to: now) : nil
            predicate = ek.predicateForCompletedReminders(withCompletionDateStarting: depuis, ending: nil, calendars: cals)
        case "tous": predicate = ek.predicateForReminders(in: cals)
        default: throw MCPError("statut inconnu : \(statut) (a_faire, termines, tous)")
        }
        var items = EK.fetch(predicate)

        // Filtres EventKit
        switch vue {
        case "aujourdhui":
            let demain = cal.date(byAdding: .day, value: 1, to: today)!
            items = items.filter { dueDate($0).map { $0 < demain } ?? false }
        case "en_retard":
            items = items.filter { r in
                guard let dc = r.dueDateComponents, let d = Dates.date(dc) else { return false }
                return dc.hour == nil ? d < today : d < now
            }
        case "semaine":
            let fin = cal.date(byAdding: .day, value: 8, to: today)!
            items = items.filter { dueDate($0).map { $0 < fin } ?? false }
        case "programmes":
            items = items.filter { $0.dueDateComponents != nil }
        case nil, "drapeau", "termines_recents": break
        default: throw MCPError("vue inconnue : \(vue!)")
        }
        if let t = a.nonEmpty("texte").map(fold) {
            items = items.filter { fold(($0.title ?? "") + "\n" + ($0.notes ?? "")).contains(t) }
        }
        if let s = a.nonEmpty("echeance_avant") {
            let d = try Dates.absolute(s)
            items = items.filter { dueDate($0).map { $0 < d } ?? false }
        }
        if let s = a.nonEmpty("echeance_apres") {
            let d = try Dates.absolute(s)
            items = items.filter { dueDate($0).map { $0 >= d } ?? false }
        }
        if a.bool("sans_echeance") == true { items = items.filter { $0.dueDateComponents == nil } }

        // Filtres ReminderKit (drapeau, tag, parent) : infos pour tous les candidats
        let tag = a.nonEmpty("tag").map { fold($0.hasPrefix("#") ? String($0.dropFirst()) : $0) }
        let drapeau = vue == "drapeau" ? true : a.bool("drapeau")
        let parent = a.nonEmpty("parent_id")
        var infos: [String: RKInfo] = [:]
        if tag != nil || drapeau != nil || parent != nil {
            try RK.require()
            infos = RK.infos(items.map(\.calendarItemIdentifier))
            items = items.filter { r in
                let i = infos[r.calendarItemIdentifier] ?? RKInfo()
                if let tag, !i.tags.contains(where: { fold($0) == tag }) { return false }
                if let drapeau, i.flagged != drapeau { return false }
                if let parent, i.parentID != parent { return false }
                return true
            }
        }

        // Tri : terminés du plus récent au plus ancien ; sinon par échéance (sans échéance à la fin)
        if statut == "termines" {
            items.sort { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
        } else {
            items.sort { x, y in
                switch (dueDate(x), dueDate(y)) {
                case let (dx?, dy?): return dx != dy ? dx < dy : (x.creationDate ?? .distantPast) < (y.creationDate ?? .distantPast)
                case (_?, nil): return true
                case (nil, _?): return false
                default: return (x.creationDate ?? .distantPast) < (y.creationDate ?? .distantPast)
                }
            }
        }

        let total = items.count
        let page = Array(items.prefix(max(1, a.int("limite") ?? 100)))
        let ids = page.map(\.calendarItemIdentifier)
        let missing = ids.filter { infos[$0] == nil }
        if !missing.isEmpty { infos.merge(RK.infos(missing)) { a, _ in a } }
        let kids = RK.childCounts(ids)
        let sections = RK.sectionsOf(page.compactMap { r in r.calendar.map { (r.calendarItemIdentifier, $0.calendarIdentifier) } })

        var out: JSON = ["total": total, "rappels": page.map { describe($0, infos[$0.calendarItemIdentifier], section: sections[$0.calendarItemIdentifier], nbSousTaches: kids[$0.calendarItemIdentifier]) }]
        if total > page.count { out["tronque"] = "\(page.count) affichés sur \(total) : augmenter limite ou filtrer" }
        return out
    }

    static func describe(_ r: EKReminder, _ i: RKInfo?, section: (id: String, name: String)? = nil, nbSousTaches: Int? = nil) -> JSON {
        var d: JSON = ["id": r.calendarItemIdentifier, "titre": r.title ?? ""]
        if let c = r.calendar { d["liste_id"] = c.calendarIdentifier; d["liste"] = c.title }
        if r.isCompleted { d["termine"] = true; if let c = r.completionDate { d["termine_le"] = Dates.text(c) } }
        if let dc = r.dueDateComponents { d["echeance"] = Dates.text(dc) }
        if let dc = r.startDateComponents { d["debut"] = Dates.text(dc) }
        if let p = Prio.label(r.priority) { d["priorite"] = p }
        if let n = r.notes, !n.isEmpty { d["notes"] = n }
        if let al = r.alarms, !al.isEmpty { d["alarmes"] = al.map(Alarms.json) }
        if let rr = r.recurrenceRules?.first { d["recurrence"] = Recurrence.json(rr) }
        if let i {
            if i.flagged { d["drapeau"] = true }
            if !i.tags.isEmpty { d["tags"] = i.tags }
            if let u = i.url { d["url"] = u }
            if let p = i.parentID { d["parent_id"] = p }
            if i.images > 0 { d["images"] = i.images }
        }
        if let s = section { d["section_id"] = s.id; d["section"] = s.name }
        if let n = nbSousTaches, n > 0 { d["nb_sous_taches"] = n }
        return d
    }

    // MARK: - Écriture des rappels

    /// Applique les champs EventKit ; clé absente = inchangé, null ou "" = effacé
    private static func applyEK(_ r: EKReminder, _ a: JSON) throws {
        if let t = a.nonEmpty("titre") { r.title = t }
        if a.has("notes") { r.notes = a.nonEmpty("notes") }
        let oldDue = dueDate(r)
        if a.has("echeance") { r.dueDateComponents = try a.nonEmpty("echeance").map(Dates.components) }
        if a.has("debut") { r.startDateComponents = try a.nonEmpty("debut").map(Dates.components) }
        if a.has("priorite") { r.priority = try Prio.parse(a["priorite"]) }
        if a.has("alarmes") {
            r.alarms?.forEach { r.removeAlarm($0) }
            for al in a.objects("alarmes") ?? [] { r.addAlarm(try Alarms.parse(al)) }
        } else if a.has("echeance") {
            // Comme l'app : une échéance avec heure déclenche une alerte à cette heure
            if let old = oldDue, let al = r.alarms?.first(where: { $0.absoluteDate == old }) { r.removeAlarm(al) }
            if let dc = r.dueDateComponents, dc.hour != nil, let d = Dates.date(dc), !(r.alarms ?? []).contains(where: { $0.absoluteDate == d }) {
                r.addAlarm(EKAlarm(absoluteDate: d))
            }
        }
        if a.has("recurrence") {
            r.recurrenceRules?.forEach { r.removeRecurrenceRule($0) }
            if let rec = a.object("recurrence") { r.addRecurrenceRule(try Recurrence.parse(rec)) }
        }
    }

    private static func extras(_ a: JSON) -> Extras {
        var x = Extras()
        x.flagged = a.bool("drapeau")
        x.addTags = (a.strings("tags") ?? []) + (a.strings("ajouter_tags") ?? [])
        x.removeTags = a.strings("retirer_tags") ?? []
        if a.has("url") { x.url = a.nonEmpty("url") ?? "" }
        if a.has("section_id") { x.sectionID = a.nonEmpty("section_id") ?? "" }
        return x
    }

    static func creerRappels(_ a: JSON) throws -> Any {
        guard let items = a.objects("rappels"), !items.isEmpty else { throw MCPError("paramètre manquant : rappels (tableau)") }
        let res = items.map { creerUn($0, parent: nil) }
        return ["crees": res.filter { $0["ok"] as? Bool == true }.count, "echecs": res.filter { $0["ok"] as? Bool != true }.count, "resultats": res]
    }

    private static func creerUn(_ a: JSON, parent: EKReminder?) -> JSON {
        do {
            let titre = try a.req("titre")
            let parentID = parent?.calendarItemIdentifier ?? a.nonEmpty("parent_id")
            let r = EKReminder(eventStore: ek)
            r.title = titre
            if let p = parent { r.calendar = p.calendar }
            else if let pid = parentID { r.calendar = try EK.reminder(pid).calendar }
            else if let lid = a.nonEmpty("liste_id") { r.calendar = try EK.calendar(lid) }
            else { r.calendar = try EK.defaultList() }
            try applyEK(r, a)
            try ek.save(r, commit: true)

            var out: JSON = ["ok": true, "id": r.calendarItemIdentifier, "titre": titre]
            var x = extras(a)
            x.parentID = parentID
            do { try RK.apply(r.calendarItemIdentifier, x) }
            catch { out["avertissement"] = "rappel créé, mais \(error)" }

            if let subs = a.objects("sous_taches"), !subs.isEmpty {
                if parentID != nil {
                    out["sous_taches"] = subs.map { ["ok": false, "titre": $0.string("titre") ?? "", "erreur": "Rappels n'a qu'un niveau de sous-tâches"] }
                } else {
                    out["sous_taches"] = subs.map { creerUn($0, parent: r) }
                }
            }
            return out
        } catch {
            return ["ok": false, "titre": a.string("titre") ?? "", "erreur": "\(error)"]
        }
    }

    static func modifierRappels(_ a: JSON) throws -> Any {
        guard let items = a.objects("modifications"), !items.isEmpty else { throw MCPError("paramètre manquant : modifications (tableau)") }
        let res = items.map(modifierUn)
        return ["modifies": res.filter { $0["ok"] as? Bool == true }.count, "echecs": res.filter { $0["ok"] as? Bool != true }.count, "resultats": res]
    }

    private static func modifierUn(_ a: JSON) -> JSON {
        let id = a.string("id") ?? ""
        do {
            let r = try EK.reminder(id)
            try applyEK(r, a)
            if r.hasChanges { try ek.save(r, commit: true) }
            var listeActuelle = r.calendar?.calendarIdentifier

            // Déplacement (sous-tâches comprises) par ReminderKit : EventKit refuse un parent avec sous-tâches
            if let lid = a.nonEmpty("liste_id"), lid != listeActuelle {
                _ = try EK.calendar(lid)
                try RK.moveReminder(id, to: lid)
                listeActuelle = lid
            }

            var x = extras(a)
            if a.has("parent_id") {
                let pid = a.nonEmpty("parent_id") ?? ""
                if !pid.isEmpty {
                    // Une sous-tâche vit dans la liste de son parent
                    let pl = try EK.reminder(pid).calendar?.calendarIdentifier
                    if let pl, pl != listeActuelle { try RK.moveReminder(id, to: pl) }
                }
                x.parentID = pid
            }
            try RK.apply(id, x)
            return ["ok": true, "id": id]
        } catch {
            return ["ok": false, "id": id, "erreur": "\(error)"]
        }
    }

    static func terminerRappels(_ a: JSON) throws -> Any {
        guard let ids = a.strings("ids"), !ids.isEmpty else { throw MCPError("paramètre manquant : ids") }
        let termine = a.bool("termine") ?? true
        var res: [JSON] = []
        for id in ids {
            do {
                let r = try EK.reminder(id)
                r.isCompleted = termine
                try ek.save(r, commit: false)
                res.append(["ok": true, "id": id, "titre": r.title ?? ""])
            } catch { res.append(["ok": false, "id": id, "erreur": "\(error)"]) }
        }
        try ek.commit()
        return ["resultats": res]
    }

    static func supprimerRappels(_ a: JSON) throws -> Any {
        guard let ids = a.strings("ids"), !ids.isEmpty else { throw MCPError("paramètre manquant : ids") }
        let kids = RK.childCounts(ids)
        var res: [JSON] = []
        for id in ids {
            do {
                let r = try EK.reminder(id)
                let titre = r.title ?? ""
                try ek.remove(r, commit: false)
                var d: JSON = ["ok": true, "id": id, "titre": titre]
                if let n = kids[id], n > 0 { d["sous_taches_supprimees"] = n }
                res.append(d)
            } catch { res.append(["ok": false, "id": id, "erreur": "\(error)"]) }
        }
        try ek.commit()
        return ["resultats": res]
    }

    // MARK: - Images et tags

    static func ajouterImage(_ a: JSON) throws -> Any {
        let id = try a.req("id")
        _ = try EK.reminder(id)
        let path = (try a.req("chemin") as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { throw MCPError("fichier illisible : \(path)") }
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else {
            throw MCPError("ce fichier n'est pas une image reconnue : \(url.lastPathComponent)")
        }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else {
            throw MCPError("dimensions de l'image illisibles : \(url.lastPathComponent)")
        }
        try RK.addImage(id, data: data, uti: type.identifier, width: w, height: h)
        return ["ok": true, "id": id, "image": url.lastPathComponent, "largeur": w, "hauteur": h]
    }

    static func tags(_ a: JSON) throws -> Any {
        try RK.require()
        let cals = try a.strings("liste_ids").map { try $0.map(EK.calendar) }
        let predicate: NSPredicate
        switch a.nonEmpty("statut") ?? "a_faire" {
        case "a_faire": predicate = ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)
        case "termines": predicate = ek.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: cals)
        case "tous": predicate = ek.predicateForReminders(in: cals)
        case let s: throw MCPError("statut inconnu : \(s)")
        }
        var counts: [String: Int] = [:]
        for i in RK.infos(EK.fetch(predicate).map(\.calendarItemIdentifier)).values {
            for t in i.tags { counts[t, default: 0] += 1 }
        }
        return ["tags": counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { ["tag": $0.key, "nb": $0.value] }]
    }
}
