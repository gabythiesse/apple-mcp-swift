# mail-mcp renames (FR → EN)

## Tools

| French | English |
|---|---|
| `boites` | `list_mailboxes` |
| `messages` | `list_messages` |
| `lire_messages` | `read_messages` |
| `enregistrer_pieces_jointes` | `save_attachments` |
| `marquer_messages` | `mark_messages` |
| `deplacer_messages` | `move_messages` |
| `supprimer_messages` | `delete_messages` |
| `creer_brouillons` | `create_drafts` |
| `envoyer` | `send` |
| `gerer_boites` | `manage_mailboxes` |
| `supprimer_boites` | `delete_mailboxes` |
| `relever` | `fetch_mail` |

## Input parameters

| Tool | French | English |
|---|---|---|
| list_mailboxes | `nom_contient` | `name_contains` |
| list_messages | `vue` | `view` |
| list_messages | `boites` | `mailbox_ids` |
| list_messages | `compte` | `account_id` |
| list_messages | `non_lu` | `unread` |
| list_messages | `drapeau` | `flagged` |
| list_messages | `depuis` | `since` |
| list_messages | `avant` | `before` |
| list_messages | `de` | `from` |
| list_messages | `a` | `to` |
| list_messages | `texte` | `text` |
| list_messages | `dans_corps` | `body_contains` |
| list_messages | `avec_pj` | `has_attachments` |
| list_messages | `apercu` | `preview` |
| list_messages | `limite` | `limit` |
| list_messages | `conversation`, `ids` | unchanged |
| read_messages | `entetes` | `headers` |
| read_messages | `max_car` | `max_chars` |
| read_messages | `source`, `ids` | unchanged |
| save_attachments | `dossier` | `folder` |
| save_attachments | `noms` | `names` |
| mark_messages | `modifications` | `changes` |
| mark_messages (item) | `lu` | `read` |
| mark_messages (item) | `drapeau` | `flagged` |
| mark_messages (item) | `couleur_drapeau` | `flag_color` |
| mark_messages (item) | `couleur_fond` | `background_color` |
| mark_messages (item) | `indesirable` | `junk` |
| move_messages | `boite` | `mailbox_id` |
| move_messages | `copier` | `copy` |
| create_drafts | `brouillons` | `drafts` |
| send | `brouillon_ids` | `draft_ids` |
| create_drafts / send (message) | `a` | `to` |
| create_drafts / send (message) | `cci` | `bcc` |
| create_drafts / send (message) | `sujet` | `subject` |
| create_drafts / send (message) | `corps` | `body` |
| create_drafts / send (message) | `expediteur` | `from` |
| create_drafts / send (message) | `pieces_jointes` | `attachments` |
| create_drafts / send (message) | `repondre_a` | `reply_to_id` |
| create_drafts / send (message) | `tous` | `reply_all` |
| create_drafts / send (message) | `transferer` | `forward_id` |
| create_drafts / send (message) | `cc`, `signature` | unchanged |
| manage_mailboxes | `creer` | `create` |
| manage_mailboxes | `renommer` | `rename` |
| manage_mailboxes (create item) | `chemin` | `path` |
| manage_mailboxes (create item) | `compte` | `account_id` |
| manage_mailboxes (rename item) | `nom` | `name` |
| delete_mailboxes | `forcer` | `force` |
| fetch_mail | `compte` | `account_id` |
| fetch_mail | `synchroniser` | `sync` |

## Enum values

| Param | French | English |
|---|---|---|
| `view` | `aujourdhui` | `today` |
| `view` | `non_lus` | `unread` |
| `view` | `drapeau` | `flagged` |
| `view` | `recents` | `recent` |
| `view` | `sans_reponse` | `no_reply` |
| `view` | `selection` | `selection` |
| `flag_color` / `background_color` | `rouge`, `orange`, `jaune`, `vert`, `bleu`, `violet`, `gris` | `red`, `orange`, `yellow`, `green`, `blue`, `purple`, `gray` |
| `background_color` | `aucune` | `none` |

## Output keys

| Tool(s) | French | English |
|---|---|---|
| list_mailboxes | `comptes` | `accounts` |
| list_mailboxes (account) | `nom` | `name` |
| list_mailboxes (account) | `adresses` | `addresses` |
| list_mailboxes (local account name) | `Sur mon Mac` | `On My Mac` |
| list_mailboxes | `boites` | `mailboxes` |
| list_mailboxes (mailbox) | `non_lus` | `unread` |
| list_messages (message) | `boite` | `mailbox` |
| list_messages / read_messages | `de` | `from` |
| list_messages / read_messages / create_drafts / send | `sujet` | `subject` |
| list_messages (message) | `non_lu` | `unread` |
| list_messages (message) | `drapeau` | `flagged` |
| list_messages (message, count) / read_messages (list) | `pj` | `attachments` |
| list_messages (message) | `apercu` | `preview` |
| list_messages / read_messages | `tronque` | `truncated` |
| read_messages | `a` | `to` |
| read_messages | `cci` | `bcc` |
| read_messages | `corps` | `body` |
| read_messages (attachment) | `nom` | `name` |
| read_messages (attachment) | `taille` | `size` |
| read_messages | `entetes` | `headers` |
| all | `erreur` | `error` |
| all batch tools | `resultats` | `results` |
| save_attachments | `fichiers` | `files` |
| mark_messages | `modifies` | `updated` |
| mark_messages / delete_messages (list) | `echecs` | `failures` |
| create_drafts / send (count) | `echecs` | `failed` |
| move_messages | `boite` | `mailbox` |
| move_messages | `nouvel_id` | `new_id` |
| move_messages / create_drafts | `avertissement` | `warning` |
| delete_messages | `supprimes` | `deleted` |
| delete_mailboxes | `messages_supprimes` | `deleted_messages` |
| manage_mailboxes | `ancien_id` | `old_id` |
| manage_mailboxes (failure) | `chemin` | `path` |
| create_drafts | `crees` | `created` |
| send | `envoyes` | `sent` |
| send | `brouillon_id` | `draft_id` |

Unchanged output keys: `id`, `ok`, `type`, `total`, `signatures`, `messages`, `date`, `conv`, `cc`, `source`.

## Other changes

- Reply/forward quote text in composed emails is now English: "On <date>, <from> wrote:" and "Begin forwarded message:" with From/Subject/Date/To headers; the quote date uses `MMMM d, yyyy 'at' HH:mm` (en_US_POSIX) instead of the French format.
- Boolean strings accept `"yes"` instead of `"oui"`.
- Left in French on purpose: the Mail menu/button names used by `delete_mailboxes` UI scripting ("Boîte aux lettres", "Supprimer la boîte aux lettres…", "Supprimer", "Annuler") because they must match the French-localized Mail UI; the French special-mailbox names in Index.swift (matched against real mailbox names, alongside the English ones); internal AppleScript sentinels (`absente`, `pleine`).
