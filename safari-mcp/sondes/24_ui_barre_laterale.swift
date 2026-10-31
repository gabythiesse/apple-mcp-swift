// Sonde 24 : structure AX de la barre latérale (groupes d'onglets, liste de lecture) dans une fenêtre de test.
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
print("titre fenêtre AX:", attr(f, kAXTitleAttribute) ?? "nil")
let menu = asrun("tell application \"System Events\" to tell process \"Safari\" to return name of every menu item of menu 1 of menu bar item \"Présentation\" of menu bar 1")!
print("menu Présentation (barre latérale):", (1...menu.numberOfItems).compactMap { menu.atIndex($0)?.stringValue }.filter { $0.contains("latérale") })
asrun("tell application \"System Events\" to tell process \"Safari\" to click menu item \"Afficher la barre latérale\" of menu 1 of menu bar item \"Présentation\" of menu bar 1"); Thread.sleep(forTimeInterval: 1)
func arbre(_ el: AXUIElement, _ d: Int) {
  if d > 9 || role(el) == "AXWebArea" { return }
  let r = role(el); let desc = [(attr(el, kAXDescriptionAttribute) as? String), (attr(el, kAXIdentifierAttribute) as? String), (r == "AXButton" || r == "AXRadioButton" ? attr(el, kAXTitleAttribute) as? String : nil)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "|")
  if r != "AXRow" && r != "AXCell" && r != "AXStaticText" && r != "AXImage" { print(String(repeating: " ", count: d) + r + (desc.isEmpty ? "" : " [\(desc)]")) }
  if r == "AXRow" { return }
  for c in children(el) { arbre(c, d + 1) } }
if CommandLine.arguments.count > 2 { arbre(f, 0) }
let outl = find(f) { ["AXOutline", "AXTable", "AXList"].contains(role($0)) }
print("conteneurs:", outl.map { "\(role($0))[\((attr($0, kAXDescriptionAttribute) as? String) ?? (attr($0, kAXIdentifierAttribute) as? String) ?? "")]" })
let rows = find(f) { role($0) == "AXRow" }
print("lignes:", rows.count)
for (i, r) in rows.enumerated() { let t = texte(r); print("  \(i): " + (t.contains(cible) ? t : "(\(t.count) car.)")) }
print("lignes LL contenant example.com:", rows.filter { texte($0).contains("example.com") }.count, "| Example Domain:", rows.filter { texte($0).contains("Example Domain") }.count)
if let back = find(f, 0, { (attr($0, kAXIdentifierAttribute) as? String) == "SidebarBackButton" }).first {
  AXUIElementPerformAction(back, kAXPressAction as CFString); Thread.sleep(forTimeInterval: 1)
  print("après retour, conteneurs:", find(f) { ["AXOutline", "AXTable"].contains(role($0)) }.map { "\(role($0))[\((attr($0, kAXDescriptionAttribute) as? String) ?? (attr($0, kAXIdentifierAttribute) as? String) ?? "")]" })
  let r2 = find(f) { role($0) == "AXRow" }
  print("lignes:", r2.count, "contenant cible:", r2.filter { texte($0).contains(cible) }.map { texte($0) })
}
asrun("tell application \"System Events\" to tell process \"Safari\" to click menu item \"Masquer la barre latérale\" of menu 1 of menu bar item \"Présentation\" of menu bar 1")
asrun("tell application \"Safari\" to close window id \(W)")
print("fenêtres identiques:", ids() == avant)
