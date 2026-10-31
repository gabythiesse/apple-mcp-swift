# reminders-mcp: French → English renames

Server name: `rappels` → `reminders`.

## Tools

| French | English |
|---|---|
| `listes` | `list_lists` |
| `creer_liste` | `create_list` |
| `modifier_liste` | `update_list` |
| `supprimer_liste` | `delete_list` |
| `sections` | `list_sections` |
| `creer_section` | `create_section` |
| `supprimer_section` | `delete_section` |
| `rappels` | `list_reminders` |
| `creer_rappels` | `create_reminders` |
| `modifier_rappels` | `update_reminders` |
| `terminer_rappels` | `complete_reminders` |
| `supprimer_rappels` | `delete_reminders` |
| `ajouter_image` | `add_image` |
| `tags` | `list_tags` |

## Input parameters

| French | English | Where |
|---|---|---|
| `nom_contient` | `name_contains` | list_lists |
| `nom` | `name` | create_list, update_list, create_section |
| `couleur` | `color` | create_list, update_list |
| `groupe` | `group` | create_list |
| `groupe_id` | `group_id` | create_list, update_list |
| `force` | `force` | delete_list |
| `liste_id` | `list_id` | sections, reminders |
| `liste_ids` | `list_ids` | list_reminders, list_tags |
| `vue` | `view` | list_reminders |
| `statut` | `status` | list_reminders, list_tags |
| `texte` | `text` | list_reminders |
| `drapeau` | `flagged` | list_reminders, reminder fields |
| `echeance_avant` | `due_before` | list_reminders |
| `echeance_apres` | `due_after` | list_reminders |
| `sans_echeance` | `no_due` | list_reminders |
| `limite` | `limit` | list_reminders |
| `rappels` (array) | `reminders` | create_reminders |
| `modifications` (array) | `updates` | update_reminders |
| `termine` | `completed` | complete_reminders |
| `chemin` | `path` | add_image |
| `titre` | `title` | reminder fields |
| `echeance` | `due` | reminder fields |
| `debut` | `start` | reminder fields |
| `priorite` | `priority` | reminder fields |
| `alarmes` | `alarms` | reminder fields |
| `sous_taches` | `subtasks` | create_reminders |
| `ajouter_tags` | `add_tags` | update_reminders |
| `retirer_tags` | `remove_tags` | update_reminders |
| `minutes_avant` | `minutes_before` | alarm |
| `lieu` | `location` | alarm |
| `rayon` | `radius` | alarm |
| `quand` | `when` | alarm |
| `frequence` | `frequency` | recurrence |
| `intervalle` | `interval` | recurrence |
| `jours` | `days` | recurrence |
| `fin_le` | `until` | recurrence |

Unchanged: `id`, `ids`, `notes`, `url`, `section_id`, `parent_id`, `tags`, `tag`, `recurrence`, `date`, `latitude`, `longitude`, `occurrences`.

## Enum values

| Field | French | English |
|---|---|---|
| `priority` | `haute` / `moyenne` / `basse` / `aucune` | `high` / `medium` / `low` / `none` (`!!!`, `!!`, `!` still accepted) |
| `view` | `aujourdhui` / `en_retard` / `semaine` / `programmes` / `drapeau` / `termines_recents` | `today` / `overdue` / `week` / `scheduled` / `flagged` / `recently_completed` |
| `status` | `a_faire` / `termines` / `tous` | `incomplete` / `completed` / `all` |
| alarm `when` | `arrivee` / `depart` | `arrival` / `departure` |
| `frequency` | `jour` / `semaine` / `mois` / `annee` | `daily` / `weekly` / `monthly` / `yearly` |
| `days` | `lundi` … `dimanche` | `monday` … `sunday` |
| `color` names | `rouge`, `orange`, `jaune`, `vert`, `bleu`, `violet`, `marron`, `gris`, `rose` | `red`, `orange`, `yellow`, `green`, `blue`, `purple`, `brown`, `gray` (also `grey`), `pink` |
| boolean strings | `oui` | `yes` (`true`, `1` unchanged) |

## Output keys

| French | English | Where |
|---|---|---|
| `listes` | `lists` | list_lists |
| `nom` | `name` | lists, sections, write results |
| `compte` | `account` | list_lists |
| `couleur` | `color` | list_lists |
| `groupe` | `group` | list_lists, create_list, delete_list |
| `groupe_id` | `group_id` | list_lists, create_list |
| `nb_a_faire` | `incomplete_count` | list_lists |
| `par_defaut` | `default` | list_lists |
| `avertissement` | `warning` | create_list, create_reminders |
| `supprime` | `deleted` | delete_list, delete_section |
| `rappels_supprimes` | `deleted_reminders` | delete_list |
| `liste_id` | `list_id` | list_sections, create_section, reminder |
| `rappels` | `reminders` | list_reminders |
| `tronque` | `truncated` | list_reminders |
| `titre` | `title` | reminder, write results |
| `liste` | `list` | reminder |
| `termine` | `completed` | reminder |
| `termine_le` | `completed_at` | reminder |
| `echeance` | `due` | reminder |
| `debut` | `start` | reminder |
| `priorite` | `priority` | reminder |
| `alarmes` | `alarms` | reminder |
| `drapeau` | `flagged` | reminder |
| `nb_sous_taches` | `subtask_count` | reminder |
| `crees` | `created` | create_reminders |
| `modifies` | `updated` | update_reminders |
| `echecs` | `failed` | create_reminders, update_reminders |
| `resultats` | `results` | batch writes |
| `erreur` | `error` | batch writes |
| `sous_taches` | `subtasks` | create_reminders |
| `sous_taches_supprimees` | `deleted_subtasks` | delete_reminders |
| `largeur` / `hauteur` | `width` / `height` | add_image |
| `nb` | `count` | list_tags |
| alarm: `minutes_avant`, `lieu`, `rayon`, `quand` | `minutes_before`, `location`, `radius`, `when` | reminder alarms |
| recurrence: `frequence`, `intervalle`, `jours`, `fin_le` | `frequency`, `interval`, `days`, `until` | reminder recurrence |

Unchanged output keys: `id`, `ok`, `total`, `sections`, `section`, `section_id`, `parent_id`, `tags`, `tag`, `url`, `images`, `image`, `notes`, `recurrence`.

## Choices outside the shared glossary

- Plain-noun read tools take a `list_` prefix: `listes` → `list_lists`, `sections` → `list_sections`, `tags` → `list_tags`.
- `nom_contient` → `name_contains`, `sans_echeance` → `no_due`, `modifications` → `updates`, `chemin` → `path`, `vue` → `view`, `statut` → `status`.
- `a_faire` → `incomplete` (matches EventKit's naming), `programmes` → `scheduled` (the Reminders app's name for that view).
- French color names, priorities and `oui` are no longer accepted (English only).
