// Sonde 22 : signature de -[WBSHistory initWithDatabaseID:] et ivars de WBSHistoryController
import Foundation
import ObjectiveC
_ = dlopen("/System/Library/PrivateFrameworks/SafariShared.framework/SafariShared", RTLD_NOW)
for (c, s) in [("WBSHistory", "initWithDatabaseID:"), ("WBSHistoryController", "historyForProfileIdentifier:loadIfNeeded:"), ("WBSHistoryServiceStore", "initWithDatabaseID:itemCountLimit:historyAgeLimit:historyItemClass:")] {
  let m = class_getInstanceMethod(NSClassFromString(c)!, NSSelectorFromString(s))!
  print(c, s, String(cString: method_getTypeEncoding(m)!))
}
for c in ["WBSHistoryController", "WBSHistory", "WBSHistoryConnectionProxy"] {
  var n: UInt32 = 0
  let iv = class_copyIvarList(NSClassFromString(c)!, &n)!
  print(c, (0..<Int(n)).map { "\(String(cString: ivar_getName(iv[$0])!)):\(String(cString: ivar_getTypeEncoding(iv[$0])!))" })
}
