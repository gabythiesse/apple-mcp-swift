// Logique des outils : AppleScript pour les fenêtres et onglets, fichiers en lecture seule pour le reste
import Foundation
import PDFKit

enum Handlers {

    // MARK: - Arguments

    private static func refs(_ a: JSON, _ key: String = "tabs") throws -> [TabRef] {
        let objs = a.objects(key) ?? []
        if objs.isEmpty { return [try AS.currentTab()] }
        return try objs.map { o in
            guard let w = o.int("window_id"), let i = o.int("index") else { throw MCPError("each tab needs window_id and index") }
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
        // Apple Events bruts : 3 événements par fenêtre (noms, URL, onglet actif), < 1 ms chacun
        let fenetres = try a.int("window_id").map { [$0] } ?? AE.visibleWindowIDs()
        var lignes: [(Int, Int, [NSAppleEventDescriptor], [NSAppleEventDescriptor])] = []
        for w in fenetres {
            let tabs = AE.everyTab(of: AE.window(w))
            let noms = try AE.get(AE.prop("pnam", of: tabs))?.items ?? []
            let urls = try AE.get(AE.prop("pURL", of: tabs))?.items ?? []
            let actif = (try? AE.get(AE.prop("pidx", of: AE.prop("cTab", of: AE.window(w))))?.int) ?? 0
            lignes.append((w, actif, noms, urls))
        }
        let filtre = a.nonEmpty("text").map(fold)
        var tous: [JSON] = []
        for (wid, actif, noms, urls) in lignes {
            for (k, nom) in noms.enumerated() {
                let titre = nom.string ?? ""
                let url = k < urls.count ? urls[k].string ?? "about:blank" : ""
                if let filtre, !fold(titre + " " + url).contains(filtre) { continue }
                var o: JSON = ["window_id": wid, "index": k + 1, "title": titre, "url": url]
                if k + 1 == actif { o["active"] = true }
                tous.append(o)
            }
        }
        let limite = max(1, a.int("limit") ?? 50)
        var out: JSON = ["windows": lignes.count, "tabs": Array(tous.prefix(limite))]
        if tous.count > limite { out["total"] = tous.count; out["truncated"] = true }
        return out
    }

    static func ouvrir(_ a: JSON) throws -> Any {
        let urls = (a.strings("urls") ?? []).map(normaliser)
        guard !urls.isEmpty else { throw MCPError("missing parameter: urls") }
        let liste = "{" + urls.map(AS.lit).joined(separator: ", ") + "}"
        var fenetre: Int
        var indexes: [Int]
        if a.bool("private") == true {
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
            var w = a.int("window_id") ?? 0
            if w == 0 && a.bool("new_window") != true { w = try AS.visibleWindowIDs().first ?? 0 }
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
                if W is 0 then error "new window not found"
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
            guard l.count == 2, let wid = l[0].int else { throw MCPError("open: unexpected response") }
            fenetre = wid
            indexes = l[1].ints
        }
        var onglets: [JSON] = zip(indexes, urls).map { ["index": $0, "url": $1] }
        if a.bool("wait") == true {
            let refs = indexes.map { TabRef(fenetre: fenetre, index: $0) }
            var avant: [TabRef: String] = [:]
            for (r, u) in zip(refs, urls) where u != "about:blank" { avant[r] = "about:blank" }
            if a.bool("private") == true, let r = refs.first { avant[r] = "favorites://" }  // page de démarrage
            let etats = AS.waitLoaded(refs, before: avant)
            for k in onglets.indices {
                guard let e = etats[refs[k]] else { continue }
                onglets[k]["title"] = e.titre
                onglets[k]["url"] = e.url.isEmpty ? onglets[k]["url"] : e.url
                if !e.pret { onglets[k]["loaded"] = false }
            }
        }
        return ["window_id": fenetre, "tabs": onglets]
    }

    static func naviguer(_ a: JSON) throws -> Any {
        let actions = a.objects("actions") ?? []
        guard !actions.isEmpty else { throw MCPError("missing parameter: actions") }
        var items: [(TabRef, String, String)] = []
        for o in actions {
            guard let w = o.int("window_id"), let i = o.int("index") else { throw MCPError("each action needs window_id and index") }
            let url = o.nonEmpty("url").map(normaliser) ?? ""
            let k = o.nonEmpty("action") ?? (url.isEmpty ? "" : "url")
            guard ["url", "reload", "back", "forward", "activate"].contains(k) else { throw MCPError("unknown action: \(k) (url, reload, back, forward, activate)") }
            if k == "url" && url.isEmpty { throw MCPError("action url without url") }
            items.append((TabRef(fenetre: w, index: i), k, url))
        }
        // Apple Events bruts : une propriété posée ou un do JavaScript par onglet
        let etats: [(String, String)] = items.map { ref, k, url in
            do {
                let t = AE.tab(ref)
                let avant = try AE.get(AE.prop("pURL", of: t))?.string ?? "about:blank"
                switch k {
                case "url": try AE.set(AE.prop("pURL", of: t), NSAppleEventDescriptor(string: url))
                case "reload": try AE.set(AE.prop("pURL", of: t), NSAppleEventDescriptor(string: avant))
                case "back": _ = try AE.js("history.back()", in: ref)
                case "forward": _ = try AE.js("history.forward()", in: ref)
                default:
                    try AE.set(AE.prop("cTab", of: AE.window(ref.fenetre)), t)
                    try AE.set(AE.prop("pidx", of: AE.window(ref.fenetre)), NSAppleEventDescriptor(int32: 1))
                }
                return ("ok", avant)
            } catch { return ("\(error)", "") }
        }
        if items.contains(where: { $0.1 == "activate" }) { AS.activerSafari() }
        var res: [JSON] = []
        var aAttendre: [TabRef] = []
        var avant: [TabRef: String] = [:]
        for ((ref, k, _), (m, url)) in zip(items, etats) {
            var o = ref.json
            if m == "ok" {
                if k != "activate" { aAttendre.append(ref); if k != "reload" { avant[ref] = url } }
            } else { o["error"] = m }
            res.append(o)
        }
        if a.bool("wait") == true, !aAttendre.isEmpty {
            if aAttendre.contains(where: { avant[$0] == nil }) { Thread.sleep(forTimeInterval: 0.3) }  // rechargement : laisser partir la requête
            let etats = AS.waitLoaded(aAttendre, before: avant, timeout: 10)
            for k in res.indices {
                let ref = TabRef(fenetre: res[k]["window_id"] as! Int, index: res[k]["index"] as! Int)
                guard let e = etats[ref] else { continue }
                res[k]["title"] = e.titre; res[k]["url"] = e.url
                if !e.pret { res[k]["loaded"] = false }
            }
        }
        if res.count == 1 {
            if let e = res[0]["error"] as? String { throw MCPError(e) }
            return res[0].filter { $0.key != "window_id" && $0.key != "index" }
        }
        return ["results": res]
    }

    static func fermer(_ a: JSON) throws -> Any {
        let tabs = try (a.objects("tabs") ?? []).map { o -> (TabRef, String) in
            guard let w = o.int("window_id"), let i = o.int("index") else { throw MCPError("each tab needs window_id and index") }
            return (TabRef(fenetre: w, index: i), o.nonEmpty("expected_url") ?? "")
        }
        var brutes: [Any] = a["windows"] as? [Any] ?? []
        if let s = a["windows"] as? String { brutes = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [Any] ?? [s] }
        let fenetres = brutes.compactMap { ($0 as? NSNumber)?.intValue ?? ($0 as? String).flatMap { Int($0) } }
        guard !tabs.isEmpty || !fenetres.isEmpty else { throw MCPError("nothing to close: tabs or windows") }
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
              if (item 3 of r) is not "" and u does not start with (item 3 of r) then error "different URL: " & u
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
            let m = k < rt.count ? rt[k].string ?? "" : "failed"
            if m == "ok" { o["ok"] = true } else { o["ok"] = false; o["error"] = m }
            resultats[pos] = o
        }
        var out: JSON = ["closed": resultats.filter { $0["ok"] as? Bool == true }.count]
        if !resultats.isEmpty { out["tabs"] = resultats }
        if !fenetres.isEmpty {
            out["windows"] = zip(fenetres, rw).map { w, m -> JSON in
                m.string == "ok" ? ["window_id": w, "ok": true] : ["window_id": w, "ok": false, "error": m.string ?? "failed"]
            }
        }
        return out
    }

    // MARK: - Contenu des pages

    /// Applique `f` à chaque onglet : une erreur par onglet n'arrête pas le lot
    private static func parOnglet<T>(_ refs: [TabRef], _ f: (TabRef) throws -> T) -> [(TabRef, Result<T, MCPError>)] {
        refs.map { r in
            do { return (r, .success(try f(r))) } catch let e as MCPError { return (r, .failure(e)) } catch { return (r, .failure(MCPError("\(error)"))) }
        }
    }

    static func lirePage(_ a: JSON) throws -> Any {
        let cibles = try refs(a)
        let format = a.nonEmpty("format") ?? "markdown"
        let maxc = max(100, a.int("max_chars") ?? 8000), offset = max(0, a.int("offset") ?? 0)
        if format == "markdown" { return try lireMarkdown(a, cibles, maxc, offset) }
        let js: String
        switch format {
        // Texte découpé dans la page : seuls max_chars caractères traversent l'Apple Event (text of t envoyait tout)
        case "text": js = AS.jsWrapper("var s=document.body?document.body.innerText:'';return [s.length,s.slice(\(offset),\(offset + maxc))]")
        case "html": js = AS.jsWrapper("document.documentElement.outerHTML")
        case "links": js = AS.jsWrapper("[...document.links].slice(0,500).map(a=>[(a.innerText||a.title||'').trim().replace(/\\s+/g,' ').slice(0,120),a.href])")
        default: throw MCPError("unknown format: \(format) (markdown, text, links, html)")
        }
        let pages: [JSON] = parOnglet(cibles) { ref -> JSON in
            let (titre, url) = try AE.titleURL(ref)
            var o = ref.json
            o["title"] = titre; o["url"] = url
            var brut = try AE.js(js, in: ref) ?? ""
            if format == "text" && !brut.hasPrefix("§") {
                // JavaScript indisponible : texte de la page par Safari (plus lent, tout le texte)
                let t = try AE.get(AE.prop("ctxt", of: AE.tab(ref)))?.string ?? ""
                brut = "§" + jsonText([t.count, String(t.dropFirst(offset).prefix(maxc))])
            }
            guard brut.hasPrefix("§") else { o["error"] = "JavaScript unavailable: enable Develop > Allow JavaScript from Apple Events"; return o }
            brut.removeFirst()
            if brut.hasPrefix("ERR") { o["error"] = "JavaScript: " + brut.dropFirst(3); return o }
            if format == "links" {
                let paires = (try? JSONSerialization.jsonObject(with: Data(brut.utf8))) as? [[String]] ?? []
                var vus = Set<String>()
                let liens: [JSON] = paires.compactMap { p in
                    guard p.count == 2, !p[1].isEmpty, !p[1].hasPrefix("javascript:"), vus.insert(p[1]).inserted else { return nil }
                    return p[0].isEmpty ? ["url": p[1]] : ["text": p[0], "url": p[1]]
                }
                let lim = max(1, maxc / 80)
                o["links"] = Array(liens.prefix(lim))
                if liens.count > lim { o["total_links"] = liens.count; o["truncated"] = true }
            } else if format == "text" {
                let l = (try? JSONSerialization.jsonObject(with: Data(brut.utf8))) as? [Any] ?? []
                let n = (l.first as? Int) ?? 0, txt = l.count > 1 ? l[1] as? String ?? "" : ""
                o["text"] = txt
                if n > txt.count + offset { o["truncated"] = true }
                if n > txt.count { o["length"] = n }
                if offset > 0 { o["offset"] = offset }
            } else {
                let txt = String(brut.dropFirst(offset).prefix(maxc))
                o["html"] = txt
                if brut.count > offset + maxc { o["truncated"] = true }
                if brut.count > txt.count { o["length"] = brut.count }
                if offset > 0 { o["offset"] = offset }
            }
            return o
        }.map { ref, r in
            switch r {
            case .success(let o): return o
            case .failure(let e): var o = ref.json; o["error"] = e.description; return o
            }
        }
        // Un seul onglet visé : objet plat, sans la référence que l'appelant connaît déjà
        if cibles.count == 1 {
            if let e = pages[0]["error"] as? String { throw MCPError(e) }
            return pages[0].filter { $0.key != "window_id" && $0.key != "index" }
        }
        return ["pages": pages]
    }

    /// Format markdown : contenu principal (ou selector, ou full) converti par mcp.js ; texte de Safari pour un PDF
    private static func lireMarkdown(_ a: JSON, _ cibles: [TabRef], _ maxc: Int, _ offset: Int) throws -> Any {
        var args = passer(a, ["selector", "full", "links"])
        args["max_chars"] = maxc; args["offset"] = offset
        let pages: [JSON] = parOnglet(cibles) { ref -> JSON in
            do {
                var o = try Page.call("markdown", args, in: ref)
                if o["pdf"] as? Bool == true { throw MCPError("no result: PDF") }
                o.removeValue(forKey: "ms")
                if let t = o.removeValue(forKey: "text") { o["markdown"] = t }
                if let l = o["length"] as? Int, l > offset + ((o["markdown"] as? String)?.count ?? 0) { o["truncated"] = true }
                return o
            } catch let e as MCPError where e.description.contains("helper library") || e.description.contains("no result") {
                // PDF : texte extrait par PDFKit des octets du fichier ; sinon le texte que Safari donne de la page
                let (titre, url) = try AE.titleURL(ref)
                var t = (try? textePDF(ref, url)) ?? ""
                if t.isEmpty { t = try AE.get(AE.prop("ctxt", of: AE.tab(ref)))?.string ?? "" }
                guard !t.isEmpty else { throw MCPError("no readable text in this page (PDF without a text layer, or an image)") }
                var o: JSON = ["title": titre, "url": url, "page_type": "pdf", "text": String(t.dropFirst(offset).prefix(maxc))]
                if t.count > maxc + offset { o["truncated"] = true }
                if t.count > maxc { o["length"] = t.count }
                return o
            }
        }.map { ref, r in
            switch r {
            case .success(let o): return cibles.count == 1 ? o : o.merging(ref.json) { a, _ in a }
            case .failure(let e): return cibles.count == 1 ? ["error": e.description] : ["error": e.description].merging(ref.json) { a, _ in a }
            }
        }
        if cibles.count == 1 {
            if let e = pages[0]["error"] as? String { throw MCPError(e) }
            return pages[0]
        }
        return ["pages": pages]
    }

    /// Texte d'un PDF ouvert dans un onglet : fichier local lu directement, sinon octets relus par la page (fetch, mêmes cookies)
    private static func textePDF(_ ref: TabRef, _ url: String) throws -> String {
        let donnees: Data
        if let u = URL(string: url), u.isFileURL { donnees = try Data(contentsOf: u) }
        else {
            let o = try Page.call("pdf_data", [:], in: ref, timeout: 30)
            guard let b = o["b64"] as? String, let d = Data(base64Encoded: b) else { throw MCPError("could not read the PDF") }
            donnees = d
        }
        guard let doc = PDFDocument(data: donnees) else { throw MCPError("not a readable PDF") }
        return (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n\n")
    }

    /// Dernier résultat tronqué de run_js : offset relit la suite sans relancer le script
    nonisolated(unsafe) private static var dernierJS: (cle: String, texte: String)?

    static func executerJS(_ a: JSON) throws -> Any {
        let code = try a.req("script")
        let cibles = try refs(a)
        let timeout = max(0.1, (a.double("timeout") ?? 10000) / 1000)
        let maxc = max(100, a.int("max_chars") ?? 20000), offset = max(0, a.int("offset") ?? 0)
        let t = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = ["throw ", "var ", "let ", "const ", "if ", "if(", "for ", "for(", "while", "try", "function ", "class ", "switch", "do ", "return"]
        let simple = !t.contains(";") && !t.contains("\n") && !instructions.contains(where: t.hasPrefix)
        // await accepté : fonction async, le résultat (promesse) est sondé par Page.poll
        let fn = (t.contains("await") ? "async " : "") + "function(){\n" + (simple ? "return (\(t));" : t) + "\n}"
        let res: [JSON] = parOnglet(cibles) { ref -> JSON in
            let cle = "\(ref.fenetre)/\(ref.index)|\(code)"
            var texte: String
            var o: JSON = [:]
            if offset > 0, let d = dernierJS, d.cle == cle { texte = d.texte }
            else {
                do { o = try Page.poll(Page.raw("__mcp.js(\(fn))", in: ref, timeout: min(timeout, 5)), in: ref, timeout: timeout) }
                catch let e as MCPError where e.description.hasPrefix("no result") { throw MCPError(syntaxe(t, simple: simple, ref)) }
                catch let e as MCPError {
                    // Ligne d'erreur ramenée au code de l'appelant (l'en-tête du script occupe la ligne 1)
                    if let r = e.description.range(of: #" \(line (\d+)\)$"#, options: .regularExpression),
                       let n = Int(e.description[r].filter(\.isNumber)), n > 1 { throw MCPError("JavaScript: " + e.description[..<r.lowerBound] + " (line \(n - 1))") }
                    throw MCPError("JavaScript: " + e.description)
                }
                guard let v = o.removeValue(forKey: "value") else { return o }
                if let s = v as? String { texte = s } else {
                    let j = jsonText(v)
                    if j.count <= maxc && offset == 0 { o["result"] = v; return o }
                    texte = j
                }
            }
            if texte.count <= maxc && offset == 0 { o["result"] = texte; return o }
            dernierJS = (cle, texte)
            let debut = texte.index(texte.startIndex, offsetBy: min(offset, texte.count))
            o["result"] = String(texte[debut...].prefix(maxc))
            o["length"] = texte.count
            if offset > 0 { o["offset"] = offset }
            return o
        }.map { ref, r in
            switch r {
            case .success(let o): return o
            case .failure(let e): return ["error": e.description]
            }
        }
        if cibles.count == 1 {
            if let e = res[0]["error"] as? String { throw MCPError(e) }
            return res[0]
        }
        return ["results": zip(cibles, res).map { ref, o in o.merging(ref.json) { a, _ in a } }]
    }

    /// Message d'une erreur de syntaxe : la page compile le code à part pour en donner la raison (sauf CSP sans unsafe-eval)
    private static func syntaxe(_ t: String, simple: Bool, _ ref: TabRef) -> String {
        let corps = Page.lit(simple ? "return (\(t));" : t)
        let js = "(function(){try{var F=Object.getPrototypeOf(async function(){}).constructor;new F(\(corps));return 'ok'}catch(e){return e.name+': '+e.message+(e.line?' (line '+e.line+')':'')}})()"
        let m = (try? AE.js(js, in: ref, timeout: 2)) ?? nil
        if let m, m != "ok", !m.hasPrefix("EvalError") { return "JavaScript syntax error: " + m.replacingOccurrences(of: "SyntaxError: ", with: "") }
        return "JavaScript syntax error, or the page has no document"
    }

    // MARK: - Perception (snapshot, find, page_info) : bibliothèque mcp.js

    /// Onglet visé par window_id + index, sinon l'onglet actif de la fenêtre de premier plan
    static func onglet(_ a: JSON) throws -> TabRef {
        if let w = a.int("window_id"), let i = a.int("index") { return TabRef(fenetre: w, index: i) }
        if a.has("window_id") || a.has("index") { throw MCPError("give both window_id and index, or neither for the active tab") }
        return try AS.currentTab()
    }

    /// Arguments transmis tels quels à la page (seulement les clés connues, valeurs JSON)
    static func passer(_ a: JSON, _ cles: [String]) -> JSON {
        var o: JSON = [:]
        for k in cles { if let v = a[k], !(v is NSNull) { o[k] = v } }
        return o
    }

    static func snapshot(_ a: JSON) throws -> Any {
        let t = try onglet(a)
        var o = try Page.call("snapshot", passer(a, ["all", "viewport_only", "selector", "ref", "max_chars", "offset", "urls"]), in: t)
        o.removeValue(forKey: "ms")
        return o
    }

    static func trouver(_ a: JSON) throws -> Any {
        let t = try onglet(a)
        return try Page.call("find", passer(a, ["text", "role", "selector", "label", "near", "within", "limit"]), in: t)
    }

    static func pageInfo(_ a: JSON) throws -> Any {
        let t = try onglet(a)
        do { return try Page.call("page_info", [:], in: t) }
        catch let e as MCPError where e.description.contains("helper library") || e.description.contains("no result") {
            // Visionneuse PDF ou image : pas de document HTML pour la bibliothèque
            let (titre, url) = try AE.titleURL(t)
            var o: JSON = ["url": url, "title": titre]
            o["page_type"] = url.lowercased().contains(".pdf") ? "pdf" : "viewer (no HTML document)"
            o["note"] = "JavaScript cannot run in this page; read_page format text uses Safari's own text extraction"
            return o
        }
    }

    // MARK: - Action (click, type, press, select, check, hover, scroll, wait, act)

    static let cibleCles = ["ref", "selector", "text", "role", "label", "near", "within", "x", "y"]

    /// Arguments d'une opération de page : cible, options, politique des dialogues
    private static func argsPage(_ a: JSON, _ cles: [String]) -> JSON {
        var o = passer(a, cibleCles + cles)
        if a.has("accept_dialogs") || a.has("prompt_text") {
            var d: JSON = ["accept": a.bool("accept_dialogs") ?? true]
            if let p = a.string("prompt_text") { d["prompt"] = p }
            o["dialogs"] = d
        }
        return o
    }

    /// Opération de page qui attend sa cible (jusqu'à timeout) et survit à une navigation déclenchée par l'action
    private static func actionPage(_ op: String, _ args: JSON, _ t: TabRef, timeout: TimeInterval) throws -> JSON {
        let fin = Date().addingTimeInterval(timeout)
        let avant = (try? AE.js("location.href", in: t, timeout: 2)) ?? nil
        while true {
            do {
                let o = try Page.call(op, args, in: t, timeout: max(3, timeout))
                if o["navigating"] as? Bool == true { var n = try apresNavigation(t, avant); n["clicked"] = args["ref"] ?? args["text"] ?? args["selector"]; return n }
                return o
            }
            catch is PageNavigated { return try apresNavigation(t, avant) }
            catch let e as MCPError {
                let absent = e.description.hasPrefix("no element") || e.description.hasPrefix("near: no visible") || e.description.hasPrefix("nothing at")
                    || e.description.hasPrefix("target is disabled") || e.description.hasPrefix("target is hidden")
                if absent && Date() < fin { Thread.sleep(forTimeInterval: 0.05); continue }
                // page remplacée pendant l'appel : la bibliothèque a été réinjectée dans la nouvelle page
                if e.description.contains("watch lost") { return try apresNavigation(t, avant) }
                throw e
            }
        }
    }

    private static func apresNavigation(_ t: TabRef, _ avant: String?) throws -> JSON {
        let e = AS.waitLoaded([t], before: avant.map { [t: $0] } ?? [:], timeout: 15)[t]
        var o: JSON = ["navigated": true, "url": e?.url ?? "", "title": e?.titre ?? ""]
        if e?.pret == false { o["loaded"] = false }
        return o
    }

    /// Réponse compacte : on retire les compteurs internes, on signale une action sans effet
    private static func compact(_ o: JSON, level: String? = nil) -> JSON {
        var r = o
        let reagi = r.removeValue(forKey: "reacted") as? Bool
        r.removeValue(forKey: "mutations")
        if reagi == false && r["navigated"] == nil { r["no_effect"] = true }
        if let level, level != "dom" { r["level"] = level }
        // une même ligne d'élément n'est donnée qu'une fois : l'état après l'action remplace l'état avant
        func refDe(_ k: String) -> Substring? { (r[k] as? String)?.split(separator: " ").first }
        for principal in ["clicked", "field", "hovered"] where r[principal] != nil {
            if let t = refDe("target"), t == refDe(principal) { r[principal] = r.removeValue(forKey: "target") }
            if let f = refDe("focus"), f == refDe(principal) { r.removeValue(forKey: "focus") }
        }
        if let t = refDe("target"), t == refDe("focus") { r.removeValue(forKey: "focus") }
        return r
    }

    private static func mode(_ a: JSON) throws -> String {
        let m = a.nonEmpty("mode") ?? "auto"
        guard ["auto", "dom", "ax", "native"].contains(m) else { throw MCPError("unknown mode: \(m) (auto, dom, ax, native)") }
        return m
    }

    private static func delai(_ a: JSON, _ defaut: Double) -> TimeInterval { max(0.05, (a.double("timeout") ?? defaut) / 1000) }

    static func cliquer(_ a: JSON) throws -> Any { try cliquer(a, onglet(a)) }
    static func cliquer(_ a: JSON, _ t: TabRef) throws -> JSON {
        let m = try mode(a)
        let args = argsPage(a, ["button", "double", "modifiers", "expect", "expect_timeout", "force"])
        let attente = delai(a, 5000)
        // Niveau 1 : séquence complète d'événements DOM
        if m == "auto" || m == "dom" {
            let o = try actionPage("click", args, t, timeout: attente)
            if m == "dom" || o["reacted"] as? Bool != false || o["navigated"] != nil { return compact(o) }
            // escalade impossible écran verrouillé : le résultat DOM, avec la raison
            if Native.ecranVerrouille { var r = compact(o); r["escalation"] = Native.verrouille; return r }
        }
        // Niveaux 2 et 3 : la page n'a pas réagi (ou mode demandé) ; l'élément est relocalisé (il a pu bouger)
        let niveaux = m == "auto" ? ["ax", "native"] : [m]
        var dernier: JSON = [:]
        for niveau in niveaux {
            let loc = try actionPage("locate", args, t, timeout: attente)
            if loc["navigated"] != nil { return loc }
            guard let x = loc["x"] as? Double, let y = loc["y"] as? Double, let w = loc["watch"] as? Int else { throw MCPError("could not locate the target") }
            let prep = try Native.preparer(t)
            let p = Native.ecran(prep.web, x: x, y: y, vw: loc["vw"] as? Double ?? 0)
            var info: JSON = [:]
            if niveau == "ax" {
                if let presse = Native.axPress(at: p) { info["ax_element"] = presse } else { info["ax_element"] = "none pressable at this point" }
            } else {
                try Native.activer()
                let bouton = a.nonEmpty("button") ?? "left"
                Native.click(at: p, button: bouton, count: a.bool("double") == true ? 2 : 1, modifiers: a.strings("modifiers") ?? [])
                info["activated_safari"] = true
            }
            if prep.tabSwitched { info["tab_activated"] = true }
            var o: JSON
            do {
                o = try Page.call("settle", ["watch": w, "expect": args["expect"] ?? NSNull(), "expect_timeout": args["expect_timeout"] ?? 2000], in: t, timeout: 6)
                if o["navigating"] as? Bool == true { o = try apresNavigation(t, nil) }
            }
            catch is PageNavigated { o = try apresNavigation(t, nil) }
            catch let e as MCPError where e.description.contains("watch lost") { o = try apresNavigation(t, nil) }
            o["clicked"] = loc["target"]
            o.merge(info) { a, _ in a }
            dernier = compact(o, level: niveau)
            if o["reacted"] as? Bool != false || o["navigated"] != nil { return dernier }
        }
        return dernier
    }

    static func taper(_ a: JSON) throws -> Any { try taper(a, onglet(a)) }
    static func taper(_ a: JSON, _ t: TabRef) throws -> JSON {
        let m = try mode(a)
        guard a["value"] is String || a["value"] is NSNumber else { throw MCPError("missing parameter: value (the text to type)") }
        let valeur = a.string("value") ?? "\(a["value"]!)"
        var args = argsPage(a, ["clear"])
        args["value"] = valeur
        let aCible = cibleCles.contains { a.has($0) }
        if m != "native" && m != "ax" {
            var o = try actionPage("type", args, t, timeout: delai(a, 5000))
            let ok = o.removeValue(forKey: "ok") as? Bool ?? true
            if m == "dom" || ok || o["navigated"] != nil || Native.ecranVerrouille {
                if !ok && Native.ecranVerrouille { o["escalation"] = Native.verrouille }
                if !ok { o["warning"] = "the field does not show the typed text (the page may reformat or reject it; try mode native)" }
                if a.bool("submit") == true { o["submit"] = try presser(["keys": ["Enter"], "mode": "auto"], t) }
                return compact(o)
            }
        }
        // Clavier natif : clic natif sur le champ pour le focaliser (place le curseur), puis la frappe réelle
        var info: JSON = ["activated_safari": true, "level": "native"]
        var w: Int?
        if aCible {
            let loc = try actionPage("locate", argsPage(a, []), t, timeout: delai(a, 5000))
            guard let x = loc["x"] as? Double, let y = loc["y"] as? Double else { throw MCPError("could not locate the field") }
            w = loc["watch"] as? Int
            let prep = try Native.preparer(t)
            try Native.activer()
            Native.click(at: Native.ecran(prep.web, x: x, y: y, vw: loc["vw"] as? Double ?? 0))
            Thread.sleep(forTimeInterval: 0.1)
        } else {
            w = try Page.call("watch", [:], in: t)["watch"] as? Int
            _ = try Native.preparer(t)
            try Native.activer()
        }
        if a.bool("clear") == true { try Native.key("Cmd+A"); try Native.key("Backspace") }
        Native.type(valeur)
        if a.bool("submit") == true { try Native.key("Enter") }
        var o = (try? Page.call("settle", ["watch": w ?? 0, "quiet": 150], in: t, timeout: 4)) ?? [:]
        o.merge(info) { a, _ in a }
        if let f = try? Page.call("read", ["max_chars": 300].merging(aCible ? passer(a, cibleCles) : [:]) { a, _ in a }, in: t), a.has("ref") || a.has("selector") {
            o["value"] = f["text"]
        }
        return compact(o, level: "native")
    }

    static func presser(_ a: JSON) throws -> Any { try presser(a, onglet(a)) }
    static func presser(_ a: JSON, _ t: TabRef) throws -> JSON {
        let m = try mode(a)
        let touches = a.strings("keys") ?? a.nonEmpty("key").map { [$0] } ?? []
        guard !touches.isEmpty else { throw MCPError("missing parameter: keys (e.g. [\"Enter\"] or [\"Cmd+B\"])") }
        var args = argsPage(a, [])
        args["keys"] = touches
        if m != "native" && m != "ax" {
            let o = try actionPage("press", args, t, timeout: delai(a, 5000))
            if m == "dom" || o["reacted"] as? Bool != false || o["navigated"] != nil { return compact(o) }
            if Native.ecranVerrouille { var r = compact(o); r["escalation"] = Native.verrouille; return r }
        }
        // Raccourci que les événements synthétiques ne déclenchent pas : vraies touches, Safari au premier plan
        let w = try Page.call("watch", [:], in: t)["watch"] as? Int ?? 0
        let prep = try Native.preparer(t)
        try Native.activer()
        for k in touches { try Native.key(k); Thread.sleep(forTimeInterval: 0.05) }
        var o = try Page.call("settle", ["watch": w], in: t, timeout: 4)
        o["keys"] = touches
        o["activated_safari"] = true
        if prep.tabSwitched { o["tab_activated"] = true }
        return compact(o, level: "native")
    }

    static func choisir(_ a: JSON) throws -> Any { try choisir(a, onglet(a)) }
    static func choisir(_ a: JSON, _ t: TabRef) throws -> JSON {
        guard a.has("option") else { throw MCPError("missing parameter: option (value or visible text; a list for a multiple select)") }
        return compact(try actionPage("select", argsPage(a, ["option"]), t, timeout: delai(a, 5000)))
    }

    static func cocher(_ a: JSON) throws -> Any { try cocher(a, onglet(a)) }
    static func cocher(_ a: JSON, _ t: TabRef) throws -> JSON {
        var o = try actionPage("check", argsPage(a, ["checked"]), t, timeout: delai(a, 5000))
        if o.removeValue(forKey: "ok") as? Bool == false {
            // case dessinée par la page qui ignore les clics synthétiques : clic escaladé sur le même élément
            guard let f = o["field"] as? String, let ref = f.split(separator: " ").first else { return compact(o) }
            var c = try cliquer(["ref": String(ref), "mode": a.nonEmpty("mode") ?? "auto"], t)
            c["checked"] = (a.bool("checked") ?? true)
            return c
        }
        return compact(o)
    }

    static func survoler(_ a: JSON) throws -> Any { try survoler(a, onglet(a)) }
    static func survoler(_ a: JSON, _ t: TabRef) throws -> JSON {
        let m = try mode(a)
        if m != "native" { return compact(try actionPage("hover", argsPage(a, []), t, timeout: delai(a, 5000))) }
        let loc = try actionPage("locate", argsPage(a, []), t, timeout: delai(a, 5000))
        guard let x = loc["x"] as? Double, let y = loc["y"] as? Double, let w = loc["watch"] as? Int else { throw MCPError("could not locate the target") }
        let prep = try Native.preparer(t)
        try Native.activer()
        Native.move(to: Native.ecran(prep.web, x: x, y: y, vw: loc["vw"] as? Double ?? 0))
        var o = try Page.call("settle", ["watch": w], in: t, timeout: 4)
        o["hovered"] = loc["target"]; o["activated_safari"] = true
        return compact(o, level: "native")
    }

    static func defiler(_ a: JSON) throws -> Any { try defiler(a, onglet(a)) }
    static func defiler(_ a: JSON, _ t: TabRef) throws -> JSON {
        var args = argsPage(a, ["to", "by", "block", "wait_more"])
        if let ms = a.double("timeout") { args["timeout"] = ms }
        return try actionPage("scroll", args, t, timeout: delai(a, 5000) + 1)
    }

    static func attendre(_ a: JSON) throws -> Any { try attendre(a, onglet(a)) }
    static func attendre(_ a: JSON, _ t: TabRef) throws -> JSON {
        let t0 = Date()
        let limite = delai(a, 10000)
        let conditions = ["selector", "text", "gone", "text_gone", "url", "ready_state", "network_idle", "js"]
        guard conditions.contains(where: { a.has($0) }) || a.has("ms") else {
            throw MCPError("give a condition: selector, text, gone, text_gone, url, ready_state, network_idle, js, or ms for a plain delay")
        }
        if let ms = a.double("ms"), !conditions.contains(where: { a.has($0) }) {
            Thread.sleep(forTimeInterval: min(ms, 60000) / 1000)
            return ["waited_ms": Int(ms)]
        }
        let args = passer(a, ["selector", "text", "gone", "text_gone", "url", "ready_state", "network_idle", "idle_ms"])
        var expr = "__mcp.run('probe',\(Page.lit(args)))"
        if let js = a.nonEmpty("js") {
            let t = js.trimmingCharacters(in: .whitespacesAndNewlines)
            let simple = !t.contains(";") && !t.contains("\n") && !t.hasPrefix("return")
            expr = "__mcp.probeWith(\(Page.lit(args)),function(){\n\(simple ? "return (\(t));" : t)\n})"
        }
        var dialogues: [Any] = [], dernier: JSON = [:], navigue = false, url0: String?
        while true {
            if let o = try? Page.raw(expr, in: t, timeout: 2) {
                dialogues += o["dialogs"] as? [Any] ?? []
                if let u = o["url"] as? String { if url0 == nil { url0 = u } else if u != url0 { navigue = true } }
                if let e = o["error"] as? String { throw MCPError(e) }
                if o["met"] as? Bool == true {
                    var r: JSON = ["met": true, "ms": Int(Date().timeIntervalSince(t0) * 1000)]
                    for k in ["found", "value", "url"] { if let v = o[k] { r[k] = v } }
                    if navigue { r["navigated"] = true }
                    if !dialogues.isEmpty { r["dialogs"] = dialogues }
                    return r
                }
                dernier = o
            }
            if Date().timeIntervalSince(t0) >= limite {
                var etat = "url \(dernier["url"] ?? "?"), readyState \(dernier["ready_state"] ?? "?")"
                if let e = dernier["js_error"] { etat += ", js error \(e)" }
                throw MCPError("timed out after \(Int(limite * 1000)) ms (\(etat))")
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
    }

    // MARK: - act : plusieurs étapes en un appel

    static func agir(_ a: JSON) throws -> Any {
        let t = try onglet(a)
        let etapes = a.objects("steps") ?? []
        guard !etapes.isEmpty else { throw MCPError("missing parameter: steps (list of {action, ...})") }
        let t0 = Date()
        var trace: [JSON] = []
        for (i, e) in etapes.enumerated() {
            let action = e.nonEmpty("action") ?? ""
            var s = e
            s.removeValue(forKey: "action")
            // politique des dialogues commune à toutes les étapes, sauf si l'étape la précise
            for k in ["accept_dialogs", "prompt_text"] where s[k] == nil && a[k] != nil { s[k] = a[k] }
            let d0 = Date()
            do {
                var r: JSON
                switch action {
                case "click": r = try cliquer(s, t)
                case "type": r = try taper(s, t)
                case "press": r = try presser(s, t)
                case "select": r = try choisir(s, t)
                case "check": r = try cocher(s, t)
                case "hover": r = try survoler(s, t)
                case "scroll": r = try defiler(s, t)
                case "wait": r = try attendre(s, t)
                case "read": r = try actionPage("read", passer(s, cibleCles + ["max_chars", "offset"]), t, timeout: delai(s, 5000))
                case "snapshot":
                    r = try Page.call("snapshot", passer(s, ["all", "viewport_only", "selector", "ref", "max_chars", "offset", "urls"]), in: t)
                    r.removeValue(forKey: "ms")
                case "js":
                    var j = s; j["tabs"] = [t.json]
                    r = try executerJS(j) as? JSON ?? [:]
                case "goto":
                    guard let u = s.nonEmpty("url").map(normaliser) else { throw MCPError("goto needs url") }
                    let avant = try AE.get(AE.prop("pURL", of: AE.tab(t)))?.string ?? ""
                    try AE.set(AE.prop("pURL", of: AE.tab(t)), NSAppleEventDescriptor(string: u))
                    let st = AS.waitLoaded([t], before: [t: avant], timeout: delai(s, 15000))[t]
                    r = ["url": st?.url ?? u, "title": st?.titre ?? ""]
                    if st?.pret == false { r["loaded"] = false }
                default: throw MCPError("unknown action: \(action) (click, type, press, select, check, hover, scroll, wait, read, snapshot, js, goto)")
                }
                if s.has("expect"), r["expect_met"] as? Bool == false { throw MCPError("expected effect not seen: \(Page.lit(s["expect"]!))") }
                r.removeValue(forKey: "expect_met")
                var l: JSON = ["step": i + 1, "action": action, "ms": Int(Date().timeIntervalSince(d0) * 1000)]
                l.merge(r) { a, _ in a }
                trace.append(l)
            } catch {
                var echec: JSON = ["failed_step": i + 1, "action": action, "error": "\(error)",
                                   "ms": Int(Date().timeIntervalSince(t0) * 1000)]
                if !trace.isEmpty { echec["done"] = trace }
                // zone concernée : le dialogue ouvert s'il y en a un, sinon ce qui est à l'écran
                let info = try? Page.call("page_info", [:], in: t)
                var sa: JSON = ["viewport_only": true, "max_chars": 3000]
                if let d = (info?["open_dialogs"] as? [String])?.first, let ref = d.split(separator: " ").first { sa = ["ref": String(ref), "max_chars": 3000] }
                if let sn = try? Page.call("snapshot", sa, in: t) { echec["snapshot"] = sn["text"] }
                throw MCPFailure(payload: echec)
            }
        }
        return ["steps": trace, "ms": Int(Date().timeIntervalSince(t0) * 1000)]
    }

    // MARK: - Liste de lecture et favoris (Bookmarks.plist, lecture seule)

    private static func titre(_ n: [String: Any]) -> String {
        (n["URIDictionary"] as? [String: Any])?["title"] as? String ?? n["Title"] as? String ?? ""
    }

    static func listeDeLecture(_ a: JSON) throws -> Any {
        let racine = try Fichiers.racineFavoris()
        let rl = (racine["Children"] as? [[String: Any]] ?? []).first { $0["Title"] as? String == "com.apple.ReadingList" }
        let filtre = a.nonEmpty("text").map(fold)
        var items: [(Date, JSON)] = []
        for n in rl?["Children"] as? [[String: Any]] ?? [] {
            let info = n["ReadingList"] as? [String: Any] ?? [:]
            let t = titre(n), url = n["URLString"] as? String ?? ""
            let apercu = info["PreviewText"] as? String ?? ""
            let lu = info["DateLastViewed"] != nil
            if a.bool("unread_only") == true && lu { continue }
            if let filtre, !fold(t + " " + url + " " + apercu).contains(filtre) { continue }
            let ajout = info["DateAdded"] as? Date ?? .distantPast
            var o: JSON = ["title": t, "url": url, "read": lu]
            if ajout != .distantPast { o["added"] = Dates.format(ajout) }
            if a.bool("include_preview") == true, !apercu.isEmpty { o["preview"] = String(apercu.prefix(300)) }
            items.append((ajout, o))
        }
        items.sort { $0.0 > $1.0 }
        let limite = max(1, a.int("limit") ?? 20)
        var out: JSON = ["items": items.prefix(limite).map(\.1)]
        if items.count > limite { out["total"] = items.count; out["truncated"] = true }
        return out
    }

    static func ajouterListeDeLecture(_ a: JSON) throws -> Any {
        let elements = a.objects("items") ?? []
        guard !elements.isEmpty else { throw MCPError("missing parameter: items") }
        let liste = try "{" + elements.map { e -> String in
            guard let u = e.nonEmpty("url") else { throw MCPError("each item needs a url") }
            return "{\(AS.lit(normaliser(u))), \(AS.lit(e.nonEmpty("title") ?? "")), \(AS.lit(e.nonEmpty("preview") ?? ""))}"
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
            return m.string == "ok" ? ["url": u, "ok": true] : ["url": u, "ok": false, "error": m.string ?? "failed"]
        }
        return ["added": res.filter { $0["ok"] as? Bool == true }.count, "results": res]
    }

    static func favoris(_ a: JSON) throws -> Any {
        let racine = try Fichiers.racineFavoris()
        let filtre = a.nonEmpty("text").map(fold)
        let dossierFiltre = a.nonEmpty("folder").map(fold)
        let dossiersSeuls = a.bool("folders") == true
        var out: [JSON] = []
        func nom(_ n: [String: Any]) -> String {
            switch n["Title"] as? String {
            case "BookmarksBar": return "Favorites"
            case "BookmarksMenu": return "Bookmarks Menu"
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
                        out.append(["folder": p, "count": (c["Children"] as? [Any])?.count ?? 0, "uuid": c["WebBookmarkUUID"] as? String ?? ""])
                    }
                    parcourir(c, p)
                } else if !dossiersSeuls, type == "WebBookmarkTypeLeaf" {
                    let t = titre(c), u = c["URLString"] as? String ?? ""
                    if let dossierFiltre, !fold(chemin).contains(dossierFiltre) { continue }
                    if let filtre, !fold(t + " " + u).contains(filtre) { continue }
                    out.append(["title": t, "url": u, "folder": chemin, "uuid": c["WebBookmarkUUID"] as? String ?? ""])
                }
            }
        }
        parcourir(racine, "")
        let limite = max(1, a.int("limit") ?? 50)
        var res: JSON = [dossiersSeuls ? "folders" : "bookmarks": Array(out.prefix(limite))]
        if out.count > limite { res["total"] = out.count; res["truncated"] = true }
        return res
    }

    // MARK: - Historique (History.db, lecture seule)

    private static func like(_ s: String) -> String {
        "%" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
    }

    static func historique(_ a: JSON) throws -> Any {
        let db = try Fichiers.DB(Fichiers.history)
        var where_: [String] = [], params: [Any] = []
        if let d = a.nonEmpty("since") { where_.append("v.visit_time >= ?"); params.append(try Dates.parse(d).timeIntervalSinceReferenceDate) }
        if let d = a.nonEmpty("until") { where_.append("v.visit_time < ?"); params.append(try Dates.parse(d).timeIntervalSinceReferenceDate) }
        if let dom = a.nonEmpty("domain")?.lowercased() {
            let d = dom.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            where_.append("(i.url LIKE ? ESCAPE '\\' OR i.url LIKE ? ESCAPE '\\')")
            params.append("%://" + d + "/%"); params.append("%." + d + "/%")
        }
        var having = ""
        if let t = a.nonEmpty("text") {
            having = "HAVING (i.url LIKE ? ESCAPE '\\' OR titre LIKE ? ESCAPE '\\')"
            params.append(like(t)); params.append(like(t))
        }
        let limite = max(1, a.int("limit") ?? 20)
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
            var o: JSON = ["url": r[0] as? String ?? "", "title": r[3] as? String ?? "", "visits": r[1] as? Int ?? 0]
            if let t = r[2] as? Double { o["last_visit"] = Dates.format(Date(timeIntervalSinceReferenceDate: t)) }
            return o
        }
        var out: JSON = ["pages": pages]
        if rows.count > limite { out["truncated"] = true }
        return out
    }

    // MARK: - Groupes d'onglets (SafariTabs.db, lecture seule)

    static func groupesOnglets(_ a: JSON) throws -> Any {
        let db = try Fichiers.DB(Fichiers.tabs)
        // Onglets d'un groupe : enfants directs et onglets épinglés (sous-dossier subtype 1)
        if let g = a.int("group_id") {
            let rows = try db.rows("""
            SELECT t.title, t.url, CASE WHEN t.parent = ?1 THEN 0 ELSE 1 END AS epingle FROM bookmarks t
            WHERE t.type = 0 AND t.deleted = 0 AND (t.parent = ?1 OR t.parent IN (SELECT id FROM bookmarks WHERE parent = ?1 AND type = 1 AND subtype = 1))
            ORDER BY epingle DESC, t.order_index
            """, [g])
            return ["group_id": g, "tabs": rows.map { r -> JSON in
                var o: JSON = ["title": r[0] as? String ?? "", "url": r[1] as? String ?? ""]
                if r[2] as? Int == 1 { o["pinned"] = true }
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
        let filtre = a.nonEmpty("text").map(fold)
        let groupes: [JSON] = rows.compactMap { r in
            let local = r[3] as? Int == 1
            if local && a.bool("include_unnamed") != true { return nil }
            let nom = r[1] as? String ?? ""
            if let filtre, !fold(nom).contains(filtre) { return nil }
            var o: JSON = ["group_id": r[0] as? Int ?? 0, "name": local ? "" : nom, "tab_count": r[2] as? Int ?? 0]
            if local { o["unnamed"] = true }
            if r[4] as? Int == 1 { o["open"] = true }
            return o
        }
        return ["groups": groupes]
    }
}
