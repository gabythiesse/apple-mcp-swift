// Sonde 10 : un groupe de test existe-t-il encore ? (par identifiant) + API d'énumération des groupes
import Foundation
setvbuf(stdout, nil, _IONBF, 0)
dlopen("/System/Library/PrivateFrameworks/ReminderKit.framework/Versions/A/ReminderKit", RTLD_NOW)
let st = try new("REMStore")
for id in CommandLine.arguments.dropFirst() {
  let oid = try call(try cls("REMList"), "objectIDWithUUID:", UUID(uuidString: id)! as NSUUID)!
  let l = try? callE(st, "fetchListWithObjectID:error:", oid)
  print(id, l == nil ? "absent" : "PRÉSENT: \(try call(l!, "name") ?? "" as NSString)")
}
