# notes-mcp: French → English renames

Content convention: plain-text content is `text` (paired with `html`), appended content is `append_text` / `append_html`; the read output key is `content`.

## Tools

| French | English |
|---|---|
| dossiers | list_folders |
| notes | list_notes |
| lire_notes | read_notes |
| creer_notes | create_notes |
| modifier_notes | update_notes |
| supprimer_notes | delete_notes |
| creer_dossier | create_folder |
| renommer_dossier | rename_folder |
| supprimer_dossier | delete_folder |
| ajouter_pieces_jointes | add_attachments |
| exporter_pieces_jointes | export_attachments |
| tags | list_tags |
| ouvrir_note | open_note |

## Input parameters

| Tool | French | English |
|---|---|---|
| list_folders | nom_contient | name_contains |
| list_notes, list_tags | dossier_id | folder_id |
| list_notes | sous_dossiers (bool) | include_subfolders |
| list_notes | texte (search) | text |
| list_notes | modifiees_depuis | modified_since |
| list_notes | modifiees_avant | modified_before |
| list_notes | epinglees | pinned |
| list_notes | supprimees | include_deleted |
| list_notes | limite | limit |
| read_notes | max_caracteres | max_chars |
| create_notes, update_notes | titre | title |
| create_notes, update_notes | texte | text |
| create_notes, update_notes | dossier_id | folder_id |
| update_notes | modifications | updates |
| update_notes | ajouter_texte | append_text |
| update_notes | ajouter_html | append_html |
| delete_notes | definitif | permanent |
| create_folder, rename_folder | nom | name |
| create_folder | compte_id | account_id |
| create_folder | sous_dossiers (names) | subfolders |
| add_attachments | pieces | attachments |
| add_attachments | chemin | path |
| export_attachments | dossier | destination |

Unchanged: id, ids, note_ids, note_id, parent_id, tag, html, format, notes.

## Enum values

| Param | French | English |
|---|---|---|
| read_notes.format | texte | text |
| read_notes.format | html | html |

## Output keys

| French | English | Where |
|---|---|---|
| comptes | accounts | list_folders |
| nom | name | folders, accounts, attachments, create/rename/delete_folder |
| par_defaut | default | list_folders account |
| dossier_par_defaut | default_folder_id | list_folders account |
| dossiers | folders | list_folders account |
| nb_notes | note_count | list_folders, list_tags |
| corbeille | trash | list_folders folder |
| sous_dossiers | subfolders | create_folder |
| supprime | deleted | delete_folder (id of deleted folder) |
| notes_en_corbeille | notes_trashed | delete_folder |
| sous_dossiers_supprimes | subfolders_deleted | delete_folder |
| non_supprimes | not_deleted | delete_folder |
| titre | title | notes, results |
| dossier_id | folder_id | notes, results |
| dossier | folder | notes (folder name) |
| creee | created | read_notes |
| modifiee | modified | list_notes, read_notes |
| epinglee | pinned | list_notes, read_notes |
| verrouillee | locked | read_notes |
| contenu | content | read_notes |
| tronque | truncated | list_notes (message string), read_notes (bool) |
| partagee | shared | read_notes |
| pieces_jointes | attachments | read_notes |
| erreur | error | all per-item results |
| avertissement | warning | create_notes |
| crees | created | create_notes |
| modifiees | updated | update_notes |
| supprimees | deleted | delete_notes |
| definitif | permanent | delete_notes |
| ajoutees | added | add_attachments |
| exportees | exported | export_attachments |
| fichier | file | export_attachments |
| echecs | failed | create_notes, update_notes |
| resultats | results | all batch tools |

Unchanged: ok, id, total, notes, checklist, tags, tag, note_id, parent_id.

## Intentionally left French

- `"Supprimées récemment"` in Handlers.swift: matches the trash folder name on a French-language Mac (alongside "Recently Deleted").
- Boolean parsing still accepts `"oui"` (now also `"yes"`) for tolerance.
