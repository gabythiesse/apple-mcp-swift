// Sonde 23 : WBSHistory(initWithDatabaseID:) → passe-t-il par le service XPC (et pas le repli en processus) ? Lecture d'un élément de test.
import Foundation
import ObjectiveC
_ = dlopen("/System/Library/PrivateFrameworks/SafariShared.framework/SafariShared", RTLD_NOW)
func iv(_ o: AnyObject, _ n: String) -> Any? { guard let v = class_getInstanceVariable(object_getClass(o)!, n) else { return "∄" }; return object_getIvar(o, v) }
let id = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let H = NSClassFromString("WBSHistory") as! NSObject.Type
let h = (H.perform(NSSelectorFromString("alloc")).takeUnretainedValue() as! NSObject).perform(NSSelectorFromString("initWithDatabaseID:"), with: id).takeUnretainedValue() as! NSObject
let t0 = Date()
h.perform(NSSelectorFromString("loadHistoryAsynchronouslyIfNeeded"))
h.perform(NSSelectorFromString("waitUntilHistoryHasLoaded"))
print("chargé \(Int(Date().timeIntervalSince(t0)*1000)) ms")
if let store = iv(h, "_historyStore") as AnyObject? {
  print("store:", type(of: store))
  if let px = iv(store, "_connectionProxy") as AnyObject? { print("xpc:", iv(px, "_connection").map { "\($0)" } ?? "nil", "| repli:", iv(px, "_inProcessFallbackService").map { "\($0)" } ?? "nil") }
}
let all = h.perform(NSSelectorFromString("allItems"))?.takeUnretainedValue() as? [AnyObject]
print("nb éléments:", all?.count ?? -1)
let it = h.perform(NSSelectorFromString("itemForURLString:"), with: "file://" + URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("mcp-test-2.html").path)?.takeUnretainedValue() as? NSObject
print("item test:", it.map { "visitCount=\($0.value(forKey: "visitCount") ?? "?") title=\($0.value(forKey: "title") ?? "?") visits=\(($0.value(forKey: "visits") as? NSArray)?.count ?? -1)" } ?? "nil")
