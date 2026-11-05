// Sonde 13 : d'où vient le « début » égal à l'échéance que list_reminders renvoyait sans qu'on l'ait demandé ? (liste MCP-TEST- uniquement)
// Résultats (macOS 26, 05/11/2026) :
// - EventKit : EKReminder.dueDateComponents = … remplit startDateComponents s'il est vide, en mémoire, avant même l'enregistrement
//   (journée entière → début à 00:00). Changer ensuite l'échéance ne déplace pas ce début : il devient périmé.
// - ReminderKit (la voie de l'app) : setDueDateComponents: laisse le début vide. Un rappel daté dans l'app a aussi un début vide.
// - Remettre startDateComponents à nil après l'échéance est accepté et l'app affiche le rappel normalement.
// Le serveur laisse donc le début vide sauf si start est fourni.
import Foundation
import EventKit
setvbuf(stdout, nil, _IONBF, 0)
dlopen("/System/Library/PrivateFrameworks/ReminderKit.framework/Versions/A/ReminderKit", RTLD_NOW)
typealias FV1 = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
let ek = EKEventStore()
guard try await ek.requestFullAccessToReminders() else { exit(2) }
let listID = CommandLine.arguments[1]
guard let cal = ek.calendar(withIdentifier: listID), cal.title.hasPrefix("MCP-TEST-") else { print("REFUS : pas une liste de test"); exit(3) }
func dc(_ c: DateComponents?) -> String { guard let c else { return "nil" }; return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)" + (c.hour != nil ? " \(c.hour!):\(c.minute ?? 0)" : "") }

for (label, due) in [("journée", DateComponents(year: 2026, month: 11, day: 21)),
                     ("heure", DateComponents(timeZone: .current, year: 2026, month: 11, day: 21, hour: 10, minute: 0))] {
  let r = EKReminder(eventStore: ek); r.calendar = cal; r.title = "[mcp-test] début EK \(label)"
  r.dueDateComponents = due
  print("EK \(label), en mémoire : début =", dc(r.startDateComponents))
  try ek.save(r, commit: true)
  ek.reset()
  let r2 = ek.calendarItem(withIdentifier: r.calendarItemIdentifier) as! EKReminder
  print("EK \(label), relu : début =", dc(r2.startDateComponents), "échéance =", dc(r2.dueDateComponents))
  r2.dueDateComponents = DateComponents(year: 2026, month: 11, day: 25)
  try ek.save(r2, commit: true)
  print("EK \(label), échéance déplacée au 25 : début =", dc(r2.startDateComponents))
}

let st = try new("REMStore")
let sr = try new("REMSaveRequest", "initWithStore:", st)
let l = try callE(st, "fetchListWithObjectID:error:", try call(try cls("REMList"), "objectIDWithUUID:", UUID(uuidString: listID)! as NSUUID))!
let ci = try call(sr, "addReminderWithTitle:toListChangeItem:", "[mcp-test] début RK journée" as NSString, try call(sr, "updateList:", l))!
let (f, s, rcv) = try imp(ci, "setDueDateComponents:", FV1.self); f(rcv, s, DateComponents(year: 2026, month: 11, day: 21) as NSDateComponents)
try saveSync(sr)
let id = (try call(try call(ci, "objectID")!, "uuid") as! NSUUID).uuidString
ek.reset()
let r3 = ek.calendarItem(withIdentifier: id) as! EKReminder
print("RK journée, vu par EventKit : début =", dc(r3.startDateComponents), "échéance =", dc(r3.dueDateComponents))
