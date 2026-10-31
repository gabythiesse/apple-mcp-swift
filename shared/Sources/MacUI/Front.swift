// Session et premier plan : l'app ciblée passe devant, l'action a lieu, le premier plan revient à l'app d'avant.
import Foundation
import AppKit
import ApplicationServices

public enum Session {
    private static var dict: [String: Any] { CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:] }
    /// Écran de connexion devant (Mac verrouillé) : aucun événement réel n'atteint les apps
    public static var locked: Bool { dict["CGSSessionScreenIsLocked"] as? Bool == true }
    /// Session graphique active (pas d'autre utilisateur devant, via le changement rapide d'utilisateur)
    public static var onConsole: Bool { dict.isEmpty ? false : (dict[kCGSessionOnConsoleKey as String] as? Bool ?? true) }
    public static let lockedMessage = "the Mac's screen is locked: real clicks and keys cannot reach any app until the session is unlocked"
    public static let offConsole = "no active graphical session (another user is in front, or nobody is logged in): nothing can be clicked"

    /// Erreur si rien ne peut atteindre l'écran
    public static func check() throws {
        if !onConsole { throw UIError(offConsole) }
        if locked { throw UIError(lockedMessage) }
    }
}

/// Apps en cours, lues à neuf à chaque appel. Dans un processus sans NSApplication, NSWorkspace.runningApplications,
/// frontmostApplication et les propriétés d'un NSRunningApplication déjà obtenu restent figés (sondé le 2026-10-31 :
/// une app lancée après le démarrage n'y apparaît jamais) ; une instance neuve par pid est exacte et coûte ~3 ms pour toutes.
public enum Running {
    public static func pids() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var buf = [pid_t](repeating: 0, count: Int(n) + 64)
        let k = proc_listallpids(&buf, Int32(buf.count * MemoryLayout<pid_t>.size))
        return Array(buf.prefix(Int(max(0, k))))
    }
    public static func apps() -> [NSRunningApplication] {
        let moi = getpid()
        return pids().compactMap { $0 == moi ? nil : NSRunningApplication(processIdentifier: $0) }
    }
    public static func app(_ pid: pid_t) -> NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }
    public static func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
    public static func byBundle(_ id: String) -> NSRunningApplication? { NSRunningApplication.runningApplications(withBundleIdentifier: id).first }
    public static var front: NSRunningApplication? { apps().first { $0.isActive } }
}

public enum Front {
    /// App qui reçoit le clavier : celle que l'Accessibilité donne comme focalisée (vérité du WindowServer),
    /// sinon celle que LaunchServices dit active
    public static var frontPid: pid_t? {
        if AXIsProcessTrusted(), let f = AX.element(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute) {
            let p = AX.pid(f)
            if p > 0 { return p }
        }
        return Running.front?.processIdentifier
    }
    public static var frontmost: NSRunningApplication? { frontPid.flatMap(Running.app) }

    /// Amène l'app au premier plan (Accessibilité d'abord, plus fiable que l'activation coopérative de macOS 14+),
    /// attend que macOS le confirme. Renvoie false si elle n'est pas passée devant.
    @discardableResult
    public static func activate(_ pid: pid_t, timeout: TimeInterval = 1.0) -> Bool {
        if frontPid == pid { return true }
        guard let app = Running.app(pid) else { return false }
        if app.isHidden { app.unhide() }
        AX.set(AX.app(pid), kAXFrontmostAttribute, kCFBooleanTrue)
        if !AX.attendre(min(0.4, timeout), every: 0.02, { frontPid == pid }) {
            app.activate(options: [.activateAllWindows])
            _ = AX.attendre(timeout, every: 0.02) { frontPid == pid }
        }
        if frontPid == pid { Thread.sleep(forTimeInterval: 0.06); return true }   // le temps que la fenêtre clé se règle
        return false
    }

    /// Fenêtre devant les autres fenêtres de son app (et fenêtre principale)
    public static func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AX.set(window, kAXMainAttribute, kCFBooleanTrue)
    }

    /// Exécute `body` avec l'app `pid` au premier plan, puis rend le premier plan à l'app d'avant
    /// (sauf keep, ou si un menu reste ouvert dans l'app : le rendre le fermerait). Renvoie aussi si le premier plan a été rendu.
    public static func with<T>(_ pid: pid_t, window: AXUIElement? = nil, keep: Bool = false, _ body: () throws -> T) throws -> (T, restored: Bool) {
        try Session.check()
        guard Input.canPost() else { throw UIError(AX.denied) }
        humanPause()
        let avant = frontmost
        if let window { raise(window) }
        guard activate(pid) else {
            let nom = Running.app(pid)?.localizedName ?? "the app"
            throw UIError("\(nom) could not be brought to the front: real events not sent")
        }
        // Le focus clavier du système doit être dans l'app (l'activation se termine un peu après que macOS la déclare)
        _ = AX.attendre(0.5, every: 0.02) {
            AX.element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute).map { AX.pid($0) == pid } ?? true
        }
        // La fenêtre visée doit être la fenêtre clé de l'app : sinon les touches iraient dans une autre fenêtre
        if let window, let f = AX.element(AX.app(pid), kAXFocusedWindowAttribute), !CFEqual(f, window) {
            raise(window)
            _ = AX.attendre(0.5, every: 0.03) { AX.element(AX.app(pid), kAXFocusedWindowAttribute).map { CFEqual($0, window) } ?? false }
        }
        let r = try body()
        var rendu = false
        if !keep, let avant, avant.processIdentifier != pid, Running.alive(avant.processIdentifier), !menuOpen(pid, settle: 0.3) {
            Thread.sleep(forTimeInterval: 0.12)   // l'app traite les événements avant de perdre le premier plan
            rendu = activate(avant.processIdentifier, timeout: 0.6)
        }
        return (r, rendu)
    }

    /// Quelqu'un tape ou clique en ce moment : attendre une courte accalmie (3 s au plus) avant de prendre le premier plan,
    /// pour ne pas recevoir ses frappes dans l'app ciblée ni envoyer les nôtres dans la sienne
    public static func humanPause(max: TimeInterval = 3) {
        let fin = Date().addingTimeInterval(max)
        while Date() < fin {
            let k = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
            let m = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseDown)
            if k > 0.8 && m > 0.5 { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Un menu (barre des menus, contextuel, local) est ouvert dans l'app : fenêtre WindowServer au niveau des menus
    /// settle : laisse le temps à un menu qui se referme (animation) de disparaître avant de conclure
    public static func menuOpen(_ pid: pid_t, settle: TimeInterval = 0) -> Bool {
        func ouvert() -> Bool {
            let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let niveau = Int(CGWindowLevelForKey(.popUpMenuWindow))
            return infos.contains { ($0[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid && ($0[kCGWindowLayer as String] as? Int ?? 0) == niveau }
        }
        return settle > 0 ? !AX.attendre(settle, every: 0.05) { !ouvert() } : ouvert()
    }
}
