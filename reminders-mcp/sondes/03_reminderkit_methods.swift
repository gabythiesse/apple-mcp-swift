// Sonde 03 : méthodes des classes ReminderKit utiles (usage: swift 03... Classe [mot-clé...])
import Foundation
import ObjectiveC
dlopen("/System/Library/PrivateFrameworks/ReminderKit.framework/Versions/A/ReminderKit", RTLD_NOW)
let args = Array(CommandLine.arguments.dropFirst())
let cls: AnyClass = NSClassFromString(args[0])!
let keys = args.dropFirst()
func dump(_ c: AnyClass, _ prefix: String) {
  var n: UInt32 = 0
  guard let ms = class_copyMethodList(c, &n) else { return }
  var out: [String] = []
  for i in 0..<Int(n) {
    let s = NSStringFromSelector(method_getName(ms[i]))
    if keys.isEmpty || keys.contains(where: { s.localizedCaseInsensitiveContains($0) }) { out.append(prefix + s) }
  }
  print(out.sorted().joined(separator: "\n"))
}
dump(object_getClass(cls)!, "+")
dump(cls, "-")
print("super:", class_getSuperclass(cls).map { NSStringFromClass($0) } ?? "nil")
