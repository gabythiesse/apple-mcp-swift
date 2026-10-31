// Sonde 01 : accès aux fichiers de données de Safari, en LECTURE SEULE.
// N'affiche que l'accès et le schéma (tables, colonnes, clés), jamais une valeur.
import Foundation
import SQLite3

let home = FileManager.default.homeDirectoryForCurrentUser.path
let candidats = [
    "\(home)/Library/Safari/Bookmarks.plist",
    "\(home)/Library/Safari/History.db",
    "\(home)/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db",
    "\(home)/Library/Containers/com.apple.Safari/Data/Library/Safari/Bookmarks.plist",
    "\(home)/Library/Containers/com.apple.Safari/Data/Library/Safari/History.db",
]

func lireOctets(_ p: String) -> String {
    guard let h = FileHandle(forReadingAtPath: p) else {
        return "ouverture refusée (errno \(errno): \(String(cString: strerror(errno))))"
    }
    defer { try? h.close() }
    let d = (try? h.read(upToCount: 8)) ?? Data()
    return "lisible (\(d.count) octets lus en tête)"
}

func schemaSQLite(_ p: String) {
    var db: OpaquePointer?
    let uri = "file:\(p)?mode=ro"
    guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
        print("   sqlite : ouverture KO : \(String(cString: sqlite3_errmsg(db)))"); return
    }
    defer { sqlite3_close(db) }
    var st: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name", -1, &st, nil) == SQLITE_OK else {
        print("   sqlite : lecture du schéma KO : \(String(cString: sqlite3_errmsg(db)))"); return
    }
    var tables: [String] = []
    while sqlite3_step(st) == SQLITE_ROW { tables.append(String(cString: sqlite3_column_text(st, 0))) }
    sqlite3_finalize(st)
    for t in tables where !t.hasPrefix("sqlite_") {
        var cs: OpaquePointer?
        var cols: [String] = []
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\"\(t)\")", -1, &cs, nil) == SQLITE_OK {
            while sqlite3_step(cs) == SQLITE_ROW { cols.append(String(cString: sqlite3_column_text(cs, 1))) }
        }
        sqlite3_finalize(cs)
        print("   table \(t) : \(cols.joined(separator: ", "))")
    }
}

/// Clés utilisées dans l'arbre des favoris, sans aucune valeur
func clesPlist(_ p: String) {
    guard let d = FileManager.default.contents(atPath: p),
          let racine = try? PropertyListSerialization.propertyList(from: d, format: nil) else {
        print("   plist : lecture KO"); return
    }
    var cles = Set<String>(), types = Set<String>()
    func parcourir(_ o: Any) {
        if let dict = o as? [String: Any] {
            for (k, v) in dict { cles.insert(k); if k == "WebBookmarkType", let s = v as? String { types.insert(s) }; parcourir(v) }
        } else if let arr = o as? [Any] { arr.forEach(parcourir) }
    }
    parcourir(racine)
    print("   clés : \(cles.sorted().joined(separator: ", "))")
    print("   types de nœud : \(types.sorted().joined(separator: ", "))")
}

for p in candidats {
    let existe = FileManager.default.fileExists(atPath: p)
    print("\(p.replacingOccurrences(of: home, with: "~")) : \(existe ? lireOctets(p) : "absent")")
    guard existe, FileHandle(forReadingAtPath: p) != nil else { continue }
    if p.hasSuffix(".db") { schemaSQLite(p) } else { clesPlist(p) }
}
