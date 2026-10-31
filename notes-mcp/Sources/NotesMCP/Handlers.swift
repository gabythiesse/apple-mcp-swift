// Logique des outils : AppleScript pour tout ce qui lit et écrit dans Notes, base en lecture seule pour tags/épinglage
import Foundation

private func arr(_ x: Any?) -> [Any] { x as? [Any] ?? [] }
private func str(_ x: Any?) -> String { x as? String ?? "" }

/// Dossier connu de chaque note : accélère « note id X of folder id F » (sinon résolution lente au niveau de l'app)
enum Hints {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()
    static func set(_ note: String, _ folder: String) { lock.lock(); cache[note] = folder; lock.unlock() }
    static func get(_ note: String) -> String? { lock.lock(); defer { lock.unlock() }; return cache[note] }

    /// Dossier probable de chaque note (cache, puis base)
    static func folders(_ notes: [String]) -> [String: String] {
        var out: [String: String] = [:]
        var manquants: [Int: String] = [:]
        for n in notes {
            if let f = get(n) { out[n] = f } else if let pk = IDs.pk(n) { manquants[pk] = n }
        }
        if !manquants.isEmpty, let store = IDs.store {
            for (npk, fpk) in DB.folderOf(Array(manquants.keys)) { out[manquants[npk]!] = "x-coredata://\(store)/ICFolder/p\(fpk)" }
        }
        return out
    }
}

private let corbeilleNoms: Set<String> = ["Recently Deleted", "Supprimées récemment"]

enum Handlers {

    // MARK: - Dossiers

    static func dossiers(_ a: JSON) throws -> Any {
        let filtre = a.nonEmpty("nom_contient")
        let r = arr(try AS.run("set FILTRE to \(AS.q(filtre ?? ""))\n" + """
        set out to {}
        repeat with ac in accounts
          set ac to contents of ac
          set dfid to ""
          try
            set dfid to id of default folder of ac
          end try
          set fl to my tree(ac)
          set rows to {}
          repeat with x in fl
            if FILTRE is "" or (item 2 of x) contains FILTRE then
              set end of rows to {item 1 of x, item 2 of x, item 3 of x, count of notes of folder id (item 1 of x)}
            end if
          end repeat
          set end of out to {id of ac, name of ac, dfid, rows}
        end repeat
        return {id of default account, out}
        """))
        let defAcc = str(r.first)
        let trash = DB.trashFolders()
        let comptes: [JSON] = arr(r.last).map { x in
            let c = arr(x)
            var d: JSON = ["id": IDs.short(str(c[0])), "nom": str(c[1])]
            if str(c[0]) == defAcc { d["par_defaut"] = true }
            if !str(c[2]).isEmpty { d["dossier_par_defaut"] = IDs.short(str(c[2])) }
            d["dossiers"] = arr(c[3]).map { y -> JSON in
                let f = arr(y)
                var o: JSON = ["id": IDs.short(str(f[0])), "nom": str(f[1]), "nb_notes": f[3]]
                if !str(f[2]).isEmpty { o["parent_id"] = IDs.short(str(f[2])) }
                if corbeilleNoms.contains(str(f[1])) || (IDs.pk(str(f[0])).map { trash?.contains($0) ?? false } ?? false) { o["corbeille"] = true }
                return o
            }
            return d
        }
        return ["comptes": comptes]
    }

    static func creerDossier(_ a: JSON) throws -> Any {
        let nom = try a.req("nom")
        let parent = try a.nonEmpty("parent_id").map { "folder id \(AS.q(try IDs.full($0)))" }
            ?? a.nonEmpty("compte_id").map { "account id \(AS.q(try IDs.full($0)))" } ?? "default account"
        let subs = a.strings("sous_dossiers") ?? []
        let r = arr(try AS.run("""
        set f to make new folder at \(parent) with properties {name:\(AS.q(nom))}
        set subs to {}
        repeat with s in \(AS.list(subs))
          set end of subs to id of (make new folder at f with properties {name:(contents of s)})
        end repeat
        return {id of f, subs}
        """))
        var out: JSON = ["ok": true, "id": IDs.short(str(r[0])), "nom": nom]
        let s = IDs.shorts(r[1])
        if !s.isEmpty { out["sous_dossiers"] = zip(subs, s).map { ["id": $1, "nom": $0] } }
        return out
    }

    static func renommerDossier(_ a: JSON) throws -> Any {
        let id = try IDs.full(try a.req("id")), nom = try a.req("nom")
        _ = try AS.run("set name of folder id \(AS.q(id)) to \(AS.q(nom))")
        return ["ok": true, "id": IDs.short(id), "nom": nom]
    }

    /// Notes AppleScript ne supprime de façon fiable qu'un dossier vide, et ne supprime pas ses sous-dossiers :
    /// on vide chaque dossier (notes envoyées une à une dans « Supprimées récemment », restaurables),
    /// puis on supprime du plus profond au parent, et on vérifie qu'il ne reste rien.
    static func supprimerDossier(_ a: JSON) throws -> Any {
        let id = try IDs.full(try a.req("id"))
        let r = arr(try AS.run("""
        set fid0 to \(AS.q(id))
        set nm to name of folder id fid0
        set fl to {}
        repeat with ac in accounts
          set fl to fl & my tree(contents of ac)
        end repeat
        set sel to my subtree(fl, fid0)
        set nb to 0
        repeat with k from (count of sel) to 1 by -1
          set fo to folder id (item k of sel)
          set nids to id of notes of fo
          repeat with nid in nids
            delete note id (contents of nid) of fo
            set nb to nb + 1
          end repeat
          delete fo
        end repeat
        set restants to {}
        repeat with x in sel
          try
            get name of folder id (contents of x)
            set end of restants to contents of x
          end try
        end repeat
        return {nm, nb, (count of sel) - 1, restants}
        """, timeout: 600))
        var out: JSON = ["ok": true, "supprime": IDs.short(id), "nom": str(r[0]), "notes_en_corbeille": r[1], "sous_dossiers_supprimes": r[2]]
        let restants = IDs.shorts(r[3])
        if !restants.isEmpty { out["ok"] = false; out["non_supprimes"] = restants }
        return out
    }

    // MARK: - Notes : lecture

    static func notes(_ a: JSON) throws -> Any {
        let limite = max(1, a.int("limite") ?? 20)
        var clauses: [String] = [], prep = ""
        if let t = a.nonEmpty("texte") { clauses.append("(name contains \(AS.q(t)) or plaintext contains \(AS.q(t)))") }
        if let d = a.nonEmpty("modifiees_depuis") { prep += "set d1 to \(AS.date(try Contenu.parseDate(d)))\n"; clauses.append("modification date ≥ d1") }
        if let d = a.nonEmpty("modifiees_avant") { prep += "set d2 to \(AS.date(try Contenu.parseDate(d)))\n"; clauses.append("modification date < d2") }
        let source = clauses.isEmpty ? "notes of fo" : "(notes of fo whose \(clauses.joined(separator: " and ")))"

        // Filtres qui passent par la base
        var garder: Set<Int>? = nil
        if let tag = a.nonEmpty("tag") {
            guard let s = DB.notesWithTag(tag) else { throw MCPError("le filtre tag nécessite l'Accès complet au disque pour NotesMCP") }
            garder = s
        }
        if a.bool("epinglees") == true {
            guard let s = DB.pinned() else { throw MCPError("le filtre epinglees nécessite l'Accès complet au disque pour NotesMCP") }
            garder = garder.map { $0.intersection(s) } ?? s
        }

        let dossier = try a.nonEmpty("dossier_id").map(IDs.full)
        let inclureCorbeille = dossier != nil || a.bool("supprimees") == true
        let trashIDs = inclureCorbeille ? [] : (DB.trashFolders() ?? []).compactMap { pk in IDs.store.map { "x-coredata://\($0)/ICFolder/p\(pk)" } }
        var items: [String: (titre: String, fid: String, fnom: String, mod: Date?)] = [:]
        if let d = dossier {
            // Un dossier (et ses sous-dossiers) : un « whose » par dossier
            let cible = a.bool("sous_dossiers") == false ? "set sel to {\(AS.q(d))}" : "set sel to my subtree(fl, \(AS.q(d)))"
            let r = arr(try AS.run("""
            \(prep)set fl to {}
            repeat with ac in accounts
              set fl to fl & my tree(contents of ac)
            end repeat
            \(cible)
            set out to {}
            repeat with fid in sel
              set fid to contents of fid
              set fo to folder id fid
              set {i, n, m} to {id, name, modification date} of \(source)
              if (count of i) > 0 then set end of out to {fid, my nameOf(fl, fid), i, n, m}
            end repeat
            return out
            """))
            for g in r {
                let g = arr(g), ids = arr(g[2]), noms = arr(g[3]), mods = arr(g[4])
                for k in ids.indices { items[str(ids[k])] = (str(noms[k]), str(g[0]), str(g[1]), mods[k] as? Date) }
            }
        } else {
            // Tout : titres et dates en un « whose » au niveau de l'app (« id of container » en lot ne renvoie que
            // missing value). Dossier de chaque note : la base si elle est lisible (une requête), sinon un
            // « id of notes » par dossier. La corbeille est toujours lue par AppleScript (la base a du retard).
            let src = clauses.isEmpty ? "notes" : "(notes whose \(clauses.joined(separator: " and ")))"
            let avecBase = DB.available
            let corbNoms = AS.list(Array(corbeilleNoms)), corbIDs = AS.list(trashIDs)
            let r = arr(try AS.run("""
            \(prep)set fl to {}
            repeat with ac in accounts
              set fl to fl & my tree(contents of ac)
            end repeat
            set {i, n, m} to {id, name, modification date} of \(src)
            set fmap to {}
            if (count of i) > 0 then
              repeat with x in fl
                set fid to item 1 of x
                set corb to (item 2 of x) is in \(corbNoms) or fid is in \(corbIDs)
                if corb or not \(avecBase) then set end of fmap to {fid, id of notes of folder id fid, corb}
              end repeat
            end if
            return {fl, i, n, m, fmap}
            """))
            var noms: [String: String] = [:]
            for f in arr(r[0]) { let f = arr(f); noms[str(f[0])] = str(f[1]) }
            var dossierDe: [String: String] = [:], enCorbeille = Set<String>()
            for x in arr(r[4]) {
                let x = arr(x)
                for nid in arr(x[1]) { dossierDe[str(nid)] = str(x[0]); if x[2] as? Bool == true { enCorbeille.insert(str(nid)) } }
            }
            let ids = arr(r[1]).map(str), titres = arr(r[2]), mods = arr(r[3])
            _ = ids.first.map(IDs.short)  // fait connaître l'identifiant du magasin
            if avecBase, let store = IDs.store {
                let manquants = ids.filter { dossierDe[$0] == nil }
                let parPK = Dictionary(manquants.compactMap { id in IDs.pk(id).map { ($0, id) } }, uniquingKeysWith: { a, _ in a })
                for (npk, fpk) in DB.folderOf(Array(parPK.keys)) { dossierDe[parPK[npk]!] = "x-coredata://\(store)/ICFolder/p\(fpk)" }
            }
            for k in ids.indices {
                let id = ids[k]
                if !inclureCorbeille && enCorbeille.contains(id) { continue }
                let fid = dossierDe[id] ?? ""
                items[id] = (str(titres[k]), fid, noms[fid] ?? "", mods[k] as? Date)
            }
        }
        var tri = items.filter { garder == nil || IDs.pk($0.key).map(garder!.contains) == true }
            .sorted { ($0.value.mod ?? .distantPast) > ($1.value.mod ?? .distantPast) }
        let total = tri.count
        tri = Array(tri.prefix(limite))
        let flags = DB.flags(tri.compactMap { IDs.pk($0.key) })
        let notes: [JSON] = tri.map { (id, v) in
            Hints.set(id, v.fid)
            var o: JSON = ["id": IDs.short(id), "titre": v.titre, "dossier_id": IDs.short(v.fid), "dossier": v.fnom]
            if let m = Contenu.iso(v.mod) { o["modifiee"] = m }
            if let pk = IDs.pk(id), let f = flags?[pk] {
                if f.epinglee { o["epinglee"] = true }
                if f.checklist { o["checklist"] = true }
                if !f.tags.isEmpty { o["tags"] = f.tags }
            }
            return o
        }
        var out: JSON = ["total": total, "notes": notes]
        if total > notes.count { out["tronque"] = "\(notes.count) sur \(total) : augmenter limite ou filtrer" }
        return out
    }

    static func lireNotes(_ a: JSON) throws -> Any {
        let ids = try (a.strings("ids") ?? []).map(IDs.full)
        guard !ids.isEmpty else { throw MCPError("paramètre manquant : ids") }
        let html = a.string("format") == "html"
        let maxc = a.int("max_caracteres") ?? 20000
        let hints = Hints.folders(ids)
        let items = "{" + ids.map { "{\(AS.q($0)), \(AS.q(hints[$0] ?? ""))}" }.joined(separator: ", ") + "}"
        let r = arr(try AS.run("""
        set out to {}
        set L to \(items)
        repeat with k from 1 to count of L
          set x1 to item k of L
          try
            set n to my getNote(item 1 of x1, item 2 of x1)
            set p to properties of n
            set c to container of p
            set prot to password protected of p
            set contenu to ""
            if not prot then set contenu to \(html ? "body" : "plaintext") of p
            set {ci, cn} to {id, name} of c
            set end of out to {"ok", id of p, name of p, ci, cn, creation date of p, modification date of p, prot, shared of p, contenu, id of attachments of n, name of attachments of n}
          on error e
            set end of out to {"err", item 1 of x1, e}
          end try
        end repeat
        return out
        """))
        let oks = r.map(arr).filter { str($0.first) == "ok" }
        let flags = DB.flags(oks.compactMap { IDs.pk(str($0[1])) })
        let notes: [JSON] = r.map { x in
            let v = arr(x)
            guard str(v.first) == "ok" else { return ["id": IDs.short(str(v[1])), "ok": false, "erreur": str(v[2])] }
            Hints.set(str(v[1]), str(v[3]))
            var o: JSON = ["id": IDs.short(str(v[1])), "titre": str(v[2]), "dossier_id": IDs.short(str(v[3])), "dossier": str(v[4])]
            if let d = Contenu.iso(v[5]) { o["creee"] = d }
            if let d = Contenu.iso(v[6]) { o["modifiee"] = d }
            if v[7] as? Bool == true { o["verrouillee"] = true; o["contenu"] = "(note verrouillée : contenu illisible)" }
            else {
                var c = html ? Contenu.nettoyer(str(v[9])) : Contenu.texte(str(v[9]))
                if c.count > maxc { c = String(c.prefix(maxc)); o["tronque"] = true }
                o["contenu"] = c
            }
            if v[8] as? Bool == true { o["partagee"] = true }
            // AppleScript liste chaque pièce jointe deux fois : dédoublonnage par identifiant
            var vus = Set<String>(), pjs: [JSON] = []
            for (pid, nom) in zip(arr(v[10]), arr(v[11])) where vus.insert(str(pid)).inserted {
                pjs.append(["id": IDs.short(str(pid)), "nom": str(nom)])
            }
            if !pjs.isEmpty { o["pieces_jointes"] = pjs }
            if let pk = IDs.pk(str(v[1])), let f = flags?[pk] {
                if f.epinglee { o["epinglee"] = true }
                if f.checklist { o["checklist"] = true }
                if !f.tags.isEmpty { o["tags"] = f.tags }
            }
            return o
        }
        return ["notes": notes]
    }

    // MARK: - Notes : écriture

    /// Création sans « id of make » (≈1 s par note) : on relit les identifiants du dossier en un lot après coup
    static func creerNotes(_ a: JSON) throws -> Any {
        let entrees = a.objects("notes") ?? []
        guard !entrees.isEmpty else { throw MCPError("paramètre manquant : notes") }
        var resultats = [JSON?](repeating: nil, count: entrees.count)
        var groupes: [(dossier: String, idx: [Int], titres: [String], corps: [String])] = []
        for (k, e) in entrees.enumerated() {
            guard let titre = e.nonEmpty("titre")?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                resultats[k] = ["ok": false, "erreur": "titre manquant"]; continue
            }
            let d: String
            do { d = try e.nonEmpty("dossier_id").map(IDs.full) ?? "" } catch { resultats[k] = ["ok": false, "titre": titre, "erreur": "\(error)"]; continue }
            let corps = Contenu.titre(titre) + (Contenu.corps(e, html: "html", texte: "texte") ?? "")
            if let g = groupes.firstIndex(where: { $0.dossier == d }) {
                groupes[g].idx.append(k); groupes[g].titres.append(titre); groupes[g].corps.append(corps)
            } else { groupes.append((d, [k], [titre], [corps])) }
        }
        if !groupes.isEmpty {
            let script = groupes.map { g in """
            try
              set f to \(g.dossier.isEmpty ? "default folder of default account" : "folder id \(AS.q(g.dossier))")
              set fid to id of f
              set avant to id of notes of f
              set errs to {}
              set B to \(AS.list(g.corps))
              repeat with k from 1 to count of B
                try
                  make new note at f with properties {body:item k of B}
                on error e
                  set end of errs to {k, e}
                end try
              end repeat
              set end of out to {fid, avant, id of notes of f, name of notes of f, errs}
            on error e
              set end of out to {"", {}, {}, {}, {{0, e}}}
            end try
            """ }.joined(separator: "\n")
            let r = arr(try AS.run("set out to {}\n" + script + "\nreturn out", timeout: 600))
            for (g, x) in zip(groupes, r) {
                let v = arr(x), fid = str(v[0])
                var errs: [Int: String] = [:]
                for e in arr(v[4]) { let p = arr(e); errs[p[0] as? Int ?? 0] = str(p[1]) }
                let avant = Set(arr(v[1]).map(str))
                var pool = zip(arr(v[2]).map(str), arr(v[3]).map(str)).filter { !avant.contains($0.0) }
                for (j, k) in g.idx.enumerated() {
                    let titre = g.titres[j]
                    if let e = errs[j + 1] ?? errs[0] { resultats[k] = ["ok": false, "titre": titre, "erreur": e]; continue }
                    let pos = pool.firstIndex { $0.1.trimmingCharacters(in: .whitespacesAndNewlines) == titre } ?? (pool.isEmpty ? nil : 0)
                    guard let p = pos else { resultats[k] = ["ok": true, "titre": titre, "avertissement": "créée, identifiant non retrouvé"]; continue }
                    let id = pool.remove(at: p).0
                    Hints.set(id, fid)
                    resultats[k] = ["ok": true, "id": IDs.short(id), "titre": titre, "dossier_id": IDs.short(fid)]
                }
            }
        }
        let res = resultats.map { $0 ?? ["ok": false, "erreur": "non traité"] }
        return ["crees": res.filter { $0["ok"] as? Bool == true }.count, "echecs": res.filter { $0["ok"] as? Bool != true }.count, "resultats": res]
    }

    static func modifierNotes(_ a: JSON) throws -> Any {
        let mods = a.objects("modifications") ?? []
        guard !mods.isEmpty else { throw MCPError("paramètre manquant : modifications") }
        var blocs: [String] = []
        var erreurs: [Int: String] = [:]
        let ids = mods.compactMap { try? IDs.full($0.nonEmpty("id") ?? "") }
        let hints = Hints.folders(ids)
        let flags = DB.flags(ids.compactMap(IDs.pk)) ?? [:]
        for (k, m) in mods.enumerated() {
            do {
                let nid = try IDs.full(try m.req("id"))
                var s = "set n to my getNote(\(AS.q(nid)), \(AS.q(hints[nid] ?? "")))\n"
                let titre = m.nonEmpty("titre")?.trimmingCharacters(in: .whitespacesAndNewlines)
                let contenu = Contenu.corps(m, html: "html", texte: "texte")
                let ajout = Contenu.corps(m, html: "ajouter_html", texte: "ajouter_texte")
                // Réécrire le HTML recrée les pièces jointes (doublons, fichiers perdus) et aplatit tags et cases à cocher
                if titre != nil || contenu != nil || ajout != nil {
                    if let f = IDs.pk(nid).flatMap({ flags[$0] }), f.checklist || !f.tags.isEmpty {
                        throw MCPError("contenu non modifiable par script : la note a des \(f.checklist ? "cases à cocher" : "tags") que Notes perdrait. Seul le déplacement (dossier_id) est possible")
                    }
                    s += "if (count of attachments of n) > 0 then error \"contenu non modifiable par script : la note a des pièces jointes que Notes dupliquerait ou perdrait. Seul le déplacement (dossier_id) est possible\"\n"
                }
                switch (titre, contenu) {
                case let (t?, c?): s += "set body of n to \(AS.q(Contenu.titre(t) + c))\n"
                case let (nil, c?): s += "set body of n to \"<div><h1>\" & my esc(name of n) & \"</h1></div>\" & \(AS.q(c))\n"
                case let (t?, nil): s += """
                    set b to body of n
                    set p to offset of "</div>" in b
                    if p = 0 then
                      set body of n to \(AS.q(Contenu.titre(t))) & b
                    else if p + 6 > (length of b) then
                      set body of n to \(AS.q(Contenu.titre(t)))
                    else
                      set body of n to \(AS.q(Contenu.titre(t))) & (text (p + 6) thru -1 of b)
                    end if

                    """
                default: break
                }
                if let aj = ajout {
                    s += "set body of n to (body of n) & \(AS.q(aj))\n"
                }
                if let d = try m.nonEmpty("dossier_id").map(IDs.full) {
                    s += "move n to folder id \(AS.q(d))\nset n to note id \(AS.q(nid)) of folder id \(AS.q(d))\n"
                }
                blocs.append("""
                try
                \(s)set c to container of n
                  set end of out to {"ok", id of n, name of n, id of c}
                on error e
                  set end of out to {"err", e}
                end try
                """)
            } catch {
                erreurs[k] = "\(error)"
                blocs.append("set end of out to {\"err\", \"\"}")
            }
        }
        let r = arr(try AS.run("set out to {}\n" + blocs.joined(separator: "\n") + "\nreturn out", timeout: 600))
        let res: [JSON] = zip(mods, r).enumerated().map { k, p in
            let v = arr(p.1)
            if let e = erreurs[k] { return ["ok": false, "id": p.0.string("id") ?? "", "erreur": e] }
            guard str(v.first) == "ok" else { return ["ok": false, "id": p.0.string("id") ?? "", "erreur": str(v.last)] }
            Hints.set(str(v[1]), str(v[3]))
            var o: JSON = ["ok": true, "id": IDs.short(str(v[1])), "titre": str(v[2])]
            if p.0.has("dossier_id") { o["dossier_id"] = IDs.short(str(v[3])) }
            return o
        }
        return ["modifiees": res.filter { $0["ok"] as? Bool == true }.count, "echecs": res.filter { $0["ok"] as? Bool != true }.count, "resultats": res]
    }

    static func supprimerNotes(_ a: JSON) throws -> Any {
        let ids = try (a.strings("ids") ?? []).map(IDs.full)
        guard !ids.isEmpty else { throw MCPError("paramètre manquant : ids") }
        let definitif = a.bool("definitif") == true
        let hints = Hints.folders(ids)
        let trash = (DB.trashFolders() ?? []).sorted().first.flatMap { pk in IDs.store.map { "x-coredata://\($0)/ICFolder/p\(pk)" } } ?? ""
        let items = "{" + ids.map { "{\(AS.q($0)), \(AS.q(hints[$0] ?? ""))}" }.joined(separator: ", ") + "}"
        let r = arr(try AS.run("""
        set out to {}
        set L to \(items)
        repeat with k from 1 to count of L
          set x1 to item k of L
          try
            delete my getNote(item 1 of x1, item 2 of x1)
            \(definitif ? "try\n      delete my getNote(item 1 of x1, \(AS.q(trash)))\n    end try" : "")
            set end of out to {"ok"}
          on error e
            set end of out to {"err", e}
          end try
        end repeat
        return out
        """, timeout: 600))
        let res: [JSON] = zip(ids, r).map { id, x in
            let v = arr(x)
            guard str(v.first) == "ok" else { return ["ok": false, "id": IDs.short(id), "erreur": str(v.last)] }
            if !definitif && !trash.isEmpty { Hints.set(id, trash) }  // la note est maintenant dans la corbeille
            return ["ok": true, "id": IDs.short(id)]
        }
        return ["supprimees": res.filter { $0["ok"] as? Bool == true }.count, "definitif": definitif, "resultats": res]
    }

    static func ouvrirNote(_ a: JSON) throws -> Any {
        let id = try IDs.full(try a.req("id"))
        _ = try AS.run("show my getNote(\(AS.q(id)), \(AS.q(Hints.folders([id])[id] ?? "")))\nactivate")
        return ["ok": true, "id": IDs.short(id)]
    }

    // MARK: - Pièces jointes

    static func ajouterPiecesJointes(_ a: JSON) throws -> Any {
        let pieces = a.objects("pieces") ?? []
        guard !pieces.isEmpty else { throw MCPError("paramètre manquant : pieces") }
        let ids = pieces.compactMap { try? IDs.full($0.nonEmpty("note_id") ?? "") }
        let hints = Hints.folders(ids)
        var blocs: [String] = [], erreurs: [Int: String] = [:]
        for (k, p) in pieces.enumerated() {
            do {
                let nid = try IDs.full(try p.req("note_id"))
                let chemin = (try p.req("chemin") as NSString).expandingTildeInPath
                guard chemin.hasPrefix("/"), FileManager.default.fileExists(atPath: chemin) else { throw MCPError("fichier introuvable : \(chemin)") }
                blocs.append("""
                try
                  set n to my getNote(\(AS.q(nid)), \(AS.q(hints[nid] ?? "")))
                  set pj to make new attachment at n with data (POSIX file \(AS.q(chemin)))
                  set end of out to {"ok", id of n, id of pj, name of pj}
                on error e
                  set end of out to {"err", e}
                end try
                """)
            } catch { erreurs[k] = "\(error)"; blocs.append("set end of out to {\"err\", \"\"}") }
        }
        let r = arr(try AS.run("set out to {}\n" + blocs.joined(separator: "\n") + "\nreturn out", timeout: 600))
        let res: [JSON] = zip(pieces, r).enumerated().map { k, p in
            let v = arr(p.1)
            if let e = erreurs[k] { return ["ok": false, "note_id": p.0.string("note_id") ?? "", "erreur": e] }
            guard str(v.first) == "ok" else { return ["ok": false, "note_id": p.0.string("note_id") ?? "", "erreur": str(v.last)] }
            return ["ok": true, "note_id": IDs.short(str(v[1])), "id": IDs.short(str(v[2])), "nom": str(v[3])]
        }
        return ["ajoutees": res.filter { $0["ok"] as? Bool == true }.count, "resultats": res]
    }

    /// Référence AppleScript d'une pièce jointe, par sa note quand la base la connaît
    private static func refsPJ(_ ids: [String]) -> [String: String] {
        var notes: [String: String] = [:]
        if let store = IDs.store {
            for (apk, npk) in DB.noteOfAttachments(ids.compactMap(IDs.pk)) {
                if let aid = ids.first(where: { IDs.pk($0) == apk }) { notes[aid] = "x-coredata://\(store)/ICNote/p\(npk)" }
            }
        }
        let hints = Hints.folders(Array(notes.values))
        return Dictionary(uniqueKeysWithValues: ids.map { aid in
            if let n = notes[aid] { return (aid, "attachment id \(AS.q(aid)) of (my getNote(\(AS.q(n)), \(AS.q(hints[n] ?? ""))))") }
            return (aid, "attachment id \(AS.q(aid))")
        })
    }

    // Pas de suppression de pièce jointe : « delete attachment » ne retire qu'une entrée du listing AppleScript,
    // la pièce reste dans la note (vérifié en base après 3 min, sondes 28 à 30).

    /// Notes enregistre dans un dossier de transit (dans la destination), puis le serveur déplace sans jamais écraser
    static func exporterPiecesJointes(_ a: JSON) throws -> Any {
        let dest = (try a.req("dossier") as NSString).expandingTildeInPath
        guard dest.hasPrefix("/") else { throw MCPError("dossier : chemin absolu attendu") }
        let pjIDs = try (a.strings("ids") ?? []).map(IDs.full)
        let noteIDs = try (a.strings("note_ids") ?? []).map(IDs.full)
        guard !pjIDs.isEmpty || !noteIDs.isEmpty else { throw MCPError("paramètre manquant : ids ou note_ids") }
        let fm = FileManager.default
        try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
        let transit = dest + "/.notes-mcp-\(UUID().uuidString)"
        try fm.createDirectory(atPath: transit, withIntermediateDirectories: false)
        defer { try? fm.removeItem(atPath: transit) }
        let refs = refsPJ(pjIDs)
        let hints = Hints.folders(noteIDs)
        var s = "set out to {}\nset vus to {}\nset k to 0\nset R to {}\n"
        for n in noteIDs {
            s += """
            try
              set n to my getNote(\(AS.q(n)), \(AS.q(hints[n] ?? "")))
              repeat with pj in attachments of n
                set end of R to contents of pj
              end repeat
            on error e
              set end of out to {"err", \(AS.q(n)), e}
            end try

            """
        }
        for p in pjIDs {
            s += "try\nset end of R to \(refs[p]!)\non error e\nset end of out to {\"err\", \(AS.q(p)), e}\nend try\n"
        }
        s += """
        repeat with pj in R
          set pj to contents of pj
          try
            set pid to id of pj
            if pid is not in vus then
              set end of vus to pid
              set k to k + 1
              save pj in POSIX file (\(AS.q(transit + "/")) & k)
              set end of out to {"ok", pid, name of pj, k}
            end if
          on error e
            set end of out to {"err", "", e}
          end try
        end repeat
        return out
        """
        let r = arr(try AS.run(s, timeout: 600))
        var res: [JSON] = []
        for x in r {
            let v = arr(x)
            guard str(v.first) == "ok" else { res.append(["ok": false, "id": IDs.short(str(v[1])), "erreur": str(v[2])]); continue }
            let pid = IDs.short(str(v[1])), k = "\(v[3])"
            var nom = str(v[2]).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            if nom.isEmpty || nom.hasPrefix(".") { nom = pid + nom }
            let staged = (try? fm.contentsOfDirectory(atPath: transit))?.first { $0 == k || $0.hasPrefix(k + ".") }
            guard let st = staged else { res.append(["ok": false, "id": pid, "erreur": "Notes n'a pas enregistré le fichier"]); continue }
            if (nom as NSString).pathExtension.isEmpty, !(st as NSString).pathExtension.isEmpty { nom += "." + (st as NSString).pathExtension }
            let cible = dest + "/" + nom
            if fm.fileExists(atPath: cible) { res.append(["ok": false, "id": pid, "erreur": "existe déjà, non écrasé : \(cible)"]); continue }
            do { try fm.moveItem(atPath: transit + "/" + st, toPath: cible); res.append(["ok": true, "id": pid, "fichier": cible]) }
            catch { res.append(["ok": false, "id": pid, "erreur": "\(error.localizedDescription)"]) }
        }
        return ["exportees": res.filter { $0["ok"] as? Bool == true }.count, "resultats": res]
    }

    // MARK: - Tags (base)

    static func tags(_ a: JSON) throws -> Any {
        var dossiers: [Int]? = nil
        if let d = a.nonEmpty("dossier_id") {
            guard let pk = IDs.pk(try IDs.full(d)) else { throw MCPError("dossier_id invalide") }
            dossiers = DB.folderTree(pk)
        }
        guard let t = DB.tags(folders: dossiers) else { throw MCPError("les tags se lisent dans la base de Notes : donne l'Accès complet au disque à NotesMCP (Réglages Système > Confidentialité et sécurité)") }
        return ["tags": t.map { ["tag": $0.0, "nb_notes": $0.1] }]
    }
}
