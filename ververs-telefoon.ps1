param(
    [string]$GitHubToken = "",
    [string]$GitHubRepo  = "GRwald/ai-werkplaats",
    [string]$ClaudeKey   = "",
    [switch]$PushApk
)

$ErrorActionPreference = 'Continue'

$Adb      = 'D:\Anitgravity-Lab\bouwblokken\android-sdk\platform-tools\adb.exe'
$ApkPath  = 'D:\Anitgravity-Lab\producten\werkplaats-mobiel.apk'
$BuildPs1 = 'D:\Anitgravity-Lab\projecten\werkplaats-mobiel\build-apk.ps1'

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

if ($GitHubToken) {
    Write-Host "=== GitHub-sleutel gevonden op pc -> wordt veilig via USB meegekoppeld naar je telefoon ==="
    $url += "#token=$GitHubToken&repo=$GitHubRepo"
    if ($ClaudeKey) { $url += "&claude=$ClaudeKey" }
}

Write-Host "=== 2. Ververs Werkplaats Mobiel in Brave op je Honor Magic V3 ==="
& $Adb -d shell "am start -a android.intent.action.VIEW -d '$url' com.brave.browser" | Out-Null

if ($PushApk) {
    Write-Host "=== 3. Zet werkplaats-mobiel.apk klaar in je Downloads-map op de telefoon ==="
    & $Adb -d push $ApkPath /sdcard/Download/werkplaats-mobiel.apk
}

Write-Host "=== KLAAR! Werkplaats Mobiel is ververst op je Honor Magic V3! ==="
