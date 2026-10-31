// Sonde 05 : alertes par défaut du compte (ajoutées par EventKit à l'enregistrement ?) et moyen de les éviter
import Foundation
import EventKit
let store = EKEventStore()
guard try await store.requestFullAccessToEvents() else { exit(2) }
let ts = Int(Date().timeIntervalSince1970)
let c = EKCalendar(for: .event, eventStore: store); c.title = "MCP-TEST-\(ts)"; c.source = store.defaultCalendarForNewEvents!.source
try store.saveCalendar(c, commit: true); let cid = c.calendarIdentifier
let cal = Calendar.current
let j = cal.startOfDay(for: Date().addingTimeInterval(86400 * 3))
func mk(_ t: String, allDay: Bool, alarms: [EKAlarm], noDefault: Bool = false) throws -> String {
  let e = EKEvent(eventStore: store); e.calendar = store.calendar(withIdentifier: cid); e.title = "[mcp-test] \(t)"
  e.isAllDay = allDay; e.startDate = allDay ? j : j.addingTimeInterval(10 * 3600); e.endDate = allDay ? j : j.addingTimeInterval(11 * 3600)
  for a in alarms { e.addAlarm(a) }
  if noDefault { e.setValue(true, forKey: "defaultAlarmWasDeleted") }
  try store.save(e, span: .thisEvent, commit: true); return e.eventIdentifier
}
do {
  let ids = [
    ("journée sans alerte", try mk("journée sans alerte", allDay: true, alarms: [])),
    ("journée avec -15 h", try mk("journée avec -15 h", allDay: true, alarms: [EKAlarm(relativeOffset: -15 * 3600)])),
    ("journée -15 h + défaut supprimé", try mk("journée -15 h + défaut supprimé", allDay: true, alarms: [EKAlarm(relativeOffset: -15 * 3600)], noDefault: true)),
    ("journée sans alerte + défaut supprimé", try mk("journée sans + défaut supprimé", allDay: true, alarms: [], noDefault: true)),
    ("horaire sans alerte", try mk("horaire sans alerte", allDay: false, alarms: [])),
    ("horaire -10 min", try mk("horaire -10 min", allDay: false, alarms: [EKAlarm(relativeOffset: -600)])),
  ]
  let s2 = EKEventStore(); _ = try await s2.requestFullAccessToEvents()
  for (t, id) in ids {
    let e = s2.event(withIdentifier: id)!
    print("  \(t): alarmes=\(e.alarms?.map { "\(Int($0.relativeOffset / 60)) min" } ?? []) | defaultAlarm=\(e.value(forKey: "defaultAlarm") != nil)")
  }
  // retirer toutes les alertes d'un événement qui en a
  let e = store.event(withIdentifier: ids[1].1)!; e.alarms = nil; e.setValue(true, forKey: "defaultAlarmWasDeleted")
  try store.save(e, span: .thisEvent, commit: true); store.reset()
  print("  après alarms=nil + défaut supprimé:", store.event(withIdentifier: ids[1].1)!.alarms?.count ?? 0)
} catch { print("ERREUR:", error) }
if let c = store.calendar(withIdentifier: cid) { try? store.removeCalendar(c, commit: true) }
store.reset(); print("NETTOYAGE: restants MCP-TEST =", store.calendars(for: .event).filter { $0.title.hasPrefix("MCP-TEST-") }.count)
