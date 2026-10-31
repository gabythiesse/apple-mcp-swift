// `AppleMCP permissions [--request]`: checks, or requests with --request, every macOS permission the six servers need.
// It runs inside the launcher after it became its own responsible process, so macOS sees exactly the identity the
// servers run under. The list and the code behind each line: docs/permissions.md (keep both in sync).
// Without --request nothing here can open a window: status APIs only, Automation checked with askUserIfNeeded = false,
// and the folders behind Full Disk Access are only touched once Full Disk Access is on.
import Foundation
import EventKit
import Contacts
import ApplicationServices

enum Permissions {
    enum Etat { case ok, refuse, inconnu }

    struct Service {
        let nom: String
        let pour: String
        let reglage: String   // System Settings pane (x-apple.systempreferences anchor)
        let consigne: String  // exactly which switch to turn on
        let verifier: () -> Etat
        let demander: () -> Void   // shows the macOS prompt when the state is still "not asked"; no-op otherwise
    }

    static let home = NSHomeDirectory()

    // MARK: probes

    static func eventKit(_ type: EKEntityType) -> Etat {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: return .ok
        case .notDetermined: return .inconnu
        default: return .refuse
        }
    }
    static func demanderEventKit(_ type: EKEntityType) {
        guard eventKit(type) == .inconnu else { return }
        let sem = DispatchSemaphore(value: 0)
        let store = EKEventStore()
        if type == .reminder { store.requestFullAccessToReminders { _, _ in sem.signal() } }
        else { store.requestFullAccessToEvents { _, _ in sem.signal() } }
        sem.wait()
    }

    static func contacts() -> Etat {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return .ok
        case .notDetermined: return .inconnu
        default: return .refuse
        }
    }
    static func demanderContacts() {
        guard contacts() == .inconnu else { return }
        let sem = DispatchSemaphore(value: 0)
        CNContactStore().requestAccess(for: .contacts) { _, _ in sem.signal() }
        sem.wait()
    }

    /// Automation (Apple Events) towards an app. The target must be running: it is launched hidden, in the background.
    static func automation(_ bundle: String, demander: Bool) -> Etat {
        let cible = NSAppleEventDescriptor(bundleIdentifier: bundle)
        let wildcard = AEEventClass(0x2A2A_2A2A)   // '****': any event
        var st = AEDeterminePermissionToAutomateTarget(cible.aeDesc, wildcard, wildcard, false)
        if st == OSStatus(procNotFound) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-g", "-j", "-b", bundle]
            p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
            for _ in 0..<60 where st == OSStatus(procNotFound) {
                usleep(250_000)
                st = AEDeterminePermissionToAutomateTarget(cible.aeDesc, wildcard, wildcard, false)
            }
        }
        if demander && st == OSStatus(errAEEventWouldRequireUserConsent) {
            st = AEDeterminePermissionToAutomateTarget(cible.aeDesc, wildcard, wildcard, true)
        }
        switch st {
        case noErr: return .ok
        case OSStatus(errAEEventWouldRequireUserConsent), OSStatus(procNotFound): return .inconnu
        default: return .refuse
        }
    }

    static func accessibilite() -> Etat { AXIsProcessTrusted() ? .ok : .refuse }
    static func demanderAccessibilite() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Full Disk Access has no prompt: macOS just refuses. TCC.db is the usual witness (readable only with Full Disk Access).
    /// Once it is on, the folders the servers actually read are checked too (they would prompt without it, never with it).
    static let dossiers = [
        "Library/Mail", "Library/Containers/com.apple.mail/Data",
        "Library/Group Containers/group.com.apple.notes",
        "Library/Safari", "Library/Containers/com.apple.Safari/Data/Library/Safari",
        "Downloads", "Desktop", "Documents",
    ]
    static var dossiersBloques: [String] = []
    static func disqueComplet() -> Etat {
        let fd = open(home + "/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard fd >= 0 else { return .refuse }
        close(fd)
        dossiersBloques = dossiers.filter { d in
            do { _ = try FileManager.default.contentsOfDirectory(atPath: home + "/" + d); return false }
            catch { return ((error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError)?.code != Int(ENOENT) }
        }
        return dossiersBloques.isEmpty ? .ok : .refuse
    }

    // MARK: inventory (docs/permissions.md)

    static let services: [Service] = [
        Service(nom: "Reminders", pour: "reminders", reglage: "Privacy_Reminders",
                consigne: "Reminders > turn on \"AppleMCP\"", verifier: { eventKit(.reminder) }, demander: { demanderEventKit(.reminder) }),
        Service(nom: "Calendars", pour: "calendar", reglage: "Privacy_Calendars",
                consigne: "Calendars > set \"AppleMCP\" to Full Access", verifier: { eventKit(.event) }, demander: { demanderEventKit(.event) }),
        Service(nom: "Contacts", pour: "contacts", reglage: "Privacy_Contacts",
                consigne: "Contacts > turn on \"AppleMCP\"", verifier: contacts, demander: demanderContacts),
    ] + [("Mail", "com.apple.mail", "mail"), ("Notes", "com.apple.Notes", "notes"), ("Safari", "com.apple.Safari", "safari"),
         ("Contacts", "com.apple.AddressBook", "contacts"), ("System Events", "com.apple.systemevents", "mail (delete_mailboxes)")]
        .map { app, bundle, pour in
            Service(nom: "Automation → \(app)", pour: pour, reglage: "Privacy_Automation",
                    consigne: "Automation > AppleMCP > turn on \"\(app)\"",
                    verifier: { automation(bundle, demander: false) }, demander: { _ = automation(bundle, demander: true) })
        } + [
        Service(nom: "Accessibility", pour: "safari (private windows, deletions), mail (delete_mailboxes)", reglage: "Privacy_Accessibility",
                consigne: "Accessibility > turn on \"AppleMCP\"", verifier: accessibilite, demander: demanderAccessibilite),
        Service(nom: "Full Disk Access", pour: "mail, notes, safari, file paths (attachments, vCard, images)", reglage: "Privacy_AllFiles",
                consigne: "Full Disk Access > turn on \"AppleMCP\" (not in the list? drag bin/AppleMCP into it)",
                verifier: disqueComplet, demander: {}),
    ]

    // MARK: run

    static func ouvrirReglage(_ ancre: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["x-apple.systempreferences:com.apple.preference.security?\(ancre)"]
        try? p.run(); p.waitUntilExit()
    }

    /// Prints the ✓/✗ table. Returns 0 when everything is granted.
    static func tableau() -> Int32 {
        var manquants = 0
        for s in services {
            let e = s.verifier()
            if e != .ok { manquants += 1 }
            let nom = s.nom.padding(toLength: 28, withPad: " ", startingAt: 0)
            print("  \(e == .ok ? "✓" : "✗") \(nom) \(s.pour)")
            if e == .inconnu { print("      → never asked yet: run ./installer.command") }
            if e == .refuse {
                print("      → System Settings > Privacy & Security > \(s.consigne)")
                if s.nom == "Full Disk Access", !dossiersBloques.isEmpty { print("        still blocked: ~/\(dossiersBloques.joined(separator: ", ~/"))") }
            }
        }
        print(manquants == 0 ? "\n  ✓ all \(services.count) permissions granted" : "\n  ✗ \(manquants) of \(services.count) missing")
        return manquants == 0 ? 0 : 1
    }

    /// Asks for each missing permission in turn: macOS prompt when it can, otherwise opens the right pane and waits
    /// (up to 3 minutes each) until the switch is on. Already granted permissions are skipped, so a rerun only redoes what is missing.
    static func demanderTout() {
        for s in services where s.verifier() != .ok {
            print("→ \(s.nom) (\(s.pour))", terminator: ""); fflush(stdout)
            s.demander()
            if s.verifier() == .ok { print(": ✓"); continue }
            if s.nom == "Full Disk Access" {
                let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-R", exe]   // in Finder, ready to drag into the list if AppleMCP is not there yet
                try? p.run(); p.waitUntilExit()
            }
            ouvrirReglage(s.reglage)
            print("\n   System Settings > Privacy & Security > \(s.consigne)\n   waiting for the switch…", terminator: ""); fflush(stdout)
            var ok = false
            for _ in 0..<180 { if s.verifier() == .ok { ok = true; break }; sleep(1) }
            print(ok ? " ✓" : " still off, moving on")
        }
    }

    static func run(request: Bool) -> Int32 {
        if request { demanderTout(); print("") }
        return tableau()
    }
}
