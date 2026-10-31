// Supprime les calendriers de test : par identifiant si fourni, sinon ceux dont le titre suit exactement MCP-TEST-<horodatage>[-suffixe] (jamais d'autre)
import Foundation
import EventKit
let ek = EKEventStore()
_ = try await ek.requestFullAccessToEvents()
let ids = Array(CommandLine.arguments.dropFirst())
let motif = try NSRegularExpression(pattern: #"^MCP-TEST-\d{10}(-[A-Z0-9]{1,3})?$"#)
let cibles = ek.calendars(for: .event).filter { c in
  ids.isEmpty ? motif.firstMatch(in: c.title, range: NSRange(c.title.startIndex..., in: c.title)) != nil : ids.contains(c.calendarIdentifier)
}
for c in cibles {
  guard c.title.hasPrefix("MCP-TEST-") else { print("REFUS:", c.title); continue }
  let n = ek.events(matching: ek.predicateForEvents(withStart: Date().addingTimeInterval(-86400 * 30), end: Date().addingTimeInterval(86400 * 1000), calendars: [c])).filter { !$0.title.hasPrefix("[mcp-test]") }.count
  guard n == 0 else { print("REFUS (contient \(n) élément(s) non marqués):", c.title); continue }
  try ek.removeCalendar(c, commit: true); print("supprimé:", c.title)
}
ek.reset()
print("restants MCP-TEST:", ek.calendars(for: .event).filter { $0.title.hasPrefix("MCP-TEST-") }.map(\.title))
