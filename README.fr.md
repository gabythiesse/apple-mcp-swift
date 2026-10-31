# apple-mcp-swift — serveurs MCP pour Rappels, Calendrier, Mail, Notes, Contacts et Safari

**Six serveurs MCP natifs en Swift pour piloter Rappels, Calendrier, Mail, Notes, Contacts et Safari. Zéro dépendance. Une seule autorisation macOS.**

[English version](README.md)

Six serveurs [Model Context Protocol](https://modelcontextprotocol.io) qui permettent à Claude, Codex ou n'importe quel client MCP de piloter les apps Apple de ton Mac : créer des rappels avec sous-tâches, trouver un créneau libre, chercher dans tes mails en quelques millisecondes, ranger des notes, fusionner des contacts en double, lire un onglet Safari.

> Les noms d'outils, paramètres et réponses sont en anglais (standard MCP). Tu peux parler français à ton assistant : c'est lui qui choisit les outils.

## Pourquoi celui-ci

- **Une seule autorisation.** Tous les serveurs passent par un lanceur signé unique, `AppleMCP`. Réglages Système affiche un seul interrupteur `AppleMCP`, pas un par serveur, par client ou par recompilation.
- **Vraiment natif.** Sous-tâches, sections, tags et images dans Rappels ; groupes d'onglets dans Safari ; recherche Mail et Notes via leur index local. Ni Node, ni Python, ni SDK MCP : le protocole tient en ~120 lignes de Swift.
- **Prudent par construction.** Suppressions uniquement par identifiant. Rien ne part (mail, invitation, réponse) sans un outil dont le nom le dit. Chaque outil porte les annotations MCP (lecture seule, destructif, effet externe) : le client peut demander avant un appel risqué.

## Installation

Prérequis : macOS 14 ou plus, puce Apple, outils en ligne de commande Xcode (`xcode-select --install`).

```bash
git clone https://github.com/gabythiesse/apple-mcp-swift.git
cd apple-mcp-swift
./installer.command
```

Ou double-clic sur `installer.command` dans le Finder. Quelques minutes la première fois, en 7 étapes :

1. Crée une identité de signature locale « Apple MCP » dans un trousseau dédié.
2. Compile les six serveurs et le lanceur, signés avec cette identité.
3. Demande à macOS de faire confiance au certificat : **ton mot de passe de session, une fois**.
4. Déclare les six serveurs dans l'app Claude et Codex s'ils sont installés (ta config est sauvegardée avant).
5. Appelle chaque serveur une fois : **clique « Autoriser »** à chaque fenêtre `AppleMCP` (Rappels, Calendrier, Contacts, Automatisation).
6. Ouvre **Accès complet au disque** : active `AppleMCP` (Mail lit son index local).
7. Ouvre **Accessibilité** : active `AppleMCP` (fenêtres privées et suppressions dans Safari).

Quitte et relance Claude, puis essaie : *« Montre-moi mes rappels du jour. »*

Pour un autre client MCP : commande `bin/AppleMCP`, argument = nom du serveur (`reminders`, `calendar`, `mail`, `notes`, `contacts`, `safari`). Exemple de config dans le [README anglais](README.md#other-mcp-clients).

## Serveurs et outils

77 outils au total : Rappels (14), Calendrier (11), Mail (12), Notes (13), Contacts (13), Safari (14). La liste détaillée est dans le [README anglais](README.md#servers-and-tools).

## Comment ça marche

- **Un seul processus responsable.** Le lanceur se déclare responsable de lui-même (`responsibility_spawnattrs_setdisclaim`) puis lance le serveur demandé : macOS attribue toutes les autorisations à `AppleMCP`.
- **Signature locale stable.** macOS lie les autorisations à « identifiant + certificat ». Avec un certificat local, les recompilations gardent leurs autorisations.
- **Une voie d'accès par fonction.** Frameworks publics quand ils suffisent, AppleScript in-process sinon, frameworks privés pour ce qu'Apple n'expose pas, SQLite en lecture seule pour la recherche rapide.
- **`sondes/`** contient les petites expériences derrière chaque choix technique, y compris les résultats négatifs.

## Limites

- **Frameworks privés** (ReminderKit, NotesShared, LinkServices) : une mise à jour de macOS peut les casser.
- **Testé sur macOS 26.5 uniquement**, puce Apple uniquement. Compilation sur place obligatoire.
- **Certaines suppressions pilotent les menus de l'app** et ne marchent pour l'instant que sur un Mac **en français** : `delete_mailboxes` (Mail), et dans Safari `delete_history`, `delete_tab_groups`, `delete_from_reading_list`.
- **Les tests touchent tes vraies données** : `*/tests/smoke.py` crée des éléments `MCP-TEST-<horodatage>` dans les vraies apps et vérifie qu'il ne reste rien. Ils n'envoient jamais de mail ni d'invitation.

## FAQ

### Comment connecter Claude à Rappels sur Mac ?
Lance `./installer.command` (voir [Installation](#installation)). Il déclare les serveurs dans l'app Claude et Codex, puis tu demandes à Claude en langage courant : *« Rappelle-moi d'appeler la banque demain à 9 h. »*

### Claude peut-il lire et envoyer des mails avec Apple Mail ?
Oui. `list_messages` et `read_messages` cherchent dans l'index local de Mail, `create_drafts` prépare des mails sans les envoyer, et seul `send` envoie vraiment.

### Ça marche avec d'autres clients MCP que Claude ?
Oui. Tout client MCP en stdio peut appeler le lanceur `AppleMCP` (voir la [version anglaise](README.md#other-mcp-clients)).

### Quelle différence avec les autres serveurs MCP pour Apple ?
Swift natif sans Node ni Python, frameworks privés pour ce qu'AppleScript n'atteint pas (sous-tâches, sections, tags et images de Rappels), et un seul lanceur signé : macOS n'affiche qu'une autorisation `AppleMCP`.

## Licence

[MIT](LICENSE)
