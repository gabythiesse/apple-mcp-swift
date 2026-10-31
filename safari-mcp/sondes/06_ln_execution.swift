// Sonde 06 : exécuter une App Intent de Safari via LinkServices (privé), hors Raccourcis.
// Action de test : CreateNewWindow(isPrivate: true). La fenêtre créée est repérée par différence
// d'identifiants (AppleScript, ids seulement) puis fermée.
import Foundation
import ObjectiveC

dlopen("/System/Library/PrivateFrameworks/LinkServices.framework/LinkServices", RTLD_NOW)
dlopen("/System/Library/PrivateFrameworks/LinkMetadata.framework/LinkMetadata", RTLD_NOW)

typealias F0 = @convention(c) (AnyObject, Selector) -> AnyObject?
typealias F2 = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?) -> AnyObject?
typealias F3 = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, AnyObject?) -> AnyObject?
typealias F2E = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject?
typealias F5E = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, AnyObject?, AnyObject?, AnyObject?, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject?
typealias Fv = @convention(c) (AnyObject, Selector) -> Void
func imp<T>(_ o: AnyObject, _ s: String, _ t: T.Type) -> (T, Selector) {
    let sel = NSSelectorFromString(s)
    guard let m = class_getMethodImplementation(object_getClass(o), sel), o.responds(to: sel) else { print("✗ \(type(of: o)) ne répond pas à \(s)"); exit(1) }
    return (unsafeBitCast(m, to: t), sel)
}
func alloc(_ c: String) -> AnyObject { let k: AnyObject = NSClassFromString(c)!; let (f, s) = imp(k, "alloc", F0.self); return f(k, s)! }

func ids() -> Set<Int32> {
    var e: NSDictionary?
    let d = NSAppleScript(source: #"tell application "Safari" to get id of every window"#)!.executeAndReturnError(&e)
    return Set(d.numberOfItems > 0 ? (1...d.numberOfItems).compactMap { d.atIndex($0)?.int32Value } : [d.int32Value])
}

// Délégué : on accepte tout ce qui est demandé côté exécution, on logue la fin
final class Delegue: NSObject {
    var fini = false
    @objc(executor:didFinishWithResult:error:) func fin(_ e: AnyObject?, _ r: AnyObject?, _ err: NSError?) {
        print("   didFinish : résultat \(r.map { "\(type(of: $0))" } ?? "nil"), erreur \(err.map { "\($0.domain) \($0.code) \($0.localizedDescription)" } ?? "aucune")"); fini = true
    }
    @objc(executor:didPerformActionWithResult:error:) func perf(_ e: AnyObject?, _ r: AnyObject?, _ err: NSError?) {
        print("   didPerform : erreur \(err.map { "\($0.domain) \($0.code) \($0.localizedDescription)" } ?? "aucune")")
    }
    @objc(executor:didCompleteExecutionWithResult:error:) func comp(_ e: AnyObject?, _ r: AnyObject?, _ err: NSError?) {
        print("   didComplete : erreur \(err.map { "\($0.domain) \($0.code) \($0.localizedDescription)" } ?? "aucune")"); fini = true
    }
    @objc(executor:needsValueWithRequest:) func v(_ e: AnyObject?, _ r: AnyObject?) { print("   needsValue \(String(describing: r))") }
    @objc(executor:needsConfirmationWithRequest:) func c(_ e: AnyObject?, _ r: AnyObject?) { print("   needsConfirmation \(String(describing: r))") }
    @objc(executor:needsDisambiguationWithRequest:) func d(_ e: AnyObject?, _ r: AnyObject?) { print("   needsDisambiguation") }
}
if let p = objc_getProtocol("LNActionExecutorDelegate") { class_addProtocol(Delegue.self, p) }

// 1. Métadonnées de l'action
let provider: AnyObject = { let a = alloc("LNMetadataProvider"); let (f, s) = imp(a, "init", F0.self); return f(a, s)! }()
var err: NSError?
let (fm, sm) = imp(provider, "actionForBundleIdentifier:andActionIdentifier:error:", F2E.self)
guard let meta = fm(provider, sm, "com.apple.Safari" as NSString, "CreateNewWindow" as NSString, &err) else { print("✗ métadonnées : \(String(describing: err))"); exit(1) }
print("✓ métadonnées CreateNewWindow")

// 2. Action avec isPrivate = true
let vt: AnyObject = { let k: AnyObject = NSClassFromString("LNPrimitiveValueType")!; let (f, s) = imp(k, "boolValueType", F0.self); return f(k, s)! }()
let val: AnyObject = { let a = alloc("LNValue"); let (f, s) = imp(a, "initWithValue:valueType:", F2.self); return f(a, s, NSNumber(value: true), vt)! }()
let prop: AnyObject = { let a = alloc("LNProperty"); let (f, s) = imp(a, "initWithIdentifier:value:", F2.self); return f(a, s, "isPrivate" as NSString, val)! }()
let action: AnyObject = { let a = alloc("LNAction"); let (f, s) = imp(a, "initWithMetadata:bundleIdentifier:parameters:", F3.self); return f(a, s, meta, "com.apple.Safari" as NSString, [prop] as NSArray)! }()
print("✓ action construite")

// 3. Connexion à Safari
let mgrK: AnyObject = NSClassFromString("LNConnectionManager")!
let mgr: AnyObject = { let (f, s) = imp(mgrK, "sharedInstance", F0.self); return f(mgrK, s)! }()
let (fc, sc) = imp(mgr, "connectionForEffectiveBundleIdentifier:appBundleIdentifier:processInstanceIdentifier:mangledTypeName:userIdentity:error:", F5E.self)
typealias FIntO = @convention(c) (AnyObject, Selector, Int, AnyObject?) -> AnyObject?
let typeEBI = Int(CommandLine.arguments.dropFirst().first ?? "0") ?? 0
let ebi: AnyObject = { let a = alloc("LNEffectiveBundleIdentifier"); let (f, s) = imp(a, "initWithType:bundleIdentifier:", FIntO.self); return f(a, s, typeEBI, "com.apple.Safari" as NSString)! }()
guard let conn = fc(mgr, sc, ebi, "com.apple.Safari" as NSString, nil, nil, nil, &err) else { print("✗ connexion : \(String(describing: err))"); exit(1) }
print("✓ connexion : \(type(of: conn))")

// 4. Exécution
let avant = ids()
let opts: AnyObject = { let a = alloc("LNActionExecutorOptions"); let (f, s) = imp(a, "init", F0.self); return f(a, s)! }()
let del = Delegue()
let (fe, se) = imp(conn, "executorForAction:options:delegate:", F3.self)
guard let ex = fe(conn, se, action, opts, del) else { print("✗ exécuteur nul"); exit(1) }
let t0 = Date()
let (fp, sp) = imp(ex, "perform", Fv.self)
fp(ex, sp)
while !del.fini && Date().timeIntervalSince(t0) < 15 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
print("   durée \(Int(Date().timeIntervalSince(t0) * 1000)) ms, fini=\(del.fini)")

// 5. Vérification et nettoyage par identifiant
Thread.sleep(forTimeInterval: 1)
let nouvelles = ids().subtracting(avant)
print(nouvelles.isEmpty ? "✗ aucune nouvelle fenêtre" : "✓ nouvelle(s) fenêtre(s) : \(nouvelles.sorted())")
for w in nouvelles where nouvelles.count == 1 {  // plus d'une : ambigu, on ne ferme rien
    var e: NSDictionary?
    NSAppleScript(source: "tell application \"Safari\" to close window id \(w)")!.executeAndReturnError(&e)
    print(e == nil ? "✓ fenêtre \(w) fermée" : "✗ fermeture \(w) : \(e!)")
}
print("restantes nouvelles : \(ids().subtracting(avant).count)")
