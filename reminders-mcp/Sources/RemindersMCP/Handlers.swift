// Logique des outils : EventKit pour le cœur, ReminderKit pour ce qu'EventKit n'expose pas
import Foundation
import EventKit
import ImageIO
import UniformTypeIdentifiers

enum Handlers {
    private static var ek: EKEventStore { EK.store }

    // MARK: - Listes et groupes

    static func listes(_ a: JSON) throws -> Any {
        let filtre = a.nonEmpty("name_contains")
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
            var d: JSON = ["id": c.calendarIdentifier, "name": c.title, "account": c.source?.title ?? ""]
            if let h = Colors.hex(c.cgColor) { d["color"] = h }
            let info = st.flatMap { RK.listInfo($0, c.calendarIdentifier) }
            if info?.isGroup == true { d["group"] = true } else { d["incomplete_count"] = counts[c.calendarIdentifier] ?? 0 }
            if let g = info?.parentID { d["group_id"] = g }
            if c.calendarIdentifier == defaultID { d["default"] = true }
            return d
        }
        // EventKit n'énumère pas les groupes : ReminderKit les ajoute
        let seen = Set(cals.map(\.calendarIdentifier))
        for g in RK.groups() where !seen.contains(g.id) && (filtre == nil || g.name.localizedStandardContains(filtre!)) {
            out.append(["id": g.id, "name": g.name, "account": g.account, "group": true])
        }
        return ["lists": out]
    }

    static func creerListe(_ a: JSON) throws -> Any {
        let nom = try a.req("name")
        let groupeID = a.nonEmpty("group_id")
        if a.bool("group") == true {
            let id = try RK.createGroup(nom, sameAccountAs: try groupeID.map(EK.calendar)?.calendarIdentifier ?? EK.defaultList().calendarIdentifier)
            return ["ok": true, "id": id, "name": nom, "group": true]
        }
        let c = EKCalendar(for: .reminder, eventStore: ek)
        c.title = nom
        c.source = try groupeID.map { try EK.calendar($0).source } ?? EK.defaultList().source
        if let col = a.nonEmpty("color") { c.cgColor = try Colors.parse(col) }
        try ek.saveCalendar(c, commit: true)
        var out: JSON = ["ok": true, "id": c.calendarIdentifier, "name": nom]
        if let g = groupeID {
            do { try RK.moveList(c.calendarIdentifier, toGroup: g); out["group_id"] = g }
            catch { out["warning"] = "list created outside the group: \(error)" }
        }
        return out
    }

    static func modifierListe(_ a: JSON) throws -> Any {
        let id = try a.req("id")
        let c = try EK.calendar(id)
        if let nom = a.nonEmpty("name") { c.title = nom }
        if let col = a.nonEmpty("color") { c.cgColor = try Colors.parse(col) }
        if c.hasChanges { try ek.saveCalendar(c, commit: true) }
        if a.has("group_id") { try RK.moveList(id, toGroup: a.nonEmpty("group_id")) }
        return ["ok": true, "id": id, "name": c.title]
    }

    static func supprimerListe(_ a: JSON) throws -> Any {
        let id = try a.req("id")
        let c = try EK.calendar(id)
        if let st = try? RK.store(), RK.listInfo(st, id)?.isGroup == true {
            let enfants = ek.calendars(for: .reminder).filter { RK.listInfo(st, $0.calendarIdentifier)?.parentID == id }
            guard enfants.isEmpty else {
                throw MCPError("group \"\(c.title)\" contains \(enfants.count) list(s) (\(enfants.map(\.title).joined(separator: ", "))). Move them out with update_list group_id \"\" or delete them first.")
            }
            try RK.deleteGroup(id)
            return ["ok": true, "deleted": id, "name": c.title, "group": true]
        }
        let n = EK.fetch(ek.predicateForReminders(in: [c])).count
        if n > 0 && a.bool("force") != true {
            throw MCPError("list \"\(c.title)\" contains \(n) reminder(s). Retry with force: true to delete it with its contents.")
        }
        try ek.removeCalendar(c, commit: true)
        return ["ok": true, "deleted": id, "name": c.title, "deleted_reminders": n]
    }

    // MARK: - Sections

    static func sections(_ a: JSON) throws -> Any {
        let id = try a.req("list_id")
        _ = try EK.calendar(id)
        return ["list_id": id, "sections": try RK.sections(id).map { ["id": $0.id, "name": $0.name] }]
    }

    static func creerSection(_ a: JSON) throws -> Any {
        let id = try a.req("list_id")
        _ = try EK.calendar(id)
        let nom = try a.req("name")
        return ["ok": true, "id": try RK.createSection(id, name: nom), "name": nom, "list_id": id]
    }

    static func supprimerSection(_ a: JSON) throws -> Any {
        let id = try a.req("id")
        return ["ok": true, "deleted": id, "name": try RK.deleteSection(id)]
    }

    // MARK: - Lecture des rappels

    private static func dueDate(_ r: EKReminder) -> Date? { r.dueDateComponents.flatMap(Dates.date) }
    private static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }

    static func rappels(_ a: JSON) throws -> Any {
        let vue = a.nonEmpty("view")
        var statut = a.nonEmpty("status") ?? "incomplete"
        if vue == "recently_completed" { statut = "completed" }
        else if vue != nil { statut = "incomplete" }

        let cals = try a.strings("list_ids").map { try $0.map(EK.calendar) }
        let now = Date()
        let cal = Dates.cal
        let today = cal.startOfDay(for: now)

        let predicate: NSPredicate
        switch statut {
        case "incomplete": predicate = ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)
        case "completed":
            let depuis = vue == "recently_completed" ? cal.date(byAdding: .day, value: -7, to: now) : nil
            predicate = ek.predicateForCompletedReminders(withCompletionDateStarting: depuis, ending: nil, calendars: cals)
        case "all": predicate = ek.predicateForReminders(in: cals)
        default: throw MCPError("unknown status: \(statut) (incomplete, completed, all)")
        }
        var items = EK.fetch(predicate)

        // Filtres EventKit
        switch vue {
        case "today":
            let demain = cal.date(byAdding: .day, value: 1, to: today)!
            items = items.filter { dueDate($0).map { $0 < demain } ?? false }
        case "overdue":
            items = items.filter { r in
                guard let dc = r.dueDateComponents, let d = Dates.date(dc) else { return false }
                return dc.hour == nil ? d < today : d < now
            }
        case "week":
            let fin = cal.date(byAdding: .day, value: 8, to: today)!
            items = items.filter { dueDate($0).map { $0 < fin } ?? false }
        case "scheduled":
            items = items.filter { $0.dueDateComponents != nil }
        case nil, "flagged", "recently_completed": break
        default: throw MCPError("unknown view: \(vue!) (today, overdue, week, scheduled, flagged, recently_completed)")
        }
        if let t = a.nonEmpty("text").map(fold) {
            items = items.filter { fold(($0.title ?? "") + "\n" + ($0.notes ?? "")).contains(t) }
        }
        if let s = a.nonEmpty("due_before") {
            let d = try Dates.absolute(s)
            items = items.filter { dueDate($0).map { $0 < d } ?? false }
        }
        if let s = a.nonEmpty("due_after") {
            let d = try Dates.absolute(s)
            items = items.filter { dueDate($0).map { $0 >= d } ?? false }
        }
        if a.bool("no_due") == true { items = items.filter { $0.dueDateComponents == nil } }

        // Filtres ReminderKit (drapeau, tag, parent) : infos pour tous les candidats
        let tag = a.nonEmpty("tag").map { fold($0.hasPrefix("#") ? String($0.dropFirst()) : $0) }
        let drapeau = vue == "flagged" ? true : a.bool("flagged")
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
        if statut == "completed" {
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
        let page = Array(items.prefix(max(1, a.int("limit") ?? 100)))
        let ids = page.map(\.calendarItemIdentifier)
        let missing = ids.filter { infos[$0] == nil }
        if !missing.isEmpty { infos.merge(RK.infos(missing)) { a, _ in a } }
        let kids = RK.childCounts(ids)
        let sections = RK.sectionsOf(page.compactMap { r in r.calendar.map { (r.calendarItemIdentifier, $0.calendarIdentifier) } })

        var out: JSON = ["total": total, "reminders": page.map { describe($0, infos[$0.calendarItemIdentifier], section: sections[$0.calendarItemIdentifier], nbSousTaches: kids[$0.calendarItemIdentifier]) }]
        if total > page.count { out["truncated"] = "showing \(page.count) of \(total): raise limit or filter" }
        return out
    }

    static func describe(_ r: EKReminder, _ i: RKInfo?, section: (id: String, name: String)? = nil, nbSousTaches: Int? = nil) -> JSON {
        var d: JSON = ["id": r.calendarItemIdentifier, "title": r.title ?? ""]
        if let c = r.calendar { d["list_id"] = c.calendarIdentifier; d["list"] = c.title }
        if r.isCompleted { d["completed"] = true; if let c = r.completionDate { d["completed_at"] = Dates.text(c) } }
        if let dc = r.dueDateComponents { d["due"] = Dates.text(dc) }
        if let dc = r.startDateComponents { d["start"] = Dates.text(dc) }
        if let p = Prio.label(r.priority) { d["priority"] = p }
        if let n = r.notes, !n.isEmpty { d["notes"] = n }
        if let al = r.alarms, !al.isEmpty { d["alarms"] = al.map(Alarms.json) }
        if let rr = r.recurrenceRules?.first { d["recurrence"] = Recurrence.json(rr) }
        if let i {
            if i.flagged { d["flagged"] = true }
            if !i.tags.isEmpty { d["tags"] = i.tags }
            if let u = i.url { d["url"] = u }
            if let p = i.parentID { d["parent_id"] = p }
            if i.images > 0 { d["images"] = i.images }
        }
        if let s = section { d["section_id"] = s.id; d["section"] = s.name }
        if let n = nbSousTaches, n > 0 { d["subtask_count"] = n }
        return d
    }

    // MARK: - Écriture des rappels

    /// Applique les champs EventKit ; clé absente = inchangé, null ou "" = effacé
    private static func applyEK(_ r: EKReminder, _ a: JSON) throws {
        if let t = a.nonEmpty("title") { r.title = t }
        if a.has("notes") { r.notes = a.nonEmpty("notes") }
        let oldDue = dueDate(r)
        if a.has("due") { r.dueDateComponents = try a.nonEmpty("due").map(Dates.components) }
        if a.has("start") { r.startDateComponents = try a.nonEmpty("start").map(Dates.components) }
        if a.has("priority") { r.priority = try Prio.parse(a["priority"]) }
        if a.has("alarms") {
            r.alarms?.forEach { r.removeAlarm($0) }
            for al in a.objects("alarms") ?? [] { r.addAlarm(try Alarms.parse(al)) }
        } else if a.has("due") {
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
        x.flagged = a.bool("flagged")
        x.addTags = (a.strings("tags") ?? []) + (a.strings("add_tags") ?? [])
        x.removeTags = a.strings("remove_tags") ?? []
        if a.has("url") { x.url = a.nonEmpty("url") ?? "" }
        if a.has("section_id") { x.sectionID = a.nonEmpty("section_id") ?? "" }
        return x
    }

    static func creerRappels(_ a: JSON) throws -> Any {
        guard let items = a.objects("reminders"), !items.isEmpty else { throw MCPError("missing parameter: reminders (array)") }
        let res = items.map { creerUn($0, parent: nil) }
        return ["created": res.filter { $0["ok"] as? Bool == true }.count, "failed": res.filter { $0["ok"] as? Bool != true }.count, "results": res]
    }

    private static func creerUn(_ a: JSON, parent: EKReminder?) -> JSON {
        do {
            let titre = try a.req("title")
            let parentID = parent?.calendarItemIdentifier ?? a.nonEmpty("parent_id")
            let r = EKReminder(eventStore: ek)
            r.title = titre
            if let p = parent { r.calendar = p.calendar }
            else if let pid = parentID { r.calendar = try EK.reminder(pid).calendar }
            else if let lid = a.nonEmpty("list_id") { r.calendar = try EK.calendar(lid) }
            else { r.calendar = try EK.defaultList() }
            try applyEK(r, a)
            try ek.save(r, commit: true)

            var out: JSON = ["ok": true, "id": r.calendarItemIdentifier, "title": titre]
            var x = extras(a)
            x.parentID = parentID
            do { try RK.apply(r.calendarItemIdentifier, x) }
            catch { out["warning"] = "reminder created, but \(error)" }

            if let subs = a.objects("subtasks"), !subs.isEmpty {
                if parentID != nil {
                    out["subtasks"] = subs.map { ["ok": false, "title": $0.string("title") ?? "", "error": "Reminders only supports one level of subtasks"] }
                } else {
                    out["subtasks"] = subs.map { creerUn($0, parent: r) }
                }
            }
            return out
        } catch {
            return ["ok": false, "title": a.string("title") ?? "", "error": "\(error)"]
        }
    }

    static func modifierRappels(_ a: JSON) throws -> Any {
        guard let items = a.objects("updates"), !items.isEmpty else { throw MCPError("missing parameter: updates (array)") }
        let res = items.map(modifierUn)
        return ["updated": res.filter { $0["ok"] as? Bool == true }.count, "failed": res.filter { $0["ok"] as? Bool != true }.count, "results": res]
    }

    private static func modifierUn(_ a: JSON) -> JSON {
        let id = a.string("id") ?? ""
        do {
            let r = try EK.reminder(id)
            try applyEK(r, a)
            if r.hasChanges { try ek.save(r, commit: true) }
            var listeActuelle = r.calendar?.calendarIdentifier

            // Déplacement (sous-tâches comprises) par ReminderKit : EventKit refuse un parent avec sous-tâches
            if let lid = a.nonEmpty("list_id"), lid != listeActuelle {
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
            return ["ok": false, "id": id, "error": "\(error)"]
        }
    }

    static func terminerRappels(_ a: JSON) throws -> Any {
        guard let ids = a.strings("ids"), !ids.isEmpty else { throw MCPError("missing parameter: ids") }
        let termine = a.bool("completed") ?? true
        var res: [JSON] = []
        for id in ids {
            do {
                let r = try EK.reminder(id)
                r.isCompleted = termine
                try ek.save(r, commit: false)
                res.append(["ok": true, "id": id, "title": r.title ?? ""])
            } catch { res.append(["ok": false, "id": id, "error": "\(error)"]) }
        }
        try ek.commit()
        return ["results": res]
    }

    static func supprimerRappels(_ a: JSON) throws -> Any {
        guard let ids = a.strings("ids"), !ids.isEmpty else { throw MCPError("missing parameter: ids") }
        let kids = RK.childCounts(ids)
        var res: [JSON] = []
        for id in ids {
            do {
                let r = try EK.reminder(id)
                let titre = r.title ?? ""
                try ek.remove(r, commit: false)
                var d: JSON = ["ok": true, "id": id, "title": titre]
                if let n = kids[id], n > 0 { d["deleted_subtasks"] = n }
                res.append(d)
            } catch { res.append(["ok": false, "id": id, "error": "\(error)"]) }
        }
        try ek.commit()
        return ["results": res]
    }

    // MARK: - Images et tags

    static func ajouterImage(_ a: JSON) throws -> Any {
        let id = try a.req("id")
        _ = try EK.reminder(id)
        let path = (try a.req("path") as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { throw MCPError("cannot read file: \(path)") }
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else {
            throw MCPError("not a recognized image file: \(url.lastPathComponent)")
        }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else {
            throw MCPError("cannot read image dimensions: \(url.lastPathComponent)")
        }
        try RK.addImage(id, data: data, uti: type.identifier, width: w, height: h)
        return ["ok": true, "id": id, "image": url.lastPathComponent, "width": w, "height": h]
    }

    static func tags(_ a: JSON) throws -> Any {
        try RK.require()
        let cals = try a.strings("list_ids").map { try $0.map(EK.calendar) }
        let predicate: NSPredicate
        switch a.nonEmpty("status") ?? "incomplete" {
        case "incomplete": predicate = ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)
        case "completed": predicate = ek.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: cals)
        case "all": predicate = ek.predicateForReminders(in: cals)
        case let s: throw MCPError("unknown status: \(s) (incomplete, completed, all)")
        }
        var counts: [String: Int] = [:]
        for i in RK.infos(EK.fetch(predicate).map(\.calendarItemIdentifier)).values {
            for t in i.tags { counts[t, default: 0] += 1 }
        }
        return ["tags": counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { ["tag": $0.key, "count": $0.value] }]
    }
}
