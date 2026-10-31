// Sonde 17 : source / texte / HTML via JS sur une fenêtre de test about:blank (aucune entrée d'historique)
import Foundation
func run(_ l: String, _ s: String) -> NSAppleEventDescriptor? {
    var e: NSDictionary?; let t0 = Date(); let r = NSAppleScript(source: s)!.executeAndReturnError(&e)
    let ms = Int(Date().timeIntervalSince(t0) * 1000)
    if let e { print("✗ \(l) (\(ms) ms) : \(e[NSAppleScript.errorMessage] ?? "")"); return nil }
    print("✓ \(l) (\(ms) ms) : \((r.stringValue ?? "").prefix(120))"); return r
}
func ids() -> Set<Int32> { var e: NSDictionary?; let d = NSAppleScript(source: #"tell application "Safari" to get id of every window whose visible is true"#)!.executeAndReturnError(&e); return Set((1...max(1, d.numberOfItems)).compactMap { d.atIndex($0)?.int32Value }) }
let avant = ids()
_ = run("fenêtre de test", #"tell application "Safari" to make new document with properties {URL:"about:blank"}"#)
Thread.sleep(forTimeInterval: 1)
guard ids().subtracting(avant).count == 1, let W = ids().subtracting(avant).first else { print("✗ non isolée"); exit(1) }
let t = "current tab of window id \(W)"
_ = run("injection JS", "tell application \"Safari\" to do JavaScript \"document.title='[mcp-test] source'; document.body.innerHTML='<h1>[mcp-test]</h1><p>marqueur-source</p><table><tr><td>a</td><td>1</td></tr></table>'; 'ok'\" in \(t)")
_ = run("texte (AppleScript)", "tell application \"Safari\" to return text of \(t)")
_ = run("source (AppleScript), longueur", "tell application \"Safari\" to set s to source of \(t)\nreturn (length of s) as text")
_ = run("HTML courant (JS outerHTML)", "tell application \"Safari\" to do JavaScript \"document.documentElement.outerHTML\" in \(t)")
_ = run("JS : résultat objet → JSON", "tell application \"Safari\" to do JavaScript \"JSON.stringify({titre: document.title, n: document.querySelectorAll('td').length})\" in \(t)")
_ = run("JS : erreur levée", "tell application \"Safari\" to do JavaScript \"throw new Error('x')\" in \(t)")
_ = run("JS : history.back sans historique", "tell application \"Safari\" to do JavaScript \"history.back(); 'ok'\" in \(t)")
_ = run("fermer", "tell application \"Safari\" to close window id \(W)")
print("fenêtres visibles identiques : \(ids() == avant)")
