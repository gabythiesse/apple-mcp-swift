// Serveur MCP Contacts : point d'entrée appelé par le lanceur (bin/ContactsMCP), boucle stdio (un message JSON-RPC par ligne)
import Foundation

@_cdecl("contacts_mcp_main")
public func contactsMCPMain() {
    // Lancé par l'app Claude, le processus hérite de sa « responsabilité » TCC et l'accès Contacts est refusé sans invite :
    // on se relance une fois en responsable de soi-même (voir Private.swift). Le processus parent attend et relaie la sortie.
    Responsabilite.relancerSiBesoin()

    // La boucle stdio tourne hors du thread principal. Le thread principal fait tourner sa boucle d'événements (RunLoop) :
    // NSAppleScript y attend ses réponses Apple Event ; avec dispatchMain(), elles arrivaient par intermittence au bout du délai (120 s).
    DispatchQueue(label: "contacts-mcp.stdio").async {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else {
                Stdio.send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "JSON invalide"]])
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
}
