// Sonde 04 : adressage d'une occurrence (id + date), occurrence détachée, déplacement / renommage / suppression avec objets frais,
// voie privée EventKit (temps de trajet, pièce jointe, lien visio détecté), calcul des créneaux libres, lieu texte + structuré.
import Foundation
import EventKit
import CoreLocation

let store = EKEventStore()
guard try await store.requestFullAccessToEvents() else { exit(2) }
let ts = Int(Date().timeIntervalSince1970)
let src = store.defaultCalendarForNewEvents!.source!
var calIDs: [String] = []
func newCal(_ suffix: String) throws -> String {
  let c = EKCalendar(for: .event, eventStore: store); c.title = "MCP-TEST-\(ts)\(suffix)"; c.source = src
  try store.saveCalendar(c, commit: true); calIDs.append(c.calendarIdentifier); return c.calendarIdentifier
}
func C(_ id: String) -> EKCalendar { store.calendar(withIdentifier: id)! }
let cal = Calendar.current
func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: d, to: Date())!)! }
func ok(_ c: Bool, _ l: String) { print(c ? "  OK " : "  KO ", l) }
func evs(_ ids: [String], _ a: Date = at(-1, 0), _ b: Date = at(60, 0)) -> [EKEvent] { store.events(matching: store.predicateForEvents(withStart: a, end: b, calendars: ids.map(C))) }
func mk(_ cid: String, _ t: String, _ s: Date, _ e: Date, _ f: (EKEvent) -> Void = { _ in }) throws -> String {
  let x = EKEvent(eventStore: store); x.calendar = C(cid); x.title = t; x.startDate = s; x.endDate = e; f(x)
  try store.save(x, span: .futureEvents, commit: true); return x.eventIdentifier
}

do {
  let A = try newCal("-A"), B = try newCal("-B")

  // Lieu texte + structuré : l'ordre compte-t-il ?
  let L = try mk(A, "[mcp-test] lieu", at(2, 8), at(2, 9)) { x in
    let s = EKStructuredLocation(title: "Tour Eiffel"); s.geoLocation = CLLocation(latitude: 48.8584, longitude: 2.2945)
    x.structuredLocation = s; x.location = "Tour Eiffel, Champ de Mars, Paris" }
  store.reset(); let l = store.event(withIdentifier: L)!
  ok(l.location == "Tour Eiffel, Champ de Mars, Paris" && l.structuredLocation?.geoLocation != nil, "lieu texte posé après le structuré : texte=\(l.location ?? "nil"), geo=\(l.structuredLocation?.geoLocation != nil)")

  // Occurrence : adressage par (id de série, date d'occurrence)
  let S = try mk(A, "[mcp-test] quotidien", at(1, 9), at(1, 10)) { $0.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 5))) }
  store.reset()
  let occ = evs([A]).filter { $0.eventIdentifier == S }.sorted { $0.startDate < $1.startDate }
  let d3 = occ[2].occurrenceDate!
  let t0 = Date()
  let found = store.events(matching: store.predicateForEvents(withStart: d3, end: d3.addingTimeInterval(1), calendars: [C(A)])).first { $0.eventIdentifier == S && $0.occurrenceDate == d3 }
  ok(found != nil, "occurrence retrouvée par (id, date) en \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
  found!.title = "[mcp-test] quotidien (modifiée)"; found!.startDate = at(20, 15); found!.endDate = at(20, 16)
  try store.save(found!, span: .thisEvent, commit: true)
  let detId = found!.eventIdentifier!
  store.reset()
  let det = store.event(withIdentifier: detId)
  ok(det?.isDetached == true && det?.startDate == at(20, 15), "occurrence détachée (déplacée de 17 jours) retrouvée par son propre id ; id différent de la série : \(detId != S)")
  let viaWindow = evs([A]).first { $0.title.hasSuffix("(modifiée)") }
  ok(viaWindow?.eventIdentifier == detId && viaWindow?.occurrenceDate == d3, "relue dans une fenêtre : même id détaché, occurrenceDate = date d'origine")
  // supprimer toute la série depuis une occurrence quelconque (span futureEvents sur la 1re)
  let first = evs([A]).filter { $0.eventIdentifier == S }.min { $0.startDate < $1.startDate }!
  try store.remove(first, span: .futureEvents, commit: true); store.reset()
  ok(evs([A]).filter { $0.title.hasPrefix("[mcp-test] quotidien") }.isEmpty, "série + occurrence détachée supprimées ensemble")

  // Voie privée : temps de trajet, lien visio détecté, pièce jointe
  let P = try mk(A, "[mcp-test] privé", at(3, 14), at(3, 15)) { x in
    x.notes = "Rejoindre : https://zoom.us/j/1234567890"
    x.setValue(1800.0, forKey: "travelTime")
  }
  store.reset(); var p = store.event(withIdentifier: P)!
  ok((p.value(forKey: "travelTime") as? Double) == 1800, "temps de trajet relu (store neuf) : \(p.value(forKey: "travelTime") ?? "nil") s, startDateIncludingTravel = \(p.value(forKey: "startDateIncludingTravel") ?? "nil")")
  print("   lien visio détecté :", p.value(forKey: "conferenceURLForDisplay") ?? "nil")
  // pièce jointe
  let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-test-\(ts).txt")
  try "pièce jointe de test".write(to: tmp, atomically: true, encoding: .utf8)
  let AttCls = NSClassFromString("EKAttachment") as! NSObject.Type
  let att = AttCls.perform(NSSelectorFromString("alloc")).takeUnretainedValue().perform(NSSelectorFromString("initWithFilepath:"), with: tmp as NSURL)?.takeUnretainedValue()
  print("   supportsAddingAttachments:", p.value(forKey: "supportsAddingAttachments") ?? "nil", "| EKAttachment créé:", att != nil)
  if let att { p.perform(NSSelectorFromString("addAttachment:"), with: att) }
  do { try store.save(p, span: .thisEvent, commit: true); print("   pièce jointe : enregistrement OK") } catch { print("   pièce jointe : échec save :", error) }
  store.reset(); p = store.event(withIdentifier: P)!
  let atts = (p.value(forKey: "attachments") as? [NSObject]) ?? Array((p.value(forKey: "attachments") as? Set<NSObject>) ?? [])
  ok(atts.count == 1, "pièce jointe relue : \(atts.map { "\($0.value(forKey: "fileName") ?? "?") \($0.value(forKey: "fileSize") ?? "?") o" })")
  try? FileManager.default.removeItem(at: tmp)

  // Créneaux libres (calcul local) sur le jour +5 entre 9h et 18h, 30 min mini
  _ = try mk(B, "[mcp-test] libre", at(5, 10), at(5, 11, 30)) { $0.availability = .free }
  _ = try mk(B, "[mcp-test] occupé", at(5, 14), at(5, 15))
  _ = try mk(B, "[mcp-test] chevauche", at(5, 14, 30), at(5, 16))
  _ = try mk(B, "[mcp-test] court", at(5, 16, 10), at(5, 16, 20))
  _ = try mk(B, "[mcp-test] jour entier", cal.startOfDay(for: at(5, 0)), cal.startOfDay(for: at(5, 0))) { $0.isAllDay = true }
  store.reset()
  let busy = evs([B], at(5, 9), at(5, 18)).filter { !$0.isAllDay && $0.availability != .free }.map { ($0.startDate!, $0.endDate!) }.sorted { $0.0 < $1.0 }
  var slots: [(Date, Date)] = []; var cur = at(5, 9)
  for (s, e) in busy { if s.timeIntervalSince(cur) >= 1800 { slots.append((cur, s)) }; cur = max(cur, e) }
  if at(5, 18).timeIntervalSince(cur) >= 1800 { slots.append((cur, at(5, 18))) }
  let f = DateFormatter(); f.dateFormat = "HH:mm"
  let txt = slots.map { "\(f.string(from: $0.0))-\(f.string(from: $0.1))" }
  ok(txt == ["09:00-14:00", "16:20-18:00"], "créneaux libres : \(txt) (16:00-16:10 trop court écarté)")

  // Déplacer vers B, renommer + recolorer A, supprimer un événement simple
  let mv = store.event(withIdentifier: L)!; mv.calendar = C(B); try store.save(mv, span: .thisEvent, commit: true)
  let ca = C(A); ca.title = "MCP-TEST-\(ts)-A2"; ca.cgColor = CGColor(srgbRed: 1, green: 0.58, blue: 0, alpha: 1); try store.saveCalendar(ca, commit: true)
  store.reset()
  ok(store.event(withIdentifier: L)?.calendar.calendarIdentifier == B, "déplacé vers B, identifiant conservé")
  ok(C(A).title.hasSuffix("-A2"), "calendrier renommé + recoloré")
  try store.remove(store.event(withIdentifier: L)!, span: .thisEvent, commit: true); store.reset()
  ok(store.event(withIdentifier: L) == nil, "événement simple supprimé par identifiant")
} catch { print("ERREUR:", error) }
for id in calIDs { if let c = store.calendar(withIdentifier: id), c.title.hasPrefix("MCP-TEST-") { try? store.removeCalendar(c, commit: true) } }
store.reset()
print("NETTOYAGE: calendriers MCP-TEST restants =", store.calendars(for: .event).filter { $0.title.hasPrefix("MCP-TEST-") }.count)
