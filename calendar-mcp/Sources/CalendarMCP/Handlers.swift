// Logique des outils : EventKit pour le cœur, voie privée (Private.swift) pour trajet, pièces jointes, visio, invitations
import Foundation
import EventKit

enum Handlers {
    private static var ek: EKEventStore { EK.store }
    private static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }

    // MARK: - Calendriers

    static func calendriers(_ a: JSON) throws -> Any {
        let filtre = a.nonEmpty("name_contains")
        let defID = ek.defaultCalendarForNewEvents?.calendarIdentifier
        let cals = ek.calendars(for: .event).filter { filtre == nil || $0.title.localizedStandardContains(filtre!) }
            .sorted { ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title) }
        let out: [JSON] = cals.map { c in
            var d: JSON = ["id": c.calendarIdentifier, "name": c.title, "account": EK.sourceType(c.source)]
            if let h = Colors.hex(c.cgColor) { d["color"] = h }
            if !c.allowsContentModifications { d["read_only"] = true }
            if c.calendarIdentifier == defID { d["default"] = true }
            return d
        }
        var comptes: [JSON] = []
        var vus = Set<String>()
        for src in ek.sources where [.local, .exchange, .calDAV, .mobileMe].contains(src.sourceType) {
            guard src.sourceType == .local || !src.calendars(for: .event).isEmpty else { continue }
            let k = "\(src.title)|\(EK.sourceType(src))"
            if vus.insert(k).inserted { comptes.append(["name": src.title, "type": EK.sourceType(src)]) }
        }
        return ["calendars": out, "accounts": comptes]
    }

    static func creerCalendrier(_ a: JSON) throws -> Any {
        let nom = try a.req("name")
        let src: EKSource
        if let compte = a.nonEmpty("account") {
            let candidats = ek.sources.filter { s in
                [.local, .exchange, .calDAV, .mobileMe].contains(s.sourceType) &&
                    (EK.sourceType(s) == compte.lowercased() || s.title.localizedCaseInsensitiveCompare(compte) == .orderedSame)
            }
            guard let s = candidats.first(where: { !$0.calendars(for: .event).isEmpty }) ?? candidats.first else {
                throw MCPError("account not found: \(compte) (see accounts in list_calendars)")
            }
            src = s
        } else {
            guard let s = ek.defaultCalendarForNewEvents?.source else { throw MCPError("no default account") }
            src = s
        }
        let c = EKCalendar(for: .event, eventStore: ek)
        c.title = nom
        c.source = src
        if let col = a.nonEmpty("color") { c.cgColor = try Colors.parse(col) }
        try ek.saveCalendar(c, commit: true)
        return ["id": c.calendarIdentifier, "name": c.title, "account": EK.sourceType(src)]
    }

    static func modifierCalendrier(_ a: JSON) throws -> Any {
        let c = try EK.calendar(try a.req("id"))
        if let nom = a.nonEmpty("name") { c.title = nom }
        if let col = a.nonEmpty("color") { c.cgColor = try Colors.parse(col) }
        try ek.saveCalendar(c, commit: true)
        var d: JSON = ["id": c.calendarIdentifier, "name": c.title]
        if let h = Colors.hex(c.cgColor) { d["color"] = h }
        return d
    }

    static func supprimerCalendrier(_ a: JSON) throws -> Any {
        let c = try EK.calendar(try a.req("id"))
        if a.bool("force") != true {
            let now = Date()
            let n = EK.events(Dates.cal.date(byAdding: .year, value: -2, to: now)!, Dates.cal.date(byAdding: .year, value: 2, to: now)!, [c]).count
            if n > 0 { throw MCPError("calendar \"\(c.title)\" contains \(n) event(s) within ±2 years: use force: true to delete it with its events") }
        }
        try ek.removeCalendar(c, commit: true)
        return ["ok": true, "id": c.calendarIdentifier, "name": c.title]
    }

    // MARK: - Lecture

    private static func selfAttendee(_ e: EKEvent) -> EKParticipant? { e.attendees?.first { $0.isCurrentUser } }

    private static func status(_ s: EKParticipantStatus) -> String {
        switch s {
        case .accepted: return "accepted"
        case .declined: return "declined"
        case .tentative: return "tentative"
        case .pending: return "pending"
        case .delegated: return "delegated"
        default: return "unknown"
        }
    }

    private static func email(_ p: EKParticipant) -> String? {
        let u = p.url.absoluteString
        return u.lowercased().hasPrefix("mailto:") ? String(u.dropFirst(7)) : nil
    }

    static func describe(_ e: EKEvent, detail: Bool = false) -> JSON {
        var d: JSON = ["id": e.eventIdentifier ?? "", "title": e.title ?? ""]
        if e.isAllDay {
            d["day"] = Dates.day(e.startDate)
            if !Dates.cal.isDate(e.startDate, inSameDayAs: e.endDate) { d["until"] = Dates.day(e.endDate) }
        } else {
            d["start"] = Dates.text(e.startDate)
            d["end"] = Dates.text(e.endDate)
        }
        d["calendar"] = e.calendar?.title ?? ""
        if let l = e.location, !l.isEmpty { d["location"] = l }
        if e.hasRecurrenceRules || e.isDetached, let o = e.occurrenceDate { d["occurrence"] = Dates.text(o) }
        if let v = Priv.conference(e) { d["video_call"] = v }
        if e.availability != .busy, e.availability != .notSupported, let l = Dispo.label(e.availability) { d["availability"] = l }
        if let t = Priv.travelMinutes(e) { d["travel_time_min"] = t }
        if e.hasAttendees {
            d["attendee_count"] = e.attendees?.count ?? 0
            if let me = selfAttendee(e), e.organizer?.isCurrentUser != true { d["my_response"] = status(me.participantStatus) }
        }
        guard detail else { return d }
        d["calendar_id"] = e.calendar?.calendarIdentifier ?? ""
        if let n = e.notes, !n.isEmpty { d["notes"] = n }
        if let u = e.url { d["url"] = u.absoluteString }
        if let g = e.structuredLocation?.geoLocation { d["latitude"] = g.coordinate.latitude; d["longitude"] = g.coordinate.longitude }
        if let tz = e.timeZone, tz.identifier != TimeZone.current.identifier { d["time_zone"] = tz.identifier }
        if let al = e.alarms, !al.isEmpty { d["alarms"] = al.map(Alarms.json) }
        if let r = e.recurrenceRules?.first { d["recurrence"] = Recurrence.json(r) }
        if e.isDetached { d["modified_occurrence"] = true }
        if let o = e.organizer { d["organizer"] = o.name ?? email(o) ?? "" }
        if let at = e.attendees, !at.isEmpty {
            d["attendees"] = at.map { p -> JSON in
                var x: JSON = ["status": status(p.participantStatus)]
                if let n = p.name { x["name"] = n }
                if let m = email(p) { x["email"] = m }
                if p.isCurrentUser { x["is_me"] = true }
                return x
            }
        }
        let pj = Priv.attachmentNames(e)
        if !pj.isEmpty { d["attachments"] = pj }
        return d
    }

    private static func calendarsFilter(_ a: JSON) throws -> [EKCalendar]? {
        guard let ids = a.strings("calendar_ids"), !ids.isEmpty else { return nil }
        return try ids.map(EK.calendar)
    }

    /// Fenêtre de lecture : vue, ou debut/fin explicites
    private static func window(_ a: JSON, vue: String?) throws -> (Date, Date) {
        let today = Dates.startOfToday()
        var (s, e): (Date, Date)
        switch vue {
        case "today": (s, e) = (today, Dates.addDays(today, 1))
        case "tomorrow": (s, e) = (Dates.addDays(today, 1), Dates.addDays(today, 2))
        case "upcoming": (s, e) = (Date(), Dates.addDays(today, 30))
        case nil, "week", "conflicts":
            (s, e) = a.nonEmpty("text") != nil && vue == nil ? (Dates.addDays(today, -365), Dates.addDays(today, 365)) : (today, Dates.addDays(today, 7))
        default: throw MCPError("unknown view: \(vue!) (today, tomorrow, week, upcoming, conflicts)")
        }
        if let x = a.nonEmpty("start") { s = try Dates.date(x) }
        if let x = a.nonEmpty("end") {
            let p = try Dates.parse(x)
            e = p.date
            if p.date <= s && !p.hasTime { e = Dates.addDays(p.date, 1) }  // fin = même jour sans heure : journée incluse
        } else if a.nonEmpty("start") != nil, vue == nil { e = max(e, Dates.addDays(s, 7)) }
        guard e > s else { throw MCPError("empty window: end must be after start") }
        return (s, e)
    }

    static func evenements(_ a: JSON) throws -> Any {
        if let id = a.nonEmpty("id") {
            let (ev, _) = try locate(id, a.nonEmpty("occurrence"), nil)
            return ["events": [describe(ev, detail: true)]]
        }
        let vue = a.nonEmpty("view")
        let (s, e) = try window(a, vue: vue)
        var items = EK.events(s, e, try calendarsFilter(a))
        if vue == "upcoming" { items = items.filter { $0.endDate > Date() } }
        if let t = a.nonEmpty("text").map(fold) {
            items = items.filter { fold(($0.title ?? "") + "\n" + ($0.notes ?? "") + "\n" + ($0.location ?? "")).contains(t) }
        }
        if a.bool("invitations") == true {
            items = items.filter { selfAttendee($0)?.participantStatus == .pending && $0.organizer?.isCurrentUser != true }
        }
        items.sort { $0.startDate != $1.startDate ? $0.startDate < $1.startDate : ($0.title ?? "") < ($1.title ?? "") }

        if vue == "conflicts" {
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
        let limite = max(1, a.int("limit") ?? 20)
        var out: [JSON] = []
        if vue == "conflicts" {
            // Recalcule les chevauchements pour la page renvoyée
            let page = Array(items.prefix(limite))
            for x in page {
                var d = describe(x, detail: detail)
                d["overlaps"] = items.filter { $0 !== x && $0.startDate < x.endDate && x.startDate < $0.endDate }.map { $0.title ?? "" }
                out.append(d)
            }
        } else {
            out = items.prefix(limite).map { describe($0, detail: detail) }
        }
        var res: JSON = ["total": total, "events": out]
        if total > out.count { res["truncated"] = "\(out.count) shown of \(total): increase limit or filter" }
        return res
    }

    // MARK: - Localiser un événement ou une occurrence

    /// Renvoie l'objet à écrire et la portée EventKit
    static func locate(_ id: String, _ occurrence: String?, _ portee: String?) throws -> (EKEvent, EKSpan) {
        if let p = portee, !["this_occurrence", "following", "series"].contains(p) {
            throw MCPError("scope: this_occurrence, following or series")
        }
        guard let master = ek.event(withIdentifier: id) else { throw MCPError("event not found: \(id)") }
        let recurring = master.hasRecurrenceRules
        guard let occ = occurrence else {
            if recurring, portee == "this_occurrence" || portee == "following" {
                throw MCPError("occurrence required with scope \(portee!)")
            }
            return (master, recurring ? .futureEvents : .thisEvent)
        }
        // Occurrence détachée (déjà modifiée seule) : son propre identifiant suffit
        if master.isDetached, !recurring { return (master, .thisEvent) }
        let d = try Dates.date(occ)
        let candidats = ek.events(matching: ek.predicateForEvents(withStart: d.addingTimeInterval(-60), end: d.addingTimeInterval(60), calendars: [master.calendar]))
        guard let found = candidats.first(where: { ($0.eventIdentifier == id || $0.calendarItemIdentifier == master.calendarItemIdentifier) && abs(($0.occurrenceDate ?? $0.startDate).timeIntervalSince(d)) < 60 }) else {
            if !recurring { return (master, .thisEvent) }
            throw MCPError("occurrence \(occ) not found for \(id)")
        }
        switch portee ?? "this_occurrence" {
        case "following": return (found, .futureEvents)
        case "series": return (master, .futureEvents)
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
        if a.has("title") { e.title = try a.req("title") }

        // Dates
        let tz: TimeZone? = try a.nonEmpty("time_zone").map { z in
            guard let t = TimeZone(identifier: z) else { throw MCPError("unknown time zone: \(z)") }
            return t
        }
        let dur = creating ? 3600 : e.endDate.timeIntervalSince(e.startDate)
        var allDay = creating ? false : e.isAllDay
        var start = creating ? Date() : e.startDate!
        var end: Date?
        if let x = a.nonEmpty("start") {
            let pr = try Dates.parse(x, tz: tz ?? .current)
            start = pr.date
            if a.bool("all_day") == nil { allDay = !pr.hasTime }
        }
        if let j = a.bool("all_day") { allDay = j }
        if let x = a.nonEmpty("end") { end = try Dates.parse(x, tz: tz ?? .current).date }
        else if let m = a.double("duration_min") { end = start.addingTimeInterval(m * 60) }
        if a.has("start") || a.has("end") || a.has("duration_min") || a.has("all_day") || creating {
            if allDay {
                let s = Dates.cal.startOfDay(for: start)
                let f = Dates.cal.startOfDay(for: end ?? (creating ? start : start.addingTimeInterval(max(0, dur))))
                guard f >= s else { throw MCPError("end before start") }
                e.isAllDay = true; e.startDate = s; e.endDate = f
                if creating || a.has("all_day") { e.timeZone = nil }
            } else {
                let f = end ?? start.addingTimeInterval(creating ? 3600 : dur)
                guard f > start else { throw MCPError("end before or equal to start") }
                e.isAllDay = false; e.startDate = start; e.endDate = f
            }
        }
        if let tz, !allDay { e.timeZone = tz }

        // Texte
        if a.has("notes") { e.notes = a.nonEmpty("notes") }
        if a.has("url") {
            if let u = a.nonEmpty("url") {
                guard let url = URL(string: u) else { throw MCPError("invalid URL: \(u)") }
                e.url = url
            } else { e.url = nil }
        }
        try Lieu.apply(e, a)
        if let d = a.nonEmpty("availability") { e.availability = try Dispo.parse(d) }
        if let t = a.double("travel_time_min") { try Priv.setTravel(e, minutes: t) }

        // Alertes
        if a.has("alarms") {
            let wanted = try (a.objects("alarms") ?? []).map(Alarms.parse)
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
        p.attachments = a.strings(creating ? "attachments" : "add_attachments") ?? []
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
            do { try ek.save(e, span: span, commit: true) } catch { warnings.append("second save (alarms, attachments): \(error.localizedDescription)") }
        }
        return warnings
    }

    private static func summary(_ e: EKEvent) -> JSON {
        var d: JSON = ["ok": true, "id": e.eventIdentifier ?? "", "title": e.title ?? ""]
        if e.isAllDay {
            d["day"] = Dates.day(e.startDate)
            if !Dates.cal.isDate(e.startDate, inSameDayAs: e.endDate) { d["until"] = Dates.day(e.endDate) }
        } else { d["start"] = Dates.text(e.startDate); d["end"] = Dates.text(e.endDate) }
        if e.hasRecurrenceRules || e.isDetached, let o = e.occurrenceDate { d["occurrence"] = Dates.text(o) }
        return d
    }

    private static func batch(_ items: [JSON], _ verb: String, _ one: (JSON) throws -> JSON) -> JSON {
        let res: [JSON] = items.map { item in
            do { return try one(item) } catch {
                var d: JSON = ["ok": false, "error": "\(error is MCPError ? "\(error)" : error.localizedDescription)"]
                if let id = item.nonEmpty("id") { d["id"] = id } else if let t = item.nonEmpty("title") { d["title"] = t }
                return d
            }
        }
        let ok = res.filter { $0["ok"] as? Bool == true }.count
        return [verb: ok, "failed": res.count - ok, "results": res]
    }

    // MARK: - Création, modification, suppression

    static func creerEvenements(_ a: JSON) throws -> Any {
        guard let items = a.objects("events"), !items.isEmpty else { throw MCPError("events: empty list") }
        return batch(items, "created") { x in
            guard x.nonEmpty("title") != nil else { throw MCPError("missing title") }
            guard x.nonEmpty("start") != nil else { throw MCPError("missing start") }
            let e = EKEvent(eventStore: ek)
            e.calendar = try EK.writableCalendar(x.nonEmpty("calendar_id"))
            let p = try apply(e, x, creating: true)
            let span: EKSpan = e.hasRecurrenceRules ? .futureEvents : .thisEvent
            try ek.save(e, span: span, commit: true)
            let w = finish(e, p, span: span)
            var d = summary(e)
            if p.aligned != nil { d["start_adjusted"] = true }
            if !w.isEmpty { d["warnings"] = w }
            return d
        }
    }

    static func modifierEvenements(_ a: JSON) throws -> Any {
        guard let items = a.objects("updates"), !items.isEmpty else { throw MCPError("updates: empty list") }
        return batch(items, "updated") { x in
            var (e, span) = try locate(try x.req("id"), x.nonEmpty("occurrence"), x.nonEmpty("scope"))
            if let cid = x.nonEmpty("calendar_id") {
                if e.hasRecurrenceRules || e.isDetached, let m = ek.event(withIdentifier: x.nonEmpty("id")!), m.hasRecurrenceRules { e = m; span = .futureEvents }
                e.calendar = try EK.writableCalendar(cid)
            }
            let p = try apply(e, x, creating: false)
            try ek.save(e, span: span, commit: true)
            let w = finish(e, p, span: span)
            var d = summary(e)
            if p.aligned != nil { d["start_adjusted"] = true }
            if !w.isEmpty { d["warnings"] = w }
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
        guard let items = targets(a, "events") else { throw MCPError("events: empty list") }
        return batch(items, "deleted") { x in
            let (e, span) = try locate(try x.req("id"), x.nonEmpty("occurrence"), x.nonEmpty("scope"))
            let titre = e.title ?? ""
            try ek.remove(e, span: span, commit: true)
            var d: JSON = ["ok": true, "id": x.nonEmpty("id")!, "title": titre]
            if let o = x.nonEmpty("occurrence") { d["occurrence"] = o }
            if span == .futureEvents, e.hasRecurrenceRules { d["scope"] = x.nonEmpty("scope") ?? "series" }
            return d
        }
    }

    // MARK: - Créneaux libres

    private static func hm(_ s: String?, _ def: (Int, Int)) throws -> (Int, Int) {
        guard let s else { return def }
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, (0...24).contains(p[0]), (0...59).contains(p[1]) else { throw MCPError("invalid time: \(s) (HH:MM)") }
        return (p[0], p[1])
    }

    static func creneauxLibres(_ a: JSON) throws -> Any {
        let now = Date()
        let from = try a.nonEmpty("start").map(Dates.date) ?? now
        var to = Dates.addDays(Dates.cal.startOfDay(for: from), 7)
        if let x = a.nonEmpty("end") {
            let p = try Dates.parse(x)
            to = p.hasTime ? p.date : Dates.addDays(p.date, 1)
        }
        guard to > from else { throw MCPError("end must be after start") }
        let minDur = max(5, a.double("duration_min") ?? 30) * 60
        let (h1, m1) = try hm(a.nonEmpty("day_start"), (9, 0)), (h2, m2) = try hm(a.nonEmpty("day_end"), (18, 0))
        let weekend = a.bool("include_weekends") == true
        let cals = try calendarsFilter(a) ?? ek.calendars(for: .event).filter { $0.type != .birthday }
        let busy = EK.events(from, to, cals)
            .filter { !$0.isAllDay && $0.availability != .free && selfAttendee($0)?.participantStatus != .declined }
            .map { (Priv.busyStart($0), $0.endDate!) }
            .sorted { $0.0 < $1.0 }
        let limite = max(1, a.int("limit") ?? 20)
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
        return ["slots": Array(slots.prefix(limite))]
    }

    private static func slot(_ s: Date, _ e: Date) -> JSON {
        ["start": Dates.text(s), "end": Dates.text(e), "minutes": Int(e.timeIntervalSince(s) / 60)]
    }

    // MARK: - Invitations (effet externe)

    static func inviter(_ a: JSON) throws -> Any {
        guard let items = a.objects("invitations"), !items.isEmpty else { throw MCPError("invitations: empty list") }
        return batch(items, "sent") { x in
            let (e, span) = try locate(try x.req("id"), x.nonEmpty("occurrence"), x.nonEmpty("scope"))
            guard e.calendar.source.sourceType != .local else { throw MCPError("an \"On My Mac\" calendar cannot send invitations") }
            guard let people = x.objects("attendees"), !people.isEmpty else { throw MCPError("attendees: empty list") }
            var ajoutes: [String] = []
            for p in people {
                let mail = try p.req("email")
                guard mail.contains("@") else { throw MCPError("invalid email: \(mail)") }
                try Priv.addAttendee(e, email: mail, name: p.nonEmpty("name"))
                ajoutes.append(mail)
            }
            try ek.save(e, span: span, commit: true)
            return ["ok": true, "id": e.eventIdentifier ?? "", "title": e.title ?? "", "attendees": ajoutes]
        }
    }

    static func repondreInvitations(_ a: JSON) throws -> Any {
        guard let items = a.objects("responses"), !items.isEmpty else { throw MCPError("responses: empty list") }
        let map: [String: EKParticipantStatus] = ["accepted": .accepted, "declined": .declined, "tentative": .tentative]
        return batch(items, "sent") { x in
            guard let st = map[x.string("response") ?? ""] else { throw MCPError("response: accepted, declined or tentative") }
            let (e, span) = try locate(try x.req("id"), x.nonEmpty("occurrence"), x.nonEmpty("scope"))
            guard selfAttendee(e) != nil, e.organizer?.isCurrentUser != true else { throw MCPError("not a received invitation: \(e.title ?? "")") }
            try Priv.setParticipation(e, st)
            try ek.save(e, span: span, commit: true)
            return ["ok": true, "id": e.eventIdentifier ?? "", "title": e.title ?? "", "response": x.string("response")!]
        }
    }
}
