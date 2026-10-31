// Sonde 21 : WBSHistoryController hors Safari → WBSHistory chargé via le service ; lecture d'UN élément de test.
// Lecture seule. Affiche aussi les méthodes « Visit » de WBSHistory / WBSHistoryItem.
import Foundation
import ObjectiveC
_ = dlopen("/System/Library/PrivateFrameworks/SafariShared.framework/SafariShared", RTLD_NOW)
func sels(_ c: AnyClass, _ f: (String) -> Bool) -> [String] {
  var m: UInt32 = 0; var out: [String] = []
  if let ms = class_copyMethodList(c, &m) { for x in 0..<Int(m) { let s = NSStringFromSelector(method_getName(ms[x])); if f(s) { out.append(s) } } }
  return out
}
print("WBSHistory visits:", sels(NSClassFromString("WBSHistory")!, { $0.contains("isit") && !$0.hasPrefix("_") }))
print("WBSHistoryItem:", sels(NSClassFromString("WBSHistoryItem")!, { !$0.hasPrefix("_") && !$0.hasPrefix("set") }).prefix(60))
let ctrlC = NSClassFromString("WBSHistoryController") as! NSObject.Type
let ctrl = ctrlC.init()
let t0 = Date()
for pid in ["DefaultProfile", ""] {
  let h = ctrl.perform(NSSelectorFromString("historyForProfileIdentifier:loadIfNeeded:"), with: pid, with: true)?.takeUnretainedValue() as? NSObject
  print("profil '\(pid)':", h.map { "\($0)" } ?? "nil")
  guard let h else { continue }
  h.perform(NSSelectorFromString("waitUntilHistoryHasLoaded"))
  print("chargé en \(Int(Date().timeIntervalSince(t0)*1000)) ms")
  let url = "file://" + URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("mcp-test-2.html").path
  let it = h.perform(NSSelectorFromString("itemForURLString:"), with: url)?.takeUnretainedValue() as? NSObject
  print("item test:", it.map { "\($0) visitCount=\($0.value(forKey: "visitCount") ?? "?") title=\($0.value(forKey: "title") ?? "?")" } ?? "nil")
  break
}
