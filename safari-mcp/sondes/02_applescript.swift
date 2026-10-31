// Sonde 02 : voie AppleScript (NSAppleScript dans le binaire) sur une fenêtre de test.
// Ne lit que les identifiants des fenêtres existantes (pour isoler la sienne), jamais leur contenu.
// Ouvre une fenêtre sur des pages locales [mcp-test], la manipule, puis la ferme.
import Foundation

let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let p1 = dir.appendingPathComponent("mcp-test-1.html").absoluteString
let p2 = dir.appendingPathComponent("mcp-test-2.html").absoluteString

@discardableResult
func run(_ label: String, _ src: String) -> NSAppleEventDescriptor? {
    let t0 = Date()
    var err: NSDictionary?
    let r = NSAppleScript(source: src)!.executeAndReturnError(&err)
    let ms = Int(Date().timeIntervalSince(t0) * 1000)
    if let err {
        print("✗ \(label) (\(ms) ms) : \(err[NSAppleScript.errorNumber] ?? "") \(err[NSAppleScript.errorMessage] ?? "")")
        return nil
    }
    print("✓ \(label) (\(ms) ms) : \(r.stringValue ?? describe(r))")
    return r
}
func describe(_ d: NSAppleEventDescriptor) -> String {
    guard d.numberOfItems > 0 else { return "\(d)" }
    return "[" + (1...d.numberOfItems).map { d.atIndex($0).map { $0.stringValue ?? describe($0) } ?? "?" }.joined(separator: " | ") + "]"
}

let avant = run("ids des fenêtres existantes (ids seulement)", #"tell application "Safari" to get id of every window"#)
let ids = Set((avant.map { d in d.numberOfItems > 0 ? (1...d.numberOfItems).compactMap { d.atIndex($0)?.int32Value } : [] }) ?? [])
print("   \(ids.count) fenêtre(s) déjà ouverte(s)")

// Nouvelle fenêtre de test, repérée par différence d'ids
run("nouvelle fenêtre de test", """
tell application "Safari" to make new document with properties {URL:"\(p1)"}
""")
Thread.sleep(forTimeInterval: 1.0)
let apres = run("ids après", #"tell application "Safari" to get id of every window"#)!
let nouveaux = (1...apres.numberOfItems).compactMap { apres.atIndex($0)?.int32Value }.filter { !ids.contains($0) }
guard nouveaux.count == 1, let W = nouveaux.first else { print("✗ fenêtre de test introuvable : \(nouveaux)"); exit(1) }
print("   fenêtre de test id \(W)")
let w = "window id \(W)"

defer {}
run("nouvel onglet dans la fenêtre de test", """
tell application "Safari" to tell \(w) to set t to make new tab at end of tabs with properties {URL:"\(p2)"}
""")
Thread.sleep(forTimeInterval: 1.0)

// Lecture en lot : un seul script pour tous les onglets de la fenêtre de test
run("lecture en lot (index, nom, URL, visible)", """
tell application "Safari" to tell \(w)
  set out to {}
  repeat with t in tabs
    set end of out to ((index of t) as text) & tab & (name of t) & tab & (URL of t) & tab & ((visible of t) as text)
  end repeat
  set AppleScript's text item delimiters to linefeed
  return out as text
end tell
""")
run("onglet courant", "tell application \"Safari\" to return index of current tab of \(w)")
run("propriétés de la fenêtre (nom, bounds, miniaturisée)", """
tell application "Safari" to tell \(w) to return (name as text) & " / " & ((bounds) as text) & " / " & (miniaturized as text)
""")
run("texte de l'onglet 1 (contient le marqueur ?)", """
tell application "Safari" to return (text of tab 1 of \(w)) contains "marqueur-mcp-test-1"
""")
run("source de l'onglet 1 (longueur)", "tell application \"Safari\" to return length of (source of tab 1 of \(w))")
run("do JavaScript (titre)", "tell application \"Safari\" to do JavaScript \"document.title\" in tab 1 of \(w)")
run("do JavaScript (DOM, renvoie JSON)", """
tell application "Safari" to do JavaScript "JSON.stringify([...document.links].map(a=>({t:a.textContent,h:a.getAttribute('href')})))" in tab 1 of \(w)
""")
run("activer l'onglet 1", "tell application \"Safari\" to tell \(w) to set current tab to tab 1")
run("naviguer : URL de l'onglet 1 → page 2", "tell application \"Safari\" to set URL of tab 1 of \(w) to \"\(p2)\"")
Thread.sleep(forTimeInterval: 1.0)
run("URL relue", "tell application \"Safari\" to return URL of tab 1 of \(w)")
run("recharger (set URL à elle-même)", "tell application \"Safari\" to tell tab 1 of \(w) to set URL to (URL as text)")
run("redimensionner la fenêtre", "tell application \"Safari\" to set bounds of \(w) to {100, 100, 900, 700}")
run("fermer l'onglet 2", "tell application \"Safari\" to close tab 2 of \(w)")
run("nombre d'onglets restants", "tell application \"Safari\" to return count of tabs of \(w)")
run("fermer la fenêtre de test", "tell application \"Safari\" to close \(w)")
Thread.sleep(forTimeInterval: 0.5)
run("fenêtre de test disparue ?", "tell application \"Safari\" to return (id of every window) contains \(W)")
