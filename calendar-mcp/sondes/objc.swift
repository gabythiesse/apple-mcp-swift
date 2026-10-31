// Utilitaire : liste les méthodes (instance et classe) d'une classe ObjC, filtrées par mot-clé. Usage : swift objc.swift Classe [mot]
import Foundation
import EventKit
import ObjectiveC
let a = CommandLine.arguments
guard a.count > 1, let c: AnyClass = NSClassFromString(a[1]) else { print("classe absente"); exit(1) }
let mot = a.count > 2 ? a[2].lowercased() : ""
for (k, cl) in [("-", c), ("+", object_getClass(c)!)] {
  var n: UInt32 = 0; let ms = class_copyMethodList(cl, &n)!
  let l = (0..<Int(n)).map { NSStringFromSelector(method_getName(ms[$0])) }.filter { mot.isEmpty || $0.lowercased().contains(mot) }.sorted()
  print(k, l.joined(separator: " "))
}
