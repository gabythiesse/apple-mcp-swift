// Sonde 01 : accès complet aux événements + description des comptes (types et capacités, aucun contenu)
import Foundation
import EventKit

let store = EKEventStore()
print("statut avant:", EKEventStore.authorizationStatus(for: .event).rawValue, "(3 = fullAccess)")
let ok = try await store.requestFullAccessToEvents()
print("accès complet:", ok)
guard ok else { exit(2) }
let types = ["local", "exchange", "calDAV", "mobileMe", "subscribed", "birthdays"]
for s in store.sources {
  let cals = s.calendars(for: .event)
  let modifiables = cals.filter { $0.allowsContentModifications }.count
  print("source type=\(types[s.sourceType.rawValue]) titre=\(s.sourceType == .local || s.sourceType == .calDAV || s.sourceType == .exchange ? s.title : "-") calendriers=\(cals.count) modifiables=\(modifiables)")
}
let def = store.defaultCalendarForNewEvents
print("calendrier par défaut: type de source =", def.map { types[$0.source.sourceType.rawValue] } ?? "nil",
      "| allowedEntityTypes events+reminders:", def?.allowedEntityTypes.rawValue ?? 0)
