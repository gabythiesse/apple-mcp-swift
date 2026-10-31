// screenshot (ScreenCaptureKit, autorisation « Enregistrement de l'écran » du lanceur) et windows (Accessibilité + WindowServer).
import Foundation
import AppKit
import ApplicationServices
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import MacUI

enum Screen {
    static let refus = "Screen Recording is not granted to AppleMCP: run ./installer.command once at the Mac (System Settings > Privacy & Security > Screen & System Audio Recording > AppleMCP). find and dialogs work without it"

    // MARK: - windows

    static func displays() -> [(id: CGDirectDisplayID, frame: CGRect, scale: CGFloat)] {
        var n: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &n)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
        CGGetActiveDisplayList(n, &ids, &n)
        let principal = CGMainDisplayID()
        return ids.sorted { a, _ in a == principal }.map { id in
            let b = CGDisplayBounds(id)
            let px = CGFloat(CGDisplayCopyDisplayMode(id)?.pixelWidth ?? Int(b.width))
            return (id, b, b.width > 0 ? px / b.width : 1)
        }
    }

    static func windows(_ a: JSON) throws -> Any {
        try AX.trusted()
        let filtre = a.nonEmpty("app").map { try? Apps.require($0) } ?? nil
        if a.nonEmpty("app") != nil && filtre == nil { _ = try Apps.require(a.req("app")) }
        var l: [String] = []
        let ds = displays()
        l.append("displays: " + ds.enumerated().map { i, d in "\(i + 1)\(i == 0 ? " main" : "") \(rect(d.frame)) @\(Int(d.scale))x" }.joined(separator: "; "))
        if Session.locked { l.append("! screen locked: real clicks and keys are impossible until unlocked") }
        let front = Front.frontPid
        let surEcran = Set(Dialogs.onScreenPids())
        let apps = Apps.running.filter { app in
            if let filtre { return app.processIdentifier == filtre.processIdentifier }
            return app.activationPolicy == .regular || (a.bool("all") == true && surEcran.contains(app.processIdentifier))
        }.sorted { ($0.processIdentifier == front ? 0 : 1, $0.localizedName ?? "") < ($1.processIdentifier == front ? 0 : 1, $1.localizedName ?? "") }
        for app in apps {
            let pid = app.processIdentifier
            var etat: [String] = []
            if pid == front { etat.append("front") }
            if app.isHidden { etat.append("hidden") }
            l.append("\(pid == front ? "*" : " ") \(app.localizedName ?? "?") pid=\(pid)\(etat.isEmpty ? "" : " " + etat.joined(separator: " "))")
            let axApp = AX.app(pid)
            let focus = AX.element(axApp, kAXFocusedWindowAttribute)
            for w in AX.attr(axApp, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                let v = AX.attrs(w, [kAXTitleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXMinimizedAttribute, kAXSubroleAttribute])
                var ligne = "    \(Refs.ref(w)) \"\((v[0] as? String ?? "").prefix(80))\""
                if let r = AX.frame(v[1], v[2]) { ligne += " \(rect(r))" }
                if let id = AX.windowID(w) { ligne += " id=\(id)" }
                if let sub = v[4] as? String, !["AXStandardWindow", ""].contains(sub) { ligne += " " + sub.replacingOccurrences(of: "AX", with: "").lowercased() }
                if v[3] as? Bool == true { ligne += " minimized" }
                if let focus, CFEqual(focus, w) { ligne += " focused" }
                if AX.children(w).contains(where: { AX.role($0) == "AXSheet" }) { ligne += " +sheet" }
                l.append(ligne)
            }
        }
        return l.joined(separator: "\n")
    }

    // MARK: - screenshot

    private static func attendre<T>(_ f: (@escaping (T?, Error?) -> Void) -> Void) throws -> T {
        let sem = DispatchSemaphore(value: 0)
        var r: T?, e: Error?
        f { v, err in r = v; e = err; sem.signal() }
        guard sem.wait(timeout: .now() + 8) == .success else { throw MCPError("screen capture timed out") }
        if let e { throw MCPError("screen capture failed: \(e.localizedDescription)") }
        guard let r else { throw MCPError("screen capture returned nothing") }
        return r
    }

    static func png(_ img: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw MCPError("PNG encoder unavailable") }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw MCPError("PNG encoding failed") }
        return data as Data
    }

    /// Fenêtre CG désignée : window (id de windows), ref d'une fenêtre, ou app (+ title) → sa fenêtre de devant
    static func fenetreCible(_ a: JSON) throws -> (CGWindowID, pid_t)? {
        if let id = a.int("window") { return (CGWindowID(id), 0) }
        if let r = a.nonEmpty("ref") {
            let el = try Refs.get(r)
            guard let w = AX.window(of: el), let id = AX.windowID(w) else { throw MCPError("ref \(r) has no window") }
            return (id, AX.pid(el))
        }
        guard let q = a.nonEmpty("app") else { return nil }
        let app = try Apps.require(q)
        let ws = AX.windows(app.processIdentifier)
        let t = a.nonEmpty("title").map(normalise)
        guard let w = ws.first(where: { t == nil || normalise(AX.str($0, kAXTitleAttribute)).contains(t!) }) else {
            throw MCPError("\(app.localizedName ?? q) has no \(t == nil ? "" : "matching ")window")
        }
        guard let id = AX.windowID(w) else { throw MCPError("window id unavailable") }
        return (id, app.processIdentifier)
    }

    static func screenshot(_ a: JSON) throws -> Any {
        // Jamais de fenêtre macOS pendant un outil : sans l'autorisation, on refuse avant d'appeler ScreenCaptureKit
        guard CGPreflightScreenCaptureAccess() else { throw MCPError(refus) }
        let contenu: SCShareableContent = try attendre { cb in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { c, e in cb(c, e) }
        }
        let ds = displays()
        var zone: CGRect      // en points écran globaux
        var fenetres: [SCWindow]? = nil
        if let (id, pid) = try fenetreCible(a) {
            guard let w = contenu.windows.first(where: { $0.windowID == id }) else { throw MCPError("window \(id) is not on screen (minimized, hidden or on another Space)") }
            zone = w.frame
            let proprio = pid != 0 ? pid : (w.owningApplication?.processID ?? 0)
            // La fenêtre, ses feuilles et panneaux (y compris ceux des services hors processus, comme Enregistrer sous)
            fenetres = contenu.windows.filter { x in
                let b = x.owningApplication?.bundleIdentifier ?? ""
                return x.owningApplication?.processID == proprio || ((b.hasPrefix("com.apple.appkit.xpc") || b.contains("ViewService")) && x.frame.intersects(zone))
            }
        } else if let r = a.object("region"), let w = (r["width"] as? NSNumber)?.doubleValue, let h = (r["height"] as? NSNumber)?.doubleValue {
            zone = CGRect(x: (r["x"] as? NSNumber)?.doubleValue ?? 0, y: (r["y"] as? NSNumber)?.doubleValue ?? 0, width: w, height: h)
        } else {
            let i = max(1, a.int("display") ?? 1)
            guard i <= ds.count else { throw MCPError("display \(i) not found (\(ds.count) connected)") }
            zone = ds[i - 1].frame
        }
        // Écran qui contient le centre de la zone ; la zone est rognée à cet écran
        guard let d = ds.first(where: { $0.frame.contains(CGPoint(x: zone.midX, y: zone.midY)) }) ?? ds.first,
              let scd = contenu.displays.first(where: { $0.displayID == d.id }) else { throw MCPError("no display") }
        zone = zone.intersection(d.frame)
        guard !zone.isNull, zone.width >= 1, zone.height >= 1 else { throw MCPError("the region is off screen") }
        // Échelle : pixels d'image par point écran ; par défaut 1, réduite pour que le grand côté tienne en 1568 px
        let maxi = CGFloat(a.has("scale") ? 4096 : 1568)
        var k = CGFloat(a.double("scale") ?? 1)
        k = max(0.1, min(k, d.scale, maxi / max(zone.width, zone.height)))
        let conf = SCStreamConfiguration()
        conf.sourceRect = CGRect(x: zone.minX - d.frame.minX, y: zone.minY - d.frame.minY, width: zone.width, height: zone.height)
        conf.width = Int((zone.width * k).rounded())
        conf.height = Int((zone.height * k).rounded())
        conf.showsCursor = a.bool("cursor") ?? false
        conf.captureResolution = .best
        let filtre = fenetres.map { SCContentFilter(display: scd, including: $0) } ?? SCContentFilter(display: scd, excludingWindows: [])
        let img: CGImage = try attendre { cb in SCScreenshotManager.captureImage(contentFilter: filtre, configuration: conf) { i, e in cb(i, e) } }
        let data = try png(img)
        if let p = a.nonEmpty("path") {
            let u = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            try data.write(to: u)
        }
        let legende = "\(img.width)x\(img.height) px showing screen points \(rect(zone)); screen point = (\(entier(zone.minX)) + px/\(fmt(k)), \(entier(zone.minY)) + py/\(fmt(k)))"
        return Contenu.image(data, legende)
    }

    static func fmt(_ k: CGFloat) -> String { k == k.rounded() ? String(Int(k)) : String(format: "%.3g", Double(k)) }
}
