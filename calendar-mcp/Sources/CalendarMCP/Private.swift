// Voie privée EventKit (méthodes non publiques, testées par les sondes 03 à 06) : peut casser à une mise à jour de macOS.
// Chaque appel passe par mcp_essayer : une exception ObjC devient une erreur métier au lieu de tuer le serveur.
import Foundation
import EventKit
import Garde

enum Priv {
    /// Exécute un appel privé ; une exception ObjC devient une MCPError
    static func guarded(_ what: String, _ body: () -> Void) throws {
        if let err = mcp_essayer(body) { throw MCPError("\(what) : appel privé refusé par macOS (\(err))") }
    }

    private static func value(_ o: NSObject, _ key: String) -> Any? {
        var v: Any?
        _ = mcp_essayer { v = o.value(forKey: key) }
        return v
    }

    // MARK: Temps de trajet (sonde 04)

    static func travelMinutes(_ e: EKEvent) -> Int? {
        guard let s = value(e, "travelTime") as? Double, s > 0 else { return nil }
        return Int(s / 60)
    }

    static func setTravel(_ e: EKEvent, minutes: Double) throws {
        try guarded("temps de trajet") { e.setValue(max(0, minutes) * 60, forKey: "travelTime") }
    }

    /// Début occupé, trajet compris (pour les créneaux libres)
    static func busyStart(_ e: EKEvent) -> Date {
        (value(e, "startDateIncludingTravel") as? Date) ?? e.startDate
    }

    // MARK: Lien visio détecté (sonde 04)

    static func conference(_ e: EKEvent) -> String? {
        switch value(e, "conferenceURLForDisplay") {
        case let u as URL: return u.absoluteString
        case let s as String where !s.isEmpty: return s
        default: return nil
        }
    }

    // MARK: Alerte par défaut du compte (sondes 05 et 06)

    /// Marque l'alerte par défaut comme retirée, pour qu'une 2e écriture garde exactement les alertes voulues
    static func dropDefaultAlarm(_ e: EKEvent) {
        _ = mcp_essayer { e.setValue(true, forKey: "defaultAlarmWasDeleted") }
    }

    // MARK: Pièces jointes (sonde 04 : initWithFilepath: attend une URL, une chaîne lève une exception)

    static func addAttachment(_ e: EKEvent, path: String) throws -> String {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            throw MCPError("pièce jointe introuvable : \(path)")
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw MCPError("pièce jointe illisible : \(path)") }
        if let ok = value(e, "supportsAddingAttachments") as? Bool, !ok {
            throw MCPError("ce calendrier n'accepte pas les pièces jointes")
        }
        guard let cls = NSClassFromString("EKAttachment") as? NSObject.Type else {
            throw MCPError("pièces jointes indisponibles sur cette version de macOS")
        }
        let initSel = NSSelectorFromString("initWithFilepath:"), addSel = NSSelectorFromString("addAttachment:")
        guard cls.instancesRespond(to: initSel), e.responds(to: addSel) else {
            throw MCPError("pièces jointes indisponibles sur cette version de macOS")
        }
        var att: AnyObject?
        try guarded("pièce jointe") {
            att = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
                .perform(initSel, with: url as NSURL)?.takeUnretainedValue()
            if let att { e.perform(addSel, with: att) }
        }
        guard att != nil else { throw MCPError("pièce jointe non créée : \(path)") }
        return url.lastPathComponent
    }

    static func attachmentNames(_ e: EKEvent) -> [String] {
        let raw = value(e, "attachments")
        let list: [NSObject] = (raw as? [NSObject]) ?? Array((raw as? Set<NSObject>) ?? [])
        return list.compactMap { value($0, "fileName") as? String }
    }

    // MARK: Invitations (effet externe : non testées en écriture)

    /// Ajoute des invités ; l'envoi part à l'enregistrement
    static func addAttendee(_ e: EKEvent, email: String, name: String?) throws {
        guard let cls = NSClassFromString("EKAttendee") as? NSObject.Type else { throw MCPError("invités indisponibles sur cette version de macOS") }
        let make = NSSelectorFromString("attendeeWithName:emailAddress:"), add = NSSelectorFromString("addAttendee:")
        guard cls.responds(to: make), e.responds(to: add) else { throw MCPError("invités indisponibles sur cette version de macOS") }
        try guarded("invité \(email)") {
            if let a = cls.perform(make, with: (name ?? email) as NSString, with: email as NSString)?.takeUnretainedValue() {
                e.perform(add, with: a)
            }
        }
    }

    /// Répond à une invitation (accepté 2, refusé 3, provisoire 4) ; la réponse part à l'organisateur à l'enregistrement
    static func setParticipation(_ e: EKEvent, _ status: EKParticipantStatus) throws {
        guard e.responds(to: NSSelectorFromString("setParticipationStatus:")) else {
            throw MCPError("réponse aux invitations indisponible sur cette version de macOS")
        }
        try guarded("réponse à l'invitation") { e.setValue(status.rawValue, forKey: "participationStatus") }
    }

    /// Les sélecteurs privés utilisés existent-ils sur ce macOS ? (vérification sans effet)
    static func selectorsPresent() -> [String: Bool] {
        let ev = EKEvent.self as NSObject.Type
        let att = NSClassFromString("EKAttendee") as? NSObject.Type
        let pj = NSClassFromString("EKAttachment") as? NSObject.Type
        return [
            "travelTime": ev.instancesRespond(to: NSSelectorFromString("setTravelTime:")),
            "attachments": ev.instancesRespond(to: NSSelectorFromString("addAttachment:")) && (pj?.instancesRespond(to: NSSelectorFromString("initWithFilepath:")) ?? false),
            "conference": ev.instancesRespond(to: NSSelectorFromString("conferenceURLForDisplay")),
            "defaultAlarm": ev.instancesRespond(to: NSSelectorFromString("setDefaultAlarmWasDeleted:")),
            "attendee": ev.instancesRespond(to: NSSelectorFromString("addAttendee:")) && (att?.responds(to: NSSelectorFromString("attendeeWithName:emailAddress:")) ?? false),
            "participation": ev.instancesRespond(to: NSSelectorFromString("setParticipationStatus:")),
        ]
    }
}
