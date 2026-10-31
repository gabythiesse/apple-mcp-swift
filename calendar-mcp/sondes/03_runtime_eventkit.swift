// Sonde 03 : méthodes non publiques d'EventKit (runtime ObjC), filtrées sur les points que l'API publique ne couvre pas
import Foundation
import EventKit
import ObjectiveC

let mots = ["travel", "attach", "invitation", "participationstatus", "conference", "privacy", "proposed", "responsemessage", "color", "selfattendee", "addattendee", "setattendees", "freebusy", "availability"]
for cls in ["EKEvent", "EKCalendarItem", "EKParticipant", "EKAttendee", "EKEventStore", "EKCalendar"] {
  guard let c: AnyClass = NSClassFromString(cls) else { print(cls, "absent"); continue }
  var n: UInt32 = 0
  let ms = class_copyMethodList(c, &n)!
  var hits: [String] = []
  for i in 0..<Int(n) {
    let s = NSStringFromSelector(method_getName(ms[i]))
    if mots.contains(where: { s.lowercased().contains($0) }) { hits.append(s) }
  }
  var cn: UInt32 = 0
  let cms = class_copyMethodList(object_getClass(c), &cn)!
  for i in 0..<Int(cn) { let s = NSStringFromSelector(method_getName(cms[i])); if mots.contains(where: { s.lowercased().contains($0) }) { hits.append("+" + s) } }
  print("\(cls) (\(n) méthodes):", hits.sorted().joined(separator: " "))
}
// classes liées à la disponibilité / pièces jointes
var count: UInt32 = 0
let img = class_getImageName(NSClassFromString("EKEvent")!)!
let names = objc_copyClassNamesForImage(img, &count)!
let cls = (0..<Int(count)).map { String(cString: names[$0]) }.filter { n in ["Availab", "Attach", "Invitation", "Conference", "Travel", "FreeBusy"].contains { n.contains($0) } }
print("classes EventKit:", cls.sorted().joined(separator: " "))
