// Supprime une liste de test par identifiant (refuse tout nom sans préfixe MCP-TEST-)
import EventKit
let ek = EKEventStore()
_ = try await ek.requestFullAccessToReminders()
for id in CommandLine.arguments.dropFirst() {
  guard let c = ek.calendar(withIdentifier: id) else { print("absent:", id); continue }
  guard c.title.hasPrefix("MCP-TEST-") else { print("REFUS (pas une liste de test):", c.title); continue }
  try ek.removeCalendar(c, commit: true); print("supprimée:", c.title)
}
