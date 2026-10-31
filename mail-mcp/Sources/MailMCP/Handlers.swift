// Logique des outils : index (lecture seule) pour lister et chercher, AppleScript pour lire, ranger et écrire
import Foundation
import UniformTypeIdentifiers

extension Dictionary where Key == String, Value == Any {
    func ints(_ k: String) -> [Int]? {
        let raw: [Any]?
        if let s = self[k] as? String, let d = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [Any] { raw = d }
        else if let s = self[k] as? String { raw = [s] }
        else if let n = self[k] as? NSNumber { raw = [n] }
        else { raw = self[k] as? [Any] }
        return raw?.compactMap { ($0 as? NSNumber)?.intValue ?? ($0 as? String).flatMap { Int($0) } }
    }
    func reqInts(_ k: String) throws -> [Int] {
        guard let v = ints(k), !v.isEmpty else { throw MCPError("missing parameter: \(k)") }
        return v
    }
}

enum Dates {
    private static func f(_ p: String) -> DateFormatter {
        let d = DateFormatter(); d.locale = Locale(identifier: "en_US_POSIX"); d.timeZone = .current; d.dateFormat = p; return d
    }
    private static let jour = f("yyyy-MM-dd"), minute = f("yyyy-MM-dd'T'HH:mm")
    static func parse(_ s: String) throws -> Date {
        if let d = minute.date(from: s) ?? jour.date(from: s) { return d }
        throw MCPError("invalid date: \(s) (expected YYYY-MM-DD or YYYY-MM-DDTHH:MM)")
    }
    static func str(_ d: Date) -> String { minute.string(from: d) }
    static func str(_ t: Int64) -> String { str(Date(timeIntervalSince1970: TimeInterval(t))) }
}

/// Dossier temporaire dans le conteneur de Mail : seul endroit où Mail (en bac à sable) lit et écrit librement
enum Conteneur {
    static let racine = NSHomeDirectory() + "/Library/Containers/com.apple.mail/Data/tmp"
    static func nouveau() throws -> String {
        let fm = FileManager.default
        // purge des dossiers laissés par des envois (plus d'une heure)
        for d in (try? fm.contentsOfDirectory(atPath: racine)) ?? [] where d.hasPrefix("mcp-mail-") {
            let p = racine + "/" + d
            if let date = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date, date < Date().addingTimeInterval(-3600) {
                try? fm.removeItem(atPath: p)
            }
        }
        let p = racine + "/mcp-mail-" + UUID().uuidString
        do { try fm.createDirectory(atPath: p, withIntermediateDirectories: true) }
        catch { throw MCPError("cannot write to Mail's container (\(error.localizedDescription)): allow access to other apps' data for Claude.") }
        return p
    }
}

enum Handlers {
    static let couleursDrapeau = ["red": 0, "orange": 1, "yellow": 2, "green": 3, "blue": 4, "purple": 5, "gray": 6]
    static let couleursFond = ["red": "red", "orange": "orange", "yellow": "yellow", "green": "green", "blue": "blue",
                               "purple": "purple", "gray": "gray", "none": "none"]

    // MARK: - Boîtes

    static let parcours = """
    on parcours(mbs, prefixe)
        tell application "Mail"
            set out to {}
            repeat with mb in mbs
                set p to prefixe & (name of mb)
                set end of out to p
                set out to out & my parcours(mailboxes of mb, p & "/")
            end repeat
            return out
        end tell
    end parcours
    """

    static func boites(_ a: JSON) throws -> Any {
        let filtre = a.nonEmpty("name_contains")
        // Parcours des boîtes locales AVANT la boucle des comptes : l'ordre inverse fait expirer Mail sous dispatchMain
        let r = try AS.run("""
        set locales to my parcours(mailboxes, "")
        set comptes to {}
        repeat with c in accounts
            set end of comptes to {id of c, name of c, account type of c as text, email addresses of c, name of every mailbox of c}
        end repeat
        return {comptes, locales, name of every signature}
        """, avant: parcours) as? [Any] ?? []
        var liste = try Index.boites()
        var connus = Set(liste.map(\.id))
        func ajoute(_ compte: String, _ chemin: String) {
            let chemin = chemin.precomposedStringWithCanonicalMapping
            let id = "\(compte)/\(chemin)"
            guard !connus.contains(id), !liste.contains(where: { $0.compte == compte && $0.nom == chemin }) else { return }
            connus.insert(id)
            liste.append(Boite(rowid: -1, id: id, compte: compte, chemin: chemin, total: 0, nonLus: 0))
        }
        var comptes: [JSON] = []
        for c in r.l(0).compactMap({ $0 as? [Any] }) {
            comptes.append(["id": c.s(0), "name": c.s(1), "type": c.s(2), "addresses": c.l(3)])
            for nom in c.l(4).compactMap({ $0 as? String }) { ajoute(c.s(0), nom) }
        }
        comptes.append(["id": "local", "name": "On My Mac"])
        for chemin in r.l(1).compactMap({ $0 as? String }) { ajoute("local", chemin) }
        let boites: [JSON] = liste
            .filter { filtre == nil || $0.chemin.localizedStandardContains(filtre!) }
            .sorted { ($0.compte, $0.chemin) < ($1.compte, $1.chemin) }
            .map { b in
                var d: JSON = ["id": b.id]
                if b.nonLus > 0 { d["unread"] = b.nonLus }
                if b.total > 0 { d["total"] = b.total }
                return d
            }
        return ["accounts": comptes, "mailboxes": boites, "signatures": r.l(2)]
    }

    static func gererBoites(_ a: JSON) throws -> Any {
        var res: [JSON] = []
        for c in a.objects("create") ?? [] {
            let chemin = c.nonEmpty("path") ?? ""
            let compte = c.nonEmpty("account_id") ?? "local"
            do {
                guard !chemin.isEmpty else { throw MCPError("missing path") }
                let mk = "make new mailbox with properties {name:\(AS.q(chemin))}"
                try AS.run(compte == "local" ? mk : "tell account id \(AS.q(compte)) to \(mk)")
                res.append(["ok": true, "id": "\(compte)/\(chemin)"])
            } catch { res.append(["ok": false, "path": chemin, "error": "\(error)"]) }
        }
        for r in a.objects("rename") ?? [] {
            let id = r.nonEmpty("id") ?? "", nom = r.nonEmpty("name") ?? ""
            do {
                guard !nom.isEmpty, !nom.contains("/") else { throw MCPError("invalid name (no /)") }
                try AS.run("set name of \(try refBoite(id)) to \(AS.q(nom))")
                var parts = id.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                parts[parts.count - 1] = nom
                res.append(["ok": true, "old_id": id, "id": parts.joined(separator: "/")])
            } catch { res.append(["ok": false, "id": id, "error": "\(error)"]) }
        }
        guard !res.isEmpty else { throw MCPError("nothing to do: provide create or rename") }
        return ["results": res]
    }

    /// AppleScript ne sait pas supprimer une boîte (« delete » → -10000, sonde 19) : menu de Mail par l'interface,
    /// après vérification de la sélection puis du texte de la feuille de confirmation (sonde 21).
    static func supprimerBoites(_ a: JSON) throws -> Any {
        guard let ids = a.strings("ids"), !ids.isEmpty else { throw MCPError("missing parameter: ids") }
        let forcer = a.bool("force") == true
        var res: [JSON] = []
        for id in ids {
            do {
                let ref = try refBoite(id)
                let nom = String(id.split(separator: "/", omittingEmptySubsequences: false).last ?? "")
                let r = try AS.runRaw("""
                tell application "Mail"
                  with timeout of 30 seconds
                    if not (exists \(ref)) then return {"absente"}
                    set b to \(ref)
                    set nb to count of messages of b
                    set sb to count of mailboxes of b
                    if \(forcer ? "false" : "(nb > 0 or sb > 0)") then return {"pleine", nb, sb}
                    activate
                    if (count of message viewers) = 0 then make new message viewer
                    set mv to message viewer 1
                    set selected mailboxes of mv to {b}
                    delay 0.5
                    set sel to selected mailboxes of mv
                    if (count of sel) is not 1 then error "unexpected selection (" & (count of sel) & " mailboxes): nothing deleted"
                    if name of item 1 of sel is not \(AS.q(nom)) or (count of messages of item 1 of sel) is not nb then error "unexpected selection: nothing deleted"
                  end timeout
                end tell
                tell application "System Events" to tell process "Mail"
                  set frontmost to true
                  click menu item "Supprimer la boîte aux lettres…" of menu 1 of menu bar item "Boîte aux lettres" of menu bar 1
                  set w to window 1
                  repeat 20 times
                    if (count of sheets of w) > 0 then exit repeat
                    delay 0.1
                  end repeat
                  if (count of sheets of w) = 0 then error "no confirmation sheet: nothing deleted"
                  set txt to (value of every static text of sheet 1 of w) as text
                  if txt does not contain \(AS.q(nom)) then
                    click button "Annuler" of sheet 1 of w
                    error "unexpected sheet (" & txt & "): nothing deleted"
                  end if
                  click button "Supprimer" of sheet 1 of w
                end tell
                tell application "Mail"
                  repeat 30 times
                    if not (exists \(ref)) then return {"ok", nb}
                    delay 0.1
                  end repeat
                end tell
                return {"still there"}
                """) as? [Any] ?? []
                switch r.s(0) {
                case "ok": res.append(["id": id, "ok": true] .merging(r.n(1) > 0 ? ["deleted_messages": r.n(1)] : [:]) { $1 })
                case "absente": res.append(["id": id, "ok": false, "error": "mailbox not found"])
                case "pleine": res.append(["id": id, "ok": false, "error": "refused: \(r.n(1)) message(s), \(r.n(2)) sub-mailbox(es); force: true to delete anyway"])
                default: res.append(["id": id, "ok": false, "error": "Delete clicked but the mailbox still exists"])
                }
            } catch {
                let m = "\(error)"
                res.append(["id": id, "ok": false, "error": m.contains("-1719") || m.contains("-25211") || m.contains("assistance")
                    ? "macOS refuses UI scripting: allow MailMCP in System Settings > Privacy & Security > Accessibility" : m])
            }
        }
        return ["results": res]
    }

    static func relever(_ a: JSON) throws -> Any {
        if let c = a.nonEmpty("account_id") {
            var s = "check for new mail for account id \(AS.q(c))"
            if a.bool("sync") == true { s += "\nsynchronize with account id \(AS.q(c))" }
            try AS.run(s)
        } else {
            try AS.run("check for new mail")
        }
        return ["ok": true]
    }

    // MARK: - Lister et chercher (index)

    static func messages(_ a: JSON) throws -> Any {
        let toutes = try Index.boites()
        var w = ["m.deleted = 0"], binds: [Any] = []
        func inRows(_ bs: [Boite]) -> String { bs.isEmpty ? "(-1)" : "(" + bs.map { String($0.rowid) }.joined(separator: ",") + ")" }
        let speciales = toutes.filter(Index.estSpeciale)

        if let ids = a.strings("mailbox_ids"), !ids.isEmpty {
            let set = Set(ids.map { $0.precomposedStringWithCanonicalMapping })
            w.append("m.mailbox IN \(inRows(toutes.filter { set.contains($0.id) }))")
        }
        if let c = a.nonEmpty("account_id") { w.append("m.mailbox IN \(inRows(toutes.filter { $0.compte == c }))") }
        if let ids = a.ints("ids"), !ids.isEmpty { w.append("m.ROWID IN (\(ids.map(String.init).joined(separator: ",")))") }

        switch a.nonEmpty("view") {
        case "today"?:
            w.append("m.date_received >= ?"); binds.append(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
            w.append("m.mailbox NOT IN \(inRows(speciales))")
        case "unread"?: w.append("m.read = 0"); w.append("m.mailbox NOT IN \(inRows(speciales))")
        case "flagged"?: w.append("m.flagged = 1")
        case "recent"?: w.append("m.mailbox NOT IN \(inRows(speciales))")
        case "no_reply"?:
            let envoyes = toutes.filter { Index.est($0, "envoyes") }
            let exclus = toutes.filter { Index.est($0, "envoyes") || Index.est($0, "brouillons") || Index.est($0, "corbeille") }
            w.append("m.mailbox IN \(inRows(envoyes)) AND m.date_received >= ?")
            binds.append(Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970)
            w.append("NOT EXISTS (SELECT 1 FROM messages r WHERE r.conversation_id = m.conversation_id AND r.date_received > m.date_received AND r.deleted = 0 AND r.mailbox NOT IN \(inRows(exclus)))")
        case "selection"?:
            let sel = try AS.run("""
            set out to {}
            repeat with m in (selection as list)
                try
                    set end of out to id of m
                end try
            end repeat
            return out
            """) as? [Any] ?? []
            let ids = sel.compactMap { ($0 as? Int) }
            w.append("m.ROWID IN (\(ids.isEmpty ? "-1" : ids.map(String.init).joined(separator: ",")))")
        case let v?: throw MCPError("unknown view: \(v)")
        case nil: break
        }
        if let v = a.bool("unread") { w.append("m.read = \(v ? 0 : 1)") }
        if let v = a.bool("flagged") { w.append("m.flagged = \(v ? 1 : 0)") }
        if let d = a.nonEmpty("since") { w.append("m.date_received >= ?"); binds.append(try Dates.parse(d).timeIntervalSince1970) }
        if let d = a.nonEmpty("before") { w.append("m.date_received < ?"); binds.append(try Dates.parse(d).timeIntervalSince1970) }
        if let t = a.nonEmpty("from") { w.append("(a.address LIKE ? OR a.comment LIKE ?)"); binds += ["%\(t)%", "%\(t)%"] }
        if let t = a.nonEmpty("to") {
            w.append("EXISTS (SELECT 1 FROM recipients r JOIN addresses ra ON ra.ROWID = r.address WHERE r.message = m.ROWID AND (ra.address LIKE ? OR ra.comment LIKE ?))")
            binds += ["%\(t)%", "%\(t)%"]
        }
        if let t = a.nonEmpty("text") {
            w.append("(s.subject LIKE ? OR a.address LIKE ? OR a.comment LIKE ? OR u.summary LIKE ?)")
            binds += Array(repeating: "%\(t)%", count: 4)
        }
        // Nombre de PJ : bits 10 à 15 de flags (la table attachments reste vide pour les brouillons, constaté au smoke test)
        if a.bool("has_attachments") == true { w.append("(((m.flags >> 10) & 63) > 0 OR EXISTS (SELECT 1 FROM attachments t WHERE t.message = m.ROWID))") }
        if let c = a.int("conversation") { w.append("m.conversation_id = ?"); binds.append(c) }
        if let t = a.nonEmpty("body_contains") {
            guard let ids = a.strings("mailbox_ids"), ids.count == 1 else { throw MCPError("body_contains requires exactly one mailbox in mailbox_ids") }
            let trouves = try AS.run("return id of (messages of \(try refBoite(ids[0])) whose content contains \(AS.q(t)))") as? [Any] ?? []
            let ns = trouves.compactMap { $0 as? Int }
            w.append("m.ROWID IN (\(ns.isEmpty ? "-1" : ns.map(String.init).joined(separator: ",")))")
        }
        let limite = max(1, a.int("limit") ?? 20)
        let rows = try Index.rows("""
        SELECT m.ROWID, m.mailbox, m.date_received, m.read, m.flagged, ifnull(m.subject_prefix,''), ifnull(s.subject,''),
               ifnull(a.address,''), ifnull(a.comment,''), m.conversation_id,
               max((m.flags >> 10) & 63, (SELECT count(*) FROM attachments t WHERE t.message = m.ROWID)), ifnull(u.summary,''), count(*) OVER ()
        FROM messages m LEFT JOIN subjects s ON s.ROWID = m.subject LEFT JOIN addresses a ON a.ROWID = m.sender
        LEFT JOIN summaries u ON u.ROWID = m.summary
        WHERE \(w.joined(separator: " AND "))
        ORDER BY m.date_received DESC LIMIT \(limite)
        """, binds)
        let parRow = Dictionary(uniqueKeysWithValues: toutes.map { ($0.rowid, $0.id) })
        let apercu = a.bool("preview") == true
        let msgs: [JSON] = rows.map { r in
            let adr = r[7] as? String ?? "", nom = r[8] as? String ?? ""
            var d: JSON = ["id": r[0] as! Int64, "mailbox": parRow[r[1] as? Int64 ?? -1] ?? "",
                           "date": Dates.str(r[2] as? Int64 ?? 0), "from": nom.isEmpty ? adr : "\(nom) <\(adr)>",
                           "subject": (r[5] as? String ?? "") + (r[6] as? String ?? ""), "conv": r[9] as? Int64 ?? 0]
            if (r[3] as? Int64) == 0 { d["unread"] = true }
            if (r[4] as? Int64) == 1 { d["flagged"] = true }
            if let n = r[10] as? Int64, n > 0 { d["attachments"] = n }
            if apercu, let s = r[11] as? String, !s.isEmpty { d["preview"] = String(s.prefix(160)) }
            return d
        }
        let total = rows.first?[12] as? Int64 ?? 0
        var out: JSON = ["total": total, "messages": msgs]
        if total > msgs.count { out["truncated"] = true }
        return out
    }

    // MARK: - Lire (AppleScript)

    static func lireMessages(_ a: JSON) throws -> Any {
        let ids = try a.reqInts("ids")
        let refs = try refsMessages(ids)
        let maxCar = a.int("max_chars") ?? 5000
        let ent = a.bool("headers") == true ? "all headers of m" : "\"\""
        let src = a.bool("source") == true ? "source of m" : "\"\""
        let corps = ids.compactMap { id -> String? in
            guard let ref = refs[id] else { return nil }
            return """
            try
                set m to \(ref)
                set pj to {}
                repeat with x in mail attachments of m
                    set end of pj to {name of x, file size of x}
                end repeat
                set end of out to {\(id), subject of m, sender of m, date received of m, address of to recipients of m, address of cc recipients of m, address of bcc recipients of m, (content of m) as text, pj, \(ent), \(src)}
            on error e
                set end of out to {\(id), "!ERR", e}
            end try
            """
        }.joined(separator: "\n")
        let r = refs.isEmpty ? [] : (try AS.run("set out to {}\n\(corps)\nreturn out") as? [Any] ?? [])
        var parId: [Int: JSON] = [:]
        for x in r.compactMap({ $0 as? [Any] }) {
            let id = x.n(0)
            if x.s(1) == "!ERR" { parId[id] = ["id": id, "error": x.s(2)]; continue }
            var d: JSON = ["id": id, "subject": x.s(1), "from": x.s(2), "to": x.l(4)]
            if let dt = x[3] as? Date { d["date"] = Dates.str(dt) }
            if !x.l(5).isEmpty { d["cc"] = x.l(5) }
            if !x.l(6).isEmpty { d["bcc"] = x.l(6) }
            let texte = x.s(7)
            d["body"] = String(texte.prefix(maxCar))
            if texte.count > maxCar { d["truncated"] = true }
            let pj = x.l(8).compactMap { $0 as? [Any] }.map { p -> JSON in
                let nom = p.s(0)
                var j: JSON = ["name": nom, "size": p.n(1)]
                if let t = UTTypeLookup.mime(nom) { j["type"] = t }
                return j
            }
            if !pj.isEmpty { d["attachments"] = pj }
            if !x.s(9).isEmpty { d["headers"] = x.s(9) }
            if !x.s(10).isEmpty { d["source"] = x.s(10) }
            parId[id] = d
        }
        return ["messages": ids.map { parId[$0] ?? ["id": $0, "error": "message not found in the index"] }]
    }

    static func enregistrerPJ(_ a: JSON) throws -> Any {
        let ids = try a.reqInts("ids")
        let fm = FileManager.default
        let dossier = (a.nonEmpty("folder").map { ($0 as NSString).expandingTildeInPath } ?? NSHomeDirectory() + "/Downloads")
        try fm.createDirectory(atPath: dossier, withIntermediateDirectories: true)
        let noms = a.strings("names").map(Set.init)
        let refs = try refsMessages(ids)
        let tmp = try Conteneur.nouveau()
        defer { try? fm.removeItem(atPath: tmp) }
        var lignes: [String] = []
        for id in ids {
            guard let ref = refs[id] else { continue }
            try fm.createDirectory(atPath: "\(tmp)/\(id)", withIntermediateDirectories: true)
            lignes.append("""
            try
                set m to \(ref)
                set i to 0
                repeat with x in mail attachments of m
                    set i to i + 1
                    set n to name of x
                    if \(noms == nil ? "true" : "{\(noms!.map(AS.q).joined(separator: ","))} contains n") then
                        set p to \(AS.q("\(tmp)/\(id)/")) & i & "-" & n
                        save x in (POSIX file p)
                        set end of out to {\(id), n}
                    end if
                end repeat
            on error e
                set end of out to {\(id), "!ERR", e}
            end try
            """)
        }
        let r = lignes.isEmpty ? [] : (try AS.run("set out to {}\n" + lignes.joined(separator: "\n") + "\nreturn out") as? [Any] ?? [])
        var res: [Int: JSON] = [:]
        for x in r.compactMap({ $0 as? [Any] }) {
            let id = x.n(0)
            var d = res[id] ?? ["id": id, "files": [String]()]
            if x.s(1) == "!ERR" { d["error"] = x.s(2); res[id] = d; continue }
            res[id] = d
        }
        // Mail a écrit dans son conteneur : on déplace vers la destination, sans écraser
        for id in ids {
            let src = "\(tmp)/\(id)"
            var fichiers: [String] = []
            for f in ((try? fm.contentsOfDirectory(atPath: src)) ?? []).sorted() {
                let nom = f.split(separator: "-", maxSplits: 1).last.map(String.init) ?? f
                var dst = "\(dossier)/\(nom)", k = 2
                while fm.fileExists(atPath: dst) {
                    let base = (nom as NSString).deletingPathExtension, ext = (nom as NSString).pathExtension
                    dst = "\(dossier)/\(base) (\(k))" + (ext.isEmpty ? "" : ".\(ext)"); k += 1
                }
                try fm.moveItem(atPath: "\(src)/\(f)", toPath: dst)
                fichiers.append(dst)
            }
            var d = res[id] ?? ["id": id]
            d["files"] = fichiers
            if refs[id] == nil { d["error"] = "message not found in the index" }
            res[id] = d
        }
        return ["results": ids.map { res[$0]! }]
    }

    // MARK: - Écrire (AppleScript)

    static func marquer(_ a: JSON) throws -> Any {
        guard let mods = a.objects("changes"), !mods.isEmpty else { throw MCPError("missing parameter: changes") }
        let refs = try refsMessages(mods.compactMap { $0.int("id") })
        var echecs: [JSON] = [], lignes: [String] = []
        for m in mods {
            guard let id = m.int("id"), let ref = refs[id] else { echecs.append(["id": m["id"] ?? NSNull(), "error": "message not found"]); continue }
            var s: [String] = []
            if let v = m.bool("read") { s.append("set read status of m to \(v)") }
            if let v = m.bool("flagged") { s.append("set flagged status of m to \(v)") }
            if let c = m.nonEmpty("flag_color") {
                guard let i = couleursDrapeau[c] else { echecs.append(["id": id, "error": "unknown flag_color: \(c)"]); continue }
                s.append("set flagged status of m to true"); s.append("set flag index of m to \(i)")
            }
            if let c = m.nonEmpty("background_color") {
                guard let en = couleursFond[c] else { echecs.append(["id": id, "error": "unknown background_color: \(c)"]); continue }
                s.append("set background color of m to \(en)")
            }
            if let v = m.bool("junk") { s.append("set junk mail status of m to \(v)") }
            guard !s.isEmpty else { echecs.append(["id": id, "error": "no field to change"]); continue }
            lignes.append("try\nset m to \(ref)\n\(s.joined(separator: "\n"))\nset end of out to {\(id)}\non error e\nset end of out to {\(id), e}\nend try")
        }
        let r = lignes.isEmpty ? [] : (try AS.run("set out to {}\n" + lignes.joined(separator: "\n") + "\nreturn out") as? [Any] ?? [])
        var ok: [Int] = []
        for x in r.compactMap({ $0 as? [Any] }) {
            if x.count > 1 { echecs.append(["id": x.n(0), "error": x.s(1)]) } else { ok.append(x.n(0)) }
        }
        var out: JSON = ["updated": ok]
        if !echecs.isEmpty { out["failures"] = echecs }
        return out
    }

    static func deplacer(_ a: JSON) throws -> Any {
        let ids = try a.reqInts("ids")
        let dest = try a.req("mailbox_id").precomposedStringWithCanonicalMapping
        let destRef = try refBoite(dest)
        let copier = a.bool("copy") == true
        let refs = try refsMessages(ids)
        let avant = try Index.maxRowid()
        var glob: [Int: Int64] = [:]
        for r in try Index.rows("SELECT ROWID, global_message_id FROM messages WHERE ROWID IN (\(ids.map(String.init).joined(separator: ",")))") {
            if let i = r[0] as? Int64, let g = r[1] as? Int64 { glob[Int(i)] = g }
        }
        let verbe = copier ? "duplicate" : "move"
        let lignes = ids.compactMap { id in refs[id].map { "try\n\(verbe) \($0) to \(destRef)\nset end of out to {\(id)}\non error e\nset end of out to {\(id), e}\nend try" } }
        let r = lignes.isEmpty ? [] : (try AS.run("set out to {}\n" + lignes.joined(separator: "\n") + "\nreturn out") as? [Any] ?? [])
        var res: [Int: JSON] = [:]
        for x in r.compactMap({ $0 as? [Any] }) {
            res[x.n(0)] = x.count > 1 ? ["id": x.n(0), "ok": false, "error": x.s(1)] : ["id": x.n(0), "ok": true]
        }
        // Le message déplacé reçoit un nouvel identifiant : on le retrouve dans l'index (même global_message_id).
        // Plusieurs messages peuvent partager ce global_message_id (copie et original) : file d'attente par valeur.
        var attendus: [Int64: [Int]] = [:]
        for id in ids where res[id]?["ok"] as? Bool == true { if let g = glob[id] { attendus[g, default: []].append(id) } }
        var pris = Set<Int64>()
        let fin = Date().addingTimeInterval(4)
        while !attendus.isEmpty && Date() < fin {
            let rows = try Index.boites().filter { $0.id == dest }
            if !rows.isEmpty {
                for r in try Index.rows("SELECT ROWID, global_message_id FROM messages WHERE ROWID > ? AND mailbox IN (\(rows.map { String($0.rowid) }.joined(separator: ","))) AND global_message_id IN (\(attendus.keys.map(String.init).joined(separator: ","))) ORDER BY ROWID", [avant]) {
                    guard let n = r[0] as? Int64, let g = r[1] as? Int64, !pris.contains(n), var file = attendus[g], !file.isEmpty else { continue }
                    let id = file.removeFirst()
                    attendus[g] = file.isEmpty ? nil : file
                    pris.insert(n)
                    res[id]?["new_id"] = n
                }
            }
            if !attendus.isEmpty { Thread.sleep(forTimeInterval: 0.1) }
        }
        for id in attendus.values.flatMap({ $0 }) { res[id]?["warning"] = "done, but the new id is not indexed yet: look it up again with list_messages" }
        return ["mailbox": dest, "results": ids.map { res[$0] ?? ["id": $0, "ok": false, "error": "message not found in the index"] }]
    }

    static func supprimer(_ a: JSON) throws -> Any {
        let ids = try a.reqInts("ids")
        let refs = try refsMessages(ids)
        let lignes = ids.compactMap { id in refs[id].map { "try\ndelete \($0)\nset end of out to {\(id)}\non error e\nset end of out to {\(id), e}\nend try" } }
        let r = lignes.isEmpty ? [] : (try AS.run("set out to {}\n" + lignes.joined(separator: "\n") + "\nreturn out") as? [Any] ?? [])
        var ok: [Int] = [], echecs: [JSON] = ids.filter { refs[$0] == nil }.map { ["id": $0, "error": "message not found in the index"] }
        for x in r.compactMap({ $0 as? [Any] }) {
            if x.count > 1 { echecs.append(["id": x.n(0), "error": x.s(1)]) } else { ok.append(x.n(0)) }
        }
        var out: JSON = ["deleted": ok]
        if !echecs.isEmpty { out["failures"] = echecs }
        return out
    }
}

/// Type MIME déduit de l'extension (la propriété MIME type de Mail échoue)
enum UTTypeLookup {
    static func mime(_ nom: String) -> String? {
        let ext = (nom as NSString).pathExtension
        return ext.isEmpty ? nil : UTType(filenameExtension: ext)?.preferredMIMEType
    }
}
