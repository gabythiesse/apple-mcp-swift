// Sonde 03 : méthodes non publiques du framework Contacts liées à la fusion (link/unify), à « Ma carte » et au partage.
// Lecture du runtime ObjC seulement, aucune donnée.
import Foundation
import Contacts
import ObjectiveC

let _s = CNContactStore(); _ = _s.defaultContainerIdentifier; _ = dlopen("/System/Library/Frameworks/Contacts.framework/Contacts", RTLD_NOW)
let keys = CommandLine.arguments.dropFirst().isEmpty ? ["link", "unlink", "unif", "merge", "me", "preferred", "duplicate", "note"] : Array(CommandLine.arguments.dropFirst())
for name in ["CNSaveRequest", "CNContactStore", "CNMutableContact", "CNContact", "CNContainer", "CNGroup", "CNMutableGroup"] {
  guard let c: AnyClass = NSClassFromString(name) else { print(name, "absente"); continue }
  for (meta, cls) in [("+", object_getClass(c)!), ("-", c)] {
    var n: UInt32 = 0
    guard let ms = class_copyMethodList(cls, &n) else { continue }
    let sels = (0..<Int(n)).map { NSStringFromSelector(method_getName(ms[$0])) }.filter { s in keys.contains { s.localizedCaseInsensitiveContains($0) } }.sorted()
    for s in sels { print("\(meta)[\(name) \(s)]") }
    free(ms)
  }
}
