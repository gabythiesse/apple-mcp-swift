// Serveur MCP Computer : boucle stdio (un message JSON-RPC par ligne)
import Foundation
import MacUI

Responsabilite.relancerSiBesoin()   // voir Responsabilite.swift : autorisations macOS liées au lanceur, pas au client
AX.setTimeout(1.0)                  // une app qui ne répond plus ne gèle pas l'appel

// La boucle tourne hors du fil principal, qui garde une vraie RunLoop : ScreenCaptureKit, NSWorkspace
// et les notifications d'activation des apps y arrivent.
DispatchQueue(label: "computer-mcp.stdio").async {
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
RunLoop.main.run()
