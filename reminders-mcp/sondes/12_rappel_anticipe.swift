// Sonde 12 : où l'app range son « Rappel anticipé », et quelle date elle affiche (liste de test MCP-TEST- uniquement)
// usage (avec objc.swift, lancé comme enfant du lanceur AppleMCP pour l'autorisation Rappels) :
//   <listID>                         état EventKit + ReminderKit de chaque rappel de la liste
//   <listID> <rappelID> set <unité 0-4> <nombre négatif>   poser un rappel anticipé (0 min, 1 h, 2 jour, 3 semaine, 4 mois)
//   <listID> <rappelID> clear        retirer les rappels anticipés
// Résultats (macOS 26, 05/11/2026) :
// - L'app affiche REMReminder.displayDate, calculée à partir de l'échéance ET des alarmes (REMDisplayDate initWithDueDateComponents:alarms:) :
//   dès qu'il y a une alarme datée, c'est la plus tôt des alarmes qui est affichée, avant ou après l'échéance, même sans échéance.
//   Échéance 20/11 + alarme 17/11 18:00 → « 17 nov. 2026 à 18:00 » ; échéance 20/11 09:00 + alarme relative -3 j → « 17 nov. à 09:00 » ;
//   échéance 20/11 (journée) + alarme relative → « 20 nov. » (l'alarme relative est ignorée pour l'affichage).
// - Le « Rappel anticipé » posé dans l'app n'est PAS une alarme : ni EKAlarm ni REMAlarm. C'est un REMDueDateDeltaAlert
//   (delta = REMDueDateDeltaInterval unit/count, ex. « -1wk »), chargé seulement avec REMReminderFetchOptions
//   fetchOptionsIncludingDueDateDeltaAlerts. displayDate reste l'échéance. EventKit ne le voit pas et le conserve quand il réécrit le rappel.
// - Écriture : REMReminderChangeItem.dueDateDeltaAlertContext → removeAllFetchedDueDateDeltaAlerts / addDueDateDeltaAlertWithDueDateDelta:.
//   L'app relit la valeur (« 30 minutes avant », « Personnalisé : 3 jours avant »).
// - Effacer l'échéance par EventKit laisse le rappel anticipé orphelin : le serveur le retire avec l'échéance.
import Foundation
import EventKit
setvbuf(stdout, nil, _IONBF, 0)
dlopen("/System/Library/PrivateFrameworks/ReminderKit.framework/Versions/A/ReminderKit", RTLD_NOW)
typealias F2E = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject?
typealias FDelta = @convention(c) (AnyObject, Selector, Int, Int) -> AnyObject?
typealias FV0 = @convention(c) (AnyObject, Selector) -> Void

let a = CommandLine.arguments
let ek = EKEventStore()
guard try await ek.requestFullAccessToReminders() else { exit(2) }
guard let cal = ek.calendar(withIdentifier: a[1]), cal.title.hasPrefix("MCP-TEST-") else { print("REFUS : pas une liste de test"); exit(3) }
let st = try new("REMStore")
func d(_ x: Any?) -> String { x.map { "\($0)".replacingOccurrences(of: "\n", with: " ") } ?? "nil" }
func fetch(_ id: String) throws -> AnyObject {
  let oid = try call(try cls("REMReminder"), "objectIDWithUUID:", UUID(uuidString: id)! as NSUUID)!
  let opts = try call(try cls("REMReminderFetchOptions"), "fetchOptionsIncludingDueDateDeltaAlerts")
  let (f, sel, r) = try imp(st, "fetchReminderWithObjectID:fetchOptions:error:", F2E.self)
  var e: NSError?
  guard let x = f(r, sel, oid, opts, &e) else { throw e ?? ObjCError(description: "introuvable") }
  return x
}

if a.count == 2 {
  let rs: [EKReminder] = await withCheckedContinuation { c in ek.fetchReminders(matching: ek.predicateForReminders(in: [cal])) { c.resume(returning: $0 ?? []) } }
  for r in rs.sorted(by: { ($0.title ?? "") < ($1.title ?? "") }) {
    print("=== \(r.title ?? "") \(r.calendarItemIdentifier)")
    print("EK échéance:", d(r.dueDateComponents), "| début:", d(r.startDateComponents))
    print("EK alarmes:", (r.alarms ?? []).map { al in al.absoluteDate.map { "abs \($0)" } ?? "rel \(al.relativeOffset)" })
    let rem = try fetch(r.calendarItemIdentifier)
    print("RK displayDate:", d(try? call(rem, "displayDate")))
    print("RK alarmes:", d(try? call(rem, "alarms")))
    print("RK rappels anticipés:", d(try? call(try call(rem, "dueDateDeltaAlertContext")!, "dueDateDeltaAlerts")))
  }
  exit(0)
}
guard let r = ek.calendarItem(withIdentifier: a[2]) as? EKReminder, r.calendar.calendarIdentifier == cal.calendarIdentifier else { print("REFUS : rappel hors liste de test"); exit(4) }
let sr = try new("REMSaveRequest", "initWithStore:", st)
let ctx = try call(try call(sr, "updateReminder:", try fetch(a[2]))!, "dueDateDeltaAlertContext")!
let (rm, srm, rrm) = try imp(ctx, "removeAllFetchedDueDateDeltaAlerts", FV0.self); rm(rrm, srm)
if a[3] == "set" {
  let o = try call(try cls("REMDueDateDeltaInterval"), "alloc")!
  let (mk, sel, rcv) = try imp(o, "initWithUnit:count:", FDelta.self)
  print("ajouté:", d(try call(ctx, "addDueDateDeltaAlertWithDueDateDelta:", mk(rcv, sel, Int(a[4])!, Int(a[5])!))))
}
try saveSync(sr)
print("enregistré")
