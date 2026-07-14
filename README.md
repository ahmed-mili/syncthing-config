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
5. Crée un raccourci dans le dossier Démarrage (lancement automatique à l'ouverture de session,
   sans fenêtre) et un raccourci sur le Bureau.
6. Lance Syncthing et ouvre l'interface.

Relancer la commande met à jour le binaire, les scripts et les thèmes, **sans toucher** à
l'identité de la machine ni aux dossiers déjà synchronisés.

## Contenu

| Fichier | Rôle |
|---|---|
| `install.ps1` | L'installeur, cible du one-liner. |
| `payload/Syncthing_Tray.ps1` | Icône dans la zone de notification : ouvrir l'interface, quitter Syncthing. |
| `payload/SyncthingTray.vbs` | Lance le script précédent sans aucune fenêtre. |
| `payload/syncthing.ico` | Icône des raccourcis. |
| `payload/gui/mountain theme/` | Thème sombre (appliqué par défaut). |
| `payload/gui/mountain light/` | Thème clair. |

Les deux thèmes restent sélectionnables dans **Actions > Configuration > Interface graphique**.
Syncthing sert toujours le thème actif à la même adresse (`assets/css/theme.css`) : après un
changement de thème, faites **Ctrl+F5** dans le navigateur, sinon l'ancien reste en cache.

## Vie privée

Ce dépôt ne contient **aucune identité Syncthing** : ni `config.xml`, ni `cert.pem`, ni
`key.pem`, ni device ID. Ces fichiers sont l'identité cryptographique d'une machine ; les
partager permettrait de l'usurper, et deux machines portant le même device ID ne peuvent de
toute façon pas se synchroniser entre elles. Chaque installation génère la sienne, localement.

## Désinstallation

```powershell
# Quitter Syncthing par l'icône de la zone de notification, puis :
Remove-Item "$env:LOCALAPPDATA\Syncthing" -Recurse -Force
Remove-Item "$([Environment]::GetFolderPath('Startup'))\Syncthing.lnk" -Force
Remove-Item "$([Environment]::GetFolderPath('Desktop'))\Syncthing.lnk" -Force
```

## Licence

Les scripts de ce dépôt sont fournis tels quels. Syncthing est distribué séparément par ses
auteurs sous licence MPL-2.0 ; ce dépôt ne redistribue pas son binaire, il le télécharge depuis
les releases officielles.
