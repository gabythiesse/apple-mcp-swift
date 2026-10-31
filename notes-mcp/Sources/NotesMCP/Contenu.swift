// Contenu des notes : texte simple → HTML de Notes, et nettoyage du HTML relu (images base64 retirées)
import Foundation

enum Contenu {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Ligne de titre (Notes prend la 1re ligne comme titre)
    static func titre(_ t: String) -> String { "<div><h1>\(esc(t))</h1></div>" }

    /// Texte simple : # / ## / ### titres, - * • puces, 1. listes numérotées, **gras**, *italique*, ligne vide
    static func html(_ texte: String) -> String {
        var out = "", liste: String? = nil
        func fermer() { if let l = liste { out += "</\(l)>"; liste = nil } }
        func ouvrir(_ l: String) { if liste != l { fermer(); out += "<\(l)>"; liste = l } }
        for raw in texte.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let m = line.range(of: #"^[-*•]\s+(\[[ xX]\]\s+)?"#, options: .regularExpression) {
                ouvrir("ul"); out += "<li>\(inline(String(line[m.upperBound...])))</li>"
            } else if let m = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                ouvrir("ol"); out += "<li>\(inline(String(line[m.upperBound...])))</li>"
            } else {
                fermer()
                if line.isEmpty { out += "<div><br></div>" }
                else if line.hasPrefix("### ") { out += "<div><h3>\(inline(String(line.dropFirst(4))))</h3></div>" }
                else if line.hasPrefix("## ") { out += "<div><h2>\(inline(String(line.dropFirst(3))))</h2></div>" }
                else if line.hasPrefix("# ") { out += "<div><h1>\(inline(String(line.dropFirst(2))))</h1></div>" }
                else { out += "<div>\(inline(raw))</div>" }
            }
        }
        fermer()
        return out
    }

    private static func inline(_ s: String) -> String {
        var h = esc(s)
        h = h.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<b>$1</b>", options: .regularExpression)
        h = h.replacingOccurrences(of: #"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"#, with: "<i>$1</i>", options: .regularExpression)
        return h
    }

    /// Contenu à écrire : html fourni tel quel, sinon texte converti
    static func corps(_ a: JSON, html: String, texte: String) -> String? {
        if let h = a.string(html) { return h }
        if let t = a.string(texte) { return Contenu.html(t) }
        return nil
    }

    /// HTML relu : les images intégrées en base64 sont remplacées par un repère
    static func nettoyer(_ body: String) -> String {
        body.replacingOccurrences(of: #"src="data:[^"]*""#, with: "src=\"(image : voir pieces_jointes)\"", options: .regularExpression)
    }

    /// Texte relu : sans caractères de remplacement des pièces jointes, sans blancs superflus
    static func texte(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func iso(_ d: Any?) -> String? {
        guard let d = d as? Date else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.string(from: d)
    }

    static func parseDate(_ s: String) throws -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        throw MCPError("date invalide : \(s) (AAAA-MM-JJ ou AAAA-MM-JJTHH:MM)")
    }
}
