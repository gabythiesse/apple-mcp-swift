// Exécuteur de sondes : lance un fichier AppleScript via NSAppleScript (la voie du futur binaire), affiche résultat, erreur et durée
import Foundation
let path = CommandLine.arguments[1]
var src = try! String(contentsOfFile: path, encoding: .utf8)
for (i, a) in CommandLine.arguments.dropFirst(2).enumerated() { src = src.replacingOccurrences(of: "$\(i+1)", with: a) }
let t0 = Date()
var err: NSDictionary?
let script = NSAppleScript(source: src)!
let res = script.executeAndReturnError(&err)
let ms = Int(Date().timeIntervalSince(t0) * 1000)
if let e = err { print("ERREUR \(e[NSAppleScript.errorNumber] ?? "?"): \(e[NSAppleScript.errorMessage] ?? "")") }
else { print(res.stringValue ?? "(\(res.numberOfItems) éléments / descripteur \(res.descriptorType))") }
print("durée: \(ms) ms")
