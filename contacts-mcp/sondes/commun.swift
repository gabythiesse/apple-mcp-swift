// Commun aux sondes : se relancer en « responsable » de soi-même (sinon TCC refuse Contacts sans invite,
// l'app parente n'ayant pas de clé NSContactsUsageDescription), puis obtenir l'accès Contacts.
import Foundation
import Contacts

typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
func relancerResponsable() {
  if ProcessInfo.processInfo.environment["MCP_DISCLAIMED"] != nil { return }
  guard let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "responsibility_spawnattrs_setdisclaim") else { return }
  var attr: posix_spawnattr_t?
  posix_spawnattr_init(&attr)
  _ = unsafeBitCast(sym, to: Disclaim.self)(&attr, 1)
  setenv("MCP_DISCLAIMED", "1", 1)
  var argv: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) } + [nil]
  var pid: pid_t = 0
  guard posix_spawn(&pid, CommandLine.arguments[0], nil, &attr, &argv, environ) == 0 else { return }
  var st: Int32 = 0
  waitpid(pid, &st, 0)
  exit((st >> 8) & 0xff)
}
func acces() -> CNContactStore {
  relancerResponsable()
  setvbuf(stdout, nil, _IOLBF, 0)
  let store = CNContactStore()
  let sem = DispatchSemaphore(value: 0)
  var ok = false
  store.requestAccess(for: .contacts) { g, _ in ok = g; sem.signal() }
  sem.wait()
  guard ok else { print("ACCÈS REFUSÉ (statut \(CNContactStore.authorizationStatus(for: .contacts).rawValue))"); exit(2) }
  return store
}
func check(_ ok: Bool, _ label: String) { print((ok ? "  ✓ " : "  ✗ ") + label) }
