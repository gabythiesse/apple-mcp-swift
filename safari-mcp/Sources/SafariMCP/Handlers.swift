// Logique des outils : AppleScript pour les fenêtres et onglets, fichiers en lecture seule pour le reste
import Foundation

enum Handlers {

    // MARK: - Arguments

    private static func refs(_ a: JSON, _ key: String = "onglets") throws -> [TabRef] {
        let objs = a.objects(key) ?? []
        if objs.isEmpty { return [try AS.currentTab()] }
        return try objs.map { o in
            guard let w = o.int("fenetre_id"), let i = o.int("index") else { throw MCPError("chaque onglet demande fenetre_id et index") }
            return TabRef(fenetre: w, index: i)
        }
    }

    /// https:// ajouté si absent, chemin local converti en file://
    static func normaliser(_ u: String) -> String {
        let t = u.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains("://") || t.hasPrefix("about:") || t.hasPrefix("data:") || t.hasPrefix("javascript:") { return t }
        if t.hasPrefix("/") || t.hasPrefix("~") { return URL(fileURLWithPath: (t as NSString).expandingTildeInPath).absoluteString }
        return "https://" + t
    }

    private static func tronquer(_ s: String, _ max: Int) -> (String, Bool) {
        s.count > max ? (String(s.prefix(max)), true) : (s, false)
    }

    // MARK: - Onglets

    static func onglets(_ a: JSON) throws -> Any {
        let cible = a.int("fenetre_id").map { "{window id \($0)}" } ?? "(every window whose visible is true)"
        let d = try AS.run("""
        tell application "Safari"
          set out to {}
          repeat with w in \(cible)
            set ct to 0
            try
              set ct to index of current tab of w
            end try
            set end of out to {id of w, ct, name of every tab of w, URL of every tab of w}
          end repeat
          return out
        end tell
        """)
        let filtre = a.nonEmpty("texte").map(fold)
        var tous: [JSON] = []
        for w in d.items {
            let l = w.items
            guard l.count == 4, let wid = l[0].int else { continue }
            let actif = l[1].int ?? 0
            let noms = l[2].items, urls = l[3].items
            for (k, nom) in noms.enumerated() {
                let titre = nom.string ?? ""
                let url = k < urls.count ? urls[k].string ?? "about:blank" : ""
                if let filtre, !fold(titre + " " + url).contains(filtre) { continue }
                var o: JSON = ["fenetre_id": wid, "index": k + 1, "titre": titre, "url": url]
                if k + 1 == actif { o["actif"] = true }
                tous.append(o)
            }
        }
        let limite = max(1, a.int("limite") ?? 50)
        var out: JSON = ["fenetres": d.items.count, "onglets": Array(tous.prefix(limite))]
        if tous.count > limite { out["total"] = tous.count; out["tronque"] = true }
        return out
    }

    static func ouvrir(_ a: JSON) throws -> Any {
        let urls = (a.strings("urls") ?? []).map(normaliser)
        guard !urls.isEmpty else { throw MCPError("paramètre manquant : urls") }
        let liste = "{" + urls.map(AS.lit).joined(separator: ", ") + "}"
        var fenetre: Int
        var indexes: [Int]
        if a.bool("prive") == true {
            fenetre = try AS.newPrivateWindow()
            // La 1re URL remplace la page de démarrage (onglet 1), les suivantes s'ouvrent en nouveaux onglets
            let n = try AS.run("""
            tell application "Safari" to tell window id \(fenetre)
              set urls to \(liste)
              set URL of tab 1 to (item 1 of urls)
              repeat with u in (rest of urls)
                make new tab at end of tabs with properties {URL:(u as text)}
              end repeat
              return count of tabs
            end tell
            """).int ?? urls.count
            indexes = Array(1...max(1, n))
        } else {
            var w = a.int("fenetre_id") ?? 0
            if w == 0 && a.bool("nouvelle_fenetre") != true { w = try AS.visibleWindowIDs().first ?? 0 }
            let d = try AS.run("""
            tell application "Safari"
              set W to \(w)
              set urls to \(liste)
              set idx to {}
              set reste to urls
              if W is 0 then
                set avant to id of every window
                make new document with properties {URL:(item 1 of urls)}
                repeat 60 times
                  set apres to id of every window
                  repeat with k from 1 to count of apres
                    if avant does not contain (item k of apres) then set W to (item k of apres)
                  end repeat
                  if W is not 0 then exit repeat
                  delay 0.05
                end repeat
                if W is 0 then error "nouvelle fenêtre introuvable"
                set end of idx to 1
                set reste to rest of urls
              end if
              tell window id W
                repeat with u in reste
                  set t to make new tab at end of tabs with properties {URL:(u as text)}
                  set end of idx to index of t
                end repeat
                set current tab to tab (item 1 of idx)
              end tell
              return {W, idx}
            end tell
            """)
            let l = d.items
            guard l.count == 2, let wid = l[0].int else { throw MCPError("ouverture : réponse inattendue") }
            fenetre = wid
            indexes = l[1].ints
        }
        var onglets: [JSON] = zip(indexes, urls).map { ["index": $0, "url": $1] }
        if a.bool("attendre") == true {
            let refs = indexes.map { TabRef(fenetre: fenetre, index: $0) }
            var avant: [TabRef: String] = [:]
            for (r, u) in zip(refs, urls) where u != "about:blank" { avant[r] = "about:blank" }
            if a.bool("prive") == true, let r = refs.first { avant[r] = "favorites://" }  // page de démarrage
            let etats = AS.waitLoaded(refs, before: avant)
            for k in onglets.indices {
                guard let e = etats[refs[k]] else { continue }
                onglets[k]["titre"] = e.titre
                onglets[k]["url"] = e.url.isEmpty ? onglets[k]["url"] : e.url
                if !e.pret { onglets[k]["charge"] = false }
            }
        }
        return ["ok": true, "fenetre_id": fenetre, "onglets": onglets]
    }

    static func naviguer(_ a: JSON) throws -> Any {
        let actions = a.objects("actions") ?? []
        guard !actions.isEmpty else { throw MCPError("paramètre manquant : actions") }
        var items: [(TabRef, String, String)] = []
        for o in actions {
            guard let w = o.int("fenetre_id"), let i = o.int("index") else { throw MCPError("chaque action demande fenetre_id et index") }
            let url = o.nonEmpty("url").map(normaliser) ?? ""
            let k = o.nonEmpty("action") ?? (url.isEmpty ? "" : "url")
            guard ["url", "recharger", "precedent", "suivant", "activer"].contains(k) else { throw MCPError("action inconnue : \(k) (url, recharger, precedent, suivant, activer)") }
            if k == "url" && url.isEmpty { throw MCPError("action url sans url") }
            items.append((TabRef(fenetre: w, index: i), k, url))
        }
        let liste = "{" + items.map { "{\($0.0.fenetre), \($0.0.index), \(AS.lit($0.1)), \(AS.lit($0.2))}" }.joined(separator: ", ") + "}"
        let d = try AS.run("""
        tell application "Safari"
          set out to {}
          repeat with r in \(liste)
            try
              set t to tab (item 2 of r) of window id (item 1 of r)
              set avant to URL of t
              if avant is missing value then set avant to "about:blank"
              set k to item 3 of r
              if k is "url" then
                set URL of t to (item 4 of r)
              else if k is "recharger" then
                set URL of t to avant
              else if k is "precedent" then
                do JavaScript "history.back()" in t
              else if k is "suivant" then
                do JavaScript "history.forward()" in t
              else if k is "activer" then
                set current tab of window id (item 1 of r) to t
                set index of window id (item 1 of r) to 1
              end if
              set end of out to {"ok", avant}
            on error m
              set end of out to {m, ""}
            end try
          end repeat
          return out
        end tell
        """)
        if items.contains(where: { $0.1 == "activer" }) { AS.activerSafari() }
        var res: [JSON] = []
        var aAttendre: [TabRef] = []
        var avant: [TabRef: String] = [:]
        for ((ref, k, _), r) in zip(items, d.items) {
            let l = r.items
            var o = ref.json
            if l.first?.string == "ok" {
                o["ok"] = true
                if k != "activer" { aAttendre.append(ref); if k != "recharger" { avant[ref] = l.count > 1 ? l[1].string ?? "" : "" } }
            } else { o["ok"] = false; o["erreur"] = l.first?.string ?? "échec" }
            res.append(o)
        }
        if a.bool("attendre") == true, !aAttendre.isEmpty {
            if aAttendre.contains(where: { avant[$0] == nil }) { Thread.sleep(forTimeInterval: 0.3) }  // rechargement : laisser partir la requête
            let etats = AS.waitLoaded(aAttendre, before: avant, timeout: 10)
            for k in res.indices {
                let ref = TabRef(fenetre: res[k]["fenetre_id"] as! Int, index: res[k]["index"] as! Int)
                guard let e = etats[ref] else { continue }
                res[k]["titre"] = e.titre; res[k]["url"] = e.url
                if !e.pret { res[k]["charge"] = false }
            }
        }
        return ["resultats": res]
    }

    static func fermer(_ a: JSON) throws -> Any {
        let tabs = try (a.objects("onglets") ?? []).map { o -> (TabRef, String) in
            guard let w = o.int("fenetre_id"), let i = o.int("index") else { throw MCPError("chaque onglet demande fenetre_id et index") }
            return (TabRef(fenetre: w, index: i), o.nonEmpty("url_attendue") ?? "")
        }
        var brutes: [Any] = a["fenetres"] as? [Any] ?? []
        if let s = a["fenetres"] as? String { brutes = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [Any] ?? [s] }
        let fenetres = brutes.compactMap { ($0 as? NSNumber)?.intValue ?? ($0 as? String).flatMap { Int($0) } }
        guard !tabs.isEmpty || !fenetres.isEmpty else { throw MCPError("rien à fermer : onglets ou fenetres") }
        // Index décroissants dans chaque fenêtre : une fermeture ne décale pas les suivantes
        let ordre = tabs.indices.sorted { tabs[$0].0.fenetre != tabs[$1].0.fenetre ? tabs[$0].0.fenetre < tabs[$1].0.fenetre : tabs[$0].0.index > tabs[$1].0.index }
        let liste = "{" + ordre.map { "{\(tabs[$0].0.fenetre), \(tabs[$0].0.index), \(AS.lit(tabs[$0].1))}" }.joined(separator: ", ") + "}"
        let d = try AS.run("""
        tell application "Safari"
          set out to {}
          repeat with r in \(liste)
            try
              set t to tab (item 2 of r) of window id (item 1 of r)
              set u to URL of t
              if u is missing value then set u to "about:blank"
              if (item 3 of r) is not "" and u does not start with (item 3 of r) then error "URL différente : " & u
              close t
              set end of out to "ok"
            on error m
              set end of out to m
            end try
          end repeat
          set outW to {}
          repeat with w in {\(fenetres.map(String.init).joined(separator: ", "))}
            try
              close window id w
              set end of outW to "ok"
            on error m
              set end of outW to m
            end try
          end repeat
          return {out, outW}
        end tell
        """)
        let l = d.items
        let rt = l.first?.items ?? [], rw = l.count > 1 ? l[1].items : []
        var resultats = [JSON](repeating: [:], count: tabs.count)
        for (k, pos) in ordre.enumerated() {
            var o = tabs[pos].0.json
            let m = k < rt.count ? rt[k].string ?? "" : "échec"
            if m == "ok" { o["ok"] = true } else { o["ok"] = false; o["erreur"] = m }
            resultats[pos] = o
        }
        var out: JSON = ["fermes": resultats.filter { $0["ok"] as? Bool == true }.count]
        if !resultats.isEmpty { out["onglets"] = resultats }
        if !fenetres.isEmpty {
            out["fenetres"] = zip(fenetres, rw).map { w, m -> JSON in
                m.string == "ok" ? ["fenetre_id": w, "ok": true] : ["fenetre_id": w, "ok": false, "erreur": m.string ?? "échec"]
            }
        }
        return out
    }

    // MARK: - Contenu des pages

    /// Exécute le corps AppleScript `corps` (qui affecte `res` à partir de l'onglet `t`) pour chaque onglet
    private static func parOnglet(_ refs: [TabRef], _ corps: String) throws -> [(TabRef, Result<NSAppleEventDescriptor, MCPError>)] {
        let d = try AS.run("""
        tell application "Safari"
          set out to {}
          repeat with r in \(AS.refsList(refs))
            try
              set t to tab (item 2 of r) of window id (item 1 of r)
              \(corps)
              set end of out to {true, res}
            on error m
              set end of out to {false, m}
            end try
          end repeat
          return out
        end tell
        """)
        return zip(refs, d.items).map { ref, item in
            let l = item.items
            if l.first?.bool == true, l.count > 1 { return (ref, .success(l[1])) }
            return (ref, .failure(MCPError(l.count > 1 ? l[1].string ?? "échec" : "échec")))
        }
    }

    static func lirePage(_ a: JSON) throws -> Any {
        let cibles = try refs(a)
        let format = a.nonEmpty("format") ?? "texte"
        let maxc = max(100, a.int("max_caracteres") ?? 8000)
        let js: String
        switch format {
        case "texte": js = ""
        case "html": js = AS.jsWrapper("document.documentElement.outerHTML")
        case "liens": js = AS.jsWrapper("[...document.links].slice(0,500).map(a=>[(a.innerText||a.title||'').trim().replace(/\\s+/g,' ').slice(0,120),a.href])")
        default: throw MCPError("format inconnu : \(format) (texte, liens, html)")
        }
        let corps = format == "texte"
            ? "set res to {name of t, URL of t, text of t}"
            : "set v to \"\"\nset v to (do JavaScript \(AS.lit(js)) in t)\nset res to {name of t, URL of t, \"\"}\ntry\nset item 3 of res to v\nend try"
        let pages: [JSON] = try parOnglet(cibles, corps).map { ref, r in
            var o = ref.json
            switch r {
            case .failure(let e): o["erreur"] = e.description
            case .success(let d):
                let l = d.items
                o["titre"] = l.first?.string ?? ""
                o["url"] = l.count > 1 ? l[1].string ?? "about:blank" : ""
                var brut = l.count > 2 ? l[2].string ?? "" : ""
                if format != "texte" {
                    guard brut.hasPrefix("§") else { o["erreur"] = "JavaScript indisponible : activer Développement > Autoriser JavaScript depuis les Apple Events"; return o }
                    brut.removeFirst()
                    if brut.hasPrefix("ERR") { o["erreur"] = "JavaScript : " + brut.dropFirst(3); return o }
                }
                if format == "liens" {
                    let paires = (try? JSONSerialization.jsonObject(with: Data(brut.utf8))) as? [[String]] ?? []
                    var vus = Set<String>()
                    let liens: [JSON] = paires.compactMap { p in
                        guard p.count == 2, !p[1].isEmpty, !p[1].hasPrefix("javascript:"), vus.insert(p[1]).inserted else { return nil }
                        return p[0].isEmpty ? ["url": p[1]] : ["texte": p[0], "url": p[1]]
                    }
                    let lim = max(1, maxc / 80)
                    o["liens"] = Array(liens.prefix(lim))
                    if liens.count > lim { o["total_liens"] = liens.count; o["tronque"] = true }
                } else {
                    let (txt, coupe) = tronquer(brut, maxc)
                    o[format == "html" ? "html" : "texte"] = txt
                    if coupe { o["tronque"] = true; o["longueur"] = brut.count }
                }
            }
            return o
        }
        return ["pages": pages]
    }

    static func executerJS(_ a: JSON) throws -> Any {
        let code = try a.req("script")
        let cibles = try refs(a)
        let res: [JSON] = try parOnglet(cibles, "set v to (do JavaScript \(AS.lit(AS.jsWrapper(code))) in t)\nset res to \"\"\ntry\nset res to v\nend try").map { ref, r in
            var o = ref.json
            switch r {
            case .failure(let e): o["ok"] = false; o["erreur"] = e.description
            case .success(let d):
                guard var s = d.string, s.hasPrefix("§") else {
                    o["ok"] = false
                    o["erreur"] = "pas de résultat : erreur de syntaxe JavaScript, page sans document, ou réglage « Autoriser JavaScript depuis les Apple Events » désactivé"
                    return o
                }
                s.removeFirst()
                if s.hasPrefix("ERR") { o["ok"] = false; o["erreur"] = "JavaScript : " + s.dropFirst(3); return o }
                o["ok"] = true
                let (txt, coupe) = tronquer(s, 20000)
                if !coupe, let f = txt.first, f == "{" || f == "[", let v = try? JSONSerialization.jsonObject(with: Data(txt.utf8)) { o["resultat"] = v }
                else { o["resultat"] = txt; if coupe { o["tronque"] = true } }
            }
            return o
        }
        return ["resultats": res]
    }

    // MARK: - Liste de lecture et favoris (Bookmarks.plist, lecture seule)

    private static func titre(_ n: [String: Any]) -> String {
        (n["URIDictionary"] as? [String: Any])?["title"] as? String ?? n["Title"] as? String ?? ""
    }

    static func listeDeLecture(_ a: JSON) throws -> Any {
        let racine = try Fichiers.racineFavoris()
        let rl = (racine["Children"] as? [[String: Any]] ?? []).first { $0["Title"] as? String == "com.apple.ReadingList" }
        let filtre = a.nonEmpty("texte").map(fold)
        var items: [(Date, JSON)] = []
        for n in rl?["Children"] as? [[String: Any]] ?? [] {
            let info = n["ReadingList"] as? [String: Any] ?? [:]
            let t = titre(n), url = n["URLString"] as? String ?? ""
            let apercu = info["PreviewText"] as? String ?? ""
            let lu = info["DateLastViewed"] != nil
            if a.bool("non_lus") == true && lu { continue }
            if let filtre, !fold(t + " " + url + " " + apercu).contains(filtre) { continue }
            let ajout = info["DateAdded"] as? Date ?? .distantPast
            var o: JSON = ["titre": t, "url": url, "lu": lu]
            if ajout != .distantPast { o["ajoute"] = Dates.format(ajout) }
            if a.bool("apercu") == true, !apercu.isEmpty { o["apercu"] = String(apercu.prefix(300)) }
            items.append((ajout, o))
        }
        items.sort { $0.0 > $1.0 }
        let limite = max(1, a.int("limite") ?? 20)
        var out: JSON = ["elements": items.prefix(limite).map(\.1)]
        if items.count > limite { out["total"] = items.count; out["tronque"] = true }
        return out
    }

    static func ajouterListeDeLecture(_ a: JSON) throws -> Any {
        let elements = a.objects("elements") ?? []
        guard !elements.isEmpty else { throw MCPError("paramètre manquant : elements") }
        let liste = try "{" + elements.map { e -> String in
            guard let u = e.nonEmpty("url") else { throw MCPError("chaque élément demande une url") }
            return "{\(AS.lit(normaliser(u))), \(AS.lit(e.nonEmpty("titre") ?? "")), \(AS.lit(e.nonEmpty("apercu") ?? ""))}"
        }.joined(separator: ", ") + "}"
        let d = try AS.run("""
        tell application "Safari"
          set out to {}
          repeat with r in \(liste)
            try
              if (item 2 of r) is not "" and (item 3 of r) is not "" then
                add reading list item (item 1 of r) with title (item 2 of r) and preview text (item 3 of r)
              else if (item 2 of r) is not "" then
                add reading list item (item 1 of r) with title (item 2 of r)
              else
                add reading list item (item 1 of r)
              end if
              set end of out to "ok"
            on error m
              set end of out to m
            end try
          end repeat
          return out
        end tell
        """)
        let res: [JSON] = zip(elements, d.items).map { e, m in
            let u = normaliser(e.nonEmpty("url") ?? "")
            return m.string == "ok" ? ["url": u, "ok": true] : ["url": u, "ok": false, "erreur": m.string ?? "échec"]
        }
        return ["ajoutes": res.filter { $0["ok"] as? Bool == true }.count, "resultats": res]
    }

    static func favoris(_ a: JSON) throws -> Any {
        let racine = try Fichiers.racineFavoris()
        let filtre = a.nonEmpty("texte").map(fold)
        let dossierFiltre = a.nonEmpty("dossier").map(fold)
        let dossiersSeuls = a.bool("dossiers") == true
        var out: [JSON] = []
        func nom(_ n: [String: Any]) -> String {
            switch n["Title"] as? String {
            case "BookmarksBar": return "Favoris"
            case "BookmarksMenu": return "Menu des signets"
            default: return titre(n)
            }
        }
        func parcourir(_ n: [String: Any], _ chemin: String) {
            for c in n["Children"] as? [[String: Any]] ?? [] {
                let type = c["WebBookmarkType"] as? String ?? ""
                if type == "WebBookmarkTypeProxy" || (c["Title"] as? String) == "com.apple.ReadingList" { continue }
                if type == "WebBookmarkTypeList" {
                    let p = chemin.isEmpty ? nom(c) : chemin + "/" + nom(c)
                    if dossiersSeuls && (dossierFiltre == nil || fold(p).contains(dossierFiltre!)) && (filtre == nil || fold(p).contains(filtre!)) {
                        out.append(["dossier": p, "nb": (c["Children"] as? [Any])?.count ?? 0, "uuid": c["WebBookmarkUUID"] as? String ?? ""])
                    }
                    parcourir(c, p)
                } else if !dossiersSeuls, type == "WebBookmarkTypeLeaf" {
                    let t = titre(c), u = c["URLString"] as? String ?? ""
                    if let dossierFiltre, !fold(chemin).contains(dossierFiltre) { continue }
                    if let filtre, !fold(t + " " + u).contains(filtre) { continue }
                    out.append(["titre": t, "url": u, "dossier": chemin, "uuid": c["WebBookmarkUUID"] as? String ?? ""])
                }
            }
        }
        parcourir(racine, "")
        let limite = max(1, a.int("limite") ?? 50)
        var res: JSON = [dossiersSeuls ? "dossiers" : "favoris": Array(out.prefix(limite))]
        if out.count > limite { res["total"] = out.count; res["tronque"] = true }
        return res
    }

    // MARK: - Historique (History.db, lecture seule)

    private static func like(_ s: String) -> String {
        "%" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
    }

    static func historique(_ a: JSON) throws -> Any {
        let db = try Fichiers.DB(Fichiers.history)
        var where_: [String] = [], params: [Any] = []
        if let d = a.nonEmpty("depuis") { where_.append("v.visit_time >= ?"); params.append(try Dates.parse(d).timeIntervalSinceReferenceDate) }
        if let d = a.nonEmpty("jusqu_a") { where_.append("v.visit_time < ?"); params.append(try Dates.parse(d).timeIntervalSinceReferenceDate) }
        if let dom = a.nonEmpty("domaine")?.lowercased() {
            let d = dom.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            where_.append("(i.url LIKE ? ESCAPE '\\' OR i.url LIKE ? ESCAPE '\\')")
            params.append("%://" + d + "/%"); params.append("%." + d + "/%")
        }
        var having = ""
        if let t = a.nonEmpty("texte") {
            having = "HAVING (i.url LIKE ? ESCAPE '\\' OR titre LIKE ? ESCAPE '\\')"
            params.append(like(t)); params.append(like(t))
        }
        let limite = max(1, a.int("limite") ?? 20)
        params.append(limite + 1)
        let sql = """
        SELECT i.url, i.visit_count, MAX(v.visit_time) AS t,
          (SELECT v2.title FROM history_visits v2 WHERE v2.history_item = i.id AND v2.title IS NOT NULL AND v2.title != '' ORDER BY v2.visit_time DESC LIMIT 1) AS titre
        FROM history_items i JOIN history_visits v ON v.history_item = i.id
        \(where_.isEmpty ? "" : "WHERE " + where_.joined(separator: " AND "))
        GROUP BY i.id \(having)
        ORDER BY t DESC LIMIT ?
        """
        let rows = try db.rows(sql, params)
        let pages: [JSON] = rows.prefix(limite).map { r in
            var o: JSON = ["url": r[0] as? String ?? "", "titre": r[3] as? String ?? "", "visites": r[1] as? Int ?? 0]
            if let t = r[2] as? Double { o["derniere_visite"] = Dates.format(Date(timeIntervalSinceReferenceDate: t)) }
            return o
        }
        var out: JSON = ["pages": pages]
        if rows.count > limite { out["tronque"] = true }
        return out
    }

    // MARK: - Groupes d'onglets (SafariTabs.db, lecture seule)

    static func groupesOnglets(_ a: JSON) throws -> Any {
        let db = try Fichiers.DB(Fichiers.tabs)
        // Onglets d'un groupe : enfants directs et onglets épinglés (sous-dossier subtype 1)
        if let g = a.int("groupe_id") {
            let rows = try db.rows("""
            SELECT t.title, t.url, CASE WHEN t.parent = ?1 THEN 0 ELSE 1 END AS epingle FROM bookmarks t
            WHERE t.type = 0 AND t.deleted = 0 AND (t.parent = ?1 OR t.parent IN (SELECT id FROM bookmarks WHERE parent = ?1 AND type = 1 AND subtype = 1))
            ORDER BY epingle DESC, t.order_index
            """, [g])
            return ["groupe_id": g, "onglets": rows.map { r -> JSON in
                var o: JSON = ["titre": r[0] as? String ?? "", "url": r[1] as? String ?? ""]
                if r[2] as? Int == 1 { o["epingle"] = true }
                return o
            }]
        }
        let rows = try db.rows("""
        SELECT g.id, g.title,
          (SELECT COUNT(*) FROM bookmarks t WHERE t.type = 0 AND t.deleted = 0 AND (t.parent = g.id OR t.parent IN (SELECT id FROM bookmarks WHERE parent = g.id AND type = 1 AND subtype = 1))) AS nb,
          g.id IN (SELECT local_tab_group_id FROM windows WHERE local_tab_group_id IS NOT NULL) AS local,
          g.id IN (SELECT active_tab_group_id FROM windows WHERE date_closed IS NULL AND active_tab_group_id IS NOT NULL) AS actif
        FROM bookmarks g
        WHERE g.type = 1 AND g.subtype = 0 AND g.deleted = 0 AND (g.special_id IS NULL OR g.special_id = 0)
          AND g.id NOT IN (SELECT private_tab_group_id FROM windows WHERE private_tab_group_id IS NOT NULL)
        ORDER BY g.order_index, g.id
        """)
        let filtre = a.nonEmpty("texte").map(fold)
        let groupes: [JSON] = rows.compactMap { r in
            let local = r[3] as? Int == 1
            if local && a.bool("sans_nom") != true { return nil }
            let nom = r[1] as? String ?? ""
            if let filtre, !fold(nom).contains(filtre) { return nil }
            var o: JSON = ["groupe_id": r[0] as? Int ?? 0, "nom": local ? "" : nom, "nb_onglets": r[2] as? Int ?? 0]
            if local { o["sans_nom"] = true }
            if r[4] as? Int == 1 { o["ouvert"] = true }
            return o
        }
        return ["groupes": groupes]
    }
}
