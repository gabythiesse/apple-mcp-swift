// Sonde 11 : comment sortir un rappel de sa section ? (variantes d'appartenance, sur liste de test)
import Foundation
import EventKit
setvbuf(stdout, nil, _IONBF, 0)
dlopen("/System/Library/PrivateFrameworks/ReminderKit.framework/Versions/A/ReminderKit", RTLD_NOW)
typealias FMemb = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, Bool, AnyObject?) -> AnyObject?
typealias F1V = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
func uuid(_ oid: AnyObject?) -> String? { (oid.flatMap { try? call($0, "uuid") } as? NSUUID)?.uuidString }

let ek = EKEventStore()
guard try await ek.requestFullAccessToReminders() else { exit(2) }
let ts = Int(Date().timeIntervalSince1970)
let A = EKCalendar(for: .reminder, eventStore: ek); A.title = "MCP-TEST-\(ts)"; A.source = ek.defaultCalendarForNewReminders()!.source
try ek.saveCalendar(A, commit: true)
print("NETTOYAGE id:", A.calendarIdentifier)
defer { ek.reset(); if let c = ek.calendar(withIdentifier: A.calendarIdentifier) { try? ek.removeCalendar(c, commit: true) }; ek.reset(); print("reste:", ek.calendars(for: .reminder).filter { $0.title.hasPrefix("MCP-TEST-") }.count) }
let R = EKReminder(eventStore: ek); R.calendar = A; R.title = "[mcp-test] R"; try ek.save(R, commit: true)
let aOid = try call(try cls("REMList"), "objectIDWithUUID:", UUID(uuidString: A.calendarIdentifier)! as NSUUID)!
let rOid = try call(try cls("REMReminder"), "objectIDWithUUID:", UUID(uuidString: R.calendarItemIdentifier)! as NSUUID)!
let member = UUID(uuidString: R.calendarItemIdentifier)! as NSUUID

func setMembership(_ group: AnyObject?, obsolete: Bool, at date: Date = Date()) throws {
  let st = try new("REMStore"); let sr = try new("REMSaveRequest", "initWithStore:", st)
  let lci = try call(sr, "updateList:", try callE(st, "fetchListWithObjectID:error:", aOid))!
  let ctx = try call(lci, "sectionsContextChangeItem")!
  let a = try call(try cls("REMMembership"), "alloc")!
  let (mk, sel, _) = try imp(a, "initWithMemberIdentifier:groupIdentifier:isObsolete:modifiedOn:", FMemb.self)
  let m = mk(a, sel, member, group, obsolete, date as NSDate)!
  let ms = try call(try call(try cls("REMMemberships"), "alloc")!, "initWithMembershipByMemberIdentifier:", [member: m] as NSDictionary)!
  let (sv, ss, sr2) = try imp(ctx, "setUnsavedMembershipsOfRemindersInSections:", F1V.self); sv(sr2, ss, ms)
  try saveSync(sr)
}
func section() -> String {
  guard let st = try? new("REMStore"), let dv = try? new("REMListSectionsDataView", "initWithStore:", st),
        let s = try? callE(dv, "fetchListSectionWithReminderID:error:", rOid) else { return "aucune" }
  return (try? call(s, "displayName") as? String) ?? "?"
}
do {
  let st = try new("REMStore"); let sr = try new("REMSaveRequest", "initWithStore:", st)
  let lci = try call(sr, "updateList:", try callE(st, "fetchListWithObjectID:error:", aOid))!
  let sec = try call(sr, "addListSectionWithDisplayName:toListSectionContextChangeItem:", "[mcp-test] S" as NSString, try call(lci, "sectionsContextChangeItem"))!
  let secUUID = try call(try call(sec, "objectID")!, "uuid")!
  try saveSync(sr)
  try setMembership(secUUID, obsolete: false); print("dans S :", section())
  do { try setMembership(nil, obsolete: false); print("V-a groupe nil :", section()) } catch { print("V-a erreur:", error) }
  try setMembership(secUUID, obsolete: false); print("remis dans S :", section())
  do { try setMembership(UUID(uuidString: A.calendarIdentifier)! as NSUUID, obsolete: false); print("V-b groupe = liste :", section()) } catch { print("V-b erreur:", error) }
  try setMembership(secUUID, obsolete: false); print("remis dans S :", section())
  do { try setMembership(UUID() as NSUUID, obsolete: false); print("V-c groupe inexistant :", section()) } catch { print("V-c erreur:", error) }
} catch { print("ERREUR:", error) }
