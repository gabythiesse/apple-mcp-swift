# computer-mcp — état au 2026-10-31 (arrêt à un point d'étape)

## Fait (compile, signé, branché dans le lanceur)

- **Module partagé `shared/` (MacUI)** : `AX.swift` (Accessibilité, refs `AXKey`, `normalise`), `Input.swift` (CGEvent :
  clic, glisser, molette, touches, frappe Unicode), `Front.swift` (`Running` : liste d'apps lue à neuf, `Session`, `Front` :
  premier plan par l'AX, rendu à l'app d'avant, pause tant que l'humain tape), `Dialogs.swift` (scan de toutes les alertes,
  feuilles, panneaux open/save-panel, agents système ; réponse par AXPress puis vrai clic ; traductions FR/EN des boutons).
- **Serveur `computer-mcp/`**, 14 outils, tous écrits et essayés à la main :
  screenshot, windows, find, dialogs, click, type, press, scroll, drag, move, answer_dialog, watch_dialogs, app, menu.
  Outils de débogage non listés : `_inspect` (attributs AX d'un élément), `_cg` (fenêtres WindowServer, app focalisée).
- **Lanceur** : `computer` dans `launcher/Sources/AppleMCP/main.swift` ; service « Screen Recording » dans `Permissions.swift`.
  Demande faite une fois (`bin/AppleMCP permissions --request`) : AppleMCP est dans la liste, interrupteur encore éteint.
  Aucune autre permission nouvelle : 10/10 anciennes toujours ✓.
- **Safari** réutilise MacUI : `enum AX` retiré de `Suppressions.swift`, `Native.swift` ne garde que le propre à Safari
  (fenêtre ↔ onglet, zone web, CSS → écran) ; `activer()` passe par `Front` (pause humaine, garde-fou du clavier).
  `Native.dialogues()` existe (feuilles natives de Safari) mais n'est encore appelé nulle part.
- **`tests/smoke.py`** (TextEdit) : dernier passage 17/20 avant les derniers correctifs ; les 3 échecs restants ont été
  corrigés dans le code (attente de 0,5 s des feuilles, focus clavier vérifié, `move` qui amène l'app devant) mais pas re-testés.

## Découvertes à garder

- Dans un processus sans NSApplication, `NSWorkspace.runningApplications`, `frontmostApplication` et les propriétés
  d'un `NSRunningApplication` déjà obtenu restent figés : toujours passer par `Running` (pid → instance neuve).
- Le panneau « Ouvrir » de TextEdit au lancement est une fenêtre standard, `AXIdentifier = open-panel`, contenu servi par
  openAndSavePanelService : détecté par l'identifiant `*-panel`.
- Gaby tapait pendant les tests : quelques frappes de Gaby sont arrivées dans TextEdit (rien des nôtres ailleurs, vérifié
  dans 9 apps). D'où `Front.humanPause()`. Lancer les tests UI quand Gaby n'est pas au clavier.
- Une fenêtre « AppleMCP aimerait contrôler cet ordinateur (Accessibilité) » de universalAccessAuthWarn est ouverte à
  l'écran, antérieure à ce travail (l'Accessibilité est pourtant ✓) : fenêtre de confidentialité, à fermer par Gaby.

## Reste à faire (ordre du brief)

1. Re-lancer `python3 -I computer-mcp/tests/smoke.py` (Gaby absent du clavier) jusqu'à ✓ ALL OK ; noter les durées médianes.
2. Brancher `Native.dialogues()` dans les résultats des actions Safari (click, type, press, act, select, check) :
   champ `safari_dialogs` + rappel « answer with the computer server's answer_dialog ». Puis rebuild Safari
   (`./build.sh safari-mcp`) et `python3 -I safari-mcp/tests/smoke.py` : le refactor n'a pas encore été testé en réel.
3. Scénario réel : Safari réglé sur « demander pour chaque téléchargement » (via les outils : menu Safari > Réglages…,
   Général, popup « Emplacement de téléchargement des fichiers »), `watch_dialogs` avec [Autoriser] puis [Enregistrer],
   page https://www.w3.org/ + lien same-origin `download` vers le PDF dummy, vérifier le fichier sur disque, le supprimer,
   remettre le réglage d'origine. Zéro intervention.
4. Screenshot réel : attend que Gaby allume AppleMCP dans Réglages > Confidentialité > Enregistrement de l'écran.
   Vérifier aussi la fenêtre périodique de macOS 15+ (« continuer à autoriser ? ») et le dire dans le rapport.
5. Docs : `docs/permissions.md` (ligne Screen Recording + preuve dans le code, Accessibilité étendue à computer),
   `installer.command` (liste `names`, texte « seven servers », étape 5), `scripts/smoke-all.sh` (computer via le lanceur),
   README (section Computer, tableau, badge 90 → 104 outils, noms de serveurs, schéma) et README.fr.md.
6. Commits par groupe demandés par le brief : tout est dans un seul commit d'étape ; découper n'a plus de sens après coup,
   les commits suivants seront par sujet (Safari dialogues, docs, scénario).
7. Rapport final : outils, durées médianes, ce qui ne marche pas et pourquoi, permissions nouvelles (Screen Recording seule).

## Reprendre

```bash
./build.sh computer-mcp && ./build.sh launcher
python3 -I computer-mcp/tests/smoke.py
```
