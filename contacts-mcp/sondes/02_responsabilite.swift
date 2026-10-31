// Sonde 02 : l'accès Contacts est refusé sans invite quand le binaire hérite de la « responsabilité » TCC de l'app parente.
// On se relance avec posix_spawn + responsibility_spawnattrs_setdisclaim (libsystem, non public) :
// le binaire devient son propre responsable, et TCC lit SON Info.plist (NSContactsUsageDescription).
import Foundation
import Contacts

typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
if ProcessInfo.processInfo.environment["MCP_DISCLAIMED"] == nil {
  guard let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "responsibility_spawnattrs_setdisclaim") else { print("symbole absent"); exit(1) }
  let disclaim = unsafeBitCast(sym, to: Disclaim.self)
  var attr: posix_spawnattr_t?
  posix_spawnattr_init(&attr)
  print("disclaim:", disclaim(&attr, 1))
  setenv("MCP_DISCLAIMED", "1", 1)
  let path = CommandLine.arguments[0]
  var argv: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) } + [nil]
  var pid: pid_t = 0
  let r = posix_spawn(&pid, path, nil, &attr, &argv, environ)
  print("spawn:", r)
  var st: Int32 = 0
  waitpid(pid, &st, 0)
  exit(0)
}
let store = CNContactStore()
print("[enfant] statut avant:", CNContactStore.authorizationStatus(for: .contacts).rawValue)
let sem = DispatchSemaphore(value: 0)
var ok = false
store.requestAccess(for: .contacts) { g, e in ok = g; if let e { print("[enfant] erreur:", e.localizedDescription) }; sem.signal() }
sem.wait()
print("[enfant] accès:", ok, "| statut après:", CNContactStore.authorizationStatus(for: .contacts).rawValue)
// rebuild
