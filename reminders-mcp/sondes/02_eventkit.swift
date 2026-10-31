// Sonde 02 : EventKit — accès, liste de test, rappel complet (notes, url, priorité, dates, alarmes, récurrence), relecture, suppression
import Foundation
import EventKit
import CoreLocation

let store = EKEventStore()
print("statut avant:", EKEventStore.authorizationStatus(for: .reminder).rawValue)
let ok = try await store.requestFullAccessToReminders()
print("accès complet:", ok)
guard ok else { exit(2) }

print("sources:", store.sources.map { "\($0.title)[\($0.sourceType.rawValue)]" })
let def = store.defaultCalendarForNewReminders()
print("liste par défaut source:", def?.source.title ?? "nil", def?.source.sourceType.rawValue ?? -1)

let ts = Int(Date().timeIntervalSince1970)
let cal = EKCalendar(for: .reminder, eventStore: store)
cal.title = "MCP-TEST-\(ts)"
cal.source = def!.source
try store.saveCalendar(cal, commit: true)
print("liste créée:", cal.calendarIdentifier)

let r = EKReminder(eventStore: store)
r.calendar = cal
r.title = "[mcp-test] complet"
r.notes = "note de test"
r.url = URL(string: "https://example.com")
r.priority = 1
let due = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: Date().addingTimeInterval(86400))
r.dueDateComponents = due
r.startDateComponents = due
r.addAlarm(EKAlarm(absoluteDate: Date().addingTimeInterval(3600)))
let loc = EKStructuredLocation(title: "Tour Eiffel")
loc.geoLocation = CLLocation(latitude: 48.8584, longitude: 2.2945)
loc.radius = 100
let la = EKAlarm(); la.structuredLocation = loc; la.proximity = .enter
r.addAlarm(la)
r.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.thursday)], daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: EKRecurrenceEnd(occurrenceCount: 5)))
try store.save(r, commit: true)
let rid = r.calendarItemIdentifier
print("rappel créé:", rid, "externalID:", r.calendarItemExternalIdentifier ?? "nil")

func fetch(_ p: NSPredicate) async -> [EKReminder] {
  await withCheckedContinuation { c in store.fetchReminders(matching: p) { c.resume(returning: $0 ?? []) } }
}
store.reset()
let got = await fetch(store.predicateForReminders(in: [store.calendar(withIdentifier: cal.calendarIdentifier)!]))
for x in got {
  print("relu:", x.title!, "| notes:", x.notes ?? "", "| url:", x.url?.absoluteString ?? "nil", "| prio:", x.priority,
        "| due:", x.dueDateComponents.map { "\($0.day!)/\($0.month!) \($0.hour ?? -1)h" } ?? "nil",
        "| alarmes:", x.alarms?.map { $0.structuredLocation?.title ?? "\($0.absoluteDate!)" } ?? [],
        "| récur:", x.recurrenceRules?.first?.description.prefix(120) ?? "nil")
}

// terminer puis prédicat terminés
let r2 = store.calendarItem(withIdentifier: rid) as! EKReminder
r2.isCompleted = true
try store.save(r2, commit: true)
let done = await fetch(store.predicateForCompletedReminders(withCompletionDateStarting: Date().addingTimeInterval(-60), ending: Date().addingTimeInterval(60), calendars: [cal]))
print("terminés relus:", done.map { $0.title! }, "completionDate:", done.first?.completionDate as Any)
// récurrent terminé → EventKit crée-t-il l'occurrence suivante ?
let after = await fetch(store.predicateForReminders(in: [cal]))
print("après completion:", after.map { "\($0.title!) done=\($0.isCompleted)" })

// nettoyage
try store.removeCalendar(cal, commit: true)
store.reset()
print("reste listes MCP-TEST:", store.calendars(for: .reminder).filter { $0.title.hasPrefix("MCP-TEST-") }.count)
