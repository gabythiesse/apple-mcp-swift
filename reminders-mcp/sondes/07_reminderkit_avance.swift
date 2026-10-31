// Sonde 07 : URL (EK vs pièce jointe RK), sections + appartenance, image, déplacement d'un parent avec sous-tâche, groupe de listes, relecture AppleScript
import Foundation
import EventKit
setvbuf(stdout, nil, _IONBF, 0)
dlopen("/System/Library/PrivateFrameworks/ReminderKit.framework/Versions/A/ReminderKit", RTLD_NOW)
typealias FMemb = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, Bool, AnyObject?) -> AnyObject?
typealias FImg = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, UInt, UInt) -> AnyObject?
typealias FV = @convention(c) (AnyObject, Selector) -> Void
func void(_ o: AnyObject, _ s: String) throws { let (f, sel, r) = try imp(o, s, FV.self); f(r, sel) }
func uuid(_ oid: AnyObject?) -> String? { (oid.flatMap { try? call($0, "uuid") } as? NSUUID)?.uuidString }

let ek = EKEventStore()
guard try await ek.requestFullAccessToReminders() else { exit(2) }
let ts = Int(Date().timeIntervalSince1970)
func mkList(_ n: String) throws -> EKCalendar { let c = EKCalendar(for: .reminder, eventStore: ek); c.title = n; c.source = ek.defaultCalendarForNewReminders()!.source; try ek.saveCalendar(c, commit: true); return c }
let A = try mkList("MCP-TEST-\(ts)-A"), B = try mkList("MCP-TEST-\(ts)-B")
print("NETTOYAGE ids:", A.calendarIdentifier, B.calendarIdentifier)
let P = EKReminder(eventStore: ek); P.calendar = A; P.title = "[mcp-test] P"; P.url = URL(string: "https://ek.example")
let Q = EKReminder(eventStore: ek); Q.calendar = A; Q.title = "[mcp-test] Q"
try ek.save(P, commit: false); try ek.save(Q, commit: false); try ek.commit()
var groupOid: AnyObject?
var extraLists: [String] = []

do {
  let st = try new("REMStore")
  let pOid = try call(try cls("REMReminder"), "objectIDWithUUID:", UUID(uuidString: P.calendarItemIdentifier)! as NSUUID)!
  let qOid = try call(try cls("REMReminder"), "objectIDWithUUID:", UUID(uuidString: Q.calendarItemIdentifier)! as NSUUID)!
  let aOid = try call(try cls("REMList"), "objectIDWithUUID:", UUID(uuidString: A.calendarIdentifier)! as NSUUID)!
  let pRem = try callE(st, "fetchReminderWithObjectID:error:", pOid)!

  // 1. URL : EK url -> pièce jointe RK ?
  let atts = (try call(try call(pRem, "attachmentContext")!, "attachments") as? NSArray) ?? []
  print("1. EK url vue par RK:", atts.map { "\(type(of: $0)) \((try? call($0 as AnyObject, "url")) ?? "-" as NSString)" })

  // 2. section + appartenance + 3. image + 4. sous-tâche
  let sr = try new("REMSaveRequest", "initWithStore:", st)
  let aRem = try callE(st, "fetchListWithObjectID:error:", aOid)!
  let aCI = try call(sr, "updateList:", aRem)!
  let secCtx = try call(aCI, "sectionsContextChangeItem")!
  let sec = try call(sr, "addListSectionWithDisplayName:toListSectionContextChangeItem:", "[mcp-test] Section" as NSString, secCtx)!
  let secUUID = try call(try call(sec, "objectID")!, "uuid")!
  let (fm, sm, _) = try imp(try call(try cls("REMMembership"), "alloc")!, "initWithMemberIdentifier:groupIdentifier:isObsolete:modifiedOn:", FMemb.self)
  let memb = fm(try call(try cls("REMMembership"), "alloc")!, sm, UUID(uuidString: Q.calendarItemIdentifier)! as NSUUID, secUUID, false, Date() as NSDate)!
  let membs = try call(try call(try cls("REMMemberships"), "alloc")!, "initWithMembershipByMemberIdentifier:", [UUID(uuidString: Q.calendarItemIdentifier)! as NSUUID: memb] as NSDictionary)!
  _ = try call(secCtx, "setUnsavedMembershipsOfRemindersInSections:", membs)
  let pCI = try call(sr, "updateReminder:", pRem)!
  let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
  let (fi, si, ri) = try imp(try call(pCI, "attachmentContext")!, "addImageAttachmentWithData:uti:width:height:", FImg.self)
  _ = fi(ri, si, png as NSData, "public.png" as NSString, 1, 1)
  _ = try call(sr, "addReminderWithTitle:toReminderSubtaskContextChangeItem:", "[mcp-test] P.enfant" as NSString, try call(pCI, "subtaskContext"))
  try saveSync(sr)
  print("2-4. save OK")

  let st2 = try new("REMStore")
  let dv = try new("REMListSectionsDataView", "initWithStore:", st2)
  let secs = (try callE(dv, "fetchListSectionsWithListObjectID:error:", aOid) as? NSArray) ?? []
  print("2. sections de A:", try secs.map { try call($0 as AnyObject, "displayName") ?? "nil" as NSString })
  let qSec = try? callE(dv, "fetchListSectionWithReminderID:error:", qOid)
  print("2. section de Q:", qSec.flatMap { try? call($0, "displayName") } ?? "aucune" as NSString)
  let p2 = try callE(st2, "fetchReminderWithObjectID:error:", pOid)!
  let atts2 = (try call(try call(p2, "attachmentContext")!, "attachments") as? NSArray) ?? []
  print("3. pièces jointes P:", atts2.map { "\(type(of: $0))" })

  // 4. déplacer P (avec sous-tâche) vers B via EventKit
  ek.reset()
  let pEK = ek.calendarItem(withIdentifier: P.calendarItemIdentifier) as! EKReminder
  pEK.calendar = ek.calendar(withIdentifier: B.calendarIdentifier)!
  try ek.save(pEK, commit: true)
  let st3 = try new("REMStore")
  let kids = (try callE(st3, "fetchRemindersWithParentReminderIDs:error:", [pOid] as NSArray) as? NSArray) ?? []
  for k in kids { print("4. après move EK, enfant:", try call(k as AnyObject, "titleAsString")!, "liste=B ?", uuid(try call(k as AnyObject, "listID")) == B.calendarIdentifier) }
  print("4. P en B ?", uuid(try call(try callE(st3, "fetchReminderWithObjectID:error:", pOid)!, "listID")) == B.calendarIdentifier)

  // 5. groupe de listes : créer un groupe, y créer une liste, y déplacer A
  let sr5 = try new("REMSaveRequest", "initWithStore:", st3)
  let acc = try call(try callE(st3, "fetchListWithObjectID:error:", aOid)!, "account")!
  let accCI = try call(sr5, "updateAccount:", acc)!
  let grp = try call(sr5, "addGroupWithName:toAccountGroupContextChangeItem:", "MCP-TEST-\(ts)-GROUPE" as NSString, try call(accCI, "groupContext"))!
  groupOid = try call(grp, "objectID")
  let inner = try call(sr5, "addListWithName:toListSublistContextChangeItem:", "MCP-TEST-\(ts)-DANS-GROUPE" as NSString, try call(grp, "sublistContext"))!
  extraLists.append(uuid(try call(inner, "objectID"))!)
  print("NETTOYAGE groupe:", uuid(groupOid)!, "liste interne:", extraLists[0])
  try saveSync(sr5)
  let st4 = try new("REMStore")
  let innerRem = try callE(st4, "fetchListWithObjectID:error:", try call(inner, "objectID"))!
  print("5. liste interne parent == groupe ?", uuid(try call(innerRem, "parentListID")) == uuid(groupOid))
  ek.reset(); print("5. EK voit la liste interne ?", ek.calendar(withIdentifier: extraLists[0]) != nil)
  // déplacer A dans le groupe
  let sr6 = try new("REMSaveRequest", "initWithStore:", st4)
  let grpCI = try call(sr6, "updateList:", try callE(st4, "fetchListWithObjectID:error:", groupOid)!)!
  let aCI6 = try call(sr6, "updateList:", try callE(st4, "fetchListWithObjectID:error:", aOid)!)!
  _ = try call(try call(grpCI, "sublistContext")!, "addListChangeItem:", aCI6)
  try saveSync(sr6)
  let st5 = try new("REMStore")
  print("5. A déplacée dans le groupe ?", uuid(try call(try callE(st5, "fetchListWithObjectID:error:", aOid)!, "parentListID")) == uuid(groupOid))
} catch { print("ERREUR RK:", error) }

// relecture AppleScript du drapeau / de la liste (autre voie)
var err: NSDictionary?
let out = NSAppleScript(source: "tell application \"Reminders\" to get name of reminders of list id \"\(B.calendarIdentifier)\"")!.executeAndReturnError(&err)
print("AS voit B:", (0..<out.numberOfItems).compactMap { out.atIndex($0 + 1)?.stringValue }, err?["NSAppleScriptErrorBriefMessage"] ?? "")

// nettoyage : listes par EK, puis groupe par RK
ek.reset()
for id in [A.calendarIdentifier, B.calendarIdentifier] + extraLists { if let c = ek.calendar(withIdentifier: id), c.title.hasPrefix("MCP-TEST-") { try? ek.removeCalendar(c, commit: true) } }
if let g = groupOid {
  do {
    let st = try new("REMStore"); let sr = try new("REMSaveRequest", "initWithStore:", st)
    let gCI = try call(sr, "updateList:", try callE(st, "fetchListWithObjectID:error:", g)!)!
    try void(gCI, "removeFromParent"); try saveSync(sr)
    let gone = (try? callE(try new("REMStore"), "fetchListWithObjectID:error:", g)) == nil
    print("groupe supprimé:", gone)
  } catch { print("groupe suppression:", error) }
}
ek.reset(); print("reste listes MCP-TEST (EK):", ek.calendars(for: .reminder).filter { $0.title.hasPrefix("MCP-TEST-") }.count)
