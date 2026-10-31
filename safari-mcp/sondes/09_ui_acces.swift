// Sonde 09 : Accessibilité disponible ? Lecture des seuls titres de menus de Safari (interface, pas de données)
import Foundation
import ApplicationServices
print("AXIsProcessTrusted : \(AXIsProcessTrusted())")
var e: NSDictionary?
let t0 = Date()
let r = NSAppleScript(source: """
tell application "System Events" to tell process "Safari"
  set out to {}
  repeat with m in {"Fichier", "Affichage", "Historique", "Fenêtre"}
    try
      set end of out to m & " : " & (count of menu items of menu 1 of menu bar item m of menu bar 1)
    end try
  end repeat
  set AppleScript's text item delimiters to " / "
  return out as text
end tell
""")!.executeAndReturnError(&e)
print(e.map { "✗ System Events : \($0[NSAppleScript.errorNumber] ?? "") \($0[NSAppleScript.errorMessage] ?? "")" } ?? "✓ System Events (\(Int(Date().timeIntervalSince(t0)*1000)) ms) : \(r.stringValue ?? "")")
let r2 = NSAppleScript(source: """
tell application "System Events" to tell process "Safari" to return name of every menu item of menu 1 of menu bar item "Fichier" of menu bar 1
""")!.executeAndReturnError(&e)
if e == nil { print("   Fichier : \((1...max(1, r2.numberOfItems)).compactMap { r2.atIndex($0)?.stringValue }.joined(separator: " | "))") }
