// Serveur MCP Safari : boucle stdio (un message JSON-RPC par ligne)
import Foundation

Responsabilite.relancerSiBesoin()   // voir Responsabilite.swift : autorisations macOS liées à ce binaire, pas au client

// --accessibility : demande à macOS l'accès Accessibilité pour CE binaire (fenêtre système, entrée pré-ajoutée dans
// Réglages Système > Confidentialité et sécurité > Accessibilité), puis affiche l'état et quitte. Sert à l'installation.
if CommandLine.arguments.contains("--accessibility") {
    import_ApplicationServices_trusted()
    exit(0)
}

// La boucle tourne hors du thread principal : NSAppleScript s’exécute sur la file
// principale (voir AppleScript.swift), qui tourne avec une vraie RunLoop.
DispatchQueue(label: "safari-mcp.stdio").async {
    while let line = readLine(strippingNewline: true) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            Stdio.send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error: invalid JSON"]])
            continue
        }
        if let batch = obj as? [JSON] {
            let responses = batch.compactMap(Server.handle)
            if !responses.isEmpty { Stdio.send(responses) }
        } else if let msg = obj as? JSON, let response = Server.handle(msg) {
            Stdio.send(response)
        }
    }
    exit(0)
}
RunLoop.main.run()  // boucle d’exécution réelle : les réponses Apple Event arrivent sur le fil principal
