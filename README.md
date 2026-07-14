# syncthing-config

Installation de [Syncthing](https://syncthing.net/) sur Windows en une seule commande :
binaire officiel, icône dans la zone de notification, thèmes personnalisés et démarrage
automatique.

## Installation

Ouvrir PowerShell (aucun droit administrateur nécessaire) et coller :

```powershell
irm https://ahmed-mili.github.io/syncthing-config/install.ps1 | iex
```

C'est tout. À la fin, l'installeur affiche l'adresse de l'interface web et le **device ID**
de la machine, à communiquer à l'appareil avec lequel vous voulez vous synchroniser.

## Ce que fait l'installeur

1. Télécharge la dernière version officielle de `syncthing.exe` depuis les releases
   [syncthing/syncthing](https://github.com/syncthing/syncthing/releases) (amd64, arm64 ou 386
   selon la machine) et **vérifie sa somme de contrôle SHA-256**.
2. Installe le tout dans `%LOCALAPPDATA%\Syncthing` : binaire, script de zone de notification,
   icône et thèmes.
3. Génère l'identité Syncthing de la machine (device ID, `cert.pem`, `key.pem`).
4. Applique le thème `mountain theme`.
5. Crée la tâche planifiée **Syncthing Tray**, qui lance l'icône de notification à l'ouverture
   de session, sans aucune fenêtre, et un raccourci sur le Bureau pour relancer Syncthing après
   l'avoir quitté.
6. Lance Syncthing et ouvre l'interface.

Relancer la commande met à jour le binaire, les scripts et les thèmes, **sans toucher** à
l'identité de la machine ni aux dossiers déjà synchronisés.

## Contenu

| Fichier | Rôle |
|---|---|
| `install.ps1` | L'installeur, cible du one-liner. |
| `payload/Syncthing_Tray.ps1` | Icône dans la zone de notification : ouvrir l'interface, quitter Syncthing. |
| `payload/syncthing.ico` | Icône des raccourcis. |
| `payload/gui/mountain theme/` | Thème sombre (appliqué par défaut). |
| `payload/gui/mountain light/` | Thème clair. |

Les deux thèmes restent sélectionnables dans **Actions > Configuration > Interface graphique**.
Syncthing sert toujours le thème actif à la même adresse (`assets/css/theme.css`) : après un
changement de thème, faites **Ctrl+F5** dans le navigateur, sinon l'ancien reste en cache.

## Démarrage sans fenêtre

L'icône de notification est un script PowerShell, et PowerShell est un programme console :
lancé naïvement, il ouvre une fenêtre noire à chaque ouverture de session. Le lanceur est donc
`conhost.exe --headless`, qui démarre PowerShell dans une pseudo-console **sans aucune fenêtre**.

Les autres approches ont toutes été écartées, mesures à l'appui :

| Approche | Verdict |
|---|---|
| `conhost --headless` (retenue) | Aucune fenêtre, aucune console créée. Natif Windows, aucune dépendance. |
| Raccourci vers `powershell -WindowStyle Hidden` | Un raccourci Windows ne sait pas lancer « masqué », seulement « réduit » : la console est créée puis cachée, d'où un clignotement possible. |
| Lanceur VBScript (`wscript.exe`) | Utilisé jusqu'ici. Fonctionne, mais VBScript est **déprécié par Microsoft** et `wscript.exe` est ciblé par les règles ASR de Defender. |
| AutoHotkey | Ajoute un interpréteur tiers, hors AMSI et souvent signalé par les antivirus. Aucun gain. |

Le démarrage automatique passe par une **tâche planifiée** plutôt que par un raccourci dans le
dossier Démarrage : elle s'inventorie d'une seule commande (`Get-ScheduledTask`). L'option
`-ExecutionPolicy Bypass` n'est pas décorative : sans elle, la tâche se termine sur le code
`0x1` sans jamais lancer le script.

## Vie privée

Ce dépôt ne contient **aucune identité Syncthing** : ni `config.xml`, ni `cert.pem`, ni
`key.pem`, ni device ID. Ces fichiers sont l'identité cryptographique d'une machine ; les
partager permettrait de l'usurper, et deux machines portant le même device ID ne peuvent de
toute façon pas se synchroniser entre elles. Chaque installation génère la sienne, localement.

## Désinstallation

```powershell
# Quitter Syncthing par l'icône de la zone de notification, puis :
Unregister-ScheduledTask -TaskName "Syncthing Tray" -Confirm:$false
Remove-Item "$env:LOCALAPPDATA\Syncthing" -Recurse -Force
Remove-Item "$([Environment]::GetFolderPath('Desktop'))\Syncthing.lnk" -Force
```

## Licence

Les scripts de ce dépôt sont fournis tels quels. Syncthing est distribué séparément par ses
auteurs sous licence MPL-2.0 ; ce dépôt ne redistribue pas son binaire, il le télécharge depuis
les releases officielles.
