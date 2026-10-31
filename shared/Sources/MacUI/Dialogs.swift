// Fenêtres qui attendent une réponse, dans toutes les apps : alertes, feuilles (Enregistrer sous, Autoriser les
// téléchargements, Quitter la page), panneaux modaux, fenêtres des agents système (CoreServicesUIAgent…).
// Repérées par l'Accessibilité parmi les apps qui ont une fenêtre à l'écran ; répondues par AXPress, vrai clic sinon.
import Foundation
import AppKit
import ApplicationServices

public struct Dialog {
    public let element: AXUIElement      // la feuille, ou la fenêtre elle-même
    public let pid: pid_t
    public let app: String
    public let bundle: String
    public let kind: String               // sheet, dialog, system
    public let title: String
    public let text: String
    public let buttons: [(title: String, el: AXUIElement)]
    public let defaultButton: String?
    public let cancelButton: String?
    public let fields: [(label: String, value: String, el: AXUIElement)]
    public let password: Bool             // contient un champ mot de passe
    public let secure: Bool               // fenêtre de confidentialité ou de mot de passe de macOS : ignore les clics synthétiques
    public var key: AXKey { AXKey(element) }
}

public enum Dialogs {
    /// Agents système dont les fenêtres refusent les événements synthétiques (confidentialité TCC, mot de passe, Touch ID)
    public static let secureBundles: Set<String> = [
        "com.apple.SecurityAgent", "com.apple.coreautha", "com.apple.LocalAuthentication.UIAgent", "com.apple.UserNotificationCenter",
        "com.apple.accessibility.universalAccessAuthWarn", "com.apple.TCC", "com.apple.tccd",
    ]
    /// Jamais des dialogues : barre des menus, Dock, Centre de contrôle, notifications…
    static let ignores: Set<String> = [
        "com.apple.dock", "com.apple.WindowManager", "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.Spotlight",
        "com.apple.systemuiserver", "com.apple.TextInputMenuAgent", "com.apple.TextInputSwitcher", "com.apple.wallpaper.agent",
        "com.apple.loginwindow", "com.apple.screencaptureui",
    ]
    public static let secureMessage = "this is a macOS privacy or password window: macOS ignores synthetic clicks there by design; it is answered once at install (./installer.command) or needs the Mac's password"

    /// Processus qui ont au moins une fenêtre à l'écran (WindowServer, sans autorisation)
    public static func onScreenPids() -> [pid_t] {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var vus = Set<pid_t>(), out: [pid_t] = []
        let moi = getpid()
        for i in infos {
            guard let p = (i[kCGWindowOwnerPID as String] as? Int).map(pid_t.init), p != moi, !vus.contains(p) else { continue }
            let couche = i[kCGWindowLayer as String] as? Int ?? 0
            if couche >= Int(CGWindowLevelForKey(.mainMenuWindow)) && couche != Int(CGWindowLevelForKey(.modalPanelWindow)) { continue }
            vus.insert(p); out.append(p)
        }
        return out
    }

    /// Signature des fenêtres à l'écran : change dès qu'une fenêtre (feuille, alerte) apparaît ou disparaît
    public static func windowSignature() -> Set<Int> {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(infos.compactMap { $0[kCGWindowNumber as String] as? Int })
    }

    /// Toutes les fenêtres en attente de réponse ; pids nil = toutes les apps à l'écran
    public static func scan(pids: [pid_t]? = nil) -> [Dialog] {
        var out: [Dialog] = []
        for pid in pids ?? onScreenPids() {
            guard let app = Running.app(pid) else { continue }
            let bundle = app.bundleIdentifier ?? ""
            if ignores.contains(bundle) { continue }
            let nom = app.localizedName ?? bundle
            let agent = app.activationPolicy != .regular
            for w in AX.attr(AX.app(pid), kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                let sub = AX.subrole(w)
                let modal = AX.attr(w, kAXModalAttribute) as? Bool == true
                // Panneaux de fichiers non modaux (Ouvrir de TextEdit au lancement) : fenêtre ordinaire, identifiant open-panel / save-panel,
                // contenu servi par le processus openAndSavePanelService ; ou fenêtre avec bouton par défaut et bouton Annuler
                let ident = AX.ident(w)
                let panneau = ident.hasSuffix("-panel") || (AX.element(w, kAXDefaultButtonAttribute) != nil && AX.element(w, kAXCancelButtonAttribute) != nil)
                let estDialogue = ["AXDialog", "AXSystemDialog"].contains(sub) || modal || panneau || secureBundles.contains(bundle)
                if estDialogue || agent, let d = lire(w, pid: pid, app: nom, bundle: bundle, kind: agent ? "system" : panneau && !modal && sub == "AXStandardWindow" ? "panel" : "dialog"),
                   estDialogue || !d.buttons.isEmpty {
                    out.append(d)
                }
                feuilles(w, pid: pid, app: nom, bundle: bundle, &out)
            }
        }
        return out
    }

    private static func feuilles(_ parent: AXUIElement, pid: pid_t, app: String, bundle: String, _ out: inout [Dialog]) {
        for c in AX.children(parent) where AX.role(c) == "AXSheet" {
            if let d = lire(c, pid: pid, app: app, bundle: bundle, kind: "sheet") { out.append(d) }
            feuilles(c, pid: pid, app: app, bundle: bundle, &out)   // feuille sur feuille (« Remplacer ? » sur Enregistrer sous)
        }
    }

    static let fenetreBoutons: Set<String> = ["AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton", "AXToolbarButton"]
    static let sansDescendre: Set<String> = ["AXOutline", "AXTable", "AXBrowser", "AXList", "AXWebArea", "AXGrid", "AXSheet", "AXMenu", "AXMenuBar"]

    /// Lit une feuille ou une fenêtre : titre, texte, boutons, champs (parcours en largeur, borné)
    public static func lire(_ el: AXUIElement, pid: pid_t, app: String, bundle: String, kind: String) -> Dialog? {
        var textes: [String] = [], boutons: [(String, AXUIElement)] = [], champs: [(String, String, AXUIElement)] = []
        var motDePasse = false
        var hauts: [CGFloat] = []
        var file = AX.children(el).map { ($0, 1) }, n = 0
        while !file.isEmpty && n < 400 {
            let (e, prof) = file.removeFirst(); n += 1
            let v = AX.attrs(e, [kAXRoleAttribute, kAXSubroleAttribute, kAXValueAttribute])
            let role = v[0] as? String ?? "", sub = v[1] as? String ?? ""
            switch role {
            case "AXStaticText":
                if let s = v[2] as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty, textes.count < 12 { textes.append(s); hauts.append(AX.point(e)?.y ?? 1e6) }
            case "AXTextArea":
                if let s = v[2] as? String, !s.isEmpty, AX.attr(e, "AXEditable") as? Bool != true, textes.count < 12 { textes.append(s); hauts.append(AX.point(e)?.y ?? 1e6) }
                else { champs.append((AX.label(e), v[2] as? String ?? "", e)) }
            case "AXButton":
                let t = AX.label(e)
                if !t.isEmpty, !fenetreBoutons.contains(sub), boutons.count < 16, !boutons.contains(where: { $0.0 == t }) { boutons.append((t, e)) }
            case "AXTextField", "AXComboBox", "AXSearchField":
                if sub == "AXSecureTextField" { motDePasse = true }
                let l = AX.label(e)
                champs.append((l.isEmpty ? AX.str(e, kAXPlaceholderValueAttribute) : l, sub == "AXSecureTextField" ? "" : (v[2] as? String ?? ""), e))
            default: break
            }
            if prof < 12, !sansDescendre.contains(role) { file += AX.children(e).map { ($0, prof + 1) } }
        }
        // Ordre visuel (de haut en bas) ; le titre est le premier texte qui fait une phrase (« Où : » n'en est pas une)
        textes = zip(textes, hauts).enumerated().sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }.map { $0.element.0 }
        let titreFenetre = AX.str(el, kAXTitleAttribute)
        let iTitre = textes.firstIndex { $0.count >= 12 } ?? 0
        let titre = titreFenetre.isEmpty ? (textes.isEmpty ? "" : textes[iTitre]) : titreFenetre
        var reste = textes
        if titreFenetre.isEmpty, !reste.isEmpty { reste.remove(at: iTitre) }
        let parDefaut = AX.element(el, kAXDefaultButtonAttribute).map(AX.label)
        let annuler = AX.element(el, kAXCancelButtonAttribute).map(AX.label)
        if boutons.isEmpty && champs.isEmpty && textes.isEmpty { return nil }
        let texte = reste.joined(separator: " · ")
        return Dialog(element: el, pid: pid, app: app, bundle: bundle, kind: secureBundles.contains(bundle) ? "system" : kind,
                      title: String(titre.prefix(160)), text: String(texte.prefix(300)), buttons: boutons,
                      defaultButton: parDefaut, cancelButton: annuler, fields: champs.map { (label: $0.0, value: $0.1, el: $0.2) },
                      password: motDePasse, secure: secureBundles.contains(bundle))
    }

    /// Traductions exactes des boutons courants (on ne mélange jamais deux sens : « Supprimer » n'est pas « Ne pas enregistrer »)
    static let traductions: [[String]] = [
        ["allow", "autoriser"], ["don't allow", "ne pas autoriser", "dont allow"], ["save", "enregistrer"], ["cancel", "annuler"],
        ["ok", "d'accord"], ["delete", "supprimer"], ["don't save", "ne pas enregistrer", "dont save"], ["replace", "remplacer"],
        ["open", "ouvrir"], ["quit", "quitter"], ["close", "fermer"], ["continue", "continuer"], ["yes", "oui"], ["no", "non"],
        ["done", "termine"], ["download", "telecharger"], ["keep", "conserver"], ["leave page", "quitter la page"],
        ["stay on page", "rester sur la page"], ["revert", "restaurer"], ["move to trash", "placer dans la corbeille"],
        ["new document", "nouveau document"], ["always allow", "toujours autoriser"], ["allow once", "autoriser une fois"],
    ]

    /// Bouton désigné par son nom (ou « default », « cancel ») : exact, puis traduction, puis début du titre
    public static func bouton(_ d: Dialog, _ nom: String) -> (title: String, el: AXUIElement)? {
        let n = normalise(nom)
        if n == "default" || n == "defaut", let t = d.defaultButton { return d.buttons.first { $0.title == t } ?? AX.element(d.element, kAXDefaultButtonAttribute).map { (t, $0) } }
        if n == "cancel" || n == "annuler", let t = d.cancelButton, let b = d.buttons.first(where: { $0.title == t }) { return b }
        if let b = d.buttons.first(where: { normalise($0.title) == n }) { return b }
        let equivalents = traductions.first { $0.contains(n) } ?? []
        if let b = d.buttons.first(where: { equivalents.contains(normalise($0.title)) }) { return b }
        return d.buttons.first { normalise($0.title).hasPrefix(n) && n.count >= 3 }
    }

    public struct Answer {
        public let button: String
        public let method: String     // AXPress ou CGEvent
        public let closed: Bool       // la fenêtre a disparu
        public let frontRestored: Bool
    }

    /// Répond : remplit le premier champ si fill, presse le bouton (AXPress, vrai clic si l'AXPress est refusé),
    /// vérifie que la fenêtre s'est fermée. Jamais d'erreur muette : renvoie ou lève une phrase avec la raison.
    public static func answer(_ d: Dialog, button nom: String, fill: String? = nil) throws -> Answer {
        try AX.trusted()
        guard let (titre, b) = bouton(d, nom) else {
            throw UIError("no button \"\(nom)\" in \(d.app)'s \(d.kind) \"\(d.title.prefix(60))\"; buttons: \(d.buttons.map(\.title).joined(separator: ", "))")
        }
        guard AX.enabled(b) else { throw UIError("button \"\(titre)\" is disabled in \(d.app)'s \(d.kind)") }
        if let fill, let champ = d.fields.first {
            AX.set(champ.el, kAXFocusedAttribute, kCFBooleanTrue)
            guard AX.set(champ.el, kAXValueAttribute, fill as CFString) else { throw UIError("could not fill the field \"\(champ.label)\"") }
            Thread.sleep(forTimeInterval: 0.1)
        }
        var methode = "AXPress", rendu = false
        if !AX.press(b) {
            // AXPress refusé : vrai clic au centre du bouton, l'app passe devant le temps du clic
            if d.secure { throw UIError(secureMessage) }
            guard let r = AX.frame(b), r.width > 0 else { throw UIError("button \"\(titre)\" refused the Accessibility press and has no position") }
            let w = AX.window(of: d.element)
            rendu = try Front.with(d.pid, window: w) { Input.click(at: CGPoint(x: r.midX, y: r.midY)) }.restored
            methode = "CGEvent"
        }
        let ferme = AX.attendre(1.5, every: 0.05) { !AX.alive(d.element) || !AX.alive(b) || AX.attr(d.element, kAXRoleAttribute) == nil || !ouvert(d) }
        if !ferme && d.secure { throw UIError(secureMessage) }
        return Answer(button: titre, method: methode, closed: ferme, frontRestored: rendu)
    }

    /// La feuille est encore rattachée à sa fenêtre (une feuille fermée peut rester « vivante » un instant)
    static func ouvert(_ d: Dialog) -> Bool {
        guard d.kind == "sheet" else {
            // Une fenêtre fermée reste parfois « vivante » ; elle sort tout de suite de la liste des fenêtres de l'app
            return AX.alive(d.element) && (AX.attr(AX.app(d.pid), kAXWindowsAttribute) as? [AXUIElement] ?? []).contains { CFEqual($0, d.element) }
        }
        guard let p = AX.parent(d.element) else { return false }
        return AX.children(p).contains { CFEqual($0, d.element) }
    }
}
