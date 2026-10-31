// Sonde 19 : classes d'historique de SafariShared (privé) et méthodes de suppression
import Foundation
import ObjectiveC
let path = "/System/Library/PrivateFrameworks/SafariShared.framework/SafariShared"
print("dlopen:", dlopen(path, RTLD_NOW) != nil)
var n: UInt32 = 0
for img in ["SafariShared", "SafariCore", "SafariFoundation"] {
  _ = dlopen("/System/Library/PrivateFrameworks/\(img).framework/\(img)", RTLD_NOW)
}
var count: UInt32 = 0
let all = objc_copyImageNames(&count)
for i in 0..<Int(count) {
  let img = String(cString: all[i])
  guard img.contains("Safari") else { continue }
  guard let cls = objc_copyClassNamesForImage(all[i], &n) else { continue }
  for j in 0..<Int(n) {
    let name = String(cString: cls[j])
    guard name.contains("History") && (name.hasPrefix("WBS")) else { continue }
    var line: [String] = []
    for meta in [false, true] {
      guard let c = NSClassFromString(name) else { continue }
      let k: AnyClass = meta ? object_getClass(c)! : c
      var m: UInt32 = 0
      if let ms = class_copyMethodList(k, &m) {
        for x in 0..<Int(m) { let s = NSStringFromSelector(method_getName(ms[x])); if s.lowercased().contains("remov") || s.lowercased().contains("delet") || s.contains("shared") || s.contains("Shared") { line.append((meta ? "+" : "-") + s) } }
      }
    }
    if !line.isEmpty { print("\(name) [\(img.split(separator: "/").last!)]: " + line.joined(separator: " ")) }
  }
}
