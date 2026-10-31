// capture_page : image PNG/JPEG d'un onglet, sans autorisation « Enregistrement de l'écran ».
// L'onglet fige son propre DOM (images et feuilles de style du même site incluses en ligne, valeurs des champs,
// canvas), puis un WKWebView hors écran, sans JavaScript ni cookies, le redessine à la même largeur.
// Marche Mac verrouillé, écran éteint ou Safari caché. Limite : une image d'un autre site qui exige une connexion peut manquer.
import Foundation
import AppKit
import WebKit

enum Capture {
    /// Fige l'onglet : renvoie {html, url, title, w, h, x, y, H, inl} en JSON
    private static let figer = #"""
    var d=document,de=d.documentElement,c=de.cloneNode(true),budget=15e6,inl=0;
    function abs(u,b){try{return new URL(u,b).href}catch(e){return u}}
    function paires(sel,f){var o=de.querySelectorAll(sel),k=c.querySelectorAll(sel);for(var i=0;i<o.length&&i<k.length;i++)try{f(o[i],k[i])}catch(e){}}
    paires('img',function(o,k){
      k.removeAttribute('loading');
      if(o.complete&&o.naturalWidth&&budget>0){try{var cv=d.createElement('canvas');cv.width=o.naturalWidth;cv.height=o.naturalHeight;
        cv.getContext('2d').drawImage(o,0,0);var u=cv.toDataURL('image/png');if(u.length<budget){budget-=u.length;k.src=u;k.removeAttribute('srcset');inl++;return}}catch(e){}}
      if(o.currentSrc){k.src=o.currentSrc;k.removeAttribute('srcset')}});
    paires('canvas',function(o,k){var i=d.createElement('img');i.src=o.toDataURL();i.style.cssText=getComputedStyle(o).cssText;i.width=o.width;i.height=o.height;k.replaceWith(i)});
    paires('link[rel~=stylesheet],style',function(o,k){var s=o.sheet;if(!s)return;var t='',b=s.href||d.baseURI;
      for(var r of s.cssRules)t+=r.cssText+'\n';
      t=t.replace(/url\(\s*(['"]?)([^'")]+)\1\s*\)/g,function(m,q,u){return /^(data:|#)/.test(u)?m:'url("'+abs(u,b)+'")'});
      var st=d.createElement('style');if(o.media&&o.media.mediaText)st.media=o.media.mediaText;st.textContent=t;k.replaceWith(st)});
    paires('input',function(o,k){if(o.type=='checkbox'||o.type=='radio'){if(o.checked)k.setAttribute('checked','');else k.removeAttribute('checked')}else if(o.type!='password')k.setAttribute('value',o.value)});
    paires('textarea',function(o,k){k.textContent=o.value});
    paires('select',function(o,k){for(var i=0;i<o.options.length;i++)if(o.options[i].selected)k.options[i].setAttribute('selected','')});
    c.querySelectorAll('script,noscript,iframe').forEach(function(e){e.remove()});
    return {html:'<!DOCTYPE html>'+c.outerHTML,url:location.href,title:d.title,w:innerWidth,h:innerHeight,x:scrollX,y:scrollY,
      H:Math.max(de.scrollHeight,d.body?d.body.scrollHeight:0),inl:inl}
    """#

    static let hauteurMax = 20000.0

    static func capturer(_ a: JSON) throws -> Any {
        let ref: TabRef
        if let w = a.int("window_id"), let i = a.int("index") { ref = TabRef(fenetre: w, index: i) }
        else if a.has("window_id") || a.has("index") { throw MCPError("give both window_id and index, or neither for the active tab") }
        else { ref = try AS.currentTab() }

        let d = try AS.run("""
        tell application "Safari"
          set t to \(ref.spec)
          set v to ""
          try
            set v to (do JavaScript \(AS.lit(AS.jsWrapper(figer))) in t)
          end try
          return v
        end tell
        """)
        guard var brut = d.string, brut.hasPrefix("§") else {
            throw MCPError("JavaScript unavailable: enable Develop > Allow JavaScript from Apple Events")
        }
        brut.removeFirst()
        if brut.hasPrefix("ERR") { throw MCPError("JavaScript: " + brut.dropFirst(3)) }
        guard let page = try JSONSerialization.jsonObject(with: Data(brut.utf8)) as? JSON,
              let html = page["html"] as? String, let adresse = page["url"] as? String else { throw MCPError("could not read the page") }
        let titre = page["title"] as? String ?? ""
        let num = { (k: String) in (page[k] as? NSNumber)?.doubleValue ?? 0 }
        let largeur = max(320, num("w")), hauteurVue = max(200, num("h"))
        let pleine = a.bool("full_page") ?? false
        let hauteurPage = min(max(num("H"), hauteurVue), hauteurMax)
        let rect = pleine ? NSRect(x: 0, y: 0, width: largeur, height: hauteurPage)
                          : NSRect(x: 0, y: min(num("y"), max(0, hauteurPage - hauteurVue)), width: largeur, height: hauteurVue)

        let url = try destination(a.nonEmpty("path"), titre: titre)
        let jpeg = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        // Retina (x2) sauf pour une très longue page, pour garder un fichier raisonnable
        let echelle = rect.height > 8000 ? 1.0 : 2.0
        let image = try rendre(html, base: URL(string: adresse), largeur: largeur, rect: rect, echelle: echelle)
        guard let rep = pixels(image, largeur: Int(largeur * echelle)),
              let donnees = rep.representation(using: jpeg ? .jpeg : .png, properties: jpeg ? [.compressionFactor: 0.85] : [:]) else {
            throw MCPError("could not encode the image")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try donnees.write(to: url)
        var o: JSON = ["path": url.path, "width": rep.pixelsWide, "height": rep.pixelsHigh, "title": titre, "url": adresse,
                       "inlined_images": page["inl"] ?? 0]
        o["window_id"] = ref.fenetre; o["index"] = ref.index
        if pleine && num("H") > hauteurMax { o["truncated"] = true }
        return o
    }

    /// Image ramenée à `largeur` pixels : le rendu hors écran suit l'échelle de l'écran (x2, voire plus) en plus de snapshotWidth
    private static func pixels(_ image: NSImage, largeur: Int) -> NSBitmapImageRep? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        guard cg.width > largeur else { return NSBitmapImageRep(cgImage: cg) }
        let hauteur = Int((Double(cg.height) * Double(largeur) / Double(cg.width)).rounded())
        guard let ctx = CGContext(data: nil, width: largeur, height: hauteur, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: largeur, height: hauteur))
        return ctx.makeImage().map { NSBitmapImageRep(cgImage: $0) }
    }

    /// Chemin demandé (~ accepté, extension .png ajoutée si absente), sinon ~/Pictures/Safari captures/<titre> <date>.png
    private static func destination(_ chemin: String?, titre: String) throws -> URL {
        if let chemin {
            var u = URL(fileURLWithPath: (chemin as NSString).expandingTildeInPath)
            guard u.path.hasPrefix("/") else { throw MCPError("path must be absolute") }
            if !["png", "jpg", "jpeg"].contains(u.pathExtension.lowercased()) { u.appendPathExtension("png") }
            return u
        }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let nom = String(titre.components(separatedBy: CharacterSet(charactersIn: "/:\\\n\r\t")).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces).prefix(80))
        return URL(fileURLWithPath: Fichiers.home + "/Pictures/Safari captures")
            .appendingPathComponent((nom.isEmpty ? "Page" : nom) + " " + f.string(from: Date()) + ".png")
    }

    // MARK: - Rendu hors écran (fil principal, qui tourne avec une vraie RunLoop : voir main.swift)

    private final class Rendu: NSObject, WKNavigationDelegate {
        var fini: ((Error?) -> Void)?
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) { fini?(nil); fini = nil }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { fini?(e); fini = nil }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { fini?(e); fini = nil }
    }

    private static func rendre(_ html: String, base: URL?, largeur: Double, rect: NSRect, echelle: Double) throws -> NSImage {
        precondition(!Thread.isMainThread)
        var resultat: Result<NSImage, MCPError> = .failure(MCPError("rendering timed out (30 s)"))
        let sem = DispatchSemaphore(value: 0)
        var garde: (WKWebView, Rendu)?
        DispatchQueue.main.async {
            let cfg = WKWebViewConfiguration()
            cfg.defaultWebpagePreferences.allowsContentJavaScript = false
            cfg.websiteDataStore = .nonPersistent()   // aucun cookie : rien n'est renvoyé au site au nom de l'utilisateur
            let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: largeur, height: rect.maxY), configuration: cfg)
            let r = Rendu()
            garde = (wv, r)
            wv.navigationDelegate = r
            r.fini = { e in
                if let e { resultat = .failure(MCPError("rendering failed: \(e.localizedDescription)")); sem.signal(); return }
                // Laisse le temps aux polices web de s'appliquer
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let c = WKSnapshotConfiguration()
                    c.rect = rect
                    c.snapshotWidth = NSNumber(value: largeur * echelle)
                    wv.takeSnapshot(with: c) { img, err in
                        resultat = img.map { .success($0) } ?? .failure(MCPError("snapshot failed: \(err?.localizedDescription ?? "unknown")"))
                        sem.signal()
                    }
                }
            }
            wv.loadHTMLString(html, baseURL: base)
        }
        _ = sem.wait(timeout: .now() + 30)
        DispatchQueue.main.async { withExtendedLifetime(garde) {}; garde = nil }
        return try resultat.get()
    }
}
