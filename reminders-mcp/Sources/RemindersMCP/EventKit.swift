// Voie publique : EventKit (listes, rappels, dates, priorité, notes, alarmes, récurrence, terminé)
import Foundation
import EventKit
import CoreLocation

enum EK {
    static let store = EKEventStore()
    private static var granted = false

    /// Vérifie l'accès complet à Rappels, et le demande au premier appel
    static func ready() throws {
        if !granted {
            if EKEventStore.authorizationStatus(for: .reminder) != .fullAccess {
                let sem = DispatchSemaphore(value: 0)
                var ok = false
                store.requestFullAccessToReminders { g, _ in ok = g; sem.signal() }
                sem.wait()
                guard ok else {
                    throw MCPError("access to Reminders denied. System Settings > Privacy & Security > Reminders: allow the Claude app, then restart.")
                }
            }
            granted = true
        }
        // Chaque appel d'outil repart d'un état frais (ReminderKit a pu écrire entre-temps)
        store.reset()
    }

    static func fetch(_ predicate: NSPredicate) -> [EKReminder] {
        let sem = DispatchSemaphore(value: 0)
        var out: [EKReminder] = []
        store.fetchReminders(matching: predicate) { out = $0 ?? []; sem.signal() }
        sem.wait()
        return out
    }

    static func calendar(_ id: String) throws -> EKCalendar {
        guard let c = store.calendar(withIdentifier: id), c.allowedEntityTypes.contains(.reminder) else {
            throw MCPError("list not found: \(id)")
        }
        return c
    }

    static func reminder(_ id: String) throws -> EKReminder {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw MCPError("reminder not found: \(id)")
        }
        return r
    }

    static func defaultList() throws -> EKCalendar {
        guard let c = store.defaultCalendarForNewReminders() else { throw MCPError("no default list") }
        return c
    }
}

// MARK: - Dates (heure locale ; AAAA-MM-JJ = journée entière)

enum Dates {
    static var cal: Calendar { Calendar.current }
    private static let pattern = try! NSRegularExpression(pattern: #"^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::\d{2})?)?$"#)

    static func components(_ s: String) throws -> DateComponents {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let m = pattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) {
            func g(_ i: Int) -> Int? { Range(m.range(at: i), in: t).flatMap { Int(t[$0]) } }
            var dc = DateComponents(year: g(1), month: g(2), day: g(3))
            if let h = g(4), let mi = g(5) { dc.hour = h; dc.minute = mi; dc.timeZone = .current }
            guard cal.date(from: dc) != nil else { throw MCPError("invalid date: \(s)") }
            return dc
        }
        // ISO 8601 complet avec fuseau, converti en heure locale
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: t) ?? f2.date(from: t) {
            var dc = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            dc.timeZone = .current
            return dc
        }
        throw MCPError("invalid date \"\(s)\": expected YYYY-MM-DD (all day) or YYYY-MM-DDTHH:MM (local time)")
    }

    static func absolute(_ s: String) throws -> Date {
        guard let d = cal.date(from: try components(s)) else { throw MCPError("invalid date: \(s)") }
        return d
    }

    static func date(_ dc: DateComponents) -> Date? {
        var c = dc
        c.calendar = cal
        return c.date
    }

    static func text(_ dc: DateComponents) -> String {
        if dc.hour != nil, let d = date(dc) { return text(d) }
        return String(format: "%04d-%02d-%02d", dc.year ?? 0, dc.month ?? 0, dc.day ?? 0)
    }

    static func text(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return String(format: "%04d-%02d-%02dT%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!)
    }
}

// MARK: - Priorité (valeurs de l'app : 1 haute, 5 moyenne, 9 basse, 0 aucune)

enum Prio {
    static func parse(_ v: Any?) throws -> Int {
        switch v {
        case let n as NSNumber: return max(0, min(9, n.intValue))
        case let s as String:
            switch s.lowercased() {
            case "high", "!!!": return 1
            case "medium", "!!": return 5
            case "low", "!": return 9
            case "none", "": return 0
            default: throw MCPError("unknown priority: \(s) (high, medium, low, none)")
            }
        default: return 0
        }
    }

    static func label(_ p: Int) -> String? {
        switch p {
        case 0: return nil
        case 1...4: return "high"
        case 5: return "medium"
        default: return "low"
        }
    }
}

// MARK: - Alarmes et récurrence

enum Alarms {
    static func parse(_ a: JSON) throws -> EKAlarm {
        if let d = a.nonEmpty("date") { return EKAlarm(absoluteDate: try Dates.absolute(d)) }
        if let m = a.double("minutes_before") { return EKAlarm(relativeOffset: -m * 60) }
        if let lieu = a.nonEmpty("location") {
            guard let lat = a.double("latitude"), let lon = a.double("longitude") else {
                throw MCPError("location alarm: latitude and longitude are required")
            }
            let loc = EKStructuredLocation(title: lieu)
            loc.geoLocation = CLLocation(latitude: lat, longitude: lon)
            loc.radius = a.double("radius") ?? 100
            let al = EKAlarm()
            al.structuredLocation = loc
            al.proximity = a.string("when") == "departure" ? .leave : .enter
            return al
        }
        throw MCPError("alarm: provide date, minutes_before, or location + latitude + longitude")
    }

    static func json(_ al: EKAlarm) -> JSON {
        if let loc = al.structuredLocation {
            var d: JSON = ["location": loc.title ?? "", "when": al.proximity == .leave ? "departure" : "arrival", "radius": loc.radius]
            if let g = loc.geoLocation { d["latitude"] = g.coordinate.latitude; d["longitude"] = g.coordinate.longitude }
            return d
        }
        if let d = al.absoluteDate { return ["date": Dates.text(d)] }
        return ["minutes_before": Int(-al.relativeOffset / 60)]
    }
}

enum Recurrence {
    private static let days: [(String, EKWeekday)] = [
        ("monday", .monday), ("tuesday", .tuesday), ("wednesday", .wednesday), ("thursday", .thursday),
        ("friday", .friday), ("saturday", .saturday), ("sunday", .sunday),
    ]
    private static let freqs: [(String, EKRecurrenceFrequency)] = [("daily", .daily), ("weekly", .weekly), ("monthly", .monthly), ("yearly", .yearly)]

    static func parse(_ a: JSON) throws -> EKRecurrenceRule {
        let f = a.string("frequency")?.lowercased() ?? ""
        guard let freq = freqs.first(where: { $0.0 == f })?.1 else {
            throw MCPError("recurrence: frequency = daily, weekly, monthly or yearly")
        }
        let weekdays = try a.strings("days")?.map { name -> EKRecurrenceDayOfWeek in
            guard let w = days.first(where: { $0.0 == name.lowercased() })?.1 else { throw MCPError("unknown day: \(name)") }
            return EKRecurrenceDayOfWeek(w)
        }
        var end: EKRecurrenceEnd?
        if let fin = a.nonEmpty("until") { end = EKRecurrenceEnd(end: try Dates.absolute(fin)) }
        else if let n = a.int("occurrences") { end = EKRecurrenceEnd(occurrenceCount: n) }
        return EKRecurrenceRule(recurrenceWith: freq, interval: max(1, a.int("interval") ?? 1),
                                daysOfTheWeek: weekdays?.isEmpty == true ? nil : weekdays, daysOfTheMonth: nil,
                                monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    }

    static func json(_ r: EKRecurrenceRule) -> JSON {
        var d: JSON = ["frequency": freqs.first(where: { $0.1 == r.frequency })?.0 ?? "?", "interval": r.interval]
        if let w = r.daysOfTheWeek, !w.isEmpty {
            d["days"] = w.compactMap { day in days.first(where: { $0.1 == day.dayOfTheWeek })?.0 }
        }
        if let e = r.recurrenceEnd {
            if let date = e.endDate { d["until"] = Dates.text(date) } else if e.occurrenceCount > 0 { d["occurrences"] = e.occurrenceCount }
        }
        return d
    }
}

// MARK: - Couleur des listes

enum Colors {
    static func hex(_ c: CGColor?) -> String? {
        guard let c, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let conv = c.converted(to: srgb, intent: .defaultIntent, options: nil),
              let comps = conv.components, comps.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", Int(comps[0] * 255), Int(comps[1] * 255), Int(comps[2] * 255))
    }

    static func parse(_ s: String) throws -> CGColor {
        let named: [String: String] = ["red": "#FF3B30", "orange": "#FF9500", "yellow": "#FFCC00", "green": "#34C759", "blue": "#007AFF",
                                       "purple": "#AF52DE", "brown": "#A2845E", "gray": "#8E8E93", "grey": "#8E8E93", "pink": "#FF2D55"]
        var h = (named[s.lowercased()] ?? s).trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { throw MCPError("invalid color: \(s) (#RRGGBB or red, orange, yellow, green, blue, purple, brown, gray, pink)") }
        return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
