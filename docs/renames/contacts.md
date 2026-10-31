# contacts-mcp: French → English renames

## Tools

| French | English |
|---|---|
| groupes | list_groups |
| creer_groupe | create_group |
| modifier_groupe | update_group |
| supprimer_groupe | delete_group |
| contacts | list_contacts |
| creer_contacts | create_contacts |
| modifier_contacts | update_contacts |
| supprimer_contacts | delete_contacts |
| ranger_contacts | organize_contacts |
| doublons | find_duplicates |
| fusionner_contacts | merge_contacts |
| exporter_vcard | export_vcard |
| importer_vcard | import_vcard |

## Tool parameters

| Tool | French | English |
|---|---|---|
| list_groups | nom_contient | name_contains |
| create_group / update_group | nom | name |
| create_group, create_contacts, find_duplicates, import_vcard, list_contacts | compte_id | account_id |
| list_contacts | texte | text |
| list_contacts | dans_notes | in_notes |
| list_contacts | telephone | phone |
| list_contacts, find_duplicates, organize_contacts, export_vcard, import_vcard | groupe_id | group_id |
| list_contacts | ma_carte | my_card |
| list_contacts | selection | selection (unchanged) |
| list_contacts | anniversaires_jours | birthdays_within_days |
| list_contacts | modifies_depuis | modified_since |
| list_contacts | sans | missing |
| list_contacts | detail | detail (unchanged) |
| list_contacts, find_duplicates | limite | limit |
| update_contacts | modifications | updates |
| organize_contacts (operation) | ajouter / retirer | add / remove |
| merge_contacts | cible_id | target_id |
| export_vcard / import_vcard | chemin | path |

## Contact fields (create_contacts, update_contacts input; list_contacts detail output)

| French | English |
|---|---|
| prenom | first_name |
| nom_famille | last_name |
| deuxieme_prenom | middle_name |
| prefixe | prefix |
| suffixe | suffix |
| surnom | nickname |
| nom_naissance | maiden_name |
| prenom_phonetique | phonetic_first_name |
| nom_phonetique | phonetic_last_name |
| societe | organization |
| service | department |
| poste | job_title |
| est_societe | is_company |
| telephones | phones |
| ajouter_telephones / retirer_telephones | add_phones / remove_phones |
| ajouter_emails / retirer_emails | add_emails / remove_emails |
| adresses | addresses |
| anniversaire | birthday |
| anniversaire_autre_calendrier | alternate_birthday |
| relations | related_names |
| reseaux | social_profiles |
| messageries | instant_messages |
| groupe_ids | group_ids |
| emails, urls, dates, photo, note, id | unchanged |

## Sub-object keys

| French | English |
|---|---|
| libelle | label |
| valeur | value |
| rue | street |
| ville | city |
| code_postal | postal_code |
| region | state |
| pays | country |
| code_pays | country_code |
| calendrier | calendar |
| mois / jour / annee | month / day / year |
| nom (related name) | name |
| utilisateur (social profile, instant message) | username |
| service, url, date | unchanged |

## Enum values

| Context | French | English |
|---|---|---|
| list_contacts `missing` | telephone / email | phone / email |
| alternate_birthday `calendar` | chinois / hebreu / islamique / persan | chinese / hebrew / islamic / persian |
| Common labels | domicile / travail / autre / ecole | home / work / other / school |
| Phone labels | mobile / iphone / principal | mobile / iphone / main |
| Phone labels | fax_domicile / fax_travail / bip | home_fax / work_fax / pager |
| Email / URL labels | icloud / page_accueil | icloud / homepage |
| Date label | anniversaire | anniversary |
| Related-name labels | pere / mere / parent / frere / soeur | father / mother / parent / brother / sister |
| Related-name labels | enfant / fils / fille / ami | child / son / daughter / friend |
| Related-name labels | conjoint / partenaire / assistant / manager | spouse / partner / assistant / manager |
| Account `type` (output) | sur_mon_mac / exchange / carddav / inconnu | on_my_mac / exchange / carddav / unknown |
| find_duplicates `reasons` (output) | nom / telephone / email | name / phone / email |
| Boolean string input | oui | yes |

Label aliases also accepted on input: home_page → homepage, fax_home → home_fax, fax_work → work_fax.

## Output keys

| French | English |
|---|---|
| comptes | accounts |
| groupes | groups |
| nom | name |
| nb_contacts | contact_count |
| par_defaut | default |
| nb (group members) | member_count |
| compte_id | account_id |
| avertissement | warning |
| erreur | error |
| resultats | results |
| crees / modifies / supprimes / faits | created / updated / deleted / done |
| echecs | failed |
| tronque | truncated |
| dans_jours | days_until |
| modifie_le | modified_at |
| tel (compact view) | phone |
| societe (compact view) | organization |
| est_societe | is_company |
| ajout / retrait (organize_contacts result) | add / remove |
| doublons | duplicates |
| noms | names |
| raisons | reasons |
| sources_supprimees | deleted_source_ids |
| ajouts | added |
| chemin | path |
| nb (export count) | count |
| octets | bytes |
