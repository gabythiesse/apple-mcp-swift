// Sonde 01 : liste les classes de ReminderKit (framework privé utilisé par Rappels)
import Foundation
import ObjectiveC

let path = "/System/Library/PrivateFrameworks/ReminderKit.framework/Versions/A/ReminderKit"
guard dlopen(path, RTLD_NOW) != nil else { print("dlopen KO:", String(cString: dlerror())); exit(1) }
guard let probe: AnyClass = NSClassFromString("REMStore") else { print("REMStore absent"); exit(1) }
let image = String(cString: class_getImageName(probe)!)
var count: UInt32 = 0
guard let names = objc_copyClassNamesForImage(image, &count) else { exit(1) }
var all: [String] = []
for i in 0..<Int(count) { all.append(String(cString: names[i])) }
all.sort()
let keys = CommandLine.arguments.dropFirst()
for n in all where keys.isEmpty || keys.contains(where: { n.localizedCaseInsensitiveContains($0) }) { print(n) }
print("total:", count)
