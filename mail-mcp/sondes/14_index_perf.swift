// Sonde 14 : performance de l'index sur toute la base — n'affiche QUE des nombres et des durées, aucun contenu
import Foundation
import SQLite3
let path = NSHomeDirectory() + "/Library/Mail/V10/MailData/Envelope Index"
var db: OpaquePointer?
guard sqlite3_open_v2("file:" + path + "?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { exit(1) }
func n(_ label: String, _ sql: String) {
  var st: OpaquePointer?; let t0 = Date()
  guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { print(label, "ERR", String(cString: sqlite3_errmsg(db))); return }
  var vals: [String] = []
  while sqlite3_step(st) == SQLITE_ROW { vals.append((0..<sqlite3_column_count(st)).map { String(sqlite3_column_int64(st, $0)) }.joined(separator: ":")) }
  sqlite3_finalize(st)
  print(label, vals.prefix(12).joined(separator: " "), "|", Int(Date().timeIntervalSince(t0)*1000), "ms")
}
n("messages total", "SELECT count(*) FROM messages")
n("boîtes total", "SELECT count(*) FROM mailboxes")
n("non lus 7 j toutes boîtes", "SELECT count(*) FROM messages WHERE read=0 AND deleted=0 AND date_received > strftime('%s','now','-7 days')")
n("recherche sujet+expéditeur+résumé (mot absent)", """
SELECT count(*) FROM messages m LEFT JOIN subjects s ON s.ROWID=m.subject LEFT JOIN addresses a ON a.ROWID=m.sender LEFT JOIN summaries u ON u.ROWID=m.summary
WHERE s.subject LIKE '%qzxwv-absent%' OR a.address LIKE '%qzxwv-absent%' OR a.comment LIKE '%qzxwv-absent%' OR u.summary LIKE '%qzxwv-absent%'
""")
n("recherche destinataire (mot absent)", "SELECT count(*) FROM recipients r JOIN addresses a ON a.ROWID=r.address WHERE a.address LIKE '%qzxwv-absent%'")
n("20 derniers reçus (ids seulement)", "SELECT count(*) FROM (SELECT ROWID FROM messages WHERE deleted=0 ORDER BY date_received DESC LIMIT 20)")
n("valeurs model_category (valeur:nb)", "SELECT model_category, count(*) FROM message_global_data GROUP BY model_category")
n("read_later / follow_up / send_later posés", "SELECT sum(read_later_date IS NOT NULL), sum(follow_up_start_date IS NOT NULL), sum(send_later_date IS NOT NULL) FROM message_global_data")
n("messages avec conversation", "SELECT count(DISTINCT conversation_id) FROM messages")
sqlite3_close(db)
