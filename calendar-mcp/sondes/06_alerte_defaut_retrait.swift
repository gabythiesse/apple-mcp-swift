// Sonde 06 : l'alerte par défaut iCloud des journées entières est-elle visible dans l'objet juste après save ?
// Une 2e écriture avec la liste voulue + defaultAlarmWasDeleted donne-t-elle exactement cette liste ?
import Foundation
import EventKit
let store = EKEventStore()
guard try await store.requestFullAccessToEvents() else { exit(2) }
let ts = Int(Date().timeIntervalSince1970)
let c = EKCalendar(for: .event, eventStore: store); c.title = "MCP-TEST-\(ts)"; c.source = store.defaultCalendarForNewEvents!.source
try store.saveCalendar(c, commit: true); let cid = c.calendarIdentifier
let j = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400 * 3))
do {
  for (nom, voulues) in [("une alerte -2 h", [-120.0]), ("aucune", [])] {
    let e = EKEvent(eventStore: store); e.calendar = store.calendar(withIdentifier: cid); e.title = "[mcp-test] \(nom)"
    e.isAllDay = true; e.startDate = j; e.endDate = j
    for m in voulues { e.addAlarm(EKAlarm(relativeOffset: m * 60)) }
    try store.save(e, span: .thisEvent, commit: true)
    print("  \(nom): en mémoire après save =", e.alarms?.map { Int($0.relativeOffset / 60) } ?? [])
    let t0 = Date()
    e.alarms = voulues.map { EKAlarm(relativeOffset: $0 * 60) }; e.setValue(true, forKey: "defaultAlarmWasDeleted")
    try store.save(e, span: .thisEvent, commit: true)
    let s2 = EKEventStore()
    print("  \(nom): après 2e écriture (\(Int(Date().timeIntervalSince(t0) * 1000)) ms), store neuf =", s2.event(withIdentifier: e.eventIdentifier)!.alarms?.map { Int($0.relativeOffset / 60) } ?? [])
  }
} catch { print("ERREUR:", error) }
if let c = store.calendar(withIdentifier: cid) { try? store.removeCalendar(c, commit: true) }
store.reset(); print("NETTOYAGE: restants MCP-TEST =", store.calendars(for: .event).filter { $0.title.hasPrefix("MCP-TEST-") }.count)
