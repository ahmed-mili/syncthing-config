# Icone Syncthing dans la zone de notification.
# Lance par SyncthingTray.vbs (sans fenetre). Compatible Windows PowerShell 5.1.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SyncthingHome = "$env:LOCALAPPDATA\Syncthing"
$SyncthingExe  = "$SyncthingHome\syncthing.exe"
$ConfigXml     = "$SyncthingHome\config.xml"
$IconFile      = "$SyncthingHome\syncthing.ico"

# L'interface est servie en clair tant que gui@tls vaut false, ce qui est le defaut.
# Construire l'URL depuis la config plutot que de la coder en dur.
$ApiKey  = ""
$Address = "127.0.0.1:8384"
$Scheme  = "http"
if (Test-Path $ConfigXml) {
    $xml = [xml](Get-Content $ConfigXml)
    if ($xml.configuration.gui.apikey)  { $ApiKey  = $xml.configuration.gui.apikey }
    if ($xml.configuration.gui.address) { $Address = $xml.configuration.gui.address }
    if ($xml.configuration.gui.tls -eq "true") { $Scheme = "https" }
}
$GuiUrl = "${Scheme}://${Address}/"

# La GUI en HTTPS utilise un certificat auto-signe : l'accepter pour les appels REST.
if ($Scheme -eq "https") {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}

if (-not (Get-Process -Name "syncthing" -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $SyncthingExe -ArgumentList "serve", "--no-browser" -WindowStyle Hidden
}

$NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
if (Test-Path $IconFile) {
    $NotifyIcon.Icon = New-Object System.Drawing.Icon($IconFile)
} else {
    $NotifyIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($SyncthingExe)
}
$NotifyIcon.Visible = $true
$NotifyIcon.Text = "Syncthing"

$Menu = New-Object System.Windows.Forms.ContextMenuStrip

$open = $Menu.Items.Add("Ouvrir interface Web")
$open.Add_Click({
    Start-Process $GuiUrl
})

$quit = $Menu.Items.Add("Quitter Syncthing")
$quit.Add_Click({
    try {
        $headers = @{}
        if ($ApiKey -ne "") { $headers["X-API-Key"] = $ApiKey }
        Invoke-WebRequest -Uri "${GuiUrl}rest/system/shutdown" `
            -Method POST `
            -Headers $headers `
            -TimeoutSec 2 `
            -UseBasicParsing `
            -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    Start-Sleep -Milliseconds 500

    Get-Process -Name "syncthing" -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Kill() } catch {}
    }

    $NotifyIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

$NotifyIcon.ContextMenuStrip = $Menu

# Double-clic sur l'icone : ouvrir l'interface.
$NotifyIcon.Add_DoubleClick({ Start-Process $GuiUrl })

[System.Windows.Forms.Application]::Run()
