// Sonde 09 : déplacer un parent avec sous-tâches entre listes via REMListChangeItem.addReminderChangeItem:
import Foundation
import EventKit
setvbuf(stdout, nil, _IONBF, 0)
dlopen("/System/Library/PrivateFrameworks/ReminderKit.framework/Versions/A/ReminderKit", RTLD_NOW)
func uuid(_ oid: AnyObject?) -> String? { (oid.flatMap { try? call($0, "uuid") } as? NSUUID)?.uuidString }
func rOid(_ id: String) throws -> AnyObject { try call(try cls("REMReminder"), "objectIDWithUUID:", UUID(uuidString: id)! as NSUUID)! }
func lOid(_ id: String) throws -> AnyObject { try call(try cls("REMList"), "objectIDWithUUID:", UUID(uuidString: id)! as NSUUID)! }

let ek = EKEventStore()
guard try await ek.requestFullAccessToReminders() else { exit(2) }
let ts = Int(Date().timeIntervalSince1970)
func mkList(_ n: String) throws -> EKCalendar { let c = EKCalendar(for: .reminder, eventStore: ek); c.title = n; c.source = ek.defaultCalendarForNewReminders()!.source; try ek.saveCalendar(c, commit: true); return c }
let A = try mkList("MCP-TEST-\(ts)-A"), B = try mkList("MCP-TEST-\(ts)-B")
print("NETTOYAGE ids:", A.calendarIdentifier, B.calendarIdentifier)
let P = EKReminder(eventStore: ek); P.calendar = A; P.title = "[mcp-test] P"; try ek.save(P, commit: true)

func etat(_ label: String, _ kidOid: AnyObject) throws {
  let st = try new("REMStore")
  let p = try callE(st, "fetchReminderWithObjectID:error:", try rOid(P.calendarItemIdentifier))!
  let k = try callE(st, "fetchReminderWithObjectID:error:", kidOid)!
  print(label, "P en B:", uuid(try call(p, "listID")) == B.calendarIdentifier, "| enfant en B:", uuid(try call(k, "listID")) == B.calendarIdentifier, "| lien parent:", uuid(try call(k, "parentReminderID")) == P.calendarItemIdentifier)
}
do {
  var st = try new("REMStore"); var sr = try new("REMSaveRequest", "initWithStore:", st)
  let pCI = try call(sr, "updateReminder:", try callE(st, "fetchReminderWithObjectID:error:", try rOid(P.calendarItemIdentifier))!)!
  let kidOid = try call(try call(sr, "addReminderWithTitle:toReminderSubtaskContextChangeItem:", "[mcp-test] P.enfant" as NSString, try call(pCI, "subtaskContext"))!, "objectID")!
  try saveSync(sr)

  // variante 1 : parent seul
  st = try new("REMStore"); sr = try new("REMSaveRequest", "initWithStore:", st)
  var bCI = try call(sr, "updateList:", try callE(st, "fetchListWithObjectID:error:", try lOid(B.calendarIdentifier))!)!
  var pCI2 = try call(sr, "updateReminder:", try callE(st, "fetchReminderWithObjectID:error:", try rOid(P.calendarItemIdentifier))!)!
  _ = try call(bCI, "addReminderChangeItem:", pCI2)
  do { try saveSync(sr); try etat("V1 (parent seul):", kidOid) } catch { print("V1 erreur:", (error as NSError).localizedDescription) }

  // variante 2 : parent + enfant ajoutés à B puis réattachés
  st = try new("REMStore"); sr = try new("REMSaveRequest", "initWithStore:", st)
  bCI = try call(sr, "updateList:", try callE(st, "fetchListWithObjectID:error:", try lOid(B.calendarIdentifier))!)!
  pCI2 = try call(sr, "updateReminder:", try callE(st, "fetchReminderWithObjectID:error:", try rOid(P.calendarItemIdentifier))!)!
  let kCI = try call(sr, "updateReminder:", try callE(st, "fetchReminderWithObjectID:error:", kidOid)!)!
  _ = try call(bCI, "addReminderChangeItem:", pCI2)
  _ = try call(try call(pCI2, "subtaskContext")!, "addReminderChangeItem:", kCI)
  do { try saveSync(sr); try etat("V2 (parent + enfant):", kidOid) } catch { print("V2 erreur:", (error as NSError).localizedDescription) }
  ek.reset()
  let inB: [EKReminder] = await withCheckedContinuation { c in ek.fetchReminders(matching: ek.predicateForReminders(in: [ek.calendar(withIdentifier: B.calendarIdentifier)!])) { c.resume(returning: $0 ?? []) } }
  print("EK voit dans B:", inB.map { $0.title! })
} catch { print("ERREUR:", error) }

ek.reset()
for id in [A.calendarIdentifier, B.calendarIdentifier] { if let c = ek.calendar(withIdentifier: id), c.title.hasPrefix("MCP-TEST-") { try? ek.removeCalendar(c, commit: true) } }
ek.reset(); print("reste listes MCP-TEST (EK):", ek.calendars(for: .reminder).filter { $0.title.hasPrefix("MCP-TEST-") }.count)
