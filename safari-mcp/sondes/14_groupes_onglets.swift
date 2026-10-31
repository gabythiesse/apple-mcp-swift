// Sonde 14 : groupes d'onglets. Création par le menu (Accessibilité) dans une fenêtre de test,
// relecture filtrée dans SafariTabs.db (lecture seule), suppression par le menu, vérification.
// Garde-fou : chaque action de menu n'est faite que si la fenêtre au premier plan est la fenêtre de test
// (titre AX « [mcp-test] fenêtre », posé par JavaScript sur about:blank).
import Foundation
import ApplicationServices
import AppKit
import SQLite3

let marque = "[mcp-test] groupe \(Int(Date().timeIntervalSince1970) % 100000)"
@discardableResult
func asrun(_ label: String, _ src: String) -> NSAppleEventDescriptor? {
    var e: NSDictionary?; let t0 = Date(); let r = NSAppleScript(source: src)!.executeAndReturnError(&e)
    let ms = Int(Date().timeIntervalSince(t0) * 1000)
    if let e { print("✗ \(label) (\(ms) ms) : \(e[NSAppleScript.errorMessage] ?? "")"); return nil }
    if !label.isEmpty { print("✓ \(label) (\(ms) ms)\(r.stringValue.map { " : " + $0 } ?? "")") }; return r
}
func ids() -> Set<Int32> { Set((asrun("", #"tell application "Safari" to get id of every window whose visible is true"#).map { d in (1...max(1, d.numberOfItems)).compactMap { d.atIndex($0)?.int32Value } }) ?? []) }
func attr(_ el: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(el, a as CFString, &v); return v }
let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first!.processIdentifier
let app = AXUIElementCreateApplication(pid)
func fenetreTestDevant() -> Bool {
    guard let f = attr(app, kAXFocusedWindowAttribute) else { return false }
    return (attr(f as! AXUIElement, kAXTitleAttribute) as? String)?.hasPrefix("[mcp-test] fenêtre") == true
}
func menu(_ item: String) -> Bool {
    guard fenetreTestDevant() else { print("✗ fenêtre de test pas au premier plan : « \(item) » non cliqué"); return false }
    return asrun("menu « \(item) »", "tell application \"System Events\" to tell process \"Safari\" to click menu item \"\(item)\" of menu 1 of menu bar item \"Fichier\" of menu bar 1") != nil
}
func groupesTest() -> [String] {
    var db: OpaquePointer?; var out: [String] = []
    let p = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db"
    guard sqlite3_open_v2("file:\(p)?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return ["ouverture KO"] }
    defer { sqlite3_close(db) }
    var st: OpaquePointer?
    let sql = """
    SELECT g.id, g.type, g.subtype, g.parent, g.deleted, g.num_children,
      (SELECT COUNT(*) FROM bookmarks t WHERE t.parent = g.id) AS enfants,
      (SELECT COUNT(*) FROM windows_tab_groups w WHERE w.tab_group_id = g.id) AS fenetres
    FROM bookmarks g WHERE g.title LIKE '[mcp-test]%'
    """
    sqlite3_prepare_v2(db, sql, -1, &st, nil)
    while sqlite3_step(st) == SQLITE_ROW { out.append((Int32(0)..<Int32(8)).map { "\(String(cString: sqlite3_column_name(st, $0)))=\(sqlite3_column_text(st, $0).map { String(cString: $0) } ?? "∅")" }.joined(separator: " ")) }
    sqlite3_finalize(st)
    return out
}

// 1. Fenêtre de test titrée
let avant = ids()
asrun("fenêtre de test", #"tell application "Safari" to make new document with properties {URL:"about:blank"}"#)
Thread.sleep(forTimeInterval: 1)
guard ids().subtracting(avant).count == 1, let W = ids().subtracting(avant).first else { print("✗ fenêtre non isolée"); exit(1) }
asrun("titre de test", "tell application \"Safari\" to do JavaScript \"document.title='[mcp-test] fenêtre'\" in current tab of window id \(W)")
asrun("premier plan", "tell application \"Safari\" to activate\ntell application \"Safari\" to set index of window id \(W) to 1")
Thread.sleep(forTimeInterval: 0.8)
print("fenêtre de test devant : \(fenetreTestDevant())")

// 2. Groupe vide par le menu, nommé via le champ qui prend le focus
if menu("Nouveau groupe d’onglets vide") {
    Thread.sleep(forTimeInterval: 1)
    if let f = attr(app, kAXFocusedUIElementAttribute) {
        let el = f as! AXUIElement
        print("élément focalisé : \(attr(el, kAXRoleAttribute) as? String ?? "?")")
        if (attr(el, kAXRoleAttribute) as? String) == "AXTextField" {
            AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, marque as CFString)
            asrun("valider le nom", #"tell application "System Events" to key code 36"#)
        }
    }
    Thread.sleep(forTimeInterval: 1)
    asrun("nom de la fenêtre (AppleScript)", "tell application \"Safari\" to return name of window id \(W)")
    asrun("onglets visibles dans la fenêtre", "tell application \"Safari\" to return count of tabs of window id \(W)")
    asrun("sync", #"tell application "Safari" to sync all plist to disk"#)
    Thread.sleep(forTimeInterval: 2)
    print("SafariTabs.db, lignes [mcp-test] : \(groupesTest())")
    // Le nouvel onglet du groupe porte la page de démarrage : on lui redonne le titre de test pour le garde-fou
    asrun("titre de test", "tell application \"Safari\" to do JavaScript \"document.title='[mcp-test] fenêtre'\" in current tab of window id \(W)")
    Thread.sleep(forTimeInterval: 0.5)
    // 3. Suppression du groupe courant de la fenêtre de test
    if menu("Supprimer le groupe d’onglets") {
        Thread.sleep(forTimeInterval: 1)
        // Feuille de confirmation éventuelle : bouton Supprimer de la fenêtre de test uniquement
        asrun("confirmation", """
        tell application "System Events" to tell process "Safari"
          if exists sheet 1 of window 1 then
            click (first button of sheet 1 of window 1 whose name starts with "Supprimer")
            return "feuille confirmée"
          end if
          return "pas de feuille"
        end tell
        """)
    }
}
Thread.sleep(forTimeInterval: 2)
asrun("sync", #"tell application "Safari" to sync all plist to disk"#)
Thread.sleep(forTimeInterval: 2)
print("après suppression, lignes [mcp-test] : \(groupesTest())")
asrun("fermer la fenêtre de test", "tell application \"Safari\" to close window id \(W)")
print("fenêtres visibles restantes identiques à avant : \(ids() == avant)")
