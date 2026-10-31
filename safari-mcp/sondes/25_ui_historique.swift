// Sonde 25 : structure AX de la vue Historique dans une fenêtre de test.
// N'affiche le texte que des lignes contenant l'argument 1 ; sinon seulement leur rôle et la longueur du texte.
import Foundation
import ApplicationServices
import AppKit
let cible = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Sans titre"
@discardableResult func asrun(_ src: String) -> NSAppleEventDescriptor? {
  var e: NSDictionary?; let r = NSAppleScript(source: src)!.executeAndReturnError(&e)
  if let e { print("✗ \(e[NSAppleScript.errorMessage] ?? "")") }; return r }
func attr(_ el: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(el, a as CFString, &v); return v }
func children(_ el: AXUIElement) -> [AXUIElement] { attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func role(_ el: AXUIElement) -> String { attr(el, kAXRoleAttribute) as? String ?? "" }
func texte(_ el: AXUIElement, _ d: Int = 0) -> String {
  var s = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute].compactMap { attr(el, $0) as? String }.joined(separator: "·")
  if d < 4 { for c in children(el) { s += " " + texte(c, d + 1) } }; return s }
func find(_ el: AXUIElement, _ d: Int = 0, _ p: (AXUIElement) -> Bool) -> [AXUIElement] {
  if d > 16 { return [] }; var o: [AXUIElement] = []
  for c in children(el) { if p(c) { o.append(c) }; if role(c) != "AXWebArea" { o += find(c, d + 1, p) } }; return o }
func ids() -> Set<Int32> { let d = asrun("tell application \"Safari\" to get id of every window whose visible is true")!; return Set((1...max(1, d.numberOfItems)).compactMap { d.atIndex($0)?.int32Value }) }
let avant = ids()
asrun("tell application \"Safari\" to make new document with properties {URL:\"about:blank\"}"); Thread.sleep(forTimeInterval: 1)
guard ids().subtracting(avant).count == 1, let W = ids().subtracting(avant).first else { print("✗ fenêtre"); exit(1) }
asrun("tell application \"Safari\" to activate\ntell application \"Safari\" to set index of window id \(W) to 1"); Thread.sleep(forTimeInterval: 0.8)
let app = AXUIElementCreateApplication(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first!.processIdentifier)
let f = attr(app, kAXFocusedWindowAttribute) as! AXUIElement
let menu = asrun("tell application \"System Events\" to tell process \"Safari\" to return name of every menu item of menu 1 of menu bar item \"Historique\" of menu bar 1")!
print("menu Historique:", (1...menu.numberOfItems).compactMap { menu.atIndex($0)?.stringValue }.filter { $0.contains("historique") || $0.contains("Historique") })
asrun("tell application \"System Events\" to tell process \"Safari\" to click menu item \"Afficher tout l’historique\" of menu 1 of menu bar item \"Historique\" of menu bar 1"); Thread.sleep(forTimeInterval: 1.5)
func arbre(_ el: AXUIElement, _ d: Int) {
  if d > 12 || role(el) == "AXWebArea" { return }
  let r = role(el); let desc = [(attr(el, kAXDescriptionAttribute) as? String), (attr(el, kAXIdentifierAttribute) as? String), (r == "AXButton" || r == "AXRadioButton" ? attr(el, kAXTitleAttribute) as? String : nil)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "|")
  if !["AXRow", "AXCell", "AXStaticText", "AXImage", "AXGroup"].contains(r) || !desc.isEmpty { print(String(repeating: " ", count: d) + r + (desc.isEmpty ? "" : " [\(desc)]")) }
  if r == "AXRow" || r == "AXToolbar" || desc.hasPrefix("Barre des Favoris") { return }
  for c in children(el) { arbre(c, d + 1) } }
let fen = attr(app, kAXFocusedWindowAttribute) as! AXUIElement
let ed = asrun("tell application \"System Events\" to tell process \"Safari\" to return name of every menu item of menu 1 of menu bar item \"Édition\" of menu bar 1")!
print("Édition:", (1...ed.numberOfItems).compactMap { ed.atIndex($0)?.stringValue }.prefix(12))
if let o = find(fen, 0, { role($0) == "AXOutline" }).first {
  let top = (attr(o, kAXRowsAttribute) as? [AXUIElement] ?? []).filter { (attr($0, "AXDisclosureLevel") as? Int) == 0 }
  print("lignes de niveau 0 (jours):", top.prefix(4).map { texte($0) }, "… total", top.count)
  print("attributs ligne:", top.first.map { r -> [String] in var n: CFArray?; AXUIElementCopyAttributeNames(r, &n); return n as? [String] ?? [] } ?? [])
}
if let champ = find(fen, 0, { role($0) == "AXTextField" && ((attr($0, kAXSubroleAttribute) as? String) == "AXSearchField") }).first {
  AXUIElementSetAttributeValue(champ, kAXFocusedAttribute as CFString, kCFBooleanTrue)
  AXUIElementSetAttributeValue(champ, kAXValueAttribute as CFString, cible as CFString)
  AXUIElementPerformAction(champ, "AXConfirm" as CFString); Thread.sleep(forTimeInterval: 1.5)
  let rows = find(fen) { role($0) == "AXRow" }
  print("lignes après recherche:", rows.count)
  for r in rows { let t = texte(r); print("  " + (t.contains(cible) ? t : "(\(t.count) car.)")) }
  AXUIElementSetAttributeValue(champ, kAXValueAttribute as CFString, "" as CFString)
} else { print("✗ pas de champ de recherche") }
asrun("tell application \"Safari\" to close window id \(W)")
print("fenêtres identiques:", ids() == avant)
