// Sonde 13 : suppression d'un élément de liste de lecture [mcp-test] par l'interface (Accessibilité).
// Garde-fous : fenêtre de test dédiée, recherche filtrée AVANT toute lecture des lignes, suppression
// seulement si exactement une ligne visible et qu'elle correspond à l'élément de test ; sinon abandon.
// Usage : swift 13_ui_suppr_liste_lecture.swift "<texte de recherche>" "<texte attendu dans la ligne>" "<uuid>"
import Foundation
import ApplicationServices
import AppKit

let args = CommandLine.arguments
guard args.count == 4 else { print("usage : recherche attendu uuid"); exit(2) }
let recherche = args[1], attendu = args[2], uuid = args[3]

@discardableResult
func asrun(_ src: String) -> NSAppleEventDescriptor? {
    var e: NSDictionary?; let r = NSAppleScript(source: src)!.executeAndReturnError(&e)
    if let e { print("✗ AppleScript : \(e[NSAppleScript.errorMessage] ?? "")"); return nil }; return r
}
func attr(_ el: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(el, a as CFString, &v); return v }
func children(_ el: AXUIElement) -> [AXUIElement] { attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func role(_ el: AXUIElement) -> String { attr(el, kAXRoleAttribute) as? String ?? "" }
func subrole(_ el: AXUIElement) -> String { attr(el, kAXSubroleAttribute) as? String ?? "" }
/// Parcours limité aux rôles structurels (on ne lit aucun texte pendant la recherche du champ)
func find(_ el: AXUIElement, depth: Int = 0, _ pred: (AXUIElement) -> Bool) -> [AXUIElement] {
    if depth > 14 { return [] }
    var out: [AXUIElement] = []
    for c in children(el) {
        if pred(c) { out.append(c) }
        if role(c) != "AXWebArea" { out += find(c, depth: depth + 1, pred) }  // jamais dans le contenu web
    }
    return out
}
func texte(_ el: AXUIElement, depth: Int = 0) -> String {
    var s = [attr(el, kAXTitleAttribute), attr(el, kAXDescriptionAttribute), attr(el, kAXValueAttribute)].compactMap { $0 as? String }.joined(separator: " ")
    if depth < 4 { for c in children(el) { s += " " + texte(c, depth: depth + 1) } }
    return s
}

// 1. Fenêtre de test dédiée, au premier plan
let avant = Set((asrun(#"tell application "Safari" to get id of every window"#).map { d in (1...max(1, d.numberOfItems)).compactMap { d.atIndex($0)?.int32Value } }) ?? [])
asrun(#"tell application "Safari" to make new document with properties {URL:"about:blank"}"#)
Thread.sleep(forTimeInterval: 1)
let apres = Set((asrun(#"tell application "Safari" to get id of every window"#).map { d in (1...max(1, d.numberOfItems)).compactMap { d.atIndex($0)?.int32Value } }) ?? [])
guard apres.subtracting(avant).count == 1, let W = apres.subtracting(avant).first else { print("✗ fenêtre de test non isolée"); exit(1) }
func fermer() { asrun("tell application \"Safari\" to close window id \(W)") }
asrun("tell application \"Safari\" to activate\ntell application \"Safari\" to set index of window id \(W) to 1")
Thread.sleep(forTimeInterval: 0.5)
guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first?.processIdentifier else { fermer(); exit(1) }
let app = AXUIElementCreateApplication(pid)
guard let fenetre = attr(app, kAXFocusedWindowAttribute) as! AXUIElement? else { print("✗ pas de fenêtre AX"); fermer(); exit(1) }
guard (attr(fenetre, kAXTitleAttribute) as? String) != nil else { fermer(); exit(1) }

// 2. Barre latérale liste de lecture
asrun(#"tell application "System Events" to tell process "Safari" to click menu item "Afficher la barre latérale de la liste de lecture" of menu 1 of menu bar item "Présentation" of menu bar 1"#)
Thread.sleep(forTimeInterval: 1)

// 3. Champ de recherche de la barre latérale (repéré par son rôle uniquement)
let champs = find(fenetre) { role($0) == "AXTextField" && subrole($0) == "AXSearchField" }
print("champs de recherche trouvés : \(champs.count)")
guard let champ = champs.first(where: { (attr($0, kAXDescriptionAttribute) as? String ?? "").localizedCaseInsensitiveContains("lecture") }) ?? (champs.count == 1 ? champs.first : nil) else {
    print("✗ champ de recherche de la liste de lecture introuvable : abandon"); fermer(); exit(1)
}
AXUIElementSetAttributeValue(champ, kAXFocusedAttribute as CFString, kCFBooleanTrue)
AXUIElementSetAttributeValue(champ, kAXValueAttribute as CFString, recherche as CFString)
AXUIElementPerformAction(champ, "AXConfirm" as CFString)
Thread.sleep(forTimeInterval: 1.5)

// 4. Lignes visibles après filtrage
let lignes = find(fenetre) { role($0) == "AXRow" || role($0) == "AXCell" && subrole($0) != "AXOutlineRow" }
let rows = lignes.filter { role($0) == "AXRow" }
let cibles = (rows.isEmpty ? lignes : rows).filter { texte($0).contains(attendu) }
print("lignes après filtre : \((rows.isEmpty ? lignes : rows).count), correspondant à l'élément de test : \(cibles.count)")
print("longueurs de texte des autres lignes : \((rows.isEmpty ? lignes : rows).filter { !texte($0).contains(attendu) }.map { texte($0).trimmingCharacters(in: .whitespaces).count })")
guard cibles.count == 1, let ligne = cibles.first else {
    print("✗ ambigu : abandon sans rien supprimer")
    AXUIElementSetAttributeValue(champ, kAXValueAttribute as CFString, "" as CFString); fermer(); exit(1)
}

// 5. Menu contextuel → Supprimer l'élément
// Clic droit réel au centre de la ligne vérifiée (AXShowMenu n'est pas pris en charge ici)
var pos = CGPoint.zero, taille = CGSize.zero
if let v = attr(ligne, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &pos) }
if let v = attr(ligne, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &taille) }
let centre = CGPoint(x: pos.x + min(taille.width / 2, 60), y: pos.y + taille.height / 2)
print("ligne en \(pos) taille \(taille)")
for t in [CGEventType.rightMouseDown, .rightMouseUp] { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: centre, mouseButton: .right)?.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.1) }
Thread.sleep(forTimeInterval: 0.8)
print("enfants de l'app : \(children(app).map(role))")
Thread.sleep(forTimeInterval: 0.7)
// Uniquement le menu contextuel (jamais la barre des menus, où « Supprimer le groupe d'onglets » existe)
let contextuels = children(app).filter { role($0) == "AXMenu" } + find(fenetre) { role($0) == "AXMenu" }
let menus = contextuels.flatMap { m in find(m) { role($0) == "AXMenuItem" && ((attr($0, kAXTitleAttribute) as? String) ?? "").contains("élément") && ((attr($0, kAXTitleAttribute) as? String) ?? "").hasPrefix("Supprimer") } }
print("menus contextuels : \(contextuels.count), entrées : \(contextuels.flatMap { m in find(m) { role($0) == "AXMenuItem" }.map { attr($0, kAXTitleAttribute) as? String ?? "" } })")
print("entrées « Supprimer l… » : \(menus.map { attr($0, kAXTitleAttribute) as? String ?? "" })")
if menus.count == 1 { AXUIElementPerformAction(menus[0], kAXPressAction as CFString); print("✓ suppression demandée") }
else { print("✗ entrée de menu ambiguë : abandon"); asrun(#"tell application "System Events" to key code 53"#) }
Thread.sleep(forTimeInterval: 1)

// 6. Remise en état : recherche vidée, barre latérale masquée, fenêtre de test fermée
AXUIElementSetAttributeValue(champ, kAXValueAttribute as CFString, "" as CFString)
asrun(#"tell application "System Events" to tell process "Safari" to click menu item "Masquer la barre latérale de la liste de lecture" of menu 1 of menu bar item "Présentation" of menu bar 1"#)
fermer()
asrun(#"tell application "Safari" to sync all plist to disk"#)
Thread.sleep(forTimeInterval: 3)

// 7. Vérification par une autre voie : Bookmarks.plist (lecture seule), par UUID
let home = FileManager.default.homeDirectoryForCurrentUser.path
let d = FileManager.default.contents(atPath: "\(home)/Library/Safari/Bookmarks.plist") ?? Data()
let brut = String(decoding: (try? PropertyListSerialization.data(fromPropertyList: PropertyListSerialization.propertyList(from: d, format: nil), format: .xml, options: 0)) ?? Data(), as: UTF8.self)
print(brut.contains(uuid) ? "✗ l'élément \(uuid) est encore dans Bookmarks.plist" : "✓ élément \(uuid) absent de Bookmarks.plist")
