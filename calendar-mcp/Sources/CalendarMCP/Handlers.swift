// Logique des outils : EventKit pour le cœur, voie privée (Private.swift) pour trajet, pièces jointes, visio, invitations
import Foundation
import EventKit

enum Handlers {
    private static var ek: EKEventStore { EK.store }
    private static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }

    // MARK: - Calendriers

    static func calendriers(_ a: JSON) throws -> Any {
        let filtre = a.nonEmpty("nom_contient")
        let defID = ek.defaultCalendarForNewEvents?.calendarIdentifier
        let cals = ek.calendars(for: .event).filter { filtre == nil || $0.title.localizedStandardContains(filtre!) }
            .sorted { ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title) }
        let out: [JSON] = cals.map { c in
            var d: JSON = ["id": c.calendarIdentifier, "nom": c.title, "compte": EK.sourceType(c.source)]
            if let h = Colors.hex(c.cgColor) { d["couleur"] = h }
            if !c.allowsContentModifications { d["lecture_seule"] = true }
            if c.calendarIdentifier == defID { d["par_defaut"] = true }
            return d
        }
        var comptes: [JSON] = []
        var vus = Set<String>()
        for src in ek.sources where [.local, .exchange, .calDAV, .mobileMe].contains(src.sourceType) {
            guard src.sourceType == .local || !src.calendars(for: .event).isEmpty else { continue }
            let k = "\(src.title)|\(EK.sourceType(src))"
            if vus.insert(k).inserted { comptes.append(["nom": src.title, "type": EK.sourceType(src)]) }
        }
        return ["calendriers": out, "comptes": comptes]
    }

    static func creerCalendrier(_ a: JSON) throws -> Any {
        let nom = try a.req("nom")
        let src: EKSource
        if let compte = a.nonEmpty("compte") {
            let candidats = ek.sources.filter { s in
                [.local, .exchange, .calDAV, .mobileMe].contains(s.sourceType) &&
                    (EK.sourceType(s) == compte.lowercased() || s.title.localizedCaseInsensitiveCompare(compte) == .orderedSame)
            }
            guard let s = candidats.first(where: { !$0.calendars(for: .event).isEmpty }) ?? candidats.first else {
                throw MCPError("compte introuvable : \(compte) (voir comptes dans calendriers)")
            }
            src = s
        } else {
            guard let s = ek.defaultCalendarForNewEvents?.source else { throw MCPError("aucun compte par défaut") }
            src = s
        }
        let c = EKCalendar(for: .event, eventStore: ek)
        c.title = nom
        c.source = src
        if let col = a.nonEmpty("couleur") { c.cgColor = try Colors.parse(col) }
        try ek.saveCalendar(c, commit: true)
        return ["id": c.calendarIdentifier, "nom": c.title, "compte": EK.sourceType(src)]
    }

    static func modifierCalendrier(_ a: JSON) throws -> Any {
        let c = try EK.calendar(try a.req("id"))
        if let nom = a.nonEmpty("nom") { c.title = nom }
        if let col = a.nonEmpty("couleur") { c.cgColor = try Colors.parse(col) }
        try ek.saveCalendar(c, commit: true)
        var d: JSON = ["id": c.calendarIdentifier, "nom": c.title]
        if let h = Colors.hex(c.cgColor) { d["couleur"] = h }
        return d
    }

    static func supprimerCalendrier(_ a: JSON) throws -> Any {
        let c = try EK.calendar(try a.req("id"))
        if a.bool("force") != true {
            let now = Date()
            let n = EK.events(Dates.cal.date(byAdding: .year, value: -2, to: now)!, Dates.cal.date(byAdding: .year, value: 2, to: now)!, [c]).count
            if n > 0 { throw MCPError("le calendrier « \(c.title) » contient \(n) événement(s) sur ±2 ans : force: true pour le supprimer avec") }
        }
        try ek.removeCalendar(c, commit: true)
        return ["ok": true, "id": c.calendarIdentifier, "nom": c.title]
    }

    // MARK: - Lecture

    private static func selfAttendee(_ e: EKEvent) -> EKParticipant? { e.attendees?.first { $0.isCurrentUser } }

    private static func status(_ s: EKParticipantStatus) -> String {
        switch s {
        case .accepted: return "accepte"
        case .declined: return "refuse"
        case .tentative: return "peut_etre"
        case .pending: return "en_attente"
        case .delegated: return "delegue"
        default: return "inconnu"
        }
    }

    private static func email(_ p: EKParticipant) -> String? {
        let u = p.url.absoluteString
        return u.lowercased().hasPrefix("mailto:") ? String(u.dropFirst(7)) : nil
    }

    static func describe(_ e: EKEvent, detail: Bool = false) -> JSON {
        var d: JSON = ["id": e.eventIdentifier ?? "", "titre": e.title ?? ""]
        if e.isAllDay {
            d["jour"] = Dates.day(e.startDate)
            if !Dates.cal.isDate(e.startDate, inSameDayAs: e.endDate) { d["jusqu_au"] = Dates.day(e.endDate) }
        } else {
            d["debut"] = Dates.text(e.startDate)
            d["fin"] = Dates.text(e.endDate)
        }
        d["calendrier"] = e.calendar?.title ?? ""
        if let l = e.location, !l.isEmpty { d["lieu"] = l }
        if e.hasRecurrenceRules || e.isDetached, let o = e.occurrenceDate { d["occurrence"] = Dates.text(o) }
        if let v = Priv.conference(e) { d["visio"] = v }
        if e.availability != .busy, e.availability != .notSupported, let l = Dispo.label(e.availability) { d["disponibilite"] = l }
        if let t = Priv.travelMinutes(e) { d["trajet_min"] = t }
        if e.hasAttendees {
            d["nb_invites"] = e.attendees?.count ?? 0
            if let me = selfAttendee(e), e.organizer?.isCurrentUser != true { d["ma_reponse"] = status(me.participantStatus) }
        }
        guard detail else { return d }
        d["calendrier_id"] = e.calendar?.calendarIdentifier ?? ""
        if let n = e.notes, !n.isEmpty { d["notes"] = n }
        if let u = e.url { d["url"] = u.absoluteString }
        if let g = e.structuredLocation?.geoLocation { d["latitude"] = g.coordinate.latitude; d["longitude"] = g.coordinate.longitude }
        if let tz = e.timeZone, tz.identifier != TimeZone.current.identifier { d["fuseau"] = tz.identifier }
        if let al = e.alarms, !al.isEmpty { d["alertes"] = al.map(Alarms.json) }
        if let r = e.recurrenceRules?.first { d["recurrence"] = Recurrence.json(r) }
        if e.isDetached { d["occurrence_modifiee"] = true }
        if let o = e.organizer { d["organisateur"] = o.name ?? email(o) ?? "" }
        if let at = e.attendees, !at.isEmpty {
            d["invites"] = at.map { p -> JSON in
                var x: JSON = ["statut": status(p.participantStatus)]
                if let n = p.name { x["nom"] = n }
                if let m = email(p) { x["email"] = m }
                if p.isCurrentUser { x["moi"] = true }
                return x
            }
        }
        let pj = Priv.attachmentNames(e)
        if !pj.isEmpty { d["pieces_jointes"] = pj }
        return d
    }

    private static func calendarsFilter(_ a: JSON) throws -> [EKCalendar]? {
        guard let ids = a.strings("calendrier_ids"), !ids.isEmpty else { return nil }
        return try ids.map(EK.calendar)
    }

    /// Fenêtre de lecture : vue, ou debut/fin explicites
    private static func window(_ a: JSON, vue: String?) throws -> (Date, Date) {
        let today = Dates.startOfToday()
        var (s, e): (Date, Date)
        switch vue {
        case "aujourdhui": (s, e) = (today, Dates.addDays(today, 1))
        case "demain": (s, e) = (Dates.addDays(today, 1), Dates.addDays(today, 2))
        case "a_venir": (s, e) = (Date(), Dates.addDays(today, 30))
        case nil, "semaine", "conflits":
            (s, e) = a.nonEmpty("texte") != nil && vue == nil ? (Dates.addDays(today, -365), Dates.addDays(today, 365)) : (today, Dates.addDays(today, 7))
        default: throw MCPError("vue inconnue : \(vue!) (aujourdhui, demain, semaine, a_venir, conflits)")
        }
        if let x = a.nonEmpty("debut") { s = try Dates.date(x) }
        if let x = a.nonEmpty("fin") {
            let p = try Dates.parse(x)
            e = p.date
            if p.date <= s && !p.hasTime { e = Dates.addDays(p.date, 1) }  // fin = même jour sans heure : journée incluse
        } else if a.nonEmpty("debut") != nil, vue == nil { e = max(e, Dates.addDays(s, 7)) }
        guard e > s else { throw MCPError("fenêtre vide : fin doit suivre debut") }
        return (s, e)
    }

    static func evenements(_ a: JSON) throws -> Any {
        if let id = a.nonEmpty("id") {
            let (ev, _) = try locate(id, a.nonEmpty("occurrence"), nil)
            return ["evenements": [describe(ev, detail: true)]]
        }
        let vue = a.nonEmpty("vue")
        let (s, e) = try window(a, vue: vue)
        var items = EK.events(s, e, try calendarsFilter(a))
        if vue == "a_venir" { items = items.filter { $0.endDate > Date() } }
        if let t = a.nonEmpty("texte").map(fold) {
            items = items.filter { fold(($0.title ?? "") + "\n" + ($0.notes ?? "") + "\n" + ($0.location ?? "")).contains(t) }
        }
        if a.bool("invitations") == true {
            items = items.filter { selfAttendee($0)?.participantStatus == .pending && $0.organizer?.isCurrentUser != true }
        }
        items.sort { $0.startDate != $1.startDate ? $0.startDate < $1.startDate : ($0.title ?? "") < ($1.title ?? "") }

        if vue == "conflits" {
            // Garde les événements occupés qui en chevauchent un autre
            let busy = items.filter { !$0.isAllDay && $0.availability != .free && selfAttendee($0)?.participantStatus != .declined }
            var hit = Set<ObjectIdentifier>()
            for (i, x) in busy.enumerated() {
                for y in busy[(i + 1)...] {
                    if y.startDate >= x.endDate { break }
                    hit.insert(ObjectIdentifier(x)); hit.insert(ObjectIdentifier(y))
                }
            }
            items = items.filter { hit.contains(ObjectIdentifier($0)) }
        }

        let detail = a.bool("detail") == true
        let total = items.count
        let limite = max(1, a.int("limite") ?? 20)
        var out: [JSON] = []
        if vue == "conflits" {
            // Recalcule les chevauchements pour la page renvoyée
            let page = Array(items.prefix(limite))
            for x in page {
                var d = describe(x, detail: detail)
                d["chevauche"] = items.filter { $0 !== x && $0.startDate < x.endDate && x.startDate < $0.endDate }.map { $0.title ?? "" }
                out.append(d)
            }
        } else {
            out = items.prefix(limite).map { describe($0, detail: detail) }
        }
        var res: JSON = ["total": total, "evenements": out]
        if total > out.count { res["tronque"] = "\(out.count) affichés sur \(total) : augmenter limite ou filtrer" }
        return res
    }

    // MARK: - Localiser un événement ou une occurrence

    /// Renvoie l'objet à écrire et la portée EventKit
    static func locate(_ id: String, _ occurrence: String?, _ portee: String?) throws -> (EKEvent, EKSpan) {
        if let p = portee, !["cette_occurrence", "suivantes", "serie"].contains(p) {
            throw MCPError("portee : cette_occurrence, suivantes ou serie")
        }
        guard let master = ek.event(withIdentifier: id) else { throw MCPError("événement introuvable : \(id)") }
        let recurring = master.hasRecurrenceRules
        guard let occ = occurrence else {
            if recurring, portee == "cette_occurrence" || portee == "suivantes" {
                throw MCPError("occurrence requise avec portee \(portee!)")
            }
            return (master, recurring ? .futureEvents : .thisEvent)
        }
        // Occurrence détachée (déjà modifiée seule) : son propre identifiant suffit
        if master.isDetached, !recurring { return (master, .thisEvent) }
        let d = try Dates.date(occ)
        let candidats = ek.events(matching: ek.predicateForEvents(withStart: d.addingTimeInterval(-60), end: d.addingTimeInterval(60), calendars: [master.calendar]))
        guard let found = candidats.first(where: { ($0.eventIdentifier == id || $0.calendarItemIdentifier == master.calendarItemIdentifier) && abs(($0.occurrenceDate ?? $0.startDate).timeIntervalSince(d)) < 60 }) else {
            if !recurring { return (master, .thisEvent) }
            throw MCPError("occurrence du \(occ) introuvable pour \(id)")
        }
        switch portee ?? "cette_occurrence" {
        case "suivantes": return (found, .futureEvents)
        case "serie": return (master, .futureEvents)
        default: return (found, .thisEvent)
        }
    }

    // MARK: - Écriture des champs

    private struct Pending {
        var alarms: [EKAlarm]?
        var attachments: [String] = []
        var aligned: Date?
    }

    private static func apply(_ e: EKEvent, _ a: JSON, creating: Bool) throws -> Pending {
        var p = Pending()
        if a.has("titre") { e.title = try a.req("titre") }

        // Dates
        let tz: TimeZone? = try a.nonEmpty("fuseau").map { z in
            guard let t = TimeZone(identifier: z) else { throw MCPError("fuseau inconnu : \(z)") }
            return t
        }
        let dur = creating ? 3600 : e.endDate.timeIntervalSince(e.startDate)
        var allDay = creating ? false : e.isAllDay
        var start = creating ? Date() : e.startDate!
        var end: Date?
        if let x = a.nonEmpty("debut") {
            let pr = try Dates.parse(x, tz: tz ?? .current)
            start = pr.date
            if a.bool("journee_entiere") == nil { allDay = !pr.hasTime }
        }
        if let j = a.bool("journee_entiere") { allDay = j }
        if let x = a.nonEmpty("fin") { end = try Dates.parse(x, tz: tz ?? .current).date }
        else if let m = a.double("duree_min") { end = start.addingTimeInterval(m * 60) }
        if a.has("debut") || a.has("fin") || a.has("duree_min") || a.has("journee_entiere") || creating {
            if allDay {
                let s = Dates.cal.startOfDay(for: start)
                let f = Dates.cal.startOfDay(for: end ?? (creating ? start : start.addingTimeInterval(max(0, dur))))
                guard f >= s else { throw MCPError("fin avant debut") }
                e.isAllDay = true; e.startDate = s; e.endDate = f
                if creating || a.has("journee_entiere") { e.timeZone = nil }
            } else {
                let f = end ?? start.addingTimeInterval(creating ? 3600 : dur)
                guard f > start else { throw MCPError("fin avant ou égale à debut") }
                e.isAllDay = false; e.startDate = start; e.endDate = f
            }
        }
        if let tz, !allDay { e.timeZone = tz }

        // Texte
        if a.has("notes") { e.notes = a.nonEmpty("notes") }
        if a.has("url") {
            if let u = a.nonEmpty("url") {
                guard let url = URL(string: u) else { throw MCPError("URL invalide : \(u)") }
                e.url = url
            } else { e.url = nil }
        }
        try Lieu.apply(e, a)
        if let d = a.nonEmpty("disponibilite") { e.availability = try Dispo.parse(d) }
        if let t = a.double("trajet_min") { try Priv.setTravel(e, minutes: t) }

        // Alertes
        if a.has("alertes") {
            let wanted = try (a.objects("alertes") ?? []).map(Alarms.parse)
            e.alarms = wanted.isEmpty ? nil : wanted
            p.alarms = wanted
            if wanted.isEmpty { Priv.dropDefaultAlarm(e) }
        }

        // Récurrence (recalée sur la 1re date conforme)
        if a.has("recurrence") {
            for r in e.recurrenceRules ?? [] { e.removeRecurrenceRule(r) }
            if let r = a.object("recurrence") {
                let rule = try Recurrence.parse(r)
                let first = Recurrence.firstConforming(e.startDate, rule)
                if first != e.startDate {
                    let delta = first.timeIntervalSince(e.startDate)
                    e.startDate = first
                    e.endDate = e.endDate.addingTimeInterval(delta)
                    p.aligned = first
                }
                e.addRecurrenceRule(rule)
            }
        }
        p.attachments = a.strings(creating ? "pieces_jointes" : "ajouter_pieces_jointes") ?? []
        return p
    }

    /// Après l'enregistrement : retire l'alerte par défaut ajoutée par le compte si elle n'était pas demandée, joint les fichiers
    private static func finish(_ e: EKEvent, _ p: Pending, span: EKSpan) -> [String] {
        var warnings: [String] = []
        var resave = false
        if let wanted = p.alarms {
            let have = (e.alarms ?? []).map(Alarms.key).sorted(), want = wanted.map(Alarms.key).sorted()
            if have != want {
                e.alarms = wanted.isEmpty ? nil : wanted.map { $0.copy() as! EKAlarm }
                Priv.dropDefaultAlarm(e)
                resave = true
            }
        }
        for path in p.attachments {
            do { _ = try Priv.addAttachment(e, path: path); resave = true } catch { warnings.append("\(error)") }
        }
        if resave {
            do { try ek.save(e, span: span, commit: true) } catch { warnings.append("2e écriture (alertes, pièces jointes) : \(error.localizedDescription)") }
        }
        return warnings
    }

    private static func summary(_ e: EKEvent) -> JSON {
        var d: JSON = ["ok": true, "id": e.eventIdentifier ?? "", "titre": e.title ?? ""]
        if e.isAllDay {
            d["jour"] = Dates.day(e.startDate)
            if !Dates.cal.isDate(e.startDate, inSameDayAs: e.endDate) { d["jusqu_au"] = Dates.day(e.endDate) }
        } else { d["debut"] = Dates.text(e.startDate); d["fin"] = Dates.text(e.endDate) }
        if e.hasRecurrenceRules || e.isDetached, let o = e.occurrenceDate { d["occurrence"] = Dates.text(o) }
        return d
    }

    private static func batch(_ items: [JSON], _ verb: String, _ one: (JSON) throws -> JSON) -> JSON {
        let res: [JSON] = items.map { item in
            do { return try one(item) } catch {
                var d: JSON = ["ok": false, "erreur": "\(error is MCPError ? "\(error)" : error.localizedDescription)"]
                if let id = item.nonEmpty("id") { d["id"] = id } else if let t = item.nonEmpty("titre") { d["titre"] = t }
                return d
            }
        }
        let ok = res.filter { $0["ok"] as? Bool == true }.count
        return [verb: ok, "echecs": res.count - ok, "resultats": res]
    }

    // MARK: - Création, modification, suppression

    static func creerEvenements(_ a: JSON) throws -> Any {
        guard let items = a.objects("evenements"), !items.isEmpty else { throw MCPError("evenements : liste vide") }
        return batch(items, "crees") { x in
            guard x.nonEmpty("titre") != nil else { throw MCPError("titre manquant") }
            guard x.nonEmpty("debut") != nil else { throw MCPError("debut manquant") }
            let e = EKEvent(eventStore: ek)
            e.calendar = try EK.writableCalendar(x.nonEmpty("calendrier_id"))
            let p = try apply(e, x, creating: true)
            let span: EKSpan = e.hasRecurrenceRules ? .futureEvents : .thisEvent
            try ek.save(e, span: span, commit: true)
            let w = finish(e, p, span: span)
            var d = summary(e)
            if p.aligned != nil { d["debut_recale"] = true }
            if !w.isEmpty { d["avertissements"] = w }
            return d
        }
    }

    static func modifierEvenements(_ a: JSON) throws -> Any {
        guard let items = a.objects("modifications"), !items.isEmpty else { throw MCPError("modifications : liste vide") }
        return batch(items, "modifies") { x in
            var (e, span) = try locate(try x.req("id"), x.nonEmpty("occurrence"), x.nonEmpty("portee"))
            if let cid = x.nonEmpty("calendrier_id") {
                if e.hasRecurrenceRules || e.isDetached, let m = ek.event(withIdentifier: x.nonEmpty("id")!), m.hasRecurrenceRules { e = m; span = .futureEvents }
                e.calendar = try EK.writableCalendar(cid)
            }
            let p = try apply(e, x, creating: false)
            try ek.save(e, span: span, commit: true)
            let w = finish(e, p, span: span)
            var d = summary(e)
            if p.aligned != nil { d["debut_recale"] = true }
            if !w.isEmpty { d["avertissements"] = w }
            return d
        }
    }

    /// Accepte une liste d'objets {id, occurrence, portee} ou de simples identifiants
    private static func targets(_ a: JSON, _ key: String) -> [JSON]? {
        var raw: [Any]? = a[key] as? [Any]
        if raw == nil, let s = a[key] as? String {
            raw = s.hasPrefix("[") ? (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [Any] : [s]
        }
        let out: [JSON] = (raw ?? []).compactMap { x in (x as? JSON) ?? (x as? String).map { ["id": $0] } }
        return out.isEmpty ? nil : out
    }

    static func supprimerEvenements(_ a: JSON) throws -> Any {
        guard let items = targets(a, "evenements") else { throw MCPError("evenements : liste vide") }
        return batch(items, "supprimes") { x in
            let (e, span) = try locate(try x.req("id"), x.nonEmpty("occurrence"), x.nonEmpty("portee"))
            let titre = e.title ?? ""
            try ek.remove(e, span: span, commit: true)
            var d: JSON = ["ok": true, "id": x.nonEmpty("id")!, "titre": titre]
            if let o = x.nonEmpty("occurrence") { d["occurrence"] = o }
            if span == .futureEvents, e.hasRecurrenceRules { d["portee"] = x.nonEmpty("portee") ?? "serie" }
            return d
        }
    }

    // MARK: - Créneaux libres

    private static func hm(_ s: String?, _ def: (Int, Int)) throws -> (Int, Int) {
        guard let s else { return def }
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, (0...24).contains(p[0]), (0...59).contains(p[1]) else { throw MCPError("heure invalide : \(s) (HH:MM)") }
        return (p[0], p[1])
    }

    static func creneauxLibres(_ a: JSON) throws -> Any {
        let now = Date()
        let from = try a.nonEmpty("debut").map(Dates.date) ?? now
        var to = Dates.addDays(Dates.cal.startOfDay(for: from), 7)
        if let x = a.nonEmpty("fin") {
            let p = try Dates.parse(x)
            to = p.hasTime ? p.date : Dates.addDays(p.date, 1)
        }
        guard to > from else { throw MCPError("fin doit suivre debut") }
        let minDur = max(5, a.double("duree_min") ?? 30) * 60
        let (h1, m1) = try hm(a.nonEmpty("heure_debut"), (9, 0)), (h2, m2) = try hm(a.nonEmpty("heure_fin"), (18, 0))
        let weekend = a.bool("weekend") == true
        let cals = try calendarsFilter(a) ?? ek.calendars(for: .event).filter { $0.type != .birthday }
        let busy = EK.events(from, to, cals)
            .filter { !$0.isAllDay && $0.availability != .free && selfAttendee($0)?.participantStatus != .declined }
            .map { (Priv.busyStart($0), $0.endDate!) }
            .sorted { $0.0 < $1.0 }
        let limite = max(1, a.int("limite") ?? 20)
        var slots: [JSON] = []
        var day = Dates.cal.startOfDay(for: from)
        outer: while day < to {
            let wd = Dates.cal.component(.weekday, from: day)
            if weekend || (wd != 1 && wd != 7) {
                let ds = max(from, Dates.cal.date(bySettingHour: h1, minute: m1, second: 0, of: day)!)
                let de = min(to, h2 == 24 ? Dates.addDays(day, 1) : Dates.cal.date(bySettingHour: h2, minute: m2, second: 0, of: day)!)
                var cur = ds
                if de > ds {
                    for (s, e) in busy where e > ds && s < de {
                        if s.timeIntervalSince(cur) >= minDur { slots.append(slot(cur, s)) }
                        cur = max(cur, e)
                        if slots.count >= limite { break outer }
                    }
                    if de.timeIntervalSince(cur) >= minDur { slots.append(slot(cur, de)) }
                    if slots.count >= limite { break outer }
                }
            }
            day = Dates.addDays(day, 1)
        }
        return ["creneaux": Array(slots.prefix(limite))]
    }

    private static func slot(_ s: Date, _ e: Date) -> JSON {
        ["debut": Dates.text(s), "fin": Dates.text(e), "minutes": Int(e.timeIntervalSince(s) / 60)]
    }

    // MARK: - Invitations (effet externe)

    static func inviter(_ a: JSON) throws -> Any {
        guard let items = a.objects("invitations"), !items.isEmpty else { throw MCPError("invitations : liste vide") }
        return batch(items, "envoyees") { x in
            let (e, span) = try locate(try x.req("id"), x.nonEmpty("occurrence"), x.nonEmpty("portee"))
            guard e.calendar.source.sourceType != .local else { throw MCPError("un calendrier « Sur mon Mac » ne peut pas inviter") }
            guard let people = x.objects("invites"), !people.isEmpty else { throw MCPError("invites : liste vide") }
            var ajoutes: [String] = []
            for p in people {
                let mail = try p.req("email")
                guard mail.contains("@") else { throw MCPError("e-mail invalide : \(mail)") }
                try Priv.addAttendee(e, email: mail, name: p.nonEmpty("nom"))
                ajoutes.append(mail)
            }
            try ek.save(e, span: span, commit: true)
            return ["ok": true, "id": e.eventIdentifier ?? "", "titre": e.title ?? "", "invites": ajoutes]
        }
    }

    static func repondreInvitations(_ a: JSON) throws -> Any {
        guard let items = a.objects("reponses"), !items.isEmpty else { throw MCPError("reponses : liste vide") }
        let map: [String: EKParticipantStatus] = ["accepter": .accepted, "refuser": .declined, "peut_etre": .tentative]
        return batch(items, "envoyees") { x in
            guard let st = map[x.string("reponse") ?? ""] else { throw MCPError("reponse : accepter, refuser ou peut_etre") }
            let (e, span) = try locate(try x.req("id"), x.nonEmpty("occurrence"), x.nonEmpty("portee"))
            guard selfAttendee(e) != nil, e.organizer?.isCurrentUser != true else { throw MCPError("ce n'est pas une invitation reçue : \(e.title ?? "")") }
            try Priv.setParticipation(e, st)
            try ek.save(e, span: span, commit: true)
            return ["ok": true, "id": e.eventIdentifier ?? "", "titre": e.title ?? "", "reponse": x.string("reponse")!]
        }
    }
}
