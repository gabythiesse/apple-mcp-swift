// Sonde 04 : sélecteurs utiles pour construire et exécuter une LNAction
import Foundation
import ObjectiveC
dlopen("/System/Library/PrivateFrameworks/LinkServices.framework/LinkServices", RTLD_NOW)
dlopen("/System/Library/PrivateFrameworks/LinkMetadata.framework/LinkMetadata", RTLD_NOW)
func sels(_ c: String, _ f: (String) -> Bool) {
    guard let k = NSClassFromString(c) else { print("\(c) absente"); return }
    var m: UInt32 = 0, mc: UInt32 = 0
    let i = class_copyMethodList(k, &m).map { l in (0..<Int(m)).map { NSStringFromSelector(method_getName(l[$0])) } } ?? []
    let s = class_copyMethodList(object_getClass(k), &mc).map { l in (0..<Int(mc)).map { "+" + NSStringFromSelector(method_getName(l[$0])) } } ?? []
    print("\(c) : " + (s + i).filter(f).joined(separator: "  "))
}
sels("LNAction") { $0.contains("init") }
sels("LNActionExecutor") { $0.contains("perform") || $0.contains("xecute") || $0.contains("Delegate") }
sels("LNActionExecutorOptions") { $0.contains("init") || $0.hasPrefix("set") }
sels("LNConnectionManager") { $0.contains("onnection") }
sels("LNProperty") { $0.contains("init") }
sels("LNValue") { $0.contains("init") }
