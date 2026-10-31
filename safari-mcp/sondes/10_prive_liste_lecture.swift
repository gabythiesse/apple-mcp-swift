// Sonde 10 : fenêtre privée par le menu (Accessibilité), opérations sur ses onglets (pas d'historique),
// source HTML, titre après chargement, ajout à la liste de lecture d'un élément [mcp-test],
// puis relecture filtrée de Bookmarks.plist (lecture seule). La fenêtre de test est fermée à la fin.
import Foundation

let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let p1 = dir.appendingPathComponent("mcp-test-1.html").absoluteString
let home = FileManager.default.homeDirectoryForCurrentUser.path

@discardableResult
func run(_ label: String, _ src: String, quiet: Bool = false) -> NSAppleEventDescriptor? {
    let t0 = Date(); var err: NSDictionary?
    let r = NSAppleScript(source: src)!.executeAndReturnError(&err)
    let ms = Int(Date().timeIntervalSince(t0) * 1000)
    if let err { print("✗ \(label) (\(ms) ms) : \(err[NSAppleScript.errorNumber] ?? "") \(err[NSAppleScript.errorMessage] ?? "")"); return nil }
    if !quiet { print("✓ \(label) (\(ms) ms) : \(r.stringValue ?? "\(r.numberOfItems) élément(s)")") }
    return r
}
func ids() -> Set<Int32> {
    guard let d = run("ids", #"tell application "Safari" to get id of every window"#, quiet: true) else { return [] }
    return Set(d.numberOfItems > 0 ? (1...d.numberOfItems).compactMap { d.atIndex($0)?.int32Value } : [])
}

// 1. Fenêtre privée par le menu
let avant = ids()
run("fenêtre privée (menu Fichier)", """
tell application "Safari" to activate
tell application "System Events" to tell process "Safari" to click menu item "Nouvelle fenêtre privée" of menu 1 of menu bar item "Fichier" of menu bar 1
""")
Thread.sleep(forTimeInterval: 1.0)
let nouv = ids().subtracting(avant)
guard nouv.count == 1, let W = nouv.first else { print("✗ fenêtre privée non isolée : \(nouv)"); exit(1) }
let w = "window id \(W)"
print("   fenêtre privée id \(W), visible par AppleScript")
defer { }

// 2. Onglets dans la fenêtre privée
run("charger la page de test", "tell application \"Safari\" to set URL of current tab of \(w) to \"\(p1)\"")
run("attendre le chargement (JS readyState)", """
tell application "Safari"
  repeat 50 times
    if (do JavaScript "document.readyState" in current tab of \(w)) is "complete" then exit repeat
    delay 0.1
  end repeat
  return name of current tab of \(w)
end tell
""")
run("source HTML (longueur)", "tell application \"Safari\" to set s to source of current tab of \(w)\nreturn length of s")
run("ouvrir 3 onglets en un script", """
tell application "Safari" to tell \(w)
  repeat with u in {"about:blank", "about:blank", "\(p1)"}
    make new tab at end of tabs with properties {URL:u}
  end repeat
  return count of tabs
end tell
""")
run("lecture en lot (index, nom, URL)", """
tell application "Safari" to tell \(w)
  set AppleScript's text item delimiters to " | "
  return {(index of every tab) as text, (name of every tab) as text, (URL of every tab) as text} as text
end tell
""")
run("fermer onglets 3 puis 2 (ordre décroissant)", "tell application \"Safari\" to tell \(w)\nclose tab 3\nclose tab 2\nreturn count of tabs\nend tell")

// 3. Liste de lecture : ajout d'un élément de test (aucun effet externe ; synchro iCloud possible)
let titre = "[mcp-test] lecture \(Int(Date().timeIntervalSince1970))"
let urlTest = "https://example.com/?mcp-test=\(Int(Date().timeIntervalSince1970))"
run("ajouter à la liste de lecture", "tell application \"Safari\" to add reading list item \"\(urlTest)\" with title \"\(titre)\" and preview text \"[mcp-test] aperçu\"")
run("forcer l'écriture disque (commande cachée sync all plist to disk)", "tell application \"Safari\" to sync all plist to disk")
Thread.sleep(forTimeInterval: 1.0)

// 4. Relecture filtrée de Bookmarks.plist (seuls les éléments [mcp-test] sont affichés)
let t0 = Date()
if let d = FileManager.default.contents(atPath: "\(home)/Library/Safari/Bookmarks.plist"),
   let racine = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] {
    var trouves: [String] = []
    func parcourir(_ n: [String: Any], _ dansListe: Bool) {
        let t = (n["URIDictionary"] as? [String: Any])?["title"] as? String ?? n["Title"] as? String ?? ""
        let rl = dansListe || (n["Title"] as? String) == "com.apple.ReadingList"
        if t.hasPrefix("[mcp-test]") { trouves.append("\(t) | liste_de_lecture=\(rl) | uuid=\(n["WebBookmarkUUID"] ?? "?") | url=\(n["URLString"] ?? "")") }
        for c in n["Children"] as? [[String: Any]] ?? [] { parcourir(c, rl) }
    }
    parcourir(racine, false)
    print("✓ Bookmarks.plist relu en \(Int(Date().timeIntervalSince(t0) * 1000)) ms : \(trouves.count) élément(s) [mcp-test]")
    trouves.forEach { print("   \($0)") }
} else { print("✗ Bookmarks.plist illisible") }

// 5. Fermeture de la fenêtre de test
run("fermer la fenêtre privée", "tell application \"Safari\" to close \(w)")
print("fenêtre de test restante : \(ids().contains(W))")
print("TITRE_TEST=\(titre)")
