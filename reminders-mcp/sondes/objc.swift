// Petits helpers pour appeler le runtime ObjC (frameworks privés)
import Foundation
import ObjectiveC
typealias F0 = @convention(c) (AnyObject, Selector) -> AnyObject?
typealias F1 = @convention(c) (AnyObject, Selector, AnyObject?) -> AnyObject?
typealias F2 = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?) -> AnyObject?
typealias F1E = @convention(c) (AnyObject, Selector, AnyObject?, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject?
typealias FB = @convention(c) (AnyObject, Selector, Bool) -> AnyObject?
typealias FvB = @convention(c) (AnyObject, Selector, Bool) -> Void
typealias FBool0 = @convention(c) (AnyObject, Selector) -> Bool
typealias FInt0 = @convention(c) (AnyObject, Selector) -> Int
typealias FE = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
typealias FIntO = @convention(c) (AnyObject, Selector, Int, AnyObject?) -> AnyObject?
struct ObjCError: Error, CustomStringConvertible { let description: String }
// Résout le destinataire réel (REMReminder & co. transfèrent leurs propriétés à leur objet storage)
func receiver(_ o: AnyObject, _ sel: Selector) -> AnyObject? {
  if class_respondsToSelector(object_getClass(o), sel) { return o }
  if let n = o as? NSObject, let t = n.forwardingTarget(for: sel) as AnyObject?, class_respondsToSelector(object_getClass(t), sel) { return t }
  return nil
}
func imp<T>(_ o: AnyObject, _ s: String, _ t: T.Type) throws -> (T, Selector, AnyObject) {
  let sel = NSSelectorFromString(s)
  guard let r = receiver(o, sel) else { throw ObjCError(description: "\(type(of: o)) ne répond pas à \(s)") }
  return (unsafeBitCast(class_getMethodImplementation(object_getClass(r), sel)!, to: t), sel, r)
}
func call(_ o: AnyObject, _ s: String) throws -> AnyObject? { let (f, sel, r) = try imp(o, s, F0.self); return f(r, sel) }
func call(_ o: AnyObject, _ s: String, _ a: AnyObject?) throws -> AnyObject? { let (f, sel, r) = try imp(o, s, F1.self); return f(r, sel, a) }
func call(_ o: AnyObject, _ s: String, _ a: AnyObject?, _ b: AnyObject?) throws -> AnyObject? { let (f, sel, r) = try imp(o, s, F2.self); return f(r, sel, a, b) }
func callE(_ o: AnyObject, _ s: String, _ a: AnyObject?) throws -> AnyObject? {
  let (f, sel, r) = try imp(o, s, F1E.self); var e: NSError?; let x = f(r, sel, a, &e); if let e { throw e }; return x
}
func bool(_ o: AnyObject, _ s: String) throws -> Bool { let (f, sel, r) = try imp(o, s, FBool0.self); return f(r, sel) }
func setBool(_ o: AnyObject, _ s: String, _ v: Bool) throws { let (f, sel, r) = try imp(o, s, FvB.self); f(r, sel, v) }
func saveSync(_ sr: AnyObject) throws { let (f, sel, r) = try imp(sr, "saveSynchronouslyWithError:", FE.self); var e: NSError?; if !f(r, sel, &e) { throw e ?? ObjCError(description: "save KO") } }
func cls(_ n: String) throws -> AnyObject { guard let c = NSClassFromString(n) else { throw ObjCError(description: "classe \(n) absente") }; return c as AnyObject }
func new(_ n: String, _ initSel: String, _ a: AnyObject?) throws -> AnyObject { try call(try call(try cls(n), "alloc")!, initSel, a)! }
func new(_ n: String) throws -> AnyObject { try call(try call(try cls(n), "alloc")!, "init")! }
