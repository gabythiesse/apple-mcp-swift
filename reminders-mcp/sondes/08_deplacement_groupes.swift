// Sonde 08 : déplacer un parent + sous-tâches via ReminderKit ; groupes de listes (créer, y créer une liste, y déplacer une liste, supprimer)
import Foundation
import EventKit
setvbuf(stdout, nil, _IONBF, 0)
dlopen("/System/Library/PrivateFrameworks/ReminderKit.framework/Versions/A/ReminderKit", RTLD_NOW)
typealias FV = @convention(c) (AnyObject, Selector) -> Void
func void(_ o: AnyObject, _ s: String) throws { let (f, sel, r) = try imp(o, s, FV.self); f(r, sel) }
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
var groupOid: AnyObject?
var extraLists: [String] = []

do {
  // sous-tâche via RK
  var st = try new("REMStore")
  var sr = try new("REMSaveRequest", "initWithStore:", st)
  let pCI = try call(sr, "updateReminder:", try callE(st, "fetchReminderWithObjectID:error:", try rOid(P.calendarItemIdentifier))!)!
  let kid = try call(sr, "addReminderWithTitle:toReminderSubtaskContextChangeItem:", "[mcp-test] P.enfant" as NSString, try call(pCI, "subtaskContext"))!
  let kidOid = try call(kid, "objectID")!
  try saveSync(sr)

  // déplacement RK : parent puis enfant
  st = try new("REMStore"); sr = try new("REMSaveRequest", "initWithStore:", st)
  let bCI = try call(sr, "updateList:", try callE(st, "fetchListWithObjectID:error:", try lOid(B.calendarIdentifier))!)!
  let pCI2 = try call(sr, "updateReminder:", try callE(st, "fetchReminderWithObjectID:error:", try rOid(P.calendarItemIdentifier))!)!
  let moved = try call(try call(try cls("REMReminderChangeItem"), "alloc")!, "initWithReminderChangeItem:insertIntoListChangeItem:", pCI2, bCI)!
  print("move: même objectID ?", uuid(try call(moved, "objectID")) == P.calendarItemIdentifier)
  try saveSync(sr)
  st = try new("REMStore")
  let p3 = try callE(st, "fetchReminderWithObjectID:error:", try rOid(P.calendarItemIdentifier))!
  let k3 = try callE(st, "fetchReminderWithObjectID:error:", kidOid)!
  print("après move RK: P en B ?", uuid(try call(p3, "listID")) == B.calendarIdentifier, "| enfant en B ?", uuid(try call(k3, "listID")) == B.calendarIdentifier, "| enfant toujours lié ?", uuid(try call(k3, "parentReminderID")) == P.calendarItemIdentifier)
  ek.reset()
  let inA: [EKReminder] = await withCheckedContinuation { c in ek.fetchReminders(matching: ek.predicateForReminders(in: [ek.calendar(withIdentifier: A.calendarIdentifier)!])) { c.resume(returning: $0 ?? []) } }
  let inB: [EKReminder] = await withCheckedContinuation { c in ek.fetchReminders(matching: ek.predicateForReminders(in: [ek.calendar(withIdentifier: B.calendarIdentifier)!])) { c.resume(returning: $0 ?? []) } }
  print("EK: A =", inA.map { $0.title! }, "| B =", inB.map { $0.title! })
} catch { print("ERREUR move:", error) }

do {
  var st = try new("REMStore"); var sr = try new("REMSaveRequest", "initWithStore:", st)
  let acc = try call(try callE(st, "fetchListWithObjectID:error:", try lOid(A.calendarIdentifier))!, "account")!
  let accCI = try call(sr, "updateAccount:", acc)!
  let grp = try call(sr, "addGroupWithName:toAccountGroupContextChangeItem:", "MCP-TEST-\(ts)-GROUPE" as NSString, try call(accCI, "groupContext"))!
  groupOid = try call(grp, "objectID")
  let inner = try call(sr, "addListWithName:toListSublistContextChangeItem:", "MCP-TEST-\(ts)-DANS-GROUPE" as NSString, try call(grp, "sublistContext"))!
  extraLists.append(uuid(try call(inner, "objectID"))!)
  print("NETTOYAGE groupe:", uuid(groupOid)!, "liste interne:", extraLists[0])
  try saveSync(sr)
  st = try new("REMStore")
  print("groupe: isGroup ?", try bool(try callE(st, "fetchListWithObjectID:error:", groupOid)!, "isGroup"))
  print("groupe: liste interne parent == groupe ?", uuid(try call(try callE(st, "fetchListWithObjectID:error:", try call(inner, "objectID"))!, "parentListID")) == uuid(groupOid))
  ek.reset(); print("groupe: EK voit liste interne ?", ek.calendar(withIdentifier: extraLists[0]) != nil, "| EK voit le groupe ?", ek.calendar(withIdentifier: uuid(groupOid)!) != nil)
  sr = try new("REMSaveRequest", "initWithStore:", st)
  let gCI = try call(sr, "updateList:", try callE(st, "fetchListWithObjectID:error:", groupOid)!)!
  let aCI = try call(sr, "updateList:", try callE(st, "fetchListWithObjectID:error:", try lOid(A.calendarIdentifier))!)!
  _ = try call(try call(gCI, "sublistContext")!, "addListChangeItem:", aCI)
  try saveSync(sr)
  st = try new("REMStore")
  print("groupe: A déplacée dedans ?", uuid(try call(try callE(st, "fetchListWithObjectID:error:", try lOid(A.calendarIdentifier))!, "parentListID")) == uuid(groupOid))
} catch { print("ERREUR groupe:", error) }

// nettoyage : listes par EK, puis groupe par RK
ek.reset()
for id in [A.calendarIdentifier, B.calendarIdentifier] + extraLists { if let c = ek.calendar(withIdentifier: id), c.title.hasPrefix("MCP-TEST-") { do { try ek.removeCalendar(c, commit: true) } catch { print("EK suppr", c.title, error) } } }
if let g = groupOid {
  do {
    let st = try new("REMStore"); let sr = try new("REMSaveRequest", "initWithStore:", st)
    let gCI = try call(sr, "updateList:", try callE(st, "fetchListWithObjectID:error:", g)!)!
    try void(gCI, "removeFromParent"); try saveSync(sr)
    print("groupe supprimé:", (try? callE(try new("REMStore"), "fetchListWithObjectID:error:", g)) == nil)
  } catch { print("groupe suppression:", error) }
}
ek.reset(); print("reste listes MCP-TEST (EK):", ek.calendars(for: .reminder).filter { $0.title.hasPrefix("MCP-TEST-") }.count)
