// Sonde 20 : comment obtenir une instance WBSHistory hors de Safari (init, connexion au service)
import Foundation
import ObjectiveC
_ = dlopen("/System/Library/PrivateFrameworks/SafariShared.framework/SafariShared", RTLD_NOW)
func meths(_ name: String, _ filtre: (String) -> Bool) {
  guard let c = NSClassFromString(name) else { print("✗ \(name)"); return }
  var out: [String] = []
  for meta in [false, true] {
    let k: AnyClass = meta ? object_getClass(c)! : c
    var m: UInt32 = 0
    if let ms = class_copyMethodList(k, &m) { for x in 0..<Int(m) { let s = NSStringFromSelector(method_getName(ms[x])); if filtre(s) { out.append((meta ? "+" : "-") + s) } } }
  }
  print("\(name) < \(class_getSuperclass(c).map { NSStringFromClass($0) } ?? "")> : " + out.joined(separator: " "))
}
let initish: (String) -> Bool = { $0.hasPrefix("init") || $0.hasPrefix("+") || $0.lowercased().contains("load") || $0.contains("Connection") || $0.contains("connect") || $0.contains("itemFor") || $0.contains("allItems") || $0.contains("ItemsMatching") || $0.contains("visitedLinks") }
for c in ["WBSHistory", "WBSHistoryController", "WBSHistoryServiceStore", "WBSHistoryConnectionProxy", "WBSHistoryServiceProxy", "WBSHistoryConnection", "WBSHistoryStore", "WBSHistorySQLiteStore"] { meths(c, initish) }
