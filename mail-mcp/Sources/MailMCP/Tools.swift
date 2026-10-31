// Outils exposés : noms, descriptions (quand les utiliser) et schémas d'entrée
import Foundation

private func obj(_ props: JSON, _ required: [String] = []) -> JSON {
    ["type": "object", "properties": props, "required": required]
}
private func s(_ d: String) -> JSON { ["type": "string", "description": d] }
private func b(_ d: String) -> JSON { ["type": "boolean", "description": d] }
private func n(_ d: String) -> JSON { ["type": "number", "description": d] }
private func e(_ values: [String], _ d: String) -> JSON { ["type": "string", "enum": values, "description": d] }
private func arr(_ items: JSON, _ d: String) -> JSON { ["type": "array", "items": items, "description": d] }

private let dateHelp = "YYYY-MM-DD or YYYY-MM-DDTHH:MM (local time)"
private let ids = arr(n("Message id"), "Message ids")
private let couleurs = ["red", "orange", "yellow", "green", "blue", "purple", "gray"]

/// Message à composer (brouillon ou envoi direct)
private let composition = obj([
    "to": arr(s("Address, or \"Name <address>\""), "Recipients"),
    "cc": arr(s("Address"), "Cc"),
    "bcc": arr(s("Address"), "Bcc"),
    "subject": s("Subject (for a reply or forward: leave empty to keep Re:/Fwd:)"),
    "body": s("Message text (for a reply or forward, placed above the quoted message)"),
    "from": s("Sending address, one of the accounts' addresses (default account otherwise)"),
    "signature": s("Name of a Mail signature (see list_mailboxes)"),
    "attachments": arr(s("Absolute path"), "Files to attach"),
    "reply_to_id": n("Reply to this message: recipient, Re: subject and quote are filled in (new message, not threaded on the recipient's side)"),
    "reply_all": b("With reply_to_id: reply to all"),
    "forward_id": n("Forward this message: Fwd: subject, quoted message and attachments carried over"),
])

/// Annotations MCP : lectures pures readOnly, suppression destructive, envoi openWorld
private let lectures: Set<String> = ["list_mailboxes", "list_messages", "read_messages"]
private func annotations(_ nom: String) -> JSON {
    var a: JSON = ["readOnlyHint": lectures.contains(nom), "destructiveHint": nom.hasPrefix("delete_"), "openWorldHint": nom == "send"]
    if nom.hasPrefix("delete_") { a["idempotentHint"] = true }
    return a
}

enum Tools {
    static let definitions: [JSON] = outils.map { o in
        var o = o
        o["annotations"] = annotations(o["name"] as! String)
        return o
    }

    private static let outils: [JSON] = [
        ["name": "list_mailboxes",
         "description": "Lists accounts (id, name, addresses), mailboxes (id, unread, total) and signature names. Call it to get mailbox ids.",
         "inputSchema": obj(["name_contains": s("Only keep mailboxes whose path contains this text")])],
        ["name": "list_messages",
         "description": "Searches and lists messages through Mail's index (fast): ready-made views, mailboxes, account, unread, flagged, dates, sender, recipient, text (subject, sender, start of body), attachments, conversation. body_contains searches the whole body (slower, one mailbox only). 20 results by default, newest first.",
         "inputSchema": obj([
            "view": e(["today", "unread", "flagged", "recent", "no_reply", "selection"],
                     "today = received today; unread; flagged; recent; no_reply = sent in the last 30 days with no reply in the thread; selection = messages selected in Mail. Views other than flagged/selection skip Sent, Drafts, Trash and Junk."),
            "mailbox_ids": arr(s("Mailbox id"), "Limit to these mailboxes"),
            "account_id": s("Limit to this account (id, or local)"),
            "unread": b("true = unread only, false = read only"),
            "flagged": b("true = flagged, false = not flagged"),
            "since": s("Received on or after: \(dateHelp)"),
            "before": s("Received strictly before: \(dateHelp)"),
            "from": s("Sender (address or name, partial)"),
            "to": s("To/cc recipient (address or name, partial)"),
            "text": s("Text in the subject, the sender or the start of the body"),
            "body_contains": s("Text to search for in the whole body (requires exactly one mailbox in mailbox_ids)"),
            "has_attachments": b("Only messages with attachments"),
            "conversation": n("Only this thread (conv field)"),
            "ids": ids,
            "preview": b("Add the start of the body (160 characters)"),
            "limit": n("Maximum number (20 by default)"),
         ])],
        ["name": "read_messages",
         "description": "Reads the full content of one or more messages: sender, recipients, date, body as text, attachments. Headers and raw source on request.",
         "inputSchema": obj(["ids": ids, "headers": b("Add all headers"), "source": b("Add the raw source (RFC 822)"),
                             "max_chars": n("Maximum body length (5000 by default)")], ["ids"])],
        ["name": "save_attachments",
         "description": "Saves the attachments of one or more messages to disk. Returns the file paths.",
         "inputSchema": obj(["ids": ids, "folder": s("Destination folder (Downloads by default)"),
                             "names": arr(s("File name"), "Only save these attachments")], ["ids"])],
        ["name": "mark_messages",
         "description": "Changes message state in batch: read, flag and its color, background color, junk. Only the fields provided change.",
         "inputSchema": obj(["changes": arr(obj([
            "id": n("Message id"),
            "read": b("Read (true) or unread (false)"),
            "flagged": b("Set (true) or clear (false) the flag"),
            "flag_color": e(couleurs, "Flag color (sets the flag)"),
            "background_color": e(couleurs + ["none"], "Background color in the message list"),
            "junk": b("Mark as junk or not junk"),
         ], ["id"]), "One entry per message")], ["changes"])],
        ["name": "move_messages",
         "description": "Moves (or copies) messages to a mailbox, for example to archive them. Returns each message's new id (the old one is no longer valid).",
         "inputSchema": obj(["ids": ids, "mailbox_id": s("Destination mailbox id"), "copy": b("Copy instead of moving")], ["ids", "mailbox_id"])],
        ["name": "delete_messages",
         "description": "Deletes messages or drafts by id: they go to their account's Trash. A draft created since Mail was last launched keeps a copy in Drafts until Mail is relaunched.",
         "inputSchema": obj(["ids": ids], ["ids"])],
        ["name": "create_drafts",
         "description": "Creates one or more drafts (new message, reply, reply all, forward), with attachments and signature, without sending anything. Returns each draft's id.",
         "inputSchema": obj(["drafts": arr(composition, "Drafts to create")], ["drafts"])],
        ["name": "send",
         "description": "ACTUALLY SENDS email: either existing drafts (draft_ids: recomposed, sent, then deleted), or messages composed directly (messages, same fields as create_drafts). Only use after explicit approval.",
         "inputSchema": obj(["draft_ids": ids, "messages": arr(composition, "Messages to compose and send")])],
        ["name": "manage_mailboxes",
         "description": "Creates or renames mailboxes (to delete: delete_mailboxes).",
         "inputSchema": obj([
            "create": arr(obj(["path": s("Path, e.g. \"Clients/2026\""), "account_id": s("Account (id); local by default (On My Mac)")], ["path"]), "Mailboxes to create"),
            "rename": arr(obj(["id": s("Mailbox id"), "name": s("New name (last element of the path)")], ["id", "name"]), "Mailboxes to rename"),
         ])],
        ["name": "delete_mailboxes",
         "description": "Permanently deletes mailboxes by id (with their content). Refuses a mailbox that contains messages or sub-mailboxes, unless force: true. Goes through Mail's menu: Mail comes to the front for a few seconds (requires Accessibility access).",
         "inputSchema": obj(["ids": arr(s("Mailbox id (see list_mailboxes)"), "Mailboxes to delete"),
                             "force": b("Delete even if the mailbox contains messages or sub-mailboxes")], ["ids"])],
        ["name": "fetch_mail",
         "description": "Checks for new mail (all accounts or one), and syncs the IMAP account if asked.",
         "inputSchema": obj(["account_id": s("Account id"), "sync": b("Also sync the account (requires account_id)")])],
    ]

    static func call(_ name: String, _ a: JSON) throws -> Any {
        switch name {
        case "list_mailboxes": return try Handlers.boites(a)
        case "list_messages": return try Handlers.messages(a)
        case "read_messages": return try Handlers.lireMessages(a)
        case "save_attachments": return try Handlers.enregistrerPJ(a)
        case "mark_messages": return try Handlers.marquer(a)
        case "move_messages": return try Handlers.deplacer(a)
        case "delete_messages": return try Handlers.supprimer(a)
        case "create_drafts": return try Compose.creerBrouillons(a)
        case "send": return try Compose.envoyer(a)
        case "manage_mailboxes": return try Handlers.gererBoites(a)
        case "delete_mailboxes": return try Handlers.supprimerBoites(a)
        case "fetch_mail": return try Handlers.relever(a)
        default: throw MCPError("unknown tool: \(name)")
        }
    }
}
