// Nettoyage des sondes : retrouve dans l'index (lecture seule) les messages de test (sujet « [mcp-test]… ») et les boîtes MCP-TEST-*,
// les supprime PAR IDENTIFIANT via AppleScript (2 passes : boîte → corbeille → définitif), puis vérifie qu'il ne reste rien.
import Foundation
import SQLite3
let path = NSHomeDirectory() + "/Library/Mail/V10/MailData/Envelope Index"
func query(_ sql: String) -> [[String]] {
  var db: OpaquePointer?; var st: OpaquePointer?; var out: [[String]] = []
  guard sqlite3_open_v2("file:" + path + "?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return [] }
  defer { sqlite3_close(db) }
  guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { print("ERR", String(cString: sqlite3_errmsg(db))); return [] }
  while sqlite3_step(st) == SQLITE_ROW { out.append((0..<sqlite3_column_count(st)).map { sqlite3_column_text(st, $0).map { String(cString: $0) } ?? "" }) }
  sqlite3_finalize(st); return out
}
/// URL de boîte de l'index → référence AppleScript
func ref(_ url: String) -> String {
  let u = url.replacingOccurrences(of: "\"", with: "")
  guard let r = u.range(of: "://") else { return "" }
  let rest = u[r.upperBound...]
  let parts = rest.split(separator: "/", maxSplits: 1).map(String.init)
  let chemin = (parts.count > 1 ? parts[1] : "").removingPercentEncoding?.precomposedStringWithCanonicalMapping ?? ""
  if u.hasPrefix("local://") { return "mailbox \"\(chemin)\"" }
  return "mailbox \"\(chemin)\" of (first account whose id is \"\(parts[0])\")"
}
func run(_ s: String) -> String {
  var err: NSDictionary?
  let r = NSAppleScript(source: "tell application \"Mail\"\n\(s)\nend tell")!.executeAndReturnError(&err)
  return err.map { "ERR \($0[NSAppleScript.errorNumber] ?? ""): \($0[NSAppleScript.errorMessage] ?? "")" } ?? (r.stringValue ?? "ok")
}
let testMsgs = """
SELECT m.ROWID, b.url FROM messages m JOIN mailboxes b ON b.ROWID=m.mailbox JOIN subjects s ON s.ROWID=m.subject
WHERE s.subject LIKE '[mcp-test]%'
"""
print("sorties ouvertes fermées:", run("set n to 0\nrepeat with o in (outgoing messages whose subject contains \"[mcp-test]\")\nclose o saving no\nset n to n + 1\nend repeat\nreturn n"))
for passe in 1...3 {
  let rows = query(testMsgs)
  print("passe \(passe): \(rows.count) message(s) de test")
  if rows.isEmpty { break }
  for r in rows {
    print("  supprime \(r[0]):", run("delete (first message of \(ref(r[1])) whose id is \(r[0]))"))
  }
  Thread.sleep(forTimeInterval: 3)
}
for ts in CommandLine.arguments.dropFirst() where ts.allSatisfy(\.isNumber) {
  print("boîte MCP-TEST-\(ts):", run("if exists mailbox \"MCP-TEST-\(ts)\" then\ndelete mailbox \"MCP-TEST-\(ts)\"\nend if\nreturn exists mailbox \"MCP-TEST-\(ts)\""))
  try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/Library/Containers/com.apple.mail/Data/tmp/mcp-test-\(ts)")
}
print("signatures de test restantes:", run("count of (signatures whose name starts with \"[mcp-test]\")"))
Thread.sleep(forTimeInterval: 3)
print("reste messages de test:", query(testMsgs).map { $0[0] + "@" + ($0[1].components(separatedBy: "/").last ?? "") })
print("reste boîtes MCP-TEST:", query("SELECT ROWID, url FROM mailboxes WHERE url LIKE '%MCP-TEST-%'").count)
