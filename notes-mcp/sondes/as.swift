// Helper commun aux sondes : exécute un AppleScript dans le process via NSAppleScript, avec chien de garde
import Foundation
func runAS(_ src: String, timeout: Double = 90) -> (String?, String?, Int) {
  let t0 = Date()
  let wd = DispatchWorkItem { FileHandle.standardError.write(Data("TIMEOUT \(timeout)s\n".utf8)); exit(3) }
  DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: wd)
  var err: NSDictionary?
  let r = NSAppleScript(source: src)!.executeAndReturnError(&err)
  wd.cancel()
  let ms = Int(Date().timeIntervalSince(t0) * 1000)
  if let err { return (nil, "\(err[NSAppleScript.errorNumber] ?? "?") \(err[NSAppleScript.errorMessage] ?? "")", ms) }
  return (r.stringValue ?? "\(r)", nil, ms)
}
func show(_ label: String, _ x: (String?, String?, Int)) {
  print("[\(label)] \(x.2) ms ->", x.1.map { "ERREUR " + $0 } ?? (x.0 ?? "nil"))
}
