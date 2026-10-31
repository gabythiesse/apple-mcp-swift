// Sonde 27 : actions AX (standard et personnalisées) d'une ligne de liste de lecture de test et de son tableau ; focus du tableau.
import Foundation
import ApplicationServices
import AppKit
let cible = CommandLine.arguments[1]
@discardableResult func asrun(_ src: String) -> NSAppleEventDescriptor? { var e: NSDictionary?; let r = NSAppleScript(source: src)!.executeAndReturnError(&e); if let e { print("✗ \(e[NSAppleScript.errorMessage] ?? "")") }; return r }
func attr(_ el: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(el, a as CFString, &v); return v }
func children(_ el: AXUIElement) -> [AXUIElement] { attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func role(_ el: AXUIElement) -> String { attr(el, kAXRoleAttribute) as? String ?? "" }
func ident(_ el: AXUIElement) -> String { attr(el, kAXIdentifierAttribute) as? String ?? "" }
func find(_ el: AXUIElement, _ d: Int = 0, _ p: (AXUIElement) -> Bool) -> [AXUIElement] { if d > 16 { return [] }; var o: [AXUIElement] = []; for c in children(el) { if p(c) { o.append(c) }; if role(c) != "AXWebArea" { o += find(c, d + 1, p) } }; return o }
func actions(_ el: AXUIElement) -> String {
  var n: CFArray?; AXUIElementCopyActionNames(el, &n)
  return "\(role(el)) actions=\((n as? [String]) ?? []) custom=\((attr(el, "AXCustomActions") as? [AnyObject])?.map { "\($0)" } ?? [])" }
func ids() -> Set<Int32> { let d = asrun("tell application \"Safari\" to get id of every window whose visible is true")!; return Set((1...max(1, d.numberOfItems)).compactMap { d.atIndex($0)?.int32Value }) }
let avant = ids(); asrun("tell application \"Safari\" to make new document"); Thread.sleep(forTimeInterval: 1.5)
guard let W = ids().subtracting(avant).first else { exit(1) }
asrun("tell application \"Safari\" to activate\ntell application \"Safari\" to set index of window id \(W) to 1"); Thread.sleep(forTimeInterval: 0.8)
let app = AXUIElementCreateApplication(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first!.processIdentifier)
let f = attr(app, kAXFocusedWindowAttribute) as! AXUIElement
asrun("tell application \"System Events\" to tell process \"Safari\" to click menu item \"Afficher la barre latérale de la liste de lecture\" of menu 1 of menu bar item \"Présentation\" of menu bar 1"); Thread.sleep(forTimeInterval: 1)
let table = find(f) { ident($0) == "ReadingListSidebarScrollView" }.first.flatMap { find($0) { role($0) == "AXTable" }.first }!
print("tableau:", actions(table), "focus réglable:", { var b: DarwinBoolean = false; AXUIElementIsAttributeSettable(table, kAXFocusedAttribute as CFString, &b); return b.boolValue }())
for r in attr(table, kAXRowsAttribute) as? [AXUIElement] ?? [] where find(r, 0, { (attr($0, kAXDescriptionAttribute) as? String) == cible }).count > 0 {
  print("ligne:", actions(r))
  for c in find(r, 0, { _ in true }).prefix(4) { print("  ", actions(c)) }
}
let r = AXUIElementSetAttributeValue(table, kAXFocusedAttribute as CFString, kCFBooleanTrue)
print("set focus →", r.rawValue, "focused:", attr(table, kAXFocusedAttribute) ?? "nil")
asrun("tell application \"System Events\" to tell process \"Safari\" to click menu item \"Masquer la barre latérale de la liste de lecture\" of menu 1 of menu bar item \"Présentation\" of menu bar 1")
asrun("tell application \"Safari\" to close window id \(W)")
