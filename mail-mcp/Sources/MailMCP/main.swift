// Serveur MCP Mail : boucle stdio (un message JSON-RPC par ligne)
import Foundation

Responsabilite.relancerSiBesoin()   // voir Responsabilite.swift : autorisations macOS liées à ce binaire, pas au client

// La boucle stdio tourne hors du thread principal. NSAppleScript s'exécute sur le thread principal,
// qui fait tourner une vraie boucle d'exécution (RunLoop) : sous dispatchMain(), des réponses de Mail se perdaient par intermittence (expirations de 30 s).
DispatchQueue(label: "mail-mcp.stdio").async {
    while let line = readLine(strippingNewline: true) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            Stdio.send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
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
RunLoop.main.run()
