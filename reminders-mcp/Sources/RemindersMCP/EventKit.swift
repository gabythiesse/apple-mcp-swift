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
                    throw MCPError("accès à Rappels refusé. Réglages Système > Confidentialité et sécurité > Rappels : autoriser l'app Claude, puis relancer.")
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
            throw MCPError("liste introuvable : \(id)")
        }
        return c
    }

    static func reminder(_ id: String) throws -> EKReminder {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw MCPError("rappel introuvable : \(id)")
        }
        return r
    }

    static func defaultList() throws -> EKCalendar {
        guard let c = store.defaultCalendarForNewReminders() else { throw MCPError("aucune liste par défaut") }
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
            guard cal.date(from: dc) != nil else { throw MCPError("date invalide : \(s)") }
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
        throw MCPError("date invalide « \(s) » : attendu AAAA-MM-JJ (journée) ou AAAA-MM-JJTHH:MM (heure locale)")
    }

    static func absolute(_ s: String) throws -> Date {
        guard let d = cal.date(from: try components(s)) else { throw MCPError("date invalide : \(s)") }
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
            case "haute", "!!!", "high": return 1
            case "moyenne", "!!", "medium": return 5
            case "basse", "!", "low": return 9
            case "aucune", "", "none": return 0
            default: throw MCPError("priorité inconnue : \(s) (haute, moyenne, basse, aucune)")
            }
        default: return 0
        }
    }

    static func label(_ p: Int) -> String? {
        switch p {
        case 0: return nil
        case 1...4: return "haute"
        case 5: return "moyenne"
        default: return "basse"
        }
    }
}

// MARK: - Alarmes et récurrence

enum Alarms {
    static func parse(_ a: JSON) throws -> EKAlarm {
        if let d = a.nonEmpty("date") { return EKAlarm(absoluteDate: try Dates.absolute(d)) }
        if let m = a.double("minutes_avant") { return EKAlarm(relativeOffset: -m * 60) }
        if let lieu = a.nonEmpty("lieu") {
            guard let lat = a.double("latitude"), let lon = a.double("longitude") else {
                throw MCPError("alarme de lieu : latitude et longitude requises")
            }
            let loc = EKStructuredLocation(title: lieu)
            loc.geoLocation = CLLocation(latitude: lat, longitude: lon)
            loc.radius = a.double("rayon") ?? 100
            let al = EKAlarm()
            al.structuredLocation = loc
            al.proximity = a.string("quand") == "depart" ? .leave : .enter
            return al
        }
        throw MCPError("alarme : fournir date, minutes_avant, ou lieu + latitude + longitude")
    }

    static func json(_ al: EKAlarm) -> JSON {
        if let loc = al.structuredLocation {
            var d: JSON = ["lieu": loc.title ?? "", "quand": al.proximity == .leave ? "depart" : "arrivee", "rayon": loc.radius]
            if let g = loc.geoLocation { d["latitude"] = g.coordinate.latitude; d["longitude"] = g.coordinate.longitude }
            return d
        }
        if let d = al.absoluteDate { return ["date": Dates.text(d)] }
        return ["minutes_avant": Int(-al.relativeOffset / 60)]
    }
}

enum Recurrence {
    private static let days: [(String, EKWeekday)] = [
        ("lundi", .monday), ("mardi", .tuesday), ("mercredi", .wednesday), ("jeudi", .thursday),
        ("vendredi", .friday), ("samedi", .saturday), ("dimanche", .sunday),
    ]
    private static let freqs: [(String, EKRecurrenceFrequency)] = [("jour", .daily), ("semaine", .weekly), ("mois", .monthly), ("annee", .yearly)]

    static func parse(_ a: JSON) throws -> EKRecurrenceRule {
        let f = a.string("frequence")?.lowercased() ?? ""
        guard let freq = freqs.first(where: { $0.0 == f })?.1 else {
            throw MCPError("récurrence : frequence = jour, semaine, mois ou annee")
        }
        let weekdays = try a.strings("jours")?.map { name -> EKRecurrenceDayOfWeek in
            guard let w = days.first(where: { $0.0 == name.lowercased() })?.1 else { throw MCPError("jour inconnu : \(name)") }
            return EKRecurrenceDayOfWeek(w)
        }
        var end: EKRecurrenceEnd?
        if let fin = a.nonEmpty("fin_le") { end = EKRecurrenceEnd(end: try Dates.absolute(fin)) }
        else if let n = a.int("occurrences") { end = EKRecurrenceEnd(occurrenceCount: n) }
        return EKRecurrenceRule(recurrenceWith: freq, interval: max(1, a.int("intervalle") ?? 1),
                                daysOfTheWeek: weekdays?.isEmpty == true ? nil : weekdays, daysOfTheMonth: nil,
                                monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    }

    static func json(_ r: EKRecurrenceRule) -> JSON {
        var d: JSON = ["frequence": freqs.first(where: { $0.1 == r.frequency })?.0 ?? "?", "intervalle": r.interval]
        if let w = r.daysOfTheWeek, !w.isEmpty {
            d["jours"] = w.compactMap { day in days.first(where: { $0.1 == day.dayOfTheWeek })?.0 }
        }
        if let e = r.recurrenceEnd {
            if let date = e.endDate { d["fin_le"] = Dates.text(date) } else if e.occurrenceCount > 0 { d["occurrences"] = e.occurrenceCount }
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
        let named: [String: String] = ["rouge": "#FF3B30", "orange": "#FF9500", "jaune": "#FFCC00", "vert": "#34C759",
                                       "bleu": "#007AFF", "violet": "#AF52DE", "marron": "#A2845E", "gris": "#8E8E93", "rose": "#FF2D55"]
        var h = (named[s.lowercased()] ?? s).trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { throw MCPError("couleur invalide : \(s) (#RRGGBB ou rouge, orange, jaune, vert, bleu, violet, marron, gris, rose)") }
        return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
