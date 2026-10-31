// Voie publique : EventKit (calendriers, événements, lieu, alertes, récurrence, disponibilité, fuseau, invités en lecture)
import Foundation
import EventKit
import CoreLocation

enum EK {
    static let store = EKEventStore()
    private static var granted = false

    /// Vérifie l'accès complet aux calendriers, et le demande au premier appel
    static func ready() throws {
        if !granted {
            if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
                let sem = DispatchSemaphore(value: 0)
                var ok = false
                store.requestFullAccessToEvents { g, _ in ok = g; sem.signal() }
                sem.wait()
                guard ok else {
                    throw MCPError("Calendar access denied. System Settings > Privacy & Security > Calendars: allow the Claude app (full access), then relaunch.")
                }
            }
            granted = true
        }
        // Chaque appel repart d'un état frais (l'app ou un autre appareil a pu écrire entre-temps)
        store.reset()
    }

    static func calendar(_ id: String) throws -> EKCalendar {
        guard let c = store.calendar(withIdentifier: id), c.allowedEntityTypes.contains(.event) else {
            throw MCPError("calendar not found: \(id)")
        }
        return c
    }

    static func writableCalendar(_ id: String?) throws -> EKCalendar {
        let c: EKCalendar
        if let id { c = try calendar(id) } else {
            guard let d = store.defaultCalendarForNewEvents else { throw MCPError("no default calendar") }
            c = d
        }
        guard c.allowsContentModifications else { throw MCPError("read-only calendar: \(c.title)") }
        return c
    }

    static func events(_ start: Date, _ end: Date, _ cals: [EKCalendar]?) -> [EKEvent] {
        store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: cals))
    }

    static func sourceType(_ s: EKSource?) -> String {
        switch s?.sourceType {
        case .local: return "on_my_mac"
        case .exchange: return "exchange"
        case .calDAV: return s?.title.localizedCaseInsensitiveContains("icloud") == true ? "icloud" : "caldav"
        case .mobileMe: return "icloud"
        case .subscribed: return "subscribed"
        case .birthdays: return "birthdays"
        default: return "other"
        }
    }
}

// MARK: - Dates (heure locale ; AAAA-MM-JJ = journée entière)

enum Dates {
    static var cal: Calendar { Calendar.current }
    private static let pattern = try! NSRegularExpression(pattern: #"^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::\d{2})?)?$"#)

    /// Analyse une date ; `tz` sert à lire l'heure dans un autre fuseau que celui du Mac. hasTime = false pour AAAA-MM-JJ.
    static func parse(_ s: String, tz: TimeZone = .current) throws -> (date: Date, hasTime: Bool) {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let m = pattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) {
            func g(_ i: Int) -> Int? { Range(m.range(at: i), in: t).flatMap { Int(t[$0]) } }
            var c = Calendar(identifier: .gregorian); c.timeZone = tz
            let dc = DateComponents(year: g(1), month: g(2), day: g(3), hour: g(4) ?? 0, minute: g(5) ?? 0)
            guard let d = c.date(from: dc), c.component(.day, from: d) == g(3) else { throw MCPError("invalid date: \(s)") }
            return (d, g(4) != nil)
        }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: t) ?? f2.date(from: t) { return (d, true) }
        throw MCPError("invalid date \"\(s)\": expected YYYY-MM-DD (all day) or YYYY-MM-DDTHH:MM (local time)")
    }

    static func date(_ s: String) throws -> Date { try parse(s).date }

    static func text(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return String(format: "%04d-%02d-%02dT%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!)
    }

    static func day(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func startOfToday() -> Date { cal.startOfDay(for: Date()) }
    static func addDays(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: d)! }
}

// MARK: - Lieu : texte seul, ou lieu structuré dont le titre est le texte affiché (sonde 04 : poser le texte après efface la géoloc)

enum Lieu {
    static func apply(_ e: EKEvent, _ a: JSON) throws {
        let lat = a.double("latitude"), lon = a.double("longitude")
        guard a.has("location") || lat != nil else { return }
        let texte = a.nonEmpty("location") ?? e.location
        if let lat, let lon {
            let s = EKStructuredLocation(title: texte ?? "")
            s.geoLocation = CLLocation(latitude: lat, longitude: lon)
            e.structuredLocation = s
        } else if lat != nil || lon != nil {
            throw MCPError("location: latitude and longitude go together")
        } else if let texte {
            e.structuredLocation = nil
            e.location = texte
        } else {
            e.structuredLocation = nil
            e.location = nil
        }
    }
}

// MARK: - Disponibilité

enum Dispo {
    static let values: [(String, EKEventAvailability)] = [("busy", .busy), ("free", .free), ("tentative", .tentative), ("unavailable", .unavailable)]
    static func parse(_ s: String) throws -> EKEventAvailability {
        guard let v = values.first(where: { $0.0 == s.lowercased() })?.1 else { throw MCPError("availability: busy, free, tentative or unavailable") }
        return v
    }
    static func label(_ v: EKEventAvailability) -> String? { values.first(where: { $0.1 == v })?.0 }
}

// MARK: - Alertes

enum Alarms {
    static func parse(_ a: JSON) throws -> EKAlarm {
        if let d = a.nonEmpty("date") { return EKAlarm(absoluteDate: try Dates.date(d)) }
        if let m = a.double("minutes_before") { return EKAlarm(relativeOffset: -m * 60) }
        if let lieu = a.nonEmpty("location") {
            guard let lat = a.double("latitude"), let lon = a.double("longitude") else {
                throw MCPError("location alarm: latitude and longitude required")
            }
            let loc = EKStructuredLocation(title: lieu)
            loc.geoLocation = CLLocation(latitude: lat, longitude: lon)
            loc.radius = a.double("radius") ?? 100
            let al = EKAlarm()
            al.structuredLocation = loc
            al.proximity = a.string("when") == "leaving" ? .leave : .enter
            return al
        }
        throw MCPError("alarm: give minutes_before, date, or location + latitude + longitude")
    }

    static func json(_ al: EKAlarm) -> JSON {
        if let loc = al.structuredLocation {
            var d: JSON = ["location": loc.title ?? "", "when": al.proximity == .leave ? "leaving" : "arriving"]
            if let g = loc.geoLocation { d["latitude"] = g.coordinate.latitude; d["longitude"] = g.coordinate.longitude }
            return d
        }
        if let d = al.absoluteDate { return ["date": Dates.text(d)] }
        return ["minutes_before": Int(-al.relativeOffset / 60)]
    }

    /// Signature comparable d'une alerte (pour détecter l'alerte par défaut ajoutée par le compte)
    static func key(_ al: EKAlarm) -> String {
        if let l = al.structuredLocation { return "l:\(l.title ?? ""):\(al.proximity.rawValue)" }
        if let d = al.absoluteDate { return "d:\(Int(d.timeIntervalSince1970))" }
        return "r:\(Int(al.relativeOffset))"
    }
}

// MARK: - Récurrence

enum Recurrence {
    static let days: [(String, EKWeekday)] = [
        ("monday", .monday), ("tuesday", .tuesday), ("wednesday", .wednesday), ("thursday", .thursday),
        ("friday", .friday), ("saturday", .saturday), ("sunday", .sunday),
    ]
    private static let freqs: [(String, EKRecurrenceFrequency)] = [("daily", .daily), ("weekly", .weekly), ("monthly", .monthly), ("yearly", .yearly)]
    private static let dayPattern = try! NSRegularExpression(pattern: #"^(-?\d)?\s*([a-z]+)$"#)

    /// "mardi", "2mardi" (2e mardi), "-1vendredi" (dernier vendredi)
    static func day(_ s: String) throws -> EKRecurrenceDayOfWeek {
        let t = s.lowercased().trimmingCharacters(in: .whitespaces)
        guard let m = dayPattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let r = Range(m.range(at: 2), in: t), let w = days.first(where: { $0.0 == String(t[r]) })?.1 else {
            throw MCPError("unknown day: \(s) (monday…sunday, prefix 2 for the 2nd, -1 for the last)")
        }
        let n = Range(m.range(at: 1), in: t).flatMap { Int(t[$0]) } ?? 0
        return n == 0 ? EKRecurrenceDayOfWeek(w) : EKRecurrenceDayOfWeek(w, weekNumber: n)
    }

    static func parse(_ a: JSON) throws -> EKRecurrenceRule {
        let f = a.string("frequency")?.lowercased() ?? ""
        guard let freq = freqs.first(where: { $0.0 == f })?.1 else {
            throw MCPError("recurrence: frequency = daily, weekly, monthly or yearly")
        }
        let wd = try a.strings("days")?.map(day)
        let md = a.ints("days_of_month")?.map { NSNumber(value: $0) }
        let mo = a.ints("months")?.map { NSNumber(value: $0) }
        let pos = a.ints("positions")?.map { NSNumber(value: $0) }
        var end: EKRecurrenceEnd?
        if let fin = a.nonEmpty("until") {
            var d = try Dates.date(fin)
            if !(try Dates.parse(fin).hasTime) { d = Dates.addDays(d, 1).addingTimeInterval(-60) }  // jour inclus
            end = EKRecurrenceEnd(end: d)
        } else if let n = a.int("occurrences") { end = EKRecurrenceEnd(occurrenceCount: n) }
        func nz<T>(_ x: [T]?) -> [T]? { x?.isEmpty == true ? nil : x }
        return EKRecurrenceRule(recurrenceWith: freq, interval: max(1, a.int("interval") ?? 1),
                                daysOfTheWeek: nz(wd), daysOfTheMonth: nz(md), monthsOfTheYear: nz(mo),
                                weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nz(pos), end: end)
    }

    static func json(_ r: EKRecurrenceRule) -> JSON {
        var d: JSON = ["frequency": freqs.first(where: { $0.1 == r.frequency })?.0 ?? "?"]
        if r.interval > 1 { d["interval"] = r.interval }
        if let w = r.daysOfTheWeek, !w.isEmpty {
            d["days"] = w.compactMap { day in
                days.first(where: { $0.1 == day.dayOfTheWeek }).map { (day.weekNumber != 0 ? "\(day.weekNumber)" : "") + $0.0 }
            }
        }
        if let m = r.daysOfTheMonth, !m.isEmpty { d["days_of_month"] = m.map(\.intValue) }
        if let m = r.monthsOfTheYear, !m.isEmpty { d["months"] = m.map(\.intValue) }
        if let p = r.setPositions, !p.isEmpty { d["positions"] = p.map(\.intValue) }
        if let e = r.recurrenceEnd {
            if let date = e.endDate { d["until"] = Dates.day(date) } else if e.occurrenceCount > 0 { d["occurrences"] = e.occurrenceCount }
        }
        return d
    }

    // MARK: Recalage du début sur la 1re date conforme
    // EventKit compte toujours la date de début comme 1re occurrence, même hors règle (sonde 02 : « 2e mardi » commençant un samedi).

    static func firstConforming(_ start: Date, _ r: EKRecurrenceRule) -> Date {
        let c = Dates.cal
        let hasFilter = (r.daysOfTheWeek?.isEmpty == false) || (r.daysOfTheMonth?.isEmpty == false) || (r.monthsOfTheYear?.isEmpty == false)
        guard hasFilter else { return start }
        let startDay = c.component(.day, from: start)
        var d = start
        for _ in 0..<4000 {
            if conforms(d, r, startDay: startDay) { return d }
            d = c.date(byAdding: .day, value: 1, to: d)!
        }
        return start
    }

    private static func ekWeekday(_ d: Date) -> Int { Dates.cal.component(.weekday, from: d) }  // 1 = dimanche, comme EKWeekday

    /// Conformité hors BYSETPOS
    private static func base(_ d: Date, _ r: EKRecurrenceRule, startDay: Int) -> Bool {
        let c = Dates.cal
        let month = c.component(.month, from: d), dom = c.component(.day, from: d)
        let dim = c.range(of: .day, in: .month, for: d)!.count
        if let mo = r.monthsOfTheYear, !mo.isEmpty, !mo.contains(where: { $0.intValue == month }) { return false }
        if let md = r.daysOfTheMonth, !md.isEmpty, !md.contains(where: { $0.intValue > 0 ? $0.intValue == dom : dim + $0.intValue + 1 == dom }) { return false }
        if let wd = r.daysOfTheWeek, !wd.isEmpty {
            let ok = wd.contains { w in
                guard w.dayOfTheWeek.rawValue == ekWeekday(d) else { return false }
                if w.weekNumber == 0 || r.frequency == .weekly || r.frequency == .daily { return true }
                let nth = (dom - 1) / 7 + 1, nthFromEnd = -((dim - dom) / 7 + 1)
                return w.weekNumber == nth || w.weekNumber == nthFromEnd
            }
            if !ok { return false }
        }
        // Annuel avec mois seul : le jour du mois vient de la date de début
        if r.frequency == .yearly, (r.daysOfTheMonth?.isEmpty ?? true), (r.daysOfTheWeek?.isEmpty ?? true), dom != startDay { return false }
        return true
    }

    private static func conforms(_ d: Date, _ r: EKRecurrenceRule, startDay: Int) -> Bool {
        guard base(d, r, startDay: startDay) else { return false }
        guard let pos = r.setPositions, !pos.isEmpty else { return true }
        // BYSETPOS : rang de d parmi les dates conformes de sa période (semaine ou mois)
        let c = Dates.cal
        let unit: Calendar.Component = r.frequency == .weekly ? .weekOfYear : .month
        guard let period = c.dateInterval(of: unit, for: d) else { return true }
        var all: [Date] = []
        var x = period.start
        while x < period.end {
            if base(x, r, startDay: startDay) { all.append(x) }
            x = c.date(byAdding: .day, value: 1, to: x)!
        }
        guard let i = all.firstIndex(where: { c.isDate($0, inSameDayAs: d) }) else { return false }
        return pos.contains { p in p.intValue > 0 ? p.intValue - 1 == i : all.count + p.intValue == i }
    }
}

// MARK: - Couleurs

enum Colors {
    static func hex(_ c: CGColor?) -> String? {
        guard let c, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let conv = c.converted(to: srgb, intent: .defaultIntent, options: nil),
              let comps = conv.components, comps.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", Int((comps[0] * 255).rounded()), Int((comps[1] * 255).rounded()), Int((comps[2] * 255).rounded()))
    }

    static func parse(_ s: String) throws -> CGColor {
        let named: [String: String] = ["red": "#FF3B30", "orange": "#FF9500", "yellow": "#FFCC00", "green": "#34C759",
                                       "blue": "#007AFF", "purple": "#AF52DE", "brown": "#A2845E", "gray": "#8E8E93", "grey": "#8E8E93", "pink": "#FF2D55"]
        var h = (named[s.lowercased()] ?? s).trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { throw MCPError("invalid color: \(s) (#RRGGBB or red, orange, yellow, green, blue, purple, brown, gray, pink)") }
        return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
