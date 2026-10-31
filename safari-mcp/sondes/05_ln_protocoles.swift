// Sonde 05 : délégué d'exécution, gestionnaire de connexions, types de valeurs
import Foundation
import ObjectiveC
dlopen("/System/Library/PrivateFrameworks/LinkServices.framework/LinkServices", RTLD_NOW)
dlopen("/System/Library/PrivateFrameworks/LinkMetadata.framework/LinkMetadata", RTLD_NOW)
for p in ["LNActionExecutorDelegate"] {
    guard let pr = objc_getProtocol(p) else { print("\(p) absent"); continue }
    for req in [true, false] {
        var n: UInt32 = 0
        if let l = protocol_copyMethodDescriptionList(pr, req, true, &n) {
            print("\(p) \(req ? "requis" : "optionnel") : " + (0..<Int(n)).map { NSStringFromSelector(l[$0].name!) }.joined(separator: "  "))
        }
    }
}
for c in ["LNConnectionManager", "LNPrimitiveValueType", "LNMacApplicationConnection", "LNMetadataProvider"] {
    guard let k = NSClassFromString(c) else { print("\(c) absente"); continue }
    var mc: UInt32 = 0
    let s = class_copyMethodList(object_getClass(k), &mc).map { l in (0..<Int(mc)).map { "+" + NSStringFromSelector(method_getName(l[$0])) } } ?? []
    print("\(c) : " + s.prefix(30).joined(separator: "  "))
}
