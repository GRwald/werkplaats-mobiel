param(
    [string]$GitHubToken = "",
    [string]$GitHubRepo  = "GRwald/ai-werkplaats",
    [string]$ClaudeKey   = "",
    [switch]$RebuildApk,
    [switch]$PushApk
)

$ErrorActionPreference = 'Continue'

$Adb      = 'D:\Anitgravity-Lab\bouwblokken\android-sdk\platform-tools\adb.exe'
$ApkPath  = 'D:\Anitgravity-Lab\producten\werkplaats-mobiel.apk'
$BuildPs1 = 'D:\Anitgravity-Lab\projecten\werkplaats-mobiel\build-apk.ps1'
$QrPng    = 'C:\Users\gerwa\.gemini\antigravity\brain\456e5662-f4a1-4bb0-8f89-6b3fc31d673b\qr-koppel-sleutel.png'

if (-not $GitHubToken) {
    try {
        $credInput = "protocol=https`nhost=github.com`n`n"
        $credOut = $credInput | git credential fill 2>$null
        foreach ($line in $credOut) {
            if ($line -match '^password=(.+)$') {
                $GitHubToken = $Matches[1].Trim()
            }
        }
    } catch {}
}

if ($RebuildApk) {
    Write-Host "=== 0. Bak werkplaats-mobiel.apk met ingebakken GitHub-sleutel ==="
    & powershell -ExecutionPolicy Bypass -File $BuildPs1 -GitHubToken $GitHubToken
    Copy-Item -Path $ApkPath -Destination 'D:\Anitgravity-Lab\projecten\werkplaats-mobiel\werkplaats-mobiel.apk' -Force
}

Write-Host "=== 1. Controleer verbonden Honor Magic V3 via ADB ==="
$devicesOutput = & $Adb devices -l
if ($devicesOutput -match 'AXGL024C11002371\s+offline') {
    Write-Host "Herstel vertrouwde ADB-sleutel en herverbind..."
    & $Adb kill-server
    Start-Sleep -Seconds 1
    & $Adb start-server
    Start-Sleep -Seconds 2
    $devicesOutput = & $Adb devices -l
}
Write-Host ($devicesOutput | Out-String)

$ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$url = "https://grwald.github.io/werkplaats-mobiel/?v=$ts"

if ($GitHubToken) {
    Write-Host "=== GitHub-sleutel gevonden op pc -> wordt veilig via USB/QR klaargezet ==="
    $url += "#token=$GitHubToken&repo=$GitHubRepo"
    if ($ClaudeKey) { $url += "&claude=$ClaudeKey" }
    try {
        python -c "import qrcode; img = qrcode.make('$url'); img.save(r'$QrPng')" 2>$null
    } catch {}
}

Write-Host "=== 2. Koppel GitHub-sleutel direct aan de geïnstalleerde Werkplaats Mobiel APK ==="
$apkArgs = @('-d', 'shell', 'am', 'start', '--activity-single-top', '-n', 'nl.gerwald.werkplaatsmobiel/.MainActivity', '--ez', 'refresh', 'true')
if ($GitHubToken) {
    $apkArgs += @('--es', 'token', $GitHubToken, '--es', 'repo', $GitHubRepo)
}
if ($ClaudeKey) {
    $apkArgs += @('--es', 'claude', $ClaudeKey)
}
& $Adb @apkArgs | Out-Null

if ($PushApk) {
    Write-Host "=== 3. Zet werkplaats-mobiel.apk klaar in je Downloads-map op de telefoon ==="
    & $Adb -d push $ApkPath /sdcard/Download/werkplaats-mobiel.apk
}

Write-Host "=== KLAAR! Werkplaats Mobiel is ververst op je Honor Magic V3! ==="
