' Lance Syncthing_Tray.ps1 sans aucune fenetre.
' WshShell.Run appelle CreateProcess, qui ne developpe pas les variables
' d'environnement : il faut le faire explicitement, sinon PowerShell recoit
' un chemin contenant %LOCALAPPDATA% en toutes lettres et echoue.
Set WshShell = CreateObject("WScript.Shell")
TrayScript = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%\Syncthing\Syncthing_Tray.ps1")
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & TrayScript & """", 0, False
