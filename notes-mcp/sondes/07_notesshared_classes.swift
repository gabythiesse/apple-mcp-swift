// Sonde 07 : framework privé NotesShared (chargé par Notes) : classes et méthodes filtrées par mot-clé.
// Inspection seulement : aucun contexte Core Data n'est démarré (ce serait écrire dans la base de l’utilisateur).
// Usage : swift 07... [Classe] mot-clé...
import Foundation
import ObjectiveC
let path = "/System/Library/PrivateFrameworks/NotesShared.framework/Versions/A/NotesShared"
guard dlopen(path, RTLD_NOW) != nil else { print("dlopen KO:", String(cString: dlerror())); exit(1) }
var args = Array(CommandLine.arguments.dropFirst())
if let first = args.first, let c: AnyClass = NSClassFromString(first) {
  args.removeFirst()
  for (pfx, k) in [("+", object_getClass(c)!), ("-", c)] {
    var n: UInt32 = 0; guard let ms = class_copyMethodList(k, &n) else { continue }
    let names = (0..<Int(n)).map { NSStringFromSelector(method_getName(ms[$0])) }
      .filter { s in args.isEmpty || args.contains { s.localizedCaseInsensitiveContains($0) } }.sorted()
    print(names.map { pfx + $0 }.joined(separator: "\n"))
  }
  print("super:", class_getSuperclass(c).map(NSStringFromClass) ?? "nil")
} else {
  guard let probe: AnyClass = NSClassFromString("ICNote") else { print("ICNote absent"); exit(1) }
  var count: UInt32 = 0
  let names = objc_copyClassNamesForImage(class_getImageName(probe)!, &count)!
  let all = (0..<Int(count)).map { String(cString: names[$0]) }.sorted()
  print(all.filter { n in args.isEmpty || args.contains { n.localizedCaseInsensitiveContains($0) } }.joined(separator: " "))
  print("total:", count)
}
