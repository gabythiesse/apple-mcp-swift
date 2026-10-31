// Voie base : NoteStore.sqlite en LECTURE SEULE, pour ce qu'AppleScript n'expose pas
// (tags, épinglage, checklists, dossier d'une note). Exige l'Accès complet au disque ; sans lui, ces champs sont absents.
// Schéma non documenté : peut changer à une mise à jour de macOS. Jamais d'écriture.
import Foundation
import SQLite3

enum DB {
    private static let path = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
    private static var handle: OpaquePointer?
    private static var tried = false
    private static var ent: [String: Int] = [:]
    private static let lock = NSLock()

    /// Base ouverte (ou nil si inaccessible, ou si ce n'est pas le magasin vu par AppleScript)
    private static func db() -> OpaquePointer? {
        if tried { return handle }
        tried = true
        var h: OpaquePointer?
        guard sqlite3_open_v2(path, &h, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            log("NoteStore.sqlite not accessible (Full Disk Access?): tags, pinning and checklists unavailable")
            sqlite3_close(h); return nil
        }
        sqlite3_busy_timeout(h, 2000)
        handle = h
        for r in rows("SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY") { if let n = Int(r[0]) { ent[r[1]] = n } }
        if ent["ICNote"] == nil {
            log("NoteStore.sqlite unreadable (unexpected schema)")
            sqlite3_close(h); handle = nil
        }
        return handle
    }

    static var available: Bool { lock.lock(); defer { lock.unlock() }; return db() != nil }

    private static func rows(_ sql: String) -> [[String]] {
        guard let h = handle else { return [] }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &st, nil) == SQLITE_OK else { log("SQL : \(String(cString: sqlite3_errmsg(h)))"); return [] }
        defer { sqlite3_finalize(st) }
        var out: [[String]] = []
        while sqlite3_step(st) == SQLITE_ROW {
            out.append((0..<sqlite3_column_count(st)).map { i in sqlite3_column_text(st, i).map { String(cString: $0) } ?? "" })
        }
        return out
    }

    private static func query(_ sql: (_ e: [String: Int]) -> String) -> [[String]]? {
        lock.lock(); defer { lock.unlock() }
        guard db() != nil else { return nil }
        return rows(sql(ent))
    }
    private static func inList(_ pks: [Int]) -> String { pks.map(String.init).joined(separator: ",") }

    struct Flags { var epinglee = false; var checklist = false; var tags: [String] = [] }

    /// Épinglage, checklist et tags de ces notes
    static func flags(_ pks: [Int]) -> [Int: Flags]? {
        guard !pks.isEmpty else { return [:] }
        guard let base = query({ e in "SELECT Z_PK, ZISPINNED, ZHASCHECKLIST FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT=\(e["ICNote"]!) AND Z_PK IN (\(inList(pks)))" }) else { return nil }
        var out: [Int: Flags] = [:]
        for r in base { if let pk = Int(r[0]) { out[pk] = Flags(epinglee: r[1] == "1", checklist: r[2] == "1") } }
        for r in query({ e in tagSQL(e) + " AND ZNOTE1 IN (\(inList(pks)))" }) ?? [] {
            if let pk = Int(r[0]) { out[pk, default: Flags()].tags.append(r[1]) }
        }
        for k in out.keys { out[k]!.tags = Array(Set(out[k]!.tags)).sorted() }
        return out
    }

    /// (note, tag sans #) pour les tags vivants
    private static func tagSQL(_ e: [String: Int]) -> String {
        "SELECT DISTINCT ZNOTE1, lower(ltrim(ZALTTEXT, '#')) FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT=\(e["ICInlineAttachment"] ?? -1) AND ZTYPEUTI1 LIKE '%hashtag%' AND COALESCE(ZMARKEDFORDELETION,0)=0 AND ZALTTEXT IS NOT NULL"
    }

    /// Notes portant ce tag
    static func notesWithTag(_ tag: String) -> Set<Int>? {
        let t = tag.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased().replacingOccurrences(of: "'", with: "''")
        return query({ e in tagSQL(e) + " AND lower(ltrim(ZALTTEXT, '#'))='\(t)'" }).map { Set($0.compactMap { Int($0[0]) }) }
    }

    /// Notes épinglées
    static func pinned() -> Set<Int>? {
        query({ e in "SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT=\(e["ICNote"]!) AND ZISPINNED=1 AND COALESCE(ZMARKEDFORDELETION,0)=0" })
            .map { Set($0.compactMap { Int($0[0]) }) }
    }

    /// Tags vivants avec leur nombre de notes (hors notes supprimées), éventuellement limités à des dossiers
    static func tags(folders: [Int]?) -> [(String, Int)]? {
        guard let r = query({ e in
            var sql = "SELECT lower(ltrim(t.ZALTTEXT, '#')) AS tag, count(DISTINCT t.ZNOTE1) FROM ZICCLOUDSYNCINGOBJECT t JOIN ZICCLOUDSYNCINGOBJECT n ON n.Z_PK = t.ZNOTE1" +
                " WHERE t.Z_ENT=\(e["ICInlineAttachment"] ?? -1) AND t.ZTYPEUTI1 LIKE '%hashtag%' AND COALESCE(t.ZMARKEDFORDELETION,0)=0 AND t.ZALTTEXT IS NOT NULL" +
                " AND COALESCE(n.ZMARKEDFORDELETION,0)=0 AND n.ZFOLDER NOT IN (SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT WHERE ZFOLDERTYPE=1)"
            if let f = folders { sql += " AND n.ZFOLDER IN (\(inList(f.isEmpty ? [-1] : f)))" }
            return sql + " GROUP BY tag ORDER BY 2 DESC, 1"
        }) else { return nil }
        return r.compactMap { row in Int(row[1]).map { (row[0], $0) } }
    }

    /// Un dossier et tous ses sous-dossiers
    static func folderTree(_ root: Int) -> [Int] {
        (query({ e in "WITH RECURSIVE f(pk) AS (SELECT \(root) UNION SELECT c.Z_PK FROM ZICCLOUDSYNCINGOBJECT c JOIN f ON c.ZPARENT = f.pk WHERE c.Z_ENT=\(e["ICFolder"] ?? -1)) SELECT pk FROM f" }) ?? [[String(root)]])
            .compactMap { Int($0[0]) }
    }

    /// Note de chaque pièce jointe
    static func noteOfAttachments(_ pks: [Int]) -> [Int: Int] {
        guard !pks.isEmpty else { return [:] }
        var out: [Int: Int] = [:]
        for r in query({ _ in "SELECT Z_PK, ZNOTE FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK IN (\(inList(pks))) AND ZNOTE IS NOT NULL" }) ?? [] {
            if let a = Int(r[0]), let b = Int(r[1]) { out[a] = b }
        }
        return out
    }

    /// Dossier (Z_PK) de ces notes
    static func folderOf(_ pks: [Int]) -> [Int: Int] {
        guard !pks.isEmpty else { return [:] }
        var out: [Int: Int] = [:]
        for r in query({ e in "SELECT Z_PK, ZFOLDER FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT=\(e["ICNote"]!) AND Z_PK IN (\(inList(pks)))" }) ?? [] {
            if let a = Int(r[0]), let b = Int(r[1]) { out[a] = b }
        }
        return out
    }

    /// Dossiers « Supprimées récemment »
    static func trashFolders() -> Set<Int>? {
        query({ _ in "SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT WHERE ZFOLDERTYPE=1" }).map { Set($0.compactMap { Int($0[0]) }) }
    }
}
