// Sonde 05 : cherche un fragment de sélecteur dans toutes les classes de ReminderKit
import Foundation
import ObjectiveC
dlopen("/System/Library/PrivateFrameworks/ReminderKit.framework/Versions/A/ReminderKit", RTLD_NOW)
let image = String(cString: class_getImageName(NSClassFromString("REMStore")!)!)
var n: UInt32 = 0
let names = objc_copyClassNamesForImage(image, &n)!
let keys = CommandLine.arguments.dropFirst()
for i in 0..<Int(n) {
  let cn = String(cString: names[i]); guard let c = NSClassFromString(cn) else { continue }
  for (k, cc) in [("-", c), ("+", object_getClass(c)!)] {
    var m: UInt32 = 0; guard let ms = class_copyMethodList(cc, &m) else { continue }
    for j in 0..<Int(m) { let s = NSStringFromSelector(method_getName(ms[j])); if keys.allSatisfy({ s.localizedCaseInsensitiveContains($0) }) && !s.hasPrefix("_") { print(cn, k + s) } }
  }
}
