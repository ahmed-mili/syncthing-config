<#
.SYNOPSIS
    Installe Syncthing sur Windows, avec icone dans la zone de notification,
    themes personnalises et demarrage automatique.

.DESCRIPTION
    irm https://ahmed-mili.github.io/syncthing-config/install.ps1 | iex

    Aucun droit administrateur requis : tout est installe dans
    %LOCALAPPDATA%\Syncthing. Le binaire provient des releases officielles
    syncthing/syncthing et sa somme de controle SHA-256 est verifiee.

    L'identite Syncthing (device ID, cert.pem, key.pem) est generee localement :
    elle n'est jamais telechargee et n'appartient qu'a cette machine.

    Relancer la commande met a jour le binaire, les scripts et les themes sans
    toucher a l'identite ni aux dossiers deja synchronises.

.PARAMETER Source
    Origine du payload (scripts, icone, themes). Par defaut, l'archive de la
    branche main du depot. Accepte aussi un chemin local (copie de travail).

.PARAMETER Theme
    Theme applique par defaut. Les deux themes restent selectionnables dans
    Actions > Settings > GUI Theme.
#>
[CmdletBinding()]
param(
    [string]$Source = 'https://github.com/ahmed-mili/syncthing-config/archive/refs/heads/main.zip',
    [string]$Theme  = 'mountain theme'
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Dest    = Join-Path $env:LOCALAPPDATA 'Syncthing'
$Work    = Join-Path ([IO.Path]::GetTempPath()) ("syncthing-config-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$Headers = @{ 'User-Agent' = 'syncthing-config-installer' }

function Write-Step($Message) { Write-Host "  $Message" -ForegroundColor Cyan }
function Write-Done($Message) { Write-Host "  $Message" -ForegroundColor Green }

# Invoke-WebRequest renvoie un byte[] et non une chaine lorsque le type MIME
# n'est pas textuel, ce qui est le cas de sha256sum.txt.asc (octet-stream).
function Get-RemoteText($Uri, $Headers) {
    $content = (Invoke-WebRequest -Uri $Uri -Headers $Headers -UseBasicParsing).Content
    if ($content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($content) }
    return $content
}

Write-Host ""
Write-Host "  Installation de Syncthing" -ForegroundColor White
Write-Host "  -------------------------" -ForegroundColor DarkGray

# --- Garde-fous ---------------------------------------------------------------

if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw "PowerShell 5.1 ou superieur est requis (version detectee : $($PSVersionTable.PSVersion))."
}
if ($env:OS -ne 'Windows_NT') {
    throw "Cet installeur cible Windows uniquement."
}

$archRaw = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$arch = switch ($archRaw) {
    'AMD64' { 'amd64' }
    'ARM64' { 'arm64' }
    'x86'   { '386' }
    default { throw "Architecture non supportee : $archRaw" }
}

New-Item -ItemType Directory -Force -Path $Dest, $Work | Out-Null

try {
    # --- Arret de l'instance en cours -----------------------------------------
    # Necessaire avant de remplacer syncthing.exe, et evite une icone orpheline.

    $trayProcs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
                 Where-Object { $_.CommandLine -like '*Syncthing_Tray.ps1*' }
    $running = @(Get-Process -Name 'syncthing' -ErrorAction SilentlyContinue) + @($trayProcs | ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })

    if ($running.Count -gt 0) {
        Write-Step "Arret de l'instance Syncthing en cours..."
        $running | ForEach-Object { try { $_.Kill(); [void]$_.WaitForExit(5000) } catch {} }
    }

    # --- Binaire officiel + verification SHA-256 ------------------------------

    Write-Step "Recherche de la derniere version officielle..."
    $release   = Invoke-RestMethod -Uri 'https://api.github.com/repos/syncthing/syncthing/releases/latest' -Headers $Headers
    $tag       = $release.tag_name
    $assetName = "syncthing-windows-$arch-$tag.zip"

    $asset = $release.assets | Where-Object { $_.name -eq $assetName }
    $sums  = $release.assets | Where-Object { $_.name -eq 'sha256sum.txt.asc' }
    if (-not $asset) { throw "Aucun binaire $assetName dans la release $tag." }

    Write-Step "Telechargement de Syncthing $tag ($arch)..."
    $zipPath = Join-Path $Work $assetName
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -Headers $Headers -UseBasicParsing

    if ($sums) {
        Write-Step "Verification de la somme de controle SHA-256..."
        $sumsText = Get-RemoteText -Uri $sums.browser_download_url -Headers $Headers
        $pattern  = '(?im)^([0-9a-f]{64})\s+\*?' + [regex]::Escape($assetName) + '\s*$'
        $match    = [regex]::Match($sumsText, $pattern)
        if (-not $match.Success) { throw "Somme de controle introuvable pour $assetName." }

        $expected = $match.Groups[1].Value
        $actual   = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
        if ($actual -ne $expected.ToUpper()) {
            throw "Somme de controle invalide. Attendu $expected, obtenu $actual. Telechargement abandonne."
        }
        Write-Done "Binaire authentifie."
    } else {
        Write-Warning "Fichier de sommes de controle absent de la release : verification impossible."
    }

    Expand-Archive -Path $zipPath -DestinationPath (Join-Path $Work 'bin') -Force
    $exeSource = Get-ChildItem -Path (Join-Path $Work 'bin') -Filter 'syncthing.exe' -Recurse | Select-Object -First 1
    if (-not $exeSource) { throw "syncthing.exe introuvable dans l'archive." }
    Copy-Item -Path $exeSource.FullName -Destination (Join-Path $Dest 'syncthing.exe') -Force

    # --- Payload : tray, icone, themes ----------------------------------------

    Write-Step "Installation de l'icone, du tray et des themes..."
    if ($Source -match '^https?://') {
        $payloadZip = Join-Path $Work 'payload.zip'
        Invoke-WebRequest -Uri $Source -OutFile $payloadZip -Headers $Headers -UseBasicParsing
        Expand-Archive -Path $payloadZip -DestinationPath (Join-Path $Work 'payload') -Force
        $root = Get-ChildItem -Path (Join-Path $Work 'payload') -Directory | Select-Object -First 1
        $payloadDir = Join-Path $root.FullName 'payload'
    } else {
        $payloadDir = Join-Path $Source 'payload'
    }
    if (-not (Test-Path $payloadDir)) { throw "Payload introuvable : $payloadDir" }

    Copy-Item -Path (Join-Path $payloadDir '*') -Destination $Dest -Recurse -Force

    # --- Identite locale ------------------------------------------------------

    $configXml = Join-Path $Dest 'config.xml'
    if (-not (Test-Path $configXml)) {
        Write-Step "Generation de l'identite de cette machine (device ID, cles)..."
        & (Join-Path $Dest 'syncthing.exe') generate --home $Dest | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Echec de la generation de la configuration (code $LASTEXITCODE)." }
    } else {
        Write-Step "Configuration existante conservee (identite et dossiers intacts)."
    }

    # --- Theme par defaut et navigateur silencieux ----------------------------
    # L'icone de notification suffit : Syncthing ne doit pas ouvrir le navigateur
    # a chaque ouverture de session. Le flag --no-browser du tray ne suffit pas,
    # l'option startBrowser de la config s'applique aussi aux autres lancements.

    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.Load($configXml)

    $guiNode = $xml.SelectSingleNode('/configuration/gui')
    if ($guiNode) {
        $themeNode = $guiNode.SelectSingleNode('theme')
        if (-not $themeNode) {
            $themeNode = $xml.CreateElement('theme')
            $guiNode.AppendChild($themeNode) | Out-Null
        }
        $themeNode.InnerText = $Theme
        Write-Done "Theme applique : $Theme"
    }

    $optionsNode = $xml.SelectSingleNode('/configuration/options')
    if ($optionsNode) {
        $startBrowserNode = $optionsNode.SelectSingleNode('startBrowser')
        if (-not $startBrowserNode) {
            $startBrowserNode = $xml.CreateElement('startBrowser')
            $optionsNode.AppendChild($startBrowserNode) | Out-Null
        }
        $startBrowserNode.InnerText = 'false'
        Write-Done "Ouverture automatique du navigateur desactivee."
    }

    $xml.Save($configXml)

    # --- Raccourcis Demarrage et Bureau ---------------------------------------

    Write-Step "Creation des raccourcis (demarrage automatique et bureau)..."
    $shell   = New-Object -ComObject WScript.Shell
    $vbsPath = Join-Path $Dest 'SyncthingTray.vbs'
    $targets = @(
        (Join-Path ([Environment]::GetFolderPath('Startup')) 'Syncthing.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Syncthing.lnk')
    )
    foreach ($lnkPath in $targets) {
        $lnk = $shell.CreateShortcut($lnkPath)
        $lnk.TargetPath       = Join-Path $env:WINDIR 'System32\wscript.exe'
        $lnk.Arguments        = '"' + $vbsPath + '"'
        $lnk.WorkingDirectory = $Dest
        $lnk.IconLocation     = Join-Path $Dest 'syncthing.ico'
        $lnk.Description      = 'Syncthing'
        $lnk.Save()
    }

    # --- Lancement ------------------------------------------------------------

    Write-Step "Demarrage de Syncthing..."
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList "`"$vbsPath`""

    $deviceId = (& (Join-Path $Dest 'syncthing.exe') device-id --home $Dest) | Select-Object -First 1

    $cfg     = [xml](Get-Content $configXml)
    $address = if ($cfg.configuration.gui.address) { $cfg.configuration.gui.address } else { '127.0.0.1:8384' }
    $scheme  = if ($cfg.configuration.gui.tls -eq 'true') { 'https' } else { 'http' }
    $guiUrl  = "${scheme}://${address}/"

    Write-Host ""
    Write-Done "Syncthing $tag est installe et lance."
    Write-Host ""
    Write-Host "  Interface      $guiUrl" -ForegroundColor White
    Write-Host "  Device ID      $deviceId" -ForegroundColor White
    Write-Host "  Dossier        $Dest" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  L'icone Syncthing est dans la zone de notification : clic droit pour ouvrir" -ForegroundColor DarkGray
    Write-Host "  l'interface ou quitter, double-clic pour ouvrir l'interface." -ForegroundColor DarkGray
    Write-Host "  Communiquez votre Device ID a l'autre machine pour appairer vos appareils." -ForegroundColor DarkGray
    Write-Host ""
}
finally {
    Remove-Item -Path $Work -Recurse -Force -ErrorAction SilentlyContinue
}
