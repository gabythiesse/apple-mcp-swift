// Sonde 16 : nettoyage du groupe d'onglets de test créé par la sonde 14 (« Sans titre », uuid passé en argument).
// Fenêtre de test → barre latérale → sélection du groupe (ligne unique correspondant au nom) →
// garde-fou : nom AppleScript de la fenêtre de test commence par « <nom> — » → menu Supprimer le groupe d'onglets.
import Foundation
import ApplicationServices
import AppKit
import SQLite3

let nom = CommandLine.arguments[1], uuid = CommandLine.arguments[2]
@discardableResult
func asrun(_ label: String, _ src: String) -> NSAppleEventDescriptor? {
    var e: NSDictionary?; let r = NSAppleScript(source: src)!.executeAndReturnError(&e)
    if let e { print("✗ \(label) : \(e[NSAppleScript.errorMessage] ?? "")"); return nil }
    if !label.isEmpty { print("✓ \(label)\(r.stringValue.map { " : " + $0 } ?? "")") }; return r
}
func ids() -> Set<Int32> { Set((asrun("", #"tell application "Safari" to get id of every window whose visible is true"#).map { d in (1...max(1, d.numberOfItems)).compactMap { d.atIndex($0)?.int32Value } }) ?? []) }
func attr(_ el: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(el, a as CFString, &v); return v }
func children(_ el: AXUIElement) -> [AXUIElement] { attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func role(_ el: AXUIElement) -> String { attr(el, kAXRoleAttribute) as? String ?? "" }
func find(_ el: AXUIElement, depth: Int = 0, _ pred: (AXUIElement) -> Bool) -> [AXUIElement] {
    if depth > 14 { return [] }
    var out: [AXUIElement] = []
    for c in children(el) { if pred(c) { out.append(c) }; if role(c) != "AXWebArea" { out += find(c, depth: depth + 1, pred) } }
    return out
}
func texte(_ el: AXUIElement, depth: Int = 0) -> String {
    var s = [attr(el, kAXTitleAttribute), attr(el, kAXDescriptionAttribute), attr(el, kAXValueAttribute)].compactMap { $0 as? String }.joined(separator: " ")
    if depth < 4 { for c in children(el) { s += " " + texte(c, depth: depth + 1) } }
    return s
}
func etatGroupe() -> String {
    var db: OpaquePointer?
    let p = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db"
    sqlite3_open_v2("file:\(p)?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil); defer { sqlite3_close(db) }
    var st: OpaquePointer?
    sqlite3_prepare_v2(db, "SELECT id, deleted FROM bookmarks WHERE external_uuid = ?1", -1, &st, nil)
    sqlite3_bind_text(st, 1, uuid, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    defer { sqlite3_finalize(st) }
    return sqlite3_step(st) == SQLITE_ROW ? "présent (id \(sqlite3_column_int(st, 0)), deleted=\(sqlite3_column_int(st, 1)))" : "absent"
}
print("avant : groupe \(etatGroupe())")

let avant = ids()
asrun("fenêtre de test", #"tell application "Safari" to make new document with properties {URL:"about:blank"}"#)
Thread.sleep(forTimeInterval: 1)
guard ids().subtracting(avant).count == 1, let W = ids().subtracting(avant).first else { print("✗ fenêtre non isolée"); exit(1) }
asrun("premier plan", "tell application \"Safari\" to activate\ntell application \"Safari\" to set index of window id \(W) to 1")
Thread.sleep(forTimeInterval: 0.8)
let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first!.processIdentifier
let app = AXUIElementCreateApplication(pid)
let fenetre = attr(app, kAXFocusedWindowAttribute) as! AXUIElement

asrun("barre latérale", #"tell application "System Events" to tell process "Safari" to click menu item "Afficher la barre latérale" of menu 1 of menu bar item "Présentation" of menu bar 1"#)
Thread.sleep(forTimeInterval: 1)
let lignes = find(fenetre) { role($0) == "AXRow" }
let cibles = lignes.filter { texte($0).contains(nom) }
print("lignes de la barre latérale : \(lignes.count), correspondant à « \(nom) » : \(cibles.count)")
if cibles.count == 1 {
    AXUIElementSetAttributeValue(cibles[0], kAXSelectedAttribute as CFString, kCFBooleanTrue)
    Thread.sleep(forTimeInterval: 1)
    let nomFenetre = asrun("nom de la fenêtre de test", "tell application \"Safari\" to return name of window id \(W)")?.stringValue ?? ""
    let titreAX = attr(attr(app, kAXFocusedWindowAttribute) as! AXUIElement, kAXTitleAttribute) as? String ?? ""
    if nomFenetre.hasPrefix(nom + " — ") && titreAX == nomFenetre {
        asrun("menu Supprimer le groupe d’onglets", #"tell application "System Events" to tell process "Safari" to click menu item "Supprimer le groupe d’onglets" of menu 1 of menu bar item "Fichier" of menu bar 1"#)
        Thread.sleep(forTimeInterval: 1)
        asrun("confirmation", """
        tell application "System Events" to tell process "Safari"
          if exists sheet 1 of window 1 then
            set b to name of every button of sheet 1 of window 1
            click (first button of sheet 1 of window 1 whose name starts with "Supprimer")
            return "feuille confirmée"
          end if
          return "pas de feuille"
        end tell
        """)
    } else { print("✗ garde-fou : fenêtre « \(nomFenetre) » / AX « \(titreAX) » : rien supprimé") }
}
Thread.sleep(forTimeInterval: 1)
asrun("masquer la barre latérale", #"tell application "System Events" to tell process "Safari" to click menu item "Masquer la barre latérale" of menu 1 of menu bar item "Présentation" of menu bar 1"#)
asrun("fermer la fenêtre de test", "tell application \"Safari\" to close window id \(W)")
Thread.sleep(forTimeInterval: 2)
print("après : groupe \(etatGroupe()) ; fenêtres visibles identiques : \(ids() == avant)")
