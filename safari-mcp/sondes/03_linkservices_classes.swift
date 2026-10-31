// Sonde 03 : LinkServices (privé) peut-il exécuter les App Intents de Safari hors Raccourcis ?
// Étape 1 : classes et sélecteurs liés à la connexion et à l'exécution d'actions.
import Foundation
import ObjectiveC

let chemin = "/System/Library/PrivateFrameworks/LinkServices.framework/LinkServices"
guard dlopen(chemin, RTLD_NOW) != nil else { print("dlopen KO : \(String(cString: dlerror()))"); exit(1) }
var n: UInt32 = 0
let image = "/System/Library/PrivateFrameworks/LinkServices.framework/Versions/A/LinkServices"
guard let noms = objc_copyClassNamesForImage(image, &n) ?? objc_copyClassNamesForImage(chemin, &n) else { print("aucune classe"); exit(1) }
let classes = (0..<Int(n)).map { String(cString: noms[$0]) }
print("\(classes.count) classes")
let cibles = classes.filter { ["Connection", "Executor", "ActionExecut", "ConnectionOperation"].contains(where: $0.contains) }.sorted()
print(cibles.joined(separator: ", "))
for c in ["LNConnection", "LNActionExecutor", "LNConnectionOptions", "LNMetadataProvider"] {
    guard let k = NSClassFromString(c) else { print("\(c) : absente"); continue }
    var m: UInt32 = 0
    let sels = (class_copyMethodList(k, &m).map { l in (0..<Int(m)).map { NSStringFromSelector(method_getName(l[$0])) } } ?? [])
    var mc: UInt32 = 0
    let cls = (class_copyMethodList(object_getClass(k), &mc).map { l in (0..<Int(mc)).map { "+" + NSStringFromSelector(method_getName(l[$0])) } } ?? [])
    let f = (cls + sels).filter { $0.contains("init") || $0.contains("xecut") || $0.contains("ction") || $0.contains("bundle") }
    print("\(c) : \(f.prefix(25).joined(separator: "  "))")
}
