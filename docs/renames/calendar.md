# calendar-mcp: French → English renames

Server name: `calendrier` → `calendar`.

## Tools

| French | English |
|---|---|
| `calendriers` | `list_calendars` |
| `creer_calendrier` | `create_calendar` |
| `modifier_calendrier` | `update_calendar` |
| `supprimer_calendrier` | `delete_calendar` |
| `evenements` | `list_events` |
| `creer_evenements` | `create_events` |
| `modifier_evenements` | `update_events` |
| `supprimer_evenements` | `delete_events` |
| `creneaux_libres` | `find_free_slots` |
| `inviter` | `invite` |
| `repondre_invitations` | `respond_to_invitations` |

## Input parameters

| French | English | Where |
|---|---|---|
| `nom_contient` | `name_contains` | list_calendars |
| `nom` | `name` | create/update_calendar, invite attendees |
| `couleur` | `color` | create/update_calendar |
| `compte` | `account` | create_calendar |
| `force` | `force` (unchanged) | delete_calendar |
| `vue` | `view` | list_events |
| `debut` / `fin` | `start` / `end` | list_events, create/update_events, find_free_slots |
| `calendrier_ids` | `calendar_ids` | list_events, find_free_slots |
| `texte` | `text` | list_events |
| `invitations` | `invitations` (unchanged) | list_events (bool), invite (list) |
| `detail` | `detail` (unchanged) | list_events |
| `limite` | `limit` | list_events, find_free_slots |
| `evenements` | `events` | create_events, delete_events |
| `modifications` | `updates` | update_events |
| `titre` | `title` | events |
| `duree_min` | `duration_min` | events, find_free_slots |
| `journee_entiere` | `all_day` | events |
| `fuseau` | `time_zone` | events |
| `lieu` | `location` | events, alarms |
| `disponibilite` | `availability` | events |
| `trajet_min` | `travel_time_min` | events |
| `alertes` | `alarms` | events |
| `calendrier_id` | `calendar_id` | events |
| `pieces_jointes` | `attachments` | create_events |
| `ajouter_pieces_jointes` | `add_attachments` | update_events |
| `portee` | `scope` | update/delete_events, invite, respond_to_invitations |
| `occurrence` | `occurrence` (unchanged) | |
| `heure_debut` / `heure_fin` | `day_start` / `day_end` | find_free_slots |
| `weekend` | `include_weekends` | find_free_slots |
| `invites` | `attendees` | invite |
| `reponses` | `responses` | respond_to_invitations |
| `reponse` | `response` | respond_to_invitations |
| alarm `minutes_avant` | `minutes_before` | |
| alarm `rayon` | `radius` | |
| alarm `quand` | `when` | |
| recurrence `frequence` | `frequency` | |
| recurrence `intervalle` | `interval` | |
| recurrence `jours` | `days` | |
| recurrence `jours_du_mois` | `days_of_month` | |
| recurrence `mois` | `months` | |
| recurrence `fin_le` | `until` | |
| recurrence `positions`, `occurrences` | unchanged | |

## Enum values

| Field | French | English |
|---|---|---|
| `view` | `aujourdhui`, `demain`, `semaine`, `a_venir`, `conflits` | `today`, `tomorrow`, `week`, `upcoming`, `conflicts` |
| `scope` | `cette_occurrence`, `suivantes`, `serie` | `this_occurrence`, `following`, `series` |
| `availability` | `occupe`, `libre`, `provisoire`, `absent` | `busy`, `free`, `tentative`, `unavailable` |
| alarm `when` | `arrivee`, `depart` | `arriving`, `leaving` |
| `frequency` | `jour`, `semaine`, `mois`, `annee` | `daily`, `weekly`, `monthly`, `yearly` |
| `days` | `lundi` … `dimanche` (`2mardi`, `-1vendredi`) | `monday` … `sunday` (`2tuesday`, `-1friday`) |
| `response` (input) | `accepter`, `refuser`, `peut_etre` | `accepted`, `declined`, `tentative` |
| attendee status / `my_response` (output) | `accepte`, `refuse`, `peut_etre`, `en_attente`, `delegue`, `inconnu` | `accepted`, `declined`, `tentative`, `pending`, `delegated`, `unknown` |
| account type (`account`, output) | `sur_mon_mac`, `abonnement`, `anniversaires`, `autre` (`icloud`, `exchange`, `caldav` unchanged) | `on_my_mac`, `subscribed`, `birthdays`, `other` |
| color names | `rouge`, `orange`, `jaune`, `vert`, `bleu`, `violet`, `marron`, `gris`, `rose` | `red`, `orange`, `yellow`, `green`, `blue`, `purple`, `brown`, `gray` (also `grey`), `pink` |
| bool strings | `oui` | `yes` |

## Output keys

| French | English | Where |
|---|---|---|
| `calendriers` | `calendars` | list_calendars |
| `comptes` | `accounts` | list_calendars |
| `nom` | `name` | calendars, accounts, attendees |
| `compte` | `account` | calendars |
| `couleur` | `color` | calendars |
| `lecture_seule` | `read_only` | calendars |
| `par_defaut` | `default` | calendars |
| `evenements` | `events` | list_events |
| `tronque` | `truncated` | list_events |
| `chevauche` | `overlaps` | list_events (view conflicts) |
| `titre` | `title` | events, batch results |
| `jour` | `day` | all-day events |
| `jusqu_au` | `until` | multi-day all-day events |
| `debut` / `fin` | `start` / `end` | events, slots |
| `calendrier` | `calendar` | events |
| `calendrier_id` | `calendar_id` | events (detail) |
| `lieu` | `location` | events, alarms |
| `visio` | `video_call` | events |
| `disponibilite` | `availability` | events |
| `trajet_min` | `travel_time_min` | events |
| `nb_invites` | `attendee_count` | events |
| `ma_reponse` | `my_response` | events |
| `fuseau` | `time_zone` | events (detail) |
| `alertes` | `alarms` | events (detail) |
| `occurrence_modifiee` | `modified_occurrence` | events (detail) |
| `organisateur` | `organizer` | events (detail) |
| `invites` | `attendees` | events (detail), invite result |
| `statut` | `status` | attendees |
| `moi` | `is_me` | attendees |
| `pieces_jointes` | `attachments` | events (detail) |
| `crees` / `modifies` / `supprimes` / `envoyees` | `created` / `updated` / `deleted` / `sent` | batch results (count) |
| `echecs` | `failed` | batch results |
| `resultats` | `results` | batch results |
| `erreur` | `error` | batch item |
| `debut_recale` | `start_adjusted` | create/update_events item |
| `avertissements` | `warnings` | create/update_events item |
| `portee` | `scope` | delete_events item |
| `reponse` | `response` | respond_to_invitations item |
| `creneaux` | `slots` | find_free_slots |
| recurrence and alarm keys | same as input renames above | events (detail) |
