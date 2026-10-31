// Sonde 03 : relit dans l'index (lecture seule) UNIQUEMENT les boîtes et messages de test (url contenant le préfixe passé)
import Foundation
import SQLite3
let pref = CommandLine.arguments[1]
precondition(pref.hasPrefix("MCP-TEST-"), "préfixe de test obligatoire")
let path = NSHomeDirectory() + "/Library/Mail/V10/MailData/Envelope Index"
var db: OpaquePointer?
guard sqlite3_open_v2("file:" + path + "?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { print("ouverture KO"); exit(1) }
func q(_ sql: String, _ bind: String) -> [[String]] {
  var st: OpaquePointer?; var out: [[String]] = []
  guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { print("ERR", String(cString: sqlite3_errmsg(db))); return [] }
  sqlite3_bind_text(st, 1, "%" + bind + "%", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
  while sqlite3_step(st) == SQLITE_ROW { out.append((0..<sqlite3_column_count(st)).map { sqlite3_column_text(st, $0).map { String(cString: $0) } ?? "∅" }) }
  sqlite3_finalize(st); return out
}
let t0 = Date()
for r in q("SELECT ROWID, url, total_count, unread_count FROM mailboxes WHERE url LIKE ?", pref) { print("boîte:", r) }
let msgs = q("""
SELECT m.ROWID, b.url, s.subject, a.address, a.comment, m.date_received, m.read, m.flagged, m.flag_color, m.deleted, m.conversation_id, m.global_message_id,
       (SELECT group_concat(name) FROM attachments WHERE message = m.ROWID), (SELECT summary FROM summaries WHERE ROWID = m.summary), g.message_id_header
FROM messages m JOIN mailboxes b ON b.ROWID = m.mailbox LEFT JOIN subjects s ON s.ROWID = m.subject LEFT JOIN addresses a ON a.ROWID = m.sender
LEFT JOIN message_global_data g ON g.ROWID = m.global_message_id
WHERE b.url LIKE ? OR s.subject LIKE "[mcp-test]%"
""", pref)
for r in msgs { print("message:", r) }
print("requête: \(Int(Date().timeIntervalSince(t0)*1000)) ms")
