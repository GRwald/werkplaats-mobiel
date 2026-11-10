param(
    [string]$GitHubToken = "",
    [string]$GitHubRepo  = "GRwald/ai-werkplaats",
    [string]$ClaudeKey   = "",
    [switch]$AlleenBraveVerversen
)

$ErrorActionPreference = 'Stop'
$Adb      = 'D:\Anitgravity-Lab\bouwblokken\android-sdk\platform-tools\adb.exe'
$ApkPath  = 'D:\Anitgravity-Lab\producten\werkplaats-mobiel.apk'
$BuildPs1 = 'D:\Anitgravity-Lab\projecten\werkplaats-mobiel\build-apk.ps1'

Write-Host "=== 1. Controleer verbonden Honor Magic V3 via ADB ==="
$devicesOutput = & $Adb devices -l
Write-Host ($devicesOutput | Out-String)

if (-not ($devicesOutput -match '\sdevice\s')) {
    Write-Warning "Geen telefoon gevonden via ADB. Sluit je Honor Magic V3 aan met USB-foutopsporing (of Draadloze foutopsporing) aan."
    exit 1
}

if ($AlleenBraveVerversen) {
    Write-Host "=== 2. Open/ververs Werkplaats Mobiel in Brave op je telefoon ==="
    $url = "https://grwald.github.io/werkplaats-mobiel/?v=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    if ($GitHubToken) {
        $url += "#token=$GitHubToken&repo=$GitHubRepo"
        if ($ClaudeKey) { $url += "&claude=$ClaudeKey" }
    }
    & $Adb shell am start -a android.intent.action.VIEW -d "$url" com.brave.browser
    Write-Host "=== KLAAR! Brave op je telefoon is ververst. ==="
    exit 0
}

Write-Host "=== 2. Bak nieuwste werkplaats-mobiel.apk ==="
& powershell -ExecutionPolicy Bypass -File $BuildPs1

Write-Host "=== 3. Installeer / update werkplaats-mobiel.apk op je Honor Magic V3 ==="
& $Adb install -r $ApkPath

Write-Host "=== 4. Start en ververs Werkplaats Mobiel op je scherm ==="
$argsList = @('shell', 'am', 'start', '-n', 'nl.gerwald.werkplaatsmobiel/.MainActivity', '--ez', 'refresh', 'true')
if ($GitHubToken) {
    $argsList += @('--es', 'token', $GitHubToken, '--es', 'repo', $GitHubRepo)
}
if ($ClaudeKey) {
    $argsList += @('--es', 'claude', $ClaudeKey)
}
& $Adb @argsList

Write-Host "=== KLAAR! Werkplaats Mobiel draait vers op je Honor Magic V3! ==="
