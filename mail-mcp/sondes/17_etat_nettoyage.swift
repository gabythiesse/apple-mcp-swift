// Sonde 17 : état des données de test restantes (url de boîte, drapeau deleted), index en lecture seule
import Foundation
import SQLite3
var db: OpaquePointer?; var st: OpaquePointer?
sqlite3_open_v2("file:" + NSHomeDirectory() + "/Library/Mail/V10/MailData/Envelope Index?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
sqlite3_prepare_v2(db, """
SELECT m.ROWID, b.url, m.deleted, ifnull(m.subject_prefix,''), s.subject FROM messages m JOIN mailboxes b ON b.ROWID=m.mailbox JOIN subjects s ON s.ROWID=m.subject WHERE s.subject LIKE '[mcp-test]%'
UNION ALL SELECT ROWID, url, total_count, '', 'BOITE' FROM mailboxes WHERE url LIKE '%MCP-TEST-%'
""", -1, &st, nil)
while sqlite3_step(st) == SQLITE_ROW { print((0..<5).map { sqlite3_column_text(st, $0).map { String(cString: $0) } ?? "" }.joined(separator: " | ")) }
