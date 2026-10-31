// Débogage (outil _inspect, non listé) : tous les attributs AX d'un élément
import Foundation
import ApplicationServices
import MacUI

enum Debug {
    static func cg(_ a: JSON) throws -> Any {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let filtre = try a.nonEmpty("app").map { try Apps.require($0).processIdentifier }
        var ax: pid_t = 0
        if let f = AX.element(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute) { ax = AX.pid(f) }
        var l = ["ax focused app: \(Apps.name(ax)) | isActive: \(Running.apps().filter { $0.isActive }.map { $0.localizedName ?? "?" })"]
        for i in infos {
            let p = (i[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) ?? 0
            if let filtre, p != filtre { continue }
            let b = (i[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            l.append("\(i[kCGWindowNumber as String] ?? 0) \(i[kCGWindowOwnerName as String] ?? "?") layer=\(i[kCGWindowLayer as String] ?? 0) \(rect(b)) alpha=\(i[kCGWindowAlpha as String] ?? 1)")
        }
        return l.prefix(40).joined(separator: "\n")
    }
    static func inspect(_ a: JSON) throws -> Any {
        let el: AXUIElement
        if let r = a.nonEmpty("ref") { el = try Refs.get(r) }
        else { let app = try Apps.target(a); guard let w = AX.windows(app.processIdentifier).first else { throw MCPError("no window") }; el = w }
        var noms: CFArray?
        AXUIElementCopyAttributeNames(el, &noms)
        var l: [String] = ["pid=\(AX.pid(el)) actions=\(AX.actions(el))"]
        for n in (noms as? [String] ?? []) where n != kAXChildrenAttribute {
            let v = AX.attr(el, n)
            var s = v.map { "\($0)" } ?? "nil"
            if let v, CFGetTypeID(v) == AXUIElementGetTypeID() { s = Refs.ref(v as! AXUIElement) + " " + decrire(v as! AXUIElement) }
            l.append("\(n) = \(s.replacingOccurrences(of: "\n", with: " ").prefix(120))")
        }
        return l.joined(separator: "\n")
    }
}
