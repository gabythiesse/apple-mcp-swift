// Sonde 06 : encodage des types d'arguments (pour appeler correctement les sélecteurs non-objet)
import Foundation
import ObjectiveC
dlopen("/System/Library/PrivateFrameworks/ReminderKit.framework/Versions/A/ReminderKit", RTLD_NOW)
var it = CommandLine.arguments.dropFirst().makeIterator()
while let c = it.next(), let s = it.next() {
  let cl: AnyClass = NSClassFromString(c)!
  let m = class_getInstanceMethod(cl, NSSelectorFromString(s)) ?? class_getClassMethod(cl, NSSelectorFromString(s))
  print(c, s, m.map { String(cString: method_getTypeEncoding($0)!) } ?? "absent")
}
