// Sonde 28 : coût d'un « do JavaScript » selon la voie. Mesure, sur N répétitions (médiane, p95) :
//  1. NSAppleScript(source:) + exécution à chaque appel (ce que fait AS.run aujourd'hui) ;
//  2. la compilation seule ; 3. l'exécution seule d'un script compilé une fois ;
//  4. un handler compilé une fois, appelé par executeAppleEvent ; 5. un Apple Event brut (sfri/dojs) sans AppleScript ;
//  6. avec ou sans « with timeout » / « tell application » ; 7. « text of t » contre innerText en JS.
// Ne touche qu'à la fenêtre dont l'identifiant est passé en argument (fenêtre privée ouverte par tests/bench.py) :
// onglet 1 = about:blank, onglet 2 = page lourde.
// Usage : swiftc -O 28_apple_events_bruts.swift -o .bin/28 && .bin/28 <window_id> [répétitions]
import Foundation
import AppKit

guard CommandLine.arguments.count > 1, let W = Int32(CommandLine.arguments[1]) else { print("usage : 28 <window_id> [n]"); exit(64) }
let N = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 20 : 20

func fcc(_ s: String) -> FourCharCode { s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) } }

func mesure(_ label: String, _ n: Int = N, _ f: () throws -> String?) {
    var ms: [Double] = []
    var dernier: String? = nil
    for _ in 0..<n {
        let t0 = DispatchTime.now().uptimeNanoseconds
        do { dernier = try f() } catch { print("✗ \(label) : \(error)"); return }
        ms.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
    }
    ms.sort()
    let med = ms[ms.count / 2], p95 = ms[min(ms.count - 1, Int(Double(ms.count) * 0.95))]
    print(String(format: "%-58@ médiane %7.2f ms   p95 %7.2f ms   → %@", label as NSString, med, p95, String((dernier ?? "").prefix(40)) as NSString))
}

struct Err: Error, CustomStringConvertible { let description: String }

// MARK: AppleScript

func compiler(_ src: String) throws -> NSAppleScript {
    let s = NSAppleScript(source: src)!
    var e: NSDictionary?
    guard s.compileAndReturnError(&e) else { throw Err(description: "\(e ?? [:])") }
    return s
}
func executer(_ s: NSAppleScript) throws -> String? {
    var e: NSDictionary?
    let d = s.executeAndReturnError(&e)
    if let e { throw Err(description: "\(e[NSAppleScript.errorMessage] ?? e)") }
    return d.stringValue
}

let jsTitre = "document.title"
let corps = "tell application \"Safari\" to do JavaScript \"\(jsTitre)\" in tab 1 of window id \(W)"
let complet = "with timeout of 20 seconds\n" + corps + "\nend timeout"

print("== Voies AppleScript (onglet 1, about:blank, document.title)")
mesure("1. compile + exécute à chaque appel (AS.run actuel)") { try executer(NSAppleScript(source: complet)!) }
mesure("2. compilation seule") { _ = try compiler(complet); return nil }
let precompile = try! compiler(complet)
mesure("3. exécution seule, script compilé une fois") { try executer(precompile) }
let sansTimeout = try! compiler(corps)
mesure("3b. idem sans « with timeout »") { try executer(sansTimeout) }
let parId = try! compiler("tell application id \"com.apple.Safari\" to do JavaScript \"\(jsTitre)\" in tab 1 of window id \(W)")
mesure("3c. idem « tell application id »") { try executer(parId) }
let local = try! compiler("return \"x\"")
mesure("3d. script compilé sans Apple Event (plancher NSAppleScript)") { try executer(local) }

// Handler paramétré, compilé une fois, appelé par un événement « ascr/psbr »
let handler = try! compiler("""
on dojs(js, w, i)
  with timeout of 20 seconds
    tell application "Safari" to return do JavaScript js in tab i of window id w
  end timeout
end dojs
""")
func appelHandler(_ js: String, _ w: Int32, _ i: Int32) throws -> String? {
    let ev = NSAppleEventDescriptor.appleEvent(withEventClass: fcc("ascr"), eventID: fcc("psbr"),
                                               targetDescriptor: NSAppleEventDescriptor.currentProcess(),
                                               returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    ev.setParam(NSAppleEventDescriptor(string: "dojs"), forKeyword: fcc("snam"))
    let params = NSAppleEventDescriptor.list()
    params.insert(NSAppleEventDescriptor(string: js), at: 1)
    params.insert(NSAppleEventDescriptor(int32: w), at: 2)
    params.insert(NSAppleEventDescriptor(int32: i), at: 3)
    ev.setParam(params, forKeyword: keyDirectObject)
    var e: NSDictionary?
    let d = handler.executeAppleEvent(ev, error: &e)
    if let e { throw Err(description: "\(e)") }
    return d.stringValue
}
mesure("4. handler compilé une fois + executeAppleEvent") { try appelHandler(jsTitre, W, 1) }

// MARK: Apple Events bruts

func spec(_ want: String, _ from: NSAppleEventDescriptor, _ form: String, _ seld: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
    let r = NSAppleEventDescriptor.record().coerce(toDescriptorType: typeObjectSpecifier)!
    r.setDescriptor(NSAppleEventDescriptor(typeCode: fcc(want)), forKeyword: AEKeyword(keyAEDesiredClass))
    r.setDescriptor(from, forKeyword: AEKeyword(keyAEContainer))
    r.setDescriptor(NSAppleEventDescriptor(enumCode: fcc(form)), forKeyword: AEKeyword(keyAEKeyForm))
    r.setDescriptor(seld, forKeyword: AEKeyword(keyAEKeyData))
    return r
}
func onglet(_ w: Int32, _ i: Int32) -> NSAppleEventDescriptor {
    spec("bTab", spec("cwin", .null(), "ID  ", NSAppleEventDescriptor(int32: w)), "indx", NSAppleEventDescriptor(int32: i))
}
let safariCible = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Safari")
func envoyer(_ ev: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor? {
    let rep = try ev.sendEvent(options: [.waitForReply], timeout: 5)
    if let n = rep.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, n != 0 {
        throw Err(description: "AE \(n) \(rep.paramDescriptor(forKeyword: keyErrorString)?.stringValue ?? "")")
    }
    return rep.paramDescriptor(forKeyword: keyDirectObject)
}
func evenement(_ classe: String, _ id: String, _ cible: NSAppleEventDescriptor = safariCible) -> NSAppleEventDescriptor {
    NSAppleEventDescriptor.appleEvent(withEventClass: fcc(classe), eventID: fcc(id), targetDescriptor: cible,
                                      returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
}
func doJS(_ js: String, _ w: Int32, _ i: Int32, cible: NSAppleEventDescriptor = safariCible) throws -> String? {
    let ev = evenement("sfri", "dojs", cible)
    ev.setParam(NSAppleEventDescriptor(string: js), forKeyword: keyDirectObject)
    ev.setParam(onglet(w, i), forKeyword: fcc("dcnm"))
    return try envoyer(ev)?.stringValue
}
func propriete(_ code: String, _ de: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor? {
    let ev = evenement("core", "getd")
    ev.setParam(spec("prop", de, "prop", NSAppleEventDescriptor(typeCode: fcc(code))), forKeyword: keyDirectObject)
    return try envoyer(ev)
}

print("== Apple Events bruts")
mesure("5. AE brut sfri/dojs, cible réutilisée") { try doJS(jsTitre, W, 1) }
mesure("5b. AE brut, cible recréée à chaque appel") { try doJS(jsTitre, W, 1, cible: NSAppleEventDescriptor(bundleIdentifier: "com.apple.Safari")) }
mesure("5c. AE brut get name of tab 1") { try propriete("pnam", onglet(W, 1))?.stringValue }
let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first!.processIdentifier
mesure("5d. AE brut, cible par pid") { try doJS(jsTitre, W, 1, cible: NSAppleEventDescriptor(processIdentifier: pid)) }
var all = fcc("all ")
let tous = NSAppleEventDescriptor(descriptorType: DescType(typeAbsoluteOrdinal), bytes: &all, length: 4)!
let tousOnglets = spec("bTab", spec("cwin", .null(), "ID  ", NSAppleEventDescriptor(int32: W)), "indx", tous)
mesure("5e. AE brut get URL of every tab (fenêtre de test)") { try propriete("pURL", tousOnglets).map { "\($0.numberOfItems) URL" } }
let gros = "x".padding(toLength: 10_000, withPad: "x", startingAt: 0)
mesure("5f. AE brut dojs avec un script de 10 Ko") { try doJS("'\(gros)'.length", W, 1) }

print("== Page lourde (onglet 2)")
mesure("7a. AppleScript compilé : text of t") { try executer(try compiler("tell application \"Safari\" to return text of tab 2 of window id \(W)")).map { "\($0.count) car." } }
mesure("7b. AE brut get text (ctxt)") { try propriete("ctxt", onglet(W, 2))?.stringValue.map { "\($0.count) car." } }
mesure("7c. AE brut dojs document.body.innerText") { try doJS("document.body.innerText", W, 2).map { "\($0.count) car." } }
mesure("7d. AE brut dojs document.title") { try doJS(jsTitre, W, 2) }
mesure("7e. AE brut dojs querySelectorAll('*').length") { try doJS("document.querySelectorAll('*').length", W, 2) }
