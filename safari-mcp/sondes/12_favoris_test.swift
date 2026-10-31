// Sonde 12 : relecture de Bookmarks.plist (lecture seule), n'affiche que les éléments [mcp-test]
import Foundation
let home = FileManager.default.homeDirectoryForCurrentUser.path
let t0 = Date()
guard let d = FileManager.default.contents(atPath: "\(home)/Library/Safari/Bookmarks.plist"),
      let racine = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { print("✗ illisible"); exit(1) }
var trouves: [String] = []
func parcourir(_ n: [String: Any], _ chemin: String) {
    let titre = (n["URIDictionary"] as? [String: Any])?["title"] as? String ?? n["Title"] as? String ?? ""
    // Les dossiers système (Title = com.apple.*) sont de la structure, pas du contenu
    let ici = titre.hasPrefix("com.apple.") || titre == "BookmarksBar" || titre == "BookmarksMenu" ? titre : "…"
    // Repérage par n'importe quelle valeur texte du nœud (titre, URL, aperçu) contenant « mcp-test »
    let textes = (n.values.compactMap { $0 as? String }) + ((n["URIDictionary"] as? [String: Any])?.values.compactMap { $0 as? String } ?? []) + ((n["ReadingList"] as? [String: Any])?.values.compactMap { $0 as? String } ?? [])
    if textes.contains(where: { $0.contains("mcp-test") }) {
        trouves.append("clés du nœud : \(n.keys.sorted()) | URIDictionary : \((n["URIDictionary"] as? [String: Any]) ?? [:])")
        trouves.append("\(titre) | dossier=\(chemin) | type=\(n["WebBookmarkType"] ?? "") | uuid=\(n["WebBookmarkUUID"] ?? "") | url=\(n["URLString"] ?? "") | RL=\((n["ReadingList"] as? [String: Any])?.keys.sorted() ?? [])")
    }
    for c in n["Children"] as? [[String: Any]] ?? [] { parcourir(c, chemin + "/" + ici) }
}
parcourir(racine, "")
print("\(d.count / 1024) Ko lus et parcourus en \(Int(Date().timeIntervalSince(t0) * 1000)) ms : \(trouves.count) élément(s) [mcp-test]")
trouves.forEach { print("  \($0)") }
