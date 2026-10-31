// Sonde 07 : classe attendue pour l'« effective bundle identifier »
import Foundation
import ObjectiveC
for f in ["LinkServices", "LinkMetadata"] {
    let p = "/System/Library/PrivateFrameworks/\(f).framework/Versions/A/\(f)"
    dlopen(p, RTLD_NOW)
    var n: UInt32 = 0
    guard let l = objc_copyClassNamesForImage(p, &n) else { continue }
    for i in 0..<Int(n) {
        let nm = String(cString: l[i])
        guard nm.contains("BundleIdentifier") || nm.contains("UserIdentity"), let k = NSClassFromString(nm) else { continue }
        var m: UInt32 = 0, mc: UInt32 = 0
        let s = (class_copyMethodList(object_getClass(k), &mc).map { l in (0..<Int(mc)).map { "+" + NSStringFromSelector(method_getName(l[$0])) } } ?? [])
        let ii = (class_copyMethodList(k, &m).map { l in (0..<Int(m)).map { NSStringFromSelector(method_getName(l[$0])) } } ?? []).filter { $0.contains("init") || $0 == "type" }
        print("\(nm) : " + (s + ii).joined(separator: "  "))
    }
}
