// Sonde 04 : ReminderKit — drapeau, tag, sous-tâche, URL en pièce jointe, sur un rappel de test créé via EventKit ; relecture EventKit + AppleScript
import Foundation
import EventKit
setvbuf(stdout, nil, _IONBF, 0)
dlopen("/System/Library/PrivateFrameworks/ReminderKit.framework/Versions/A/ReminderKit", RTLD_NOW)

let ek = EKEventStore()
guard try await ek.requestFullAccessToReminders() else { exit(2) }
let ts = Int(Date().timeIntervalSince1970)
let cal = EKCalendar(for: .reminder, eventStore: ek)
cal.title = "MCP-TEST-\(ts)"; cal.source = ek.defaultCalendarForNewReminders()!.source
try ek.saveCalendar(cal, commit: true)
let r = EKReminder(eventStore: ek); r.calendar = cal; r.title = "[mcp-test] parent"
try ek.save(r, commit: true)
print("EK liste:", cal.calendarIdentifier, "rappel:", r.calendarItemIdentifier)
defer { try? ek.removeCalendar(cal, commit: true) }

do {
  let st = try new("REMStore")
  let oid = try call(try cls("REMReminder"), "objectIDWithUUID:", UUID(uuidString: r.calendarItemIdentifier)! as NSUUID)!
  print("objectID:", oid)
  let rem = try callE(st, "fetchReminderWithObjectID:error:", oid)!
  print("REM relu:", try call(rem, "titleAsString") ?? "nil")
  let listOid = try call(rem, "listID")!
  print("REM listID uuid == EK calendarIdentifier ?", (try call(listOid, "uuid") as? NSUUID)?.uuidString == cal.calendarIdentifier)

  let sr = try new("REMSaveRequest", "initWithStore:", st)
  let ci = try call(sr, "updateReminder:", rem)!
  try setBool(try call(ci, "flaggedContext")!, "setFlagged:", true)
  let hc = try call(ci, "hashtagContext")!
  let (addH, sH, rH) = try imp(hc, "addHashtagWithType:name:", FIntO.self); _ = addH(rH, sH, 0, "mcptest" as NSString)
  _ = try call(try call(ci, "attachmentContext")!, "setURLAttachmentWithURL:", URL(string: "https://example.org")! as NSURL)
  let sub = try call(sr, "addReminderWithTitle:toReminderSubtaskContextChangeItem:", "[mcp-test] enfant" as NSString, try call(ci, "subtaskContext"))!
  try saveSync(sr)
  print("save OK")
  let subOid = try call(sub, "objectID")!
  print("sous-tâche objectID:", subOid)

  let st2 = try new("REMStore")
  let rem2 = try callE(st2, "fetchReminderWithObjectID:error:", oid)!
  print("RK drapeau:", try bool(try call(rem2, "flaggedContext")!, "flagged"))
  print("RK tags:", try (try call(try call(rem2, "hashtagContext")!, "hashtags") as? NSSet)?.compactMap { try call($0 as AnyObject, "name") } ?? [])
  let kids = try callE(st2, "fetchRemindersWithParentReminderIDs:error:", [oid] as NSArray) as? NSArray
  print("RK enfants:", try kids?.compactMap { try call($0 as AnyObject, "titleAsString") } ?? [])
  let subRem = try callE(st2, "fetchReminderWithObjectID:error:", subOid)!
  print("RK parent de l'enfant == parent ?", ((try call(subRem, "parentReminderID")).flatMap { try? call($0, "uuid") } as? NSUUID)?.uuidString == r.calendarItemIdentifier)
} catch { print("ERREUR RK:", error) }

// relecture EventKit (autre voie)
ek.reset()
let all: [EKReminder] = await withCheckedContinuation { c in ek.fetchReminders(matching: ek.predicateForReminders(in: [ek.calendar(withIdentifier: cal.calendarIdentifier)!])) { c.resume(returning: $0 ?? []) } }
print("EK voit:", all.map { "\($0.title!) url=\($0.url?.absoluteString ?? "nil")" })
// relecture AppleScript (autre voie)
let src = "tell application \"Reminders\" to get {name, flagged} of reminders of list id \"x-apple-reminder://\(cal.calendarIdentifier)\""
var err: NSDictionary?
let out = NSAppleScript(source: src)!.executeAndReturnError(&err)
print("AS voit:", out.stringValue ?? out.description, err ?? "")
