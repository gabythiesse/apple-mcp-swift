// Sonde 02 : calendrier de test, événements complets (lieu structuré, alarmes, URL, disponibilité, fuseau, journée entière),
// récurrences complexes, relecture par un store neuf, déplacement, modification de calendrier, nettoyage par identifiant.
import Foundation
import EventKit
import CoreLocation

let store = EKEventStore()
guard try await store.requestFullAccessToEvents() else { exit(2) }
let ts = Int(Date().timeIntervalSince1970)
let src = store.defaultCalendarForNewEvents!.source!
var calIDs: [String] = []
func newCal(_ suffix: String) throws -> EKCalendar {
  let c = EKCalendar(for: .event, eventStore: store)
  c.title = "MCP-TEST-\(ts)\(suffix)"; c.source = src
  c.cgColor = CGColor(srgbRed: 0.2, green: 0.78, blue: 0.35, alpha: 1)
  try store.saveCalendar(c, commit: true); calIDs.append(c.calendarIdentifier); return c
}
func cleanup() {
  for id in calIDs { if let c = store.calendar(withIdentifier: id), c.title.hasPrefix("MCP-TEST-") { try? store.removeCalendar(c, commit: true) } }
  store.reset()
  print("NETTOYAGE: calendriers MCP-TEST restants =", store.calendars(for: .event).filter { $0.title.hasPrefix("MCP-TEST-") }.count)
}
let cal = Calendar.current
func at(_ dayOffset: Int, _ h: Int, _ m: Int = 0) -> Date {
  cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: dayOffset, to: Date())!)!
}
func ok(_ c: Bool, _ l: String) { print(c ? "  OK " : "  KO ", l) }

do {
  let A = try newCal("-A"); let B = try newCal("-B")
  ok(true, "2 calendriers créés dans la source \(src.title) (type \(src.sourceType.rawValue))")

  // 1. Événement complet
  let e = EKEvent(eventStore: store)
  e.calendar = A; e.title = "[mcp-test] complet"; e.notes = "note de test"; e.url = URL(string: "https://example.com")
  e.startDate = at(2, 10); e.endDate = at(2, 11, 30)
  e.location = "Tour Eiffel, Paris"
  let loc = EKStructuredLocation(title: "Tour Eiffel"); loc.geoLocation = CLLocation(latitude: 48.8584, longitude: 2.2945); loc.radius = 150
  e.structuredLocation = loc
  e.availability = .free
  e.timeZone = TimeZone(identifier: "America/New_York")
  e.addAlarm(EKAlarm(relativeOffset: -15 * 60))
  e.addAlarm(EKAlarm(absoluteDate: at(1, 18)))
  let pa = EKAlarm(); let ploc = EKStructuredLocation(title: "Maison test"); ploc.geoLocation = CLLocation(latitude: 48.85, longitude: 2.35); ploc.radius = 100
  pa.structuredLocation = ploc; pa.proximity = .leave
  e.addAlarm(pa)
  try store.save(e, span: .thisEvent, commit: true)
  let E1 = e.eventIdentifier!
  print("  créé complet:", E1, "| calendarItemIdentifier:", e.calendarItemIdentifier)

  // 2. Journée entière sur 3 jours
  let jd = EKEvent(eventStore: store); jd.calendar = A; jd.title = "[mcp-test] journée"; jd.isAllDay = true
  jd.startDate = cal.startOfDay(for: at(3, 0)); jd.endDate = cal.startOfDay(for: at(5, 0))
  jd.addAlarm(EKAlarm(relativeOffset: -(15 * 3600)))  // la veille à 9h
  try store.save(jd, span: .thisEvent, commit: true)

  // 3. Récurrences complexes
  func rec(_ title: String, _ start: Date, _ rule: EKRecurrenceRule) throws -> String {
    let r = EKEvent(eventStore: store); r.calendar = A; r.title = title; r.startDate = start; r.endDate = start.addingTimeInterval(3600)
    r.addRecurrenceRule(rule); try store.save(r, span: .futureEvents, commit: true); return r.eventIdentifier
  }
  func rule(_ f: EKRecurrenceFrequency, interval: Int = 1, days: [EKRecurrenceDayOfWeek]? = nil, monthDays: [NSNumber]? = nil, months: [NSNumber]? = nil, pos: [NSNumber]? = nil, end: EKRecurrenceEnd?) -> EKRecurrenceRule {
    EKRecurrenceRule(recurrenceWith: f, interval: interval, daysOfTheWeek: days, daysOfTheMonth: monthDays, monthsOfTheYear: months, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: pos, end: end)
  }
  let base = at(1, 8)
  let R2mardi = try rec("[mcp-test] 2e mardi du mois", base, rule(.monthly, days: [EKRecurrenceDayOfWeek(.tuesday, weekNumber: 2)], end: EKRecurrenceEnd(occurrenceCount: 5)))
  let Rdernier = try rec("[mcp-test] dernier jour ouvré du mois", base, rule(.monthly, days: [.init(.monday), .init(.tuesday), .init(.wednesday), .init(.thursday), .init(.friday)], pos: [-1], end: EKRecurrenceEnd(occurrenceCount: 4)))
  let Rlmv = try rec("[mcp-test] lun-mer-ven", base, rule(.weekly, days: [.init(.monday), .init(.wednesday), .init(.friday)], end: EKRecurrenceEnd(end: at(30, 23))))
  let R2j = try rec("[mcp-test] tous les 2 jours", base, rule(.daily, interval: 2, end: EKRecurrenceEnd(occurrenceCount: 6)))
  let Ran = try rec("[mcp-test] annuel 15 mars", at(1, 8), rule(.yearly, monthDays: [15], months: [3], end: EKRecurrenceEnd(occurrenceCount: 3)))
  _ = (Rdernier, R2j, Ran)

  // Relecture par un store neuf (autre instance = vu par la base, pas par le cache)
  let s2 = EKEventStore(); _ = try await s2.requestFullAccessToEvents()
  let cA = s2.calendar(withIdentifier: A.calendarIdentifier)!
  func evs(_ st: EKEventStore, _ cals: [EKCalendar], _ days: Int = 1100) -> [EKEvent] {
    st.events(matching: st.predicateForEvents(withStart: at(-1, 0), end: at(days, 0), calendars: cals))
  }
  var all = evs(s2, [cA])
  var count: [String: Int] = [:]; for x in all { count[x.title, default: 0] += 1 }
  for (t, n) in count.sorted(by: { $0.key < $1.key }) { print("   occurrences \(t): \(n)") }
  for x in all where x.title.contains("2e mardi") || x.title.contains("dernier jour") {
    let f = DateFormatter(); f.dateFormat = "EEE yyyy-MM-dd"; f.locale = Locale(identifier: "fr_FR")
    print("     \(x.title!): \(f.string(from: x.startDate))")
  }
  if let r = all.first(where: { $0.title == "[mcp-test] 2e mardi du mois" })?.recurrenceRules?.first { print("   règle relue:", r.description.components(separatedBy: "RRULE ").last ?? "") }
  if let r = all.first(where: { $0.title.contains("dernier jour") })?.recurrenceRules?.first { print("   règle relue:", r.description.components(separatedBy: "RRULE ").last ?? "") }

  let c1 = all.first { $0.eventIdentifier == E1 }!
  ok(c1.notes == "note de test" && c1.url?.absoluteString == "https://example.com", "notes + URL relues")
  ok(c1.location == "Tour Eiffel, Paris", "location relu: \(c1.location ?? "nil")")
  ok(c1.structuredLocation?.geoLocation != nil, "lieu structuré relu: \(c1.structuredLocation?.title ?? "nil") geo=\(c1.structuredLocation?.geoLocation?.coordinate.latitude ?? 0) rayon=\(c1.structuredLocation?.radius ?? -1)")
  ok(c1.availability == .free, "disponibilité relue: \(c1.availability.rawValue)")
  ok(c1.timeZone?.identifier == "America/New_York", "fuseau relu: \(c1.timeZone?.identifier ?? "flottant")")
  let al = c1.alarms ?? []
  print("   alarmes relues (\(al.count)):", al.map { $0.structuredLocation != nil ? "lieu(\($0.structuredLocation!.title ?? ""), prox=\($0.proximity.rawValue))" : $0.absoluteDate != nil ? "date" : "rel \(Int($0.relativeOffset/60)) min" })
  ok(c1.attendees == nil && !c1.hasAttendees, "pas d'invités sur l'événement de test")
  print("   organizer:", c1.organizer == nil ? "nil" : "présent", "| status:", c1.status.rawValue, "| allowsContentModifications:", cA.allowsContentModifications)
  let j = all.first { $0.title == "[mcp-test] journée" }!
  ok(j.isAllDay, "journée entière relue, alarmes: \(j.alarms?.map { Int($0.relativeOffset/3600) } ?? []) h")
  print("   journée start/end:", j.startDate!, j.endDate!)

  // 4. Modifier UNE occurrence (la 3e du lun-mer-ven)
  var lmv = evs(store, [A]).filter { $0.title == "[mcp-test] lun-mer-ven" }.sorted { $0.startDate < $1.startDate }
  let total = lmv.count
  let o3 = lmv[2]; let o3date = o3.occurrenceDate!
  o3.title = "[mcp-test] lun-mer-ven (déplacée)"; o3.startDate = o3.startDate.addingTimeInterval(2 * 3600); o3.endDate = o3.endDate.addingTimeInterval(2 * 3600)
  try store.save(o3, span: .thisEvent, commit: true)
  store.reset()
  all = evs(store, [A])
  let det = all.filter { $0.title == "[mcp-test] lun-mer-ven (déplacée)" }
  let rest = all.filter { $0.title == "[mcp-test] lun-mer-ven" }
  ok(det.count == 1 && det[0].isDetached && rest.count == total - 1, "1 occurrence modifiée seule (isDetached=\(det.first?.isDetached ?? false), occurrenceDate garde l'original=\(det.first?.occurrenceDate == o3date)), \(rest.count)/\(total - 1) inchangées")
  ok(det.first?.eventIdentifier == Rlmv, "l'occurrence détachée garde l'eventIdentifier de la série: \(det.first?.eventIdentifier == Rlmv)")

  // 5. Modifier cette occurrence et les suivantes (à partir de la 6e)
  lmv = rest.sorted { $0.startDate < $1.startDate }
  let o6 = lmv[4]
  o6.title = "[mcp-test] lun-mer-ven (suite)"
  try store.save(o6, span: .futureEvents, commit: true)
  store.reset(); all = evs(store, [A])
  let avant = all.filter { $0.title == "[mcp-test] lun-mer-ven" }.count
  let suite = all.filter { $0.title == "[mcp-test] lun-mer-ven (suite)" }
  ok(avant + suite.count + 1 == total, "« cette occurrence et les suivantes » : \(avant) avant + \(suite.count) suite + 1 détachée = \(total)")
  print("   la suite a un nouvel id de série:", suite.first?.eventIdentifier != Rlmv, "| détachée toujours là:", all.contains { $0.title.hasSuffix("(déplacée)") })

  // 6. Supprimer UNE occurrence (2e du « tous les 2 jours »)
  let d2 = evs(store, [A]).filter { $0.title == "[mcp-test] tous les 2 jours" }.sorted { $0.startDate < $1.startDate }
  try store.remove(d2[1], span: .thisEvent, commit: true)
  store.reset()
  let d2b = evs(store, [A]).filter { $0.title == "[mcp-test] tous les 2 jours" }
  ok(d2b.count == d2.count - 1, "suppression d'une seule occurrence: \(d2.count) → \(d2b.count) ; exceptions dans la règle: \(d2b.first?.recurrenceRules?.count ?? 0) règle(s)")

  // 7. Accès par identifiant : eventIdentifier renvoie quoi pour une série ?
  let byId = store.event(withIdentifier: R2mardi)
  print("   event(withIdentifier: série) → 1re occurrence:", byId?.startDate.description ?? "nil", "| calendarItems(withExternalIdentifier):", store.calendarItems(withExternalIdentifier: byId?.calendarItemExternalIdentifier ?? "").count)

  // 8. Déplacer vers B, renommer/recolorer A
  let mv = store.event(withIdentifier: E1)!
  mv.calendar = B; try store.save(mv, span: .thisEvent, commit: true)
  A.title = "MCP-TEST-\(ts)-A2"; A.cgColor = CGColor(srgbRed: 1, green: 0.58, blue: 0, alpha: 1); try store.saveCalendar(A, commit: true)
  store.reset()
  let mvd = store.event(withIdentifier: E1)
  ok(mvd?.calendar.calendarIdentifier == B.calendarIdentifier, "déplacé vers B, même identifiant: \(mvd != nil)")
  ok(store.calendar(withIdentifier: A.calendarIdentifier)?.title == "MCP-TEST-\(ts)-A2", "calendrier renommé + recoloré")

  // 9. Supprimer toute une série (depuis la 1re occurrence, futureEvents)
  let an = evs(store, [store.calendar(withIdentifier: A.calendarIdentifier)!]).filter { $0.title == "[mcp-test] annuel 15 mars" }.sorted { $0.startDate < $1.startDate }
  print("   annuel 15 mars occurrences:", an.count, an.map { "\(cal.component(.month, from: $0.startDate))/\(cal.component(.day, from: $0.startDate))" })
  if let first = an.first { try store.remove(first, span: .futureEvents, commit: true) }
  store.reset()
  ok(evs(store, [store.calendar(withIdentifier: A.calendarIdentifier)!]).filter { $0.title == "[mcp-test] annuel 15 mars" }.isEmpty, "série entière supprimée")

  // 10. Supprimer un événement simple par identifiant
  try store.remove(store.event(withIdentifier: E1)!, span: .thisEvent, commit: true)
  store.reset(); ok(store.event(withIdentifier: E1) == nil, "événement simple supprimé par identifiant")
} catch { print("ERREUR:", error) }
cleanup()
