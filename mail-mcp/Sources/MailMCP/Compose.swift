// Composition : brouillons (nouveau, réponse, transfert) et envoi, via AppleScript
import Foundation

enum Compose {
    /// "Nom <adresse>" → (nom, adresse)
    private static func destinataire(_ s: String) -> (String?, String) {
        if let o = s.lastIndex(of: "<"), let f = s.lastIndex(of: ">"), o < f {
            let nom = s[..<o].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (nom.isEmpty ? nil : nom, String(s[s.index(after: o)..<f]).trimmingCharacters(in: .whitespaces))
        }
        return (nil, s.trimmingCharacters(in: .whitespaces))
    }

    private static let dateCitation: DateFormatter = {
        let d = DateFormatter(); d.locale = Locale(identifier: "en_US_POSIX"); d.dateFormat = "MMMM d, yyyy 'at' HH:mm"; return d
    }()

    /// Réponse et transfert recomposés en nouveau message : les commandes reply/forward de Mail figent sa file
    /// Apple Events par intermittence (sondes 07-08, smoke test), ce qui bloque tout Mail jusqu'à ce qu'on le quitte.
    private static func recomposer(_ spec: JSON, tmp: inout String?) throws -> JSON {
        let reponse = spec.int("reply_to_id") != nil
        let id = spec.int("reply_to_id") ?? spec.int("forward_id")!
        guard let ref = try refsMessages([id])[id] else { throw MCPError("message \(id) not found in the index") }
        var savePJ = ""
        if !reponse {
            let dir = try tmp ?? Conteneur.nouveau()
            tmp = dir
            savePJ = """
            set i to 0
            repeat with x in mail attachments of m
                set i to i + 1
                set p to \(AS.q(dir + "/orig-")) & i & "-" & (name of x)
                save x in (POSIX file p)
                set end of pj to p
            end repeat
            """
        }
        let x = try AS.run("""
        set m to \(ref)
        set pj to {}
        \(savePJ)
        set rt to ""
        try
            set rt to reply to of m
        end try
        set miennes to {}
        repeat with c in accounts
            set miennes to miennes & (email addresses of c)
        end repeat
        return {subject of m, sender of m, rt, address of to recipients of m, address of cc recipients of m, date received of m, (content of m) as text, pj, miennes}
        """) as? [Any] ?? []
        let sujet = x.s(0), de = x.s(1), rt = x.s(2)
        let date = (x[5] as? Date).map(dateCitation.string) ?? ""
        let texte = x.s(6).trimmingCharacters(in: .whitespacesAndNewlines)
        var out = spec
        out["reply_to_id"] = nil; out["forward_id"] = nil
        let corps = spec.string("body") ?? ""
        if reponse {
            let dest = rt.isEmpty ? de : rt
            out["subject"] = spec.nonEmpty("subject") ?? (sujet.lowercased().hasPrefix("re:") ? sujet : "Re: " + sujet)
            out["to"] = [dest] + (spec.strings("to") ?? [])
            if spec.bool("reply_all") == true {
                let miennes = Set(x.l(8).compactMap { ($0 as? String)?.lowercased() })
                var vus = Set([destinataire(dest).1.lowercased()])
                let autres = (x.l(3) + x.l(4)).compactMap { $0 as? String }.filter { ad in
                    let k = ad.lowercased()
                    return !miennes.contains(k) && vus.insert(k).inserted
                }
                out["cc"] = autres + (spec.strings("cc") ?? [])
            }
            let cite = texte.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
            out["body"] = corps + "\n\nOn \(date), \(de) wrote:\n\n" + cite
        } else {
            out["subject"] = spec.nonEmpty("subject") ?? (sujet.lowercased().hasPrefix("fwd:") ? sujet : "Fwd: " + sujet)
            let entete = ["From: \(de)", "Subject: \(sujet)", "Date: \(date)",
                          "To: \(x.l(3).compactMap { $0 as? String }.joined(separator: ", "))"]
            out["body"] = corps + "\n\nBegin forwarded message:\n\n" + entete.joined(separator: "\n") + "\n\n" + texte
            out["attachments"] = (spec.strings("attachments") ?? []) + x.l(7).compactMap { $0 as? String }
        }
        return out
    }

    /// Script qui crée l'outgoing message `om` selon la spécification, puis exécute `fin` (save / send)
    private static func script(_ specInitiale: JSON, fin: String, tmp: inout String?) throws -> String {
        var s: [String] = []
        let spec = (specInitiale.int("reply_to_id") ?? specInitiale.int("forward_id")) != nil
            ? try recomposer(specInitiale, tmp: &tmp) : specInitiale
        let corps = spec.string("body")
        s.append("set om to make new outgoing message with properties {subject:\(AS.q(spec.string("subject") ?? "")), content:\(AS.q((corps ?? "") + "\n")), visible:false}")
        for (cle, type) in [("to", "to"), ("cc", "cc"), ("bcc", "bcc")] {
            for d in spec.strings(cle) ?? [] where !d.trimmingCharacters(in: .whitespaces).isEmpty {
                let (nom, adr) = destinataire(d)
                let props = nom.map { "{name:\(AS.q($0)), address:\(AS.q(adr))}" } ?? "{address:\(AS.q(adr))}"
                s.append("make new \(type) recipient at end of \(type) recipients of om with properties \(props)")
            }
        }
        if let e = spec.nonEmpty("from") { s.append("set sender of om to \(AS.q(e))") }
        if let sig = spec.nonEmpty("signature") { s.append("set message signature of om to signature \(AS.q(sig))") }
        let pjs = spec.strings("attachments") ?? []
        if !pjs.isEmpty {
            // Mail est en bac à sable : il ignore sans erreur un fichier hors de son conteneur (sonde 05) → copie
            let dir = try tmp ?? Conteneur.nouveau()
            tmp = dir
            for (i, p) in pjs.enumerated() {
                let src = (p as NSString).expandingTildeInPath
                guard FileManager.default.isReadableFile(atPath: src) else { throw MCPError("attachment not readable: \(p)") }
                try FileManager.default.createDirectory(atPath: "\(dir)/\(i)", withIntermediateDirectories: true)
                let dst = "\(dir)/\(i)/\((src as NSString).lastPathComponent)"
                try FileManager.default.copyItem(atPath: src, toPath: dst)
                s.append("tell content of om to make new attachment with properties {file name:(POSIX file \(AS.q(dst)))} at after last paragraph")
            }
            s.append("delay 0.5")
        }
        s.append(fin)
        return s.joined(separator: "\n")
    }

    private static func normal(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ").precomposedStringWithCanonicalMapping
    }

    /// Retrouve dans l'index le brouillon enregistré (nouvel identifiant dans une boîte Brouillons)
    private static func idBrouillon(sujet: String, apres: Int64, deja: Set<Int64>) throws -> Int64? {
        let fin = Date().addingTimeInterval(5)
        let cible = normal(sujet)
        repeat {
            let brouillons = try Index.boites().filter { Index.est($0, "brouillons") }
            if !brouillons.isEmpty {
                for r in try Index.rows("""
                SELECT m.ROWID, ifnull(m.subject_prefix,'') || ifnull(s.subject,'') FROM messages m LEFT JOIN subjects s ON s.ROWID = m.subject
                WHERE m.ROWID > ? AND m.deleted = 0 AND m.mailbox IN (\(brouillons.map { String($0.rowid) }.joined(separator: ","))) ORDER BY m.ROWID DESC
                """, [apres]) {
                    if let id = r[0] as? Int64, !deja.contains(id), normal(r[1] as? String ?? "") == cible { return id }
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < fin
        return nil
    }

    static func creerBrouillons(_ a: JSON) throws -> Any {
        guard let specs = a.objects("drafts"), !specs.isEmpty else { throw MCPError("missing parameter: drafts") }
        var res: [JSON] = [], pris = Set<Int64>()
        for spec in specs {
            var tmp: String?
            defer { if let t = tmp { try? FileManager.default.removeItem(atPath: t) } }
            do {
                let avant = try Index.maxRowid()
                // save, puis close sans enregistrer : un seul brouillon (close saving yes en recrée un)
                let sc = try script(spec, fin: "save om\nset sj to subject of om\nclose om saving no\nreturn sj", tmp: &tmp)
                let sujet = try AS.run(sc) as? String ?? ""
                var d: JSON = ["ok": true, "subject": sujet]
                if let id = try idBrouillon(sujet: sujet, apres: avant, deja: pris) { d["id"] = id; pris.insert(id) }
                else { d["warning"] = "draft saved, id not indexed yet" }
                res.append(d)
            } catch { res.append(["ok": false, "subject": spec.string("subject") ?? "", "error": "\(error)"]) }
        }
        let ok = res.filter { $0["ok"] as? Bool == true }.count
        return ["created": ok, "failed": res.count - ok, "results": res]
    }

    static func envoyer(_ a: JSON) throws -> Any {
        var res: [JSON] = []
        for spec in a.objects("messages") ?? [] {
            var tmp: String?
            do {
                let sujet = try AS.run(try script(spec, fin: "set sj to subject of om\nsend om\nreturn sj", tmp: &tmp)) as? String ?? ""
                res.append(["ok": true, "subject": sujet])
            } catch { res.append(["ok": false, "subject": spec.string("subject") ?? "", "error": "\(error)"]) }
            // tmp laissé en place : Mail peut encore lire les pièces jointes pendant l'envoi (purgé après une heure)
        }
        for id in a.ints("draft_ids") ?? [] {
            var tmp: String?
            do {
                // Un brouillon enregistré n'est plus un « outgoing message » : on le recompose, on l'envoie, puis on le supprime
                guard let ref = try refsMessages([id])[id] else { throw MCPError("draft \(id) not found in the index") }
                let dir = try Conteneur.nouveau()
                tmp = dir
                let x = try AS.run("""
                set m to \(ref)
                set pj to {}
                set i to 0
                repeat with a in mail attachments of m
                    set i to i + 1
                    set p to \(AS.q(dir + "/")) & i & "-" & (name of a)
                    save a in (POSIX file p)
                    set end of pj to p
                end repeat
                return {subject of m, sender of m, address of to recipients of m, address of cc recipients of m, address of bcc recipients of m, (content of m) as text, pj}
                """) as? [Any] ?? []
                let spec: JSON = ["subject": x.s(0), "from": x.s(1), "to": x.l(2), "cc": x.l(3), "bcc": x.l(4),
                                  "body": x.s(5).trimmingCharacters(in: .newlines), "attachments": x.l(6)]
                var t2: String? = dir
                let sujet = try AS.run(try script(spec, fin: "set sj to subject of om\nsend om\nreturn sj", tmp: &t2)) as? String ?? ""
                try AS.run("delete \(ref)")
                res.append(["ok": true, "draft_id": id, "subject": sujet])
            } catch { res.append(["ok": false, "draft_id": id, "error": "\(error)"]) }
            _ = tmp
        }
        guard !res.isEmpty else { throw MCPError("nothing to send: provide messages or draft_ids") }
        let ok = res.filter { $0["ok"] as? Bool == true }.count
        return ["sent": ok, "failed": res.count - ok, "results": res]
    }
}
