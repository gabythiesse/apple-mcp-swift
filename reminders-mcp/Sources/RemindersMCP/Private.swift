// Voie privée : ReminderKit, le framework qu'utilise l'app Rappels elle-même.
// Couvre ce qu'EventKit n'expose pas : drapeau, tags, sous-tâches, sections, groupes, URL, images.
// Aucun en-tête public : appels par sélecteur via le runtime ObjC. Peut casser à une mise à jour de macOS.
import Foundation
import ObjectiveC

// MARK: - Runtime ObjC

private typealias F0 = @convention(c) (AnyObject, Selector) -> AnyObject?
private typealias F1 = @convention(c) (AnyObject, Selector, AnyObject?) -> AnyObject?
private typealias F2 = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?) -> AnyObject?
private typealias F0V = @convention(c) (AnyObject, Selector) -> Void
private typealias F1V = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
private typealias F0E = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject?
private typealias F1E = @convention(c) (AnyObject, Selector, AnyObject?, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject?
private typealias FBool = @convention(c) (AnyObject, Selector) -> Bool
private typealias FSetBool = @convention(c) (AnyObject, Selector, Bool) -> Void
private typealias FSave = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
private typealias FHashtag = @convention(c) (AnyObject, Selector, Int, AnyObject?) -> AnyObject?
private typealias FMembership = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, Bool, AnyObject?) -> AnyObject?
private typealias FImage = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, UInt, UInt) -> AnyObject?

/// Les modèles ReminderKit transfèrent leurs propriétés à un objet « storage » (forwardingTargetForSelector)
private func receiver(_ o: AnyObject, _ sel: Selector) -> AnyObject? {
    if class_respondsToSelector(object_getClass(o), sel) { return o }
    if let n = o as? NSObject, let t = n.forwardingTarget(for: sel) as AnyObject?,
       class_respondsToSelector(object_getClass(t), sel) { return t }
    return nil
}

private func imp<T>(_ o: AnyObject, _ s: String, _ t: T.Type) throws -> (T, Selector, AnyObject) {
    let sel = NSSelectorFromString(s)
    guard let r = receiver(o, sel), let cls = object_getClass(r), let m = class_getMethodImplementation(cls, sel) else {
        throw MCPError("ReminderKit: \(type(of: o)) no longer responds to \(s) (macOS may have changed this private framework)")
    }
    return (unsafeBitCast(m, to: t), sel, r)
}

private func call(_ o: AnyObject, _ s: String) throws -> AnyObject? { let (f, sel, r) = try imp(o, s, F0.self); return f(r, sel) }
private func call(_ o: AnyObject, _ s: String, _ a: AnyObject?) throws -> AnyObject? { let (f, sel, r) = try imp(o, s, F1.self); return f(r, sel, a) }
private func call(_ o: AnyObject, _ s: String, _ a: AnyObject?, _ b: AnyObject?) throws -> AnyObject? { let (f, sel, r) = try imp(o, s, F2.self); return f(r, sel, a, b) }
private func callV(_ o: AnyObject, _ s: String) throws { let (f, sel, r) = try imp(o, s, F0V.self); f(r, sel) }
private func callV(_ o: AnyObject, _ s: String, _ a: AnyObject?) throws { let (f, sel, r) = try imp(o, s, F1V.self); f(r, sel, a) }
private func callE(_ o: AnyObject, _ s: String) throws -> AnyObject? {
    let (f, sel, r) = try imp(o, s, F0E.self); var e: NSError?; let x = f(r, sel, &e); if let e { throw e }; return x
}
private func callE(_ o: AnyObject, _ s: String, _ a: AnyObject?) throws -> AnyObject? {
    let (f, sel, r) = try imp(o, s, F1E.self); var e: NSError?; let x = f(r, sel, a, &e); if let e { throw e }; return x
}
private func bool(_ o: AnyObject, _ s: String) throws -> Bool { let (f, sel, r) = try imp(o, s, FBool.self); return f(r, sel) }
private func must(_ o: AnyObject?, _ what: String) throws -> AnyObject {
    guard let o else { throw MCPError("ReminderKit: \(what) not found") }
    return o
}
/// Lecture sans échec : nil si le sélecteur n'existe pas
private func opt(_ o: AnyObject?, _ s: String) -> AnyObject? { o.flatMap { try? call($0, s) } }
private func cls(_ n: String) throws -> AnyObject {
    guard let c = NSClassFromString(n) else { throw MCPError("ReminderKit: class \(n) missing") }
    return c as AnyObject
}
private func alloc(_ n: String) throws -> AnyObject { try must(try call(try cls(n), "alloc"), n) }

/// NSArray, NSSet, NSOrderedSet ou NSDictionary (valeurs) → tableau
private func objects(_ x: AnyObject?) -> [AnyObject] {
    switch x {
    case let a as NSArray: return a.map { $0 as AnyObject }
    case let s as NSSet: return s.allObjects.map { $0 as AnyObject }
    case let o as NSOrderedSet: return o.array.map { $0 as AnyObject }
    case let d as NSDictionary: return d.allValues.map { $0 as AnyObject }
    default: return []
    }
}

// MARK: - ReminderKit

struct RKInfo {
    var flagged = false
    var tags: [String] = []
    var parentID: String?
    var listID: String?
    var url: String?
    var images = 0
}

struct Extras {
    var flagged: Bool?
    var addTags: [String] = []
    var removeTags: [String] = []
    var url: String?         // "" = retirer
    var parentID: String?    // "" = détacher du parent
    var sectionID: String?   // "" = sortir de la section

    var isEmpty: Bool {
        flagged == nil && addTags.isEmpty && removeTags.isEmpty && url == nil && parentID == nil && sectionID == nil
    }
}

enum RK {
    static let available: Bool = {
        guard dlopen("/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit", RTLD_NOW) != nil else { return false }
        return NSClassFromString("REMStore") != nil && NSClassFromString("REMSaveRequest") != nil
    }()

    static func require() throws {
        guard available else {
            throw MCPError("ReminderKit unavailable on this macOS: flag, tags, subtasks, sections, groups, URL and images are inaccessible")
        }
    }

    // MARK: Accès de base

    static func store() throws -> AnyObject { try require(); return try must(try call(try alloc("REMStore"), "init"), "REMStore") }
    private static func saveRequest(_ st: AnyObject) throws -> AnyObject { try must(try call(try alloc("REMSaveRequest"), "initWithStore:", st), "REMSaveRequest") }
    private static func save(_ sr: AnyObject) throws {
        let (f, sel, r) = try imp(sr, "saveSynchronouslyWithError:", FSave.self)
        var e: NSError?
        if !f(r, sel, &e) { throw MCPError("ReminderKit refused the save: \(e?.localizedDescription ?? "unknown reason") \(e.map { "(\($0.code))" } ?? "")") }
    }

    private static func oid(_ entity: String, _ id: String) throws -> AnyObject {
        guard let u = UUID(uuidString: id) else { throw MCPError("invalid ID: \(id)") }
        return try must(try call(try cls(entity), "objectIDWithUUID:", u as NSUUID), "objectID")
    }

    static func uuid(_ objectID: AnyObject?) -> String? { (opt(objectID, "uuid") as? NSUUID)?.uuidString }
    private static func idOf(_ o: AnyObject) -> String? { uuid(opt(o, "remObjectID") ?? opt(o, "objectID")) }

    private static func reminder(_ st: AnyObject, _ id: String) throws -> AnyObject {
        guard let r = try? callE(st, "fetchReminderWithObjectID:error:", try oid("REMReminder", id)) else { throw MCPError("reminder not found: \(id)") }
        return r
    }

    private static func list(_ st: AnyObject, _ id: String) throws -> AnyObject {
        guard let l = try? callE(st, "fetchListWithObjectID:error:", try oid("REMList", id)) else { throw MCPError("list not found: \(id)") }
        return l
    }

    private static func children(_ st: AnyObject, _ ids: [String]) throws -> [AnyObject] {
        let oids = try ids.map { try oid("REMReminder", $0) }
        return objects(try callE(st, "fetchRemindersWithParentReminderIDs:error:", oids as NSArray))
    }

    // MARK: Lecture

    private static func info(_ r: AnyObject) -> RKInfo {
        var i = RKInfo()
        if let fc = opt(r, "flaggedContext") { i.flagged = (try? bool(fc, "flagged")) ?? false }
        i.tags = objects(opt(opt(r, "hashtagContext"), "hashtags")).compactMap { opt($0, "name") as? String }.sorted()
        i.parentID = uuid(opt(r, "parentReminderID"))
        i.listID = uuid(opt(r, "listID"))
        for a in objects(opt(opt(r, "attachmentContext"), "attachments")) {
            let name = NSStringFromClass(type(of: a))
            if name.contains("URLAttachment") { i.url = (opt(a, "url") as? NSURL)?.absoluteString }
            else if name.contains("ImageAttachment") { i.images += 1 }
        }
        return i
    }

    /// Infos ReminderKit d'un lot de rappels ; vide si la voie privée est indisponible
    static func infos(_ ids: [String]) -> [String: RKInfo] {
        guard available, !ids.isEmpty, let st = try? store() else { return [:] }
        var out: [String: RKInfo] = [:]
        var i = 0
        while i < ids.count {
            let chunk = Array(ids[i..<min(i + 200, ids.count)])
            i += 200
            let oids = chunk.compactMap { try? oid("REMReminder", $0) }
            guard let res = try? callE(st, "fetchRemindersWithObjectIDs:error:", oids as NSArray) else { continue }
            for r in objects(res) { if let id = idOf(r) { out[id] = info(r) } }
        }
        return out
    }

    /// Nombre de sous-tâches par parent
    static func childCounts(_ ids: [String]) -> [String: Int] {
        guard available, !ids.isEmpty, let st = try? store(), let kids = try? children(st, ids) else { return [:] }
        var out: [String: Int] = [:]
        for k in kids { if let p = uuid(opt(k, "parentReminderID")) { out[p, default: 0] += 1 } }
        return out
    }

    static func listInfo(_ st: AnyObject, _ id: String) -> (isGroup: Bool, parentID: String?)? {
        guard let l = try? list(st, id) else { return nil }
        return ((try? bool(l, "isGroup")) ?? false, uuid(opt(l, "parentListID")))
    }

    /// Groupes de listes de tous les comptes (EventKit ne les énumère pas)
    static func groups() -> [(id: String, name: String, account: String)] {
        guard available, let st = try? store(), let accounts = try? callE(st, "fetchAccountsWithError:") else { return [] }
        var out: [(id: String, name: String, account: String)] = []
        for acc in objects(accounts) {
            guard let ctx = opt(acc, "groupContext"), let gs = try? callE(ctx, "fetchGroupsWithError:") else { continue }
            let accName = opt(acc, "displayName") as? String ?? opt(acc, "name") as? String ?? ""
            for g in objects(gs) {
                if let id = idOf(g) { out.append((id, opt(g, "name") as? String ?? "", accName)) }
            }
        }
        return out
    }

    static func sections(_ listID: String) throws -> [(id: String, name: String)] {
        let st = try store()
        let dv = try must(try call(try alloc("REMListSectionsDataView"), "initWithStore:", st), "REMListSectionsDataView")
        let secs = objects(try callE(dv, "fetchListSectionsWithListObjectID:error:", try oid("REMList", listID)))
        return secs.compactMap { s in
            guard let id = idOf(s) else { return nil }
            return (id, opt(s, "displayName") as? String ?? "")
        }
    }

    /// Section de chaque rappel (seulement pour les listes qui ont des sections)
    static func sectionsOf(_ reminders: [(id: String, listID: String)]) -> [String: (id: String, name: String)] {
        guard available, let st = try? store(),
              let dv = try? call(try alloc("REMListSectionsDataView"), "initWithStore:", st) else { return [:] }
        var hasSections: [String: Bool] = [:]
        var out: [String: (id: String, name: String)] = [:]
        for r in reminders {
            if hasSections[r.listID] == nil {
                let n = (try? sections(r.listID).count) ?? 0
                hasSections[r.listID] = n > 0
            }
            guard hasSections[r.listID] == true, let o = try? oid("REMReminder", r.id),
                  let s = try? callE(dv, "fetchListSectionWithReminderID:error:", o), let sid = idOf(s) else { continue }
            out[r.id] = (sid, opt(s, "displayName") as? String ?? "")
        }
        return out
    }

    // MARK: Écriture sur un rappel

    private static func cleanTag(_ t: String) -> String {
        var s = t.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix("#") { s.removeFirst() }
        return s.replacingOccurrences(of: " ", with: "-")
    }

    static func apply(_ id: String, _ x: Extras) throws {
        guard !x.isEmpty else { return }
        let st = try store()
        let sr = try saveRequest(st)
        let r = try reminder(st, id)
        let ci = try must(try call(sr, "updateReminder:", r), "reminder change")

        if let f = x.flagged {
            let fc = try must(try call(ci, "flaggedContext"), "flaggedContext")
            let (set, sel, rcv) = try imp(fc, "setFlagged:", FSetBool.self)
            set(rcv, sel, f)
        }

        if !x.addTags.isEmpty || !x.removeTags.isEmpty {
            let hc = try must(try call(ci, "hashtagContext"), "hashtagContext")
            let existing = objects(try call(hc, "hashtags"))
            let remove = Set(x.removeTags.map { cleanTag($0).lowercased() })
            for h in existing where remove.contains((opt(h, "name") as? String ?? "").lowercased()) {
                try callV(hc, "removeHashtag:", h)
            }
            var present = Set(existing.compactMap { (opt($0, "name") as? String)?.lowercased() }).subtracting(remove)
            for t in x.addTags.map(cleanTag) where !t.isEmpty && !present.contains(t.lowercased()) {
                let (add, sel, rcv) = try imp(hc, "addHashtagWithType:name:", FHashtag.self)
                _ = add(rcv, sel, 0, t as NSString)
                present.insert(t.lowercased())
            }
        }

        if let u = x.url {
            let ac = try must(try call(ci, "attachmentContext"), "attachmentContext")
            if u.isEmpty {
                try callV(ac, "removeURLAttachments")
            } else {
                guard let url = URL(string: u), url.scheme != nil else { throw MCPError("invalid URL: \(u)") }
                _ = try call(ac, "setURLAttachmentWithURL:", url as NSURL)
            }
        }

        if let pid = x.parentID {
            if pid.isEmpty {
                // Retirer du parent ne suffit pas : le rappel doit être remis dans sa liste, sinon il disparaît
                guard uuid(opt(r, "parentReminderID")) != nil, let listID = uuid(opt(r, "listID")) else { try save(sr); return }
                try callV(ci, "removeFromParentReminder")
                try callV(try must(try call(sr, "updateList:", try list(st, listID)), "list change"), "addReminderChangeItem:", ci)
            } else {
                guard pid != id else { throw MCPError("a reminder cannot be its own subtask") }
                let p = try reminder(st, pid)
                guard uuid(opt(p, "parentReminderID")) == nil else { throw MCPError("the parent is already a subtask: Reminders only supports one level of subtasks") }
                guard try children(st, [id]).isEmpty else { throw MCPError("this reminder has its own subtasks: Reminders only supports one level of subtasks") }
                let pci = try must(try call(sr, "updateReminder:", p), "parent change")
                try callV(try must(try call(pci, "subtaskContext"), "subtaskContext"), "addReminderChangeItem:", ci)
            }
        }

        if let sid = x.sectionID {
            guard let listID = uuid(opt(r, "listID")) else { throw MCPError("reminder's list not found") }
            // Sortir d'une section = appartenir à la liste elle-même (une appartenance « obsolète » est ignorée)
            if !sid.isEmpty, try !sections(listID).contains(where: { $0.id == sid }) {
                throw MCPError("section \(sid) is not in the reminder's list")
            }
            let group = sid.isEmpty ? listID : sid
            let lci = try must(try call(sr, "updateList:", try list(st, listID)), "list change")
            let ctx = try must(try call(lci, "sectionsContextChangeItem"), "sectionsContextChangeItem")
            let member = UUID(uuidString: id)! as NSUUID
            let (mk, sel, _) = try imp(try alloc("REMMembership"), "initWithMemberIdentifier:groupIdentifier:isObsolete:modifiedOn:", FMembership.self)
            let m = try must(mk(try alloc("REMMembership"), sel, member, UUID(uuidString: group)! as NSUUID, false, Date() as NSDate), "REMMembership")
            let ms = try must(try call(try alloc("REMMemberships"), "initWithMembershipByMemberIdentifier:", [member: m] as NSDictionary), "REMMemberships")
            try callV(ctx, "setUnsavedMembershipsOfRemindersInSections:", ms)
        }

        try save(sr)
    }

    /// Déplace un rappel vers une autre liste, avec ses sous-tâches (EventKit refuse ce cas)
    static func moveReminder(_ id: String, to listID: String) throws {
        let st = try store()
        let sr = try saveRequest(st)
        let r = try reminder(st, id)
        let ci = try must(try call(sr, "updateReminder:", r), "reminder change")
        let dest = try must(try call(sr, "updateList:", try list(st, listID)), "destination list")
        if uuid(opt(r, "parentReminderID")) != nil { try callV(ci, "removeFromParentReminder") }
        try callV(dest, "addReminderChangeItem:", ci)
        let sub = try must(try call(ci, "subtaskContext"), "subtaskContext")
        for k in try children(st, [id]) {
            try callV(sub, "addReminderChangeItem:", try must(try call(sr, "updateReminder:", k), "subtask"))
        }
        try save(sr)
    }

    static func addImage(_ id: String, data: Data, uti: String, width: Int, height: Int) throws {
        let st = try store()
        let sr = try saveRequest(st)
        let ci = try must(try call(sr, "updateReminder:", try reminder(st, id)), "reminder change")
        let ac = try must(try call(ci, "attachmentContext"), "attachmentContext")
        let (add, sel, rcv) = try imp(ac, "addImageAttachmentWithData:uti:width:height:", FImage.self)
        _ = try must(add(rcv, sel, data as NSData, uti as NSString, UInt(width), UInt(height)), "image attachment")
        try save(sr)
    }

    // MARK: Listes, groupes, sections

    static func createGroup(_ name: String, sameAccountAs listID: String) throws -> String {
        let st = try store()
        let sr = try saveRequest(st)
        let acc = try must(opt(try list(st, listID), "account"), "account")
        let aci = try must(try call(sr, "updateAccount:", acc), "account change")
        let g = try must(try call(sr, "addGroupWithName:toAccountGroupContextChangeItem:", name as NSString, try call(aci, "groupContext")), "group")
        guard let gid = uuid(opt(g, "objectID")) else { throw MCPError("group ID not found") }
        try save(sr)
        return gid
    }

    /// Range une liste dans un groupe, ou la sort de son groupe (groupID nil)
    static func moveList(_ listID: String, toGroup groupID: String?) throws {
        let st = try store()
        let sr = try saveRequest(st)
        let l = try list(st, listID)
        let lci = try must(try call(sr, "updateList:", l), "list change")
        if let gid = groupID {
            let g = try list(st, gid)
            guard (try? bool(g, "isGroup")) == true else { throw MCPError("\(gid) is not a group") }
            let gci = try must(try call(sr, "updateList:", g), "group change")
            try callV(try must(try call(gci, "sublistContext"), "sublistContext"), "addListChangeItem:", lci)
        } else {
            let aci = try must(try call(sr, "updateAccount:", try must(opt(l, "account"), "account")), "account change")
            try callV(aci, "addListChangeItem:", lci)
        }
        try save(sr)
    }

    static func deleteGroup(_ id: String) throws {
        let st = try store()
        let sr = try saveRequest(st)
        let gci = try must(try call(sr, "updateList:", try list(st, id)), "group change")
        try callV(gci, "removeFromParent")
        try save(sr)
    }

    static func createSection(_ listID: String, name: String) throws -> String {
        let st = try store()
        let sr = try saveRequest(st)
        let lci = try must(try call(sr, "updateList:", try list(st, listID)), "list change")
        let ctx = try must(try call(lci, "sectionsContextChangeItem"), "sectionsContextChangeItem")
        let s = try must(try call(sr, "addListSectionWithDisplayName:toListSectionContextChangeItem:", name as NSString, ctx), "section")
        guard let sid = uuid(opt(s, "objectID")) else { throw MCPError("section ID not found") }
        try save(sr)
        return sid
    }

    static func deleteSection(_ id: String) throws -> String {
        let st = try store()
        guard let s = try? callE(st, "fetchListSectionWithObjectID:error:", try oid("REMListSection", id)) else {
            throw MCPError("section not found: \(id)")
        }
        let name = opt(s, "displayName") as? String ?? ""
        let sr = try saveRequest(st)
        try callV(try must(try call(sr, "updateListSection:", s), "section change"), "removeFromList")
        try save(sr)
        return name
    }
}
