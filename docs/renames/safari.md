# safari-mcp: French → English renames

## Tools

| French | English |
|---|---|
| onglets | list_tabs |
| ouvrir | open |
| naviguer | navigate |
| fermer | close |
| lire_page | read_page |
| executer_js | run_js |
| liste_de_lecture | list_reading_list |
| ajouter_liste_de_lecture | add_to_reading_list |
| favoris | list_bookmarks |
| historique | list_history |
| groupes_onglets | list_tab_groups |
| supprimer_liste_de_lecture | delete_from_reading_list |
| supprimer_historique | delete_history |
| supprimer_groupe_onglets | delete_tab_groups |

## Input parameters

| French | English | Tools |
|---|---|---|
| fenetre_id | window_id | list_tabs, open, navigate, close, read_page, run_js (tab refs) |
| index | index | tab refs |
| onglets | tabs | close, read_page, run_js |
| fenetres | windows | close |
| url_attendue | expected_url | close |
| urls | urls | open, delete_from_reading_list, delete_history |
| nouvelle_fenetre | new_window | open |
| prive | private | open |
| attendre | wait | open, navigate |
| actions / action / url | actions / action / url | navigate |
| format | format | read_page |
| max_caracteres | max_chars | read_page |
| script | script | run_js |
| texte | text | list_tabs, list_reading_list, list_bookmarks, list_history, list_tab_groups, delete_history |
| limite | limit | list_tabs, list_reading_list, list_bookmarks, list_history |
| non_lus | unread_only | list_reading_list |
| apercu (bool) | include_preview | list_reading_list |
| elements | items | add_to_reading_list |
| titre / apercu (item fields) | title / preview | add_to_reading_list |
| dossier | folder | list_bookmarks |
| dossiers (bool) | folders | list_bookmarks |
| domaine | domain | list_history |
| depuis | since | list_history, delete_history |
| jusqu_a | until | list_history, delete_history |
| groupe_id | group_id | list_tab_groups |
| sans_nom (bool) | include_unnamed | list_tab_groups |
| groupe_ids | group_ids | delete_tab_groups |

## Enum values

| Param | French | English |
|---|---|---|
| navigate.action | url / recharger / precedent / suivant / activer | url / reload / back / forward / activate |
| read_page.format | texte / liens / html | text / links / html |

## Output keys

| French | English | Where |
|---|---|---|
| fenetre_id | window_id | tab refs everywhere |
| fenetres | windows | list_tabs (count), close |
| onglets | tabs | list_tabs, open, close, list_tab_groups (group_id) |
| titre | title | most tools |
| actif | active | list_tabs |
| total | total | list_tabs, list_reading_list, list_bookmarks |
| tronque | truncated | list_tabs, read_page, run_js, list_reading_list, list_bookmarks, list_history |
| charge | loaded | open, navigate (wait) |
| resultats | results | navigate, run_js, add_to_reading_list, delete_* |
| resultat | result | run_js |
| erreur | error | per-item errors |
| fermes | closed | close |
| texte | text | read_page (text format, link text) |
| liens | links | read_page |
| total_liens | total_links | read_page |
| longueur | length | read_page |
| elements | items | list_reading_list |
| lu | read | list_reading_list |
| ajoute | added | list_reading_list (date added) |
| apercu | preview | list_reading_list |
| ajoutes | added | add_to_reading_list (count) |
| favoris | bookmarks | list_bookmarks |
| dossiers | folders | list_bookmarks |
| dossier | folder | list_bookmarks |
| nb | count | list_bookmarks (folders) |
| visites | visits | list_history |
| derniere_visite | last_visit | list_history |
| groupes | groups | list_tab_groups |
| groupe_id | group_id | list_tab_groups, delete_tab_groups |
| nom | name | list_tab_groups |
| nb_onglets | tab_count | list_tab_groups |
| sans_nom | unnamed | list_tab_groups |
| ouvert | open | list_tab_groups |
| epingle | pinned | list_tab_groups (tabs) |
| supprimes | deleted | delete_from_reading_list, delete_tab_groups |
| pages_supprimees | pages_deleted | delete_history |
| visites_retirees | visits_removed | delete_history |

## Output values

| French | English | Where |
|---|---|---|
| Favoris (BookmarksBar folder name) | Favorites | list_bookmarks folder paths |
| Menu des signets (BookmarksMenu folder name) | Bookmarks Menu | list_bookmarks folder paths |
| échec | failed | fallback per-item error |

## CLI

| French | English |
|---|---|
| `--accessibilite` | `--accessibility` (stdout now `accessibility: granted` / `accessibility: to enable in …`) |
