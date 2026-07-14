# Design — `syncthing-config` : installeur Syncthing one-liner

Date : 2026-07-14
Statut : validé (brainstorming), en attente de plan d'implémentation

## Problème

Ahmed possède un kit Syncthing « propre » (icône dans la zone de notification, thèmes GUI
personnalisés, lancement au démarrage) constitué à la main dans
`C:\Users\Ahmed\Downloads\SYNCTHING`. Le partager suppose aujourd'hui une procédure manuelle
en six étapes (copier des fichiers dans `%LOCALAPPDATA%\Syncthing`, dézipper les thèmes,
créer un raccourci via `shell:startup`, poser une icône sur le bureau).

Objectif : une personne n'ayant jamais installé Syncthing obtient ce même setup en une seule
commande :

```powershell
irm https://ahmed-mili.github.io/syncthing-config/install.ps1 | iex
```

## Périmètre

**Dans le périmètre** — la distribution du *setup* :

- Téléchargement et installation du binaire officiel `syncthing.exe`.
- Le script de zone de notification (tray), son lanceur silencieux, l'icône.
- Les deux thèmes GUI personnalisés.
- Les raccourcis Démarrage et Bureau.
- La génération d'une identité Syncthing **neuve, propre à la machine cible**.

**Hors périmètre** — l'identité et la topologie d'Ahmed :

`config.xml`, `cert.pem` et `key.pem` constituent l'identité cryptographique d'une machine
Syncthing. Les publier permettrait à quiconque d'usurper la machine d'Ahmed, et deux machines
partageant un même device ID ne peuvent de toute façon pas se synchroniser entre elles. Le
repo ne contient donc **aucun** de ces fichiers, ni les device IDs des appareils d'Ahmed, ni
les chemins de ses dossiers synchronisés. Chaque installation génère sa propre identité et
appaire ses appareils elle-même.

## Architecture

### Dépôt `ahmed-mili/syncthing-config` (public, GitHub Pages sur la branche `main`, racine)

```
install.ps1              installeur — cible du one-liner
index.html               page GitHub Pages : affiche la commande à copier
README.md                installation, contenu, désinstallation
payload/
  Syncthing_Tray.ps1     script tray (corrigé, cf. « Correctifs »)
  SyncthingTray.vbs      lanceur silencieux (corrigé)
  syncthing.ico          icône des raccourcis
  gui/
    mountain theme/assets/css/theme.css      thème sombre (fond MontagneNuit.jpg)
    mountain theme/assets/img/MontagneNuit.jpg
    mountain light/assets/css/theme.css      thème clair (fond MontagneJour.jpg)
    mountain light/assets/img/MontagneJour.jpg
```

Le kit d'origine contenait trois thèmes, dont `radius dark` et `radius dark 2` avec un
`theme.css` strictement identique (hash SHA-256 identique). Le doublon est supprimé ;
`radius dark 2` devient `mountain theme` et `radius light` devient `mountain light`. Les CSS
référencent leurs images en chemin relatif (`../img/…`), le renommage des dossiers est donc
sans effet de bord ; seul le commentaire d'en-tête de chaque `theme.css` est mis à jour.

Nom de thème affiché dans l'interface Syncthing = nom du dossier. Les deux thèmes restent
sélectionnables dans Actions > Settings > GUI Theme.

### Cible de l'installation (machine de l'utilisateur)

Tout se fait en espace utilisateur, **sans droits administrateur** :

```
%LOCALAPPDATA%\Syncthing\
  syncthing.exe          binaire officiel
  Syncthing_Tray.ps1
  SyncthingTray.vbs
  syncthing.ico
  config.xml             généré localement au premier passage
  cert.pem / key.pem     identité locale, jamais versionnée
  gui\mountain theme\…
  gui\mountain light\…

%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Syncthing.lnk
%USERPROFILE%\Desktop\Syncthing.lnk
```

## Déroulé de `install.ps1`

1. **Garde-fous** : Windows uniquement, PowerShell 5.1 ou 7+, TLS 1.2 forcé (nécessaire pour
   les appels HTTPS sous PowerShell 5.1). Si un processus `syncthing` tourne déjà, l'arrêter
   proprement (API REST `/rest/system/shutdown`, sinon `Kill`) avant de remplacer le binaire.
2. **Binaire** : interroger l'API GitHub `syncthing/syncthing/releases/latest`, sélectionner
   l'asset correspondant à l'architecture (`amd64` ou `arm64` selon `PROCESSOR_ARCHITECTURE`),
   télécharger l'archive, **vérifier son SHA-256** contre le `sha256sum.txt` de la release,
   extraire `syncthing.exe` vers `%LOCALAPPDATA%\Syncthing`.
3. **Payload** : télécharger l'archive du repo
   (`https://github.com/ahmed-mili/syncthing-config/archive/refs/heads/main.zip`, une seule
   requête), en extraire `payload/` vers `%LOCALAPPDATA%\Syncthing`.
4. **Identité** : si `config.xml` est absent, la générer localement (sous-commande
   `syncthing generate --home`, à confirmer à l'exécution ; sinon, démarrage bref du binaire
   puis arrêt). Si `config.xml` existe, ne rien régénérer.
5. **Thème** : patcher `config.xml` pour que `configuration/gui/theme` vaille `mountain theme`.
   Le patch écrit uniquement ce nœud et ne touche à aucun autre réglage.
6. **Raccourcis** : créer `Syncthing.lnk` dans le dossier Démarrage et sur le Bureau, ciblant
   `wscript.exe "…\SyncthingTray.vbs"` avec `syncthing.ico` comme icône.
7. **Lancement** : démarrer le tray, puis afficher l'URL de l'interface web et le device ID
   généré, pour que l'utilisateur puisse immédiatement appairer ses machines.

**Idempotence** : relancer le one-liner met à jour le binaire, les thèmes et les scripts, sans
jamais toucher à `config.xml` au-delà du nœud `theme`, ni à `cert.pem` / `key.pem`, ni aux
dossiers déjà synchronisés.

## Correctifs sur le kit d'origine

Trois défauts constatés dans les fichiers de `Downloads\SYNCTHING`, corrigés dans le payload :

1. **`SyncthingTray.vbs` ne peut pas fonctionner tel quel.** Il passe
   `"%LOCALAPPDATA%\Syncthing\Syncthing_Tray.ps1"` à `WshShell.Run`, qui appelle `CreateProcess`
   sans développer les variables d'environnement (contrairement à `cmd.exe`). PowerShell reçoit
   donc un chemin littéral contenant `%LOCALAPPDATA%` et ne trouve pas le fichier.
   Correction : `WshShell.ExpandEnvironmentStrings(…)` avant l'appel.
2. **`Syncthing_Tray.ps1` ouvre `https://127.0.0.1:8384`** alors que Syncthing sert son
   interface en clair (`http`) tant que l'attribut `tls` du nœud `gui` vaut `false`, ce qui est
   le défaut d'une installation neuve. L'entrée « Ouvrir interface Web » aboutirait à une erreur
   de connexion. Correction : lire `configuration/gui/@tls` dans `config.xml` et construire le
   schéma d'URL en conséquence (idem pour l'appel REST d'arrêt).
3. **Le tray relance un `syncthing.exe` même si un autre tourne déjà.** Correction : ne démarrer
   le processus que si aucun `syncthing` n'est actif.

Le reste du script (menu contextuel, arrêt par API REST puis `Kill` de secours) est conservé.

## Points à vérifier empiriquement, non supposés

- **Type MIME servi par GitHub Pages pour un `.ps1`.** `Invoke-RestMethod` retourne un
  `byte[]` (et non une chaîne) lorsque le type de contenu n'est pas textuel, ce qui ferait
  échouer `| iex`. Si Pages sert `install.ps1` en `application/octet-stream`, le one-liner
  devra basculer sur `raw.githubusercontent.com` (qui sert du `text/plain`), au prix d'une URL
  plus longue. À tester réellement après activation de Pages, avant toute annonce.
- **Existence et comportement de `syncthing generate --home`** dans la version téléchargée.
- **Nom exact des assets de release** (`syncthing-windows-amd64-vX.Y.Z.zip`) et présence d'un
  fichier de sommes de contrôle exploitable sans GPG.

## Critères de succès

Sur une machine sans aucune trace de Syncthing (le PC de développement actuel remplit cette
condition : ni `%LOCALAPPDATA%\Syncthing`, ni processus, ni port 8384) :

1. La commande unique s'exécute sans erreur ni prompt administrateur.
2. `syncthing.exe` est présent et sa somme de contrôle correspond à la release officielle.
3. L'icône Syncthing apparaît dans la zone de notification ; « Ouvrir interface Web » ouvre
   l'interface ; « Quitter Syncthing » arrête bien le processus.
4. L'interface s'affiche avec le thème `mountain theme`, et `mountain light` est proposé dans
   Settings > GUI Theme.
5. Les raccourcis existent dans le dossier Démarrage et sur le Bureau, avec l'icône Syncthing.
6. Un device ID a été généré et est affiché en fin d'installation.
7. Relancer la commande une seconde fois ne casse rien et conserve le device ID.
8. Le repo ne contient ni `config.xml`, ni `cert.pem`, ni `key.pem`, ni aucun device ID.
